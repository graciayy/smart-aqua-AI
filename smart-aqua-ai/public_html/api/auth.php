<?php
/**
 * SMART AQUA AI — Akun pengelola
 *
 *   GET  auth.php?action=accounts   daftar akun (untuk layar "Pilih Akun")
 *   GET  auth.php?action=me         akun yang sedang login + seluruh datanya
 *   POST auth.php?action=login      {id, password}
 *   POST auth.php?action=register   {nama, kelompok, telepon, password}
 *   POST auth.php?action=logout
 *   POST auth.php?action=password   {lama, baru}
 *   POST auth.php?action=import     {nama, kelompok, telepon, password, state, overwrite}
 *                                   memindahkan data lama (localStorage) ke server
 */
declare(strict_types=1);
require __DIR__ . '/lib.php';

$action = $_GET['action'] ?? '';

switch ($action) {

    case 'accounts': {
        $rows = db()->query(
            'SELECT u.id, u.nama, COUNT(p.id) AS jumlah_kolam
               FROM users u LEFT JOIN ponds p ON p.user_id = u.id
           GROUP BY u.id, u.nama
           ORDER BY u.nama'
        )->fetchAll();
        json_out(['ok' => true, 'accounts' => array_map(fn($r) => [
            'id'          => (int)$r['id'],
            'nama'        => $r['nama'],
            'jumlahKolam' => (int)$r['jumlah_kolam'],
        ], $rows)]);
    }

    case 'me': {
        $u = current_user();
        if (!$u) json_out(['ok' => true, 'user' => null]);
        json_out(['ok' => true, 'user' => public_user($u), 'state' => load_state($u['id'])]);
    }

    case 'login': {
        require_method('POST');
        $in = read_json();
        $pw = trim((string)($in['password'] ?? ''));
        if (isset($in['id'])) {
            $st = db()->prepare('SELECT * FROM users WHERE id = ?');
            $st->execute([(int)$in['id']]);
            $row = $st->fetch() ?: null;
        } else {
            $row = find_user_by_name(clean_name($in['nama'] ?? ''));
        }
        if (!$row) fail('Akun tidak ditemukan.', 404, 'not_found');
        verify_password_or_fail($row, $pw);
        issue_token((int)$row['id']);
        json_out(['ok' => true, 'user' => public_user($row), 'state' => load_state((int)$row['id'])]);
    }

    case 'register': {
        require_method('POST');
        $in = read_json();
        $nama = clean_name($in['nama'] ?? '');
        $kelompok = clean_str($in['kelompok'] ?? '', 150);
        $telepon = clean_str($in['telepon'] ?? '', 30);
        $pw = trim((string)($in['password'] ?? ''));
        if ($nama === '') fail('Nama pengelola wajib diisi.');
        if (mb_strlen($pw) < 4) fail('Kata sandi minimal 4 karakter.');
        if (find_user_by_name($nama)) fail('Nama akun sudah dipakai, gunakan nama lain.', 409, 'exists');
        try {
            $id = create_user($nama, $kelompok, $telepon, $pw);
        } catch (PDOException $e) {
            if ($e->getCode() === '23000') fail('Nama akun sudah dipakai, gunakan nama lain.', 409, 'exists');
            throw $e;
        }
        issue_token($id);
        json_out(['ok' => true, 'user' => ['id' => $id, 'nama' => $nama, 'kelompok' => $kelompok, 'telepon' => $telepon], 'state' => load_state($id)]);
    }

    case 'logout': {
        require_method('POST');
        revoke_token();
        json_out(['ok' => true]);
    }

    case 'password': {
        require_method('POST');
        $u = require_user();
        $in = read_json();
        $st = db()->prepare('SELECT * FROM users WHERE id = ?');
        $st->execute([$u['id']]);
        verify_password_or_fail($st->fetch(), trim((string)($in['lama'] ?? '')));
        $baru = trim((string)($in['baru'] ?? ''));
        if (mb_strlen($baru) < 4) fail('Kata sandi baru minimal 4 karakter.');
        db()->prepare('UPDATE users SET password_hash = ?, diperbarui = ? WHERE id = ?')
            ->execute([password_hash($baru, PASSWORD_DEFAULT), now(), $u['id']]);
        // Keluarkan perangkat lain
        db()->prepare('DELETE FROM auth_tokens WHERE user_id = ?')->execute([$u['id']]);
        issue_token($u['id']);
        json_out(['ok' => true]);
    }

    case 'import': {
        require_method('POST');
        $in = read_json();
        $nama = clean_name($in['nama'] ?? '');
        $pw = trim((string)($in['password'] ?? ''));
        $state = is_array($in['state'] ?? null) ? pick_state($in['state']) : ['ponds' => []];
        if ($nama === '') fail('Nama akun kosong.');
        if (mb_strlen($pw) < 4) fail('Kata sandi akun lama kurang dari 4 karakter.');

        $row = find_user_by_name($nama);
        if ($row) {
            if (empty($in['overwrite'])) fail('Akun dengan nama ini sudah ada di server.', 409, 'exists');
            verify_password_or_fail($row, $pw);
            save_state((int)$row['id'], $state);
            json_out(['ok' => true, 'hasil' => 'diperbarui', 'id' => (int)$row['id']]);
        }
        $id = create_user($nama, clean_str($in['kelompok'] ?? '', 150), clean_str($in['telepon'] ?? '', 30), $pw);
        save_state($id, $state);
        json_out(['ok' => true, 'hasil' => 'dibuat', 'id' => $id]);
    }

    default:
        fail('Aksi tidak dikenal.', 404);
}

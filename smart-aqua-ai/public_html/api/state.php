<?php
/**
 * SMART AQUA AI — Sinkronisasi data akun
 *
 *   GET  state.php   → seluruh data kolam akun yang login
 *   POST state.php   → simpan seluruh data (profil, kolam, riwayat, ambang batas)
 *        body: {profile:{nama,kelompok,telepon}, ponds:[...], pondHistory:[...],
 *               lastPondId, speciesThreshold:{...}, speciesLabel:{...}}
 */
declare(strict_types=1);
require __DIR__ . '/lib.php';

$u = require_user();

if (($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'GET') {
    json_out(['ok' => true, 'user' => public_user($u), 'state' => load_state($u['id'])]);
}

require_method('POST');
$in = read_json();
$warning = null;

// Profil (nama harus unik — kalau bentrok, nama lama dipertahankan & data lain tetap tersimpan)
if (is_array($in['profile'] ?? null)) {
    $pf = $in['profile'];
    $nama = clean_name($pf['nama'] ?? $u['nama']);
    if ($nama === '') $nama = $u['nama'];
    if (mb_strtolower($nama) !== mb_strtolower($u['nama'])) {
        $other = find_user_by_name($nama);
        if ($other && (int)$other['id'] !== $u['id']) {
            $warning = "Nama \"{$nama}\" sudah dipakai akun lain — nama profil tidak diubah.";
            $nama = $u['nama'];
        }
    }
    $kelompok = clean_str($pf['kelompok'] ?? '', 150);
    $telepon = clean_str($pf['telepon'] ?? '', 30);
    db()->prepare('UPDATE users SET nama = ?, kelompok = ?, telepon = ?, diperbarui = ? WHERE id = ?')
        ->execute([$nama, $kelompok, $telepon, now(), $u['id']]);
    $u['nama'] = $nama;
    $u['kelompok'] = $kelompok;
    $u['telepon'] = $telepon;
}

save_state($u['id'], pick_state($in));

$out = ['ok' => true, 'user' => public_user($u), 'disimpan' => now()];
if ($warning) $out['warning'] = $warning;
json_out($out);

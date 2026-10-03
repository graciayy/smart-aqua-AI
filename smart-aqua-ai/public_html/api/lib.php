<?php
/**
 * SMART AQUA AI — pustaka bersama (koneksi DB, autentikasi, pemetaan data kolam).
 * File ini tidak untuk diakses langsung dari browser.
 */
declare(strict_types=1);

if (PHP_SAPI !== 'cli' && realpath($_SERVER['SCRIPT_FILENAME'] ?? '') === __FILE__) {
    http_response_code(404);
    exit;
}

$GLOBALS['SAA_CONFIG'] = require __DIR__ . '/config.php';
date_default_timezone_set(cfg('timezone') ?: 'Asia/Makassar');
ini_set('display_errors', '0');

if (PHP_SAPI !== 'cli') {
    header('Content-Type: application/json; charset=utf-8');
    header('X-Content-Type-Options: nosniff');
    header('Cache-Control: no-store');
    set_exception_handler(function (Throwable $e) {
        error_log('[SMART AQUA AI] ' . $e->getMessage() . ' @ ' . $e->getFile() . ':' . $e->getLine());
        $msg = cfg('debug') ? $e->getMessage() : 'Terjadi kesalahan di server. Coba lagi sebentar.';
        if ($e instanceof PDOException && !cfg('debug')) {
            $msg = 'Database tidak dapat diakses. Periksa pengaturan api/config.php.';
        }
        json_out(['ok' => false, 'error' => $msg], 500);
    });
}

const MAX_BODY_BYTES = 12 * 1024 * 1024;   // 12 MB per permintaan
const MAX_PONDS      = 100;                // per akun
const MAX_FOTO_CHARS = 2_000_000;          // ±1,5 MB per foto (data URL)
const MAX_LIST_ROWS  = 2000;               // per daftar (kas, log pakan, dst.)
const COOKIE_NAME    = 'saa_token';

/* ===================== Utilitas dasar ===================== */

// Cadangan bila ekstensi mbstring tidak aktif di hosting
if (!function_exists('mb_substr')) {
    function mb_substr(string $s, int $start, ?int $len = null): string
    {
        $chars = preg_split('//u', $s, -1, PREG_SPLIT_NO_EMPTY) ?: [];
        return implode('', array_slice($chars, $start, $len));
    }
    function mb_strlen(string $s): int
    {
        return (int)preg_match_all('/./us', $s);
    }
    function mb_strtolower(string $s): string
    {
        return strtolower($s);
    }
}

function cfg(string $k)
{
    return $GLOBALS['SAA_CONFIG'][$k] ?? null;
}

function now(): string
{
    return date('Y-m-d H:i:s');
}

function db(): PDO
{
    static $pdo = null;
    if ($pdo === null) {
        $dsn = sprintf(
            'mysql:host=%s;port=%d;dbname=%s;charset=utf8mb4',
            cfg('db_host'), (int)cfg('db_port'), cfg('db_name')
        );
        $pdo = new PDO($dsn, cfg('db_user'), cfg('db_pass'), [
            PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES   => false,
        ]);
    }
    return $pdo;
}

function json_out(array $data, int $code = 200): void
{
    http_response_code($code);
    echo json_encode($data, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_INVALID_UTF8_SUBSTITUTE);
    exit;
}

function fail(string $msg, int $code = 400, ?string $errCode = null): void
{
    $out = ['ok' => false, 'error' => $msg];
    if ($errCode) $out['code'] = $errCode;
    json_out($out, $code);
}

function require_method(string $method): void
{
    if (($_SERVER['REQUEST_METHOD'] ?? 'GET') !== $method) {
        fail('Metode tidak diizinkan.', 405);
    }
}

/** Membaca body JSON. Wajib Content-Type application/json (sekaligus perlindungan CSRF). */
function read_json(): array
{
    $ct = $_SERVER['CONTENT_TYPE'] ?? '';
    if (stripos($ct, 'application/json') !== 0) {
        fail('Content-Type harus application/json.', 415);
    }
    $len = (int)($_SERVER['CONTENT_LENGTH'] ?? 0);
    if ($len > MAX_BODY_BYTES) {
        fail('Data terlalu besar. Kurangi ukuran/jumlah foto kolam.', 413);
    }
    $raw = file_get_contents('php://input') ?: '';
    if (strlen($raw) > MAX_BODY_BYTES) {
        fail('Data terlalu besar. Kurangi ukuran/jumlah foto kolam.', 413);
    }
    $data = json_decode($raw, true);
    if (!is_array($data)) {
        fail('Format data tidak valid.', 400);
    }
    return $data;
}

function clean_str($v, int $max): string
{
    if (!is_scalar($v)) return '';
    $s = trim((string)$v);
    $s = preg_replace('/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/u', '', $s) ?? '';
    return mb_substr($s, 0, $max);
}

/** Nama akun: tanpa karakter HTML supaya aman ditampilkan di daftar akun. */
function clean_name($v): string
{
    $s = clean_str($v, 100);
    $s = str_replace(['<', '>', '"', '`'], '', $s);
    return preg_replace('/\s+/u', ' ', $s) ?? '';
}

/* ===================== Autentikasi (token cookie) ===================== */

function is_https(): bool
{
    return (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off')
        || (($_SERVER['HTTP_X_FORWARDED_PROTO'] ?? '') === 'https')
        || ((int)($_SERVER['SERVER_PORT'] ?? 0) === 443);
}

function set_token_cookie(string $token, int $expires): void
{
    setcookie(COOKIE_NAME, $token, [
        'expires'  => $expires,
        'path'     => '/',
        'secure'   => is_https(),
        'httponly' => true,
        'samesite' => 'Lax',
    ]);
}

function issue_token(int $userId): void
{
    $token = bin2hex(random_bytes(32));
    $days = (int)(cfg('token_days') ?: 30);
    $exp = time() + $days * 86400;
    db()->prepare('INSERT INTO auth_tokens (user_id, token_hash, user_agent, dibuat, kedaluwarsa) VALUES (?,?,?,?,?)')
        ->execute([$userId, hash('sha256', $token), clean_str($_SERVER['HTTP_USER_AGENT'] ?? '', 255), now(), date('Y-m-d H:i:s', $exp)]);
    // Bersihkan token kedaluwarsa (murah, sesekali)
    if (random_int(1, 20) === 1) {
        db()->prepare('DELETE FROM auth_tokens WHERE kedaluwarsa < ?')->execute([now()]);
    }
    set_token_cookie($token, $exp);
}

function revoke_token(): void
{
    $token = $_COOKIE[COOKIE_NAME] ?? '';
    if ($token !== '') {
        db()->prepare('DELETE FROM auth_tokens WHERE token_hash = ?')->execute([hash('sha256', $token)]);
    }
    set_token_cookie('', time() - 3600);
}

function current_user(): ?array
{
    $token = $_COOKIE[COOKIE_NAME] ?? '';
    if (!is_string($token) || !preg_match('/^[a-f0-9]{64}$/', $token)) return null;
    $st = db()->prepare(
        'SELECT u.id, u.nama, u.kelompok, u.telepon, u.last_pond_id, t.id AS token_id, t.kedaluwarsa
           FROM auth_tokens t JOIN users u ON u.id = t.user_id
          WHERE t.token_hash = ? AND t.kedaluwarsa > ? LIMIT 1'
    );
    $st->execute([hash('sha256', $token), now()]);
    $u = $st->fetch();
    if (!$u) return null;

    // Perpanjang otomatis bila sisa masa berlaku < separuh
    $days = (int)(cfg('token_days') ?: 30);
    if (strtotime($u['kedaluwarsa']) - time() < $days * 43200) {
        $exp = time() + $days * 86400;
        db()->prepare('UPDATE auth_tokens SET kedaluwarsa = ? WHERE id = ?')->execute([date('Y-m-d H:i:s', $exp), $u['token_id']]);
        set_token_cookie($token, $exp);
    }
    unset($u['token_id'], $u['kedaluwarsa']);
    $u['id'] = (int)$u['id'];
    return $u;
}

function require_user(): array
{
    $u = current_user();
    if (!$u) fail('Sesi berakhir. Silakan masuk lagi.', 401, 'unauthenticated');
    return $u;
}

function public_user(array $u): array
{
    return [
        'id'       => (int)$u['id'],
        'nama'     => $u['nama'],
        'kelompok' => $u['kelompok'] ?? '',
        'telepon'  => $u['telepon'] ?? '',
    ];
}

/**
 * Cek kata sandi dengan penguncian sementara (5x salah → kunci 10 menit).
 * Mengembalikan baris user bila benar; memanggil fail() bila salah/terkunci.
 */
function verify_password_or_fail(array $userRow, string $password): array
{
    if ($userRow['terkunci_sampai'] && strtotime($userRow['terkunci_sampai']) > time()) {
        $menit = (int)ceil((strtotime($userRow['terkunci_sampai']) - time()) / 60);
        fail("Terlalu banyak percobaan salah. Coba lagi dalam {$menit} menit.", 429, 'locked');
    }
    if (!password_verify($password, $userRow['password_hash'])) {
        $gagal = (int)$userRow['gagal_login'] + 1;
        $kunci = $gagal >= 5 ? date('Y-m-d H:i:s', time() + 600) : null;
        db()->prepare('UPDATE users SET gagal_login = ?, terkunci_sampai = ? WHERE id = ?')
            ->execute([$kunci ? 0 : $gagal, $kunci, $userRow['id']]);
        fail('Kata sandi salah, coba lagi.', 401, 'wrong_password');
    }
    $upd = 'UPDATE users SET gagal_login = 0, terkunci_sampai = NULL';
    $args = [];
    if (password_needs_rehash($userRow['password_hash'], PASSWORD_DEFAULT)) {
        $upd .= ', password_hash = ?';
        $args[] = password_hash($password, PASSWORD_DEFAULT);
    }
    $args[] = $userRow['id'];
    db()->prepare($upd . ' WHERE id = ?')->execute($args);
    return $userRow;
}

/* ===================== Pemetaan objek aplikasi ⇄ kolom tabel ===================== */

/** [jalur di objek JS, kolom DB, tipe] */
const POND_FIELDS = [
    ['nama', 'nama', 'str:120'],
    ['jenis', 'jenis', 'str:60'],
    ['lokasi', 'lokasi', 'str:200'],
    ['status', 'status', 'str:20'],
    ['dimensi.bentuk', 'bentuk', 'str:20'],
    ['dimensi.panjang', 'panjang', 'float'],
    ['dimensi.lebar', 'lebar', 'float'],
    ['dimensi.diameter', 'diameter', 'float'],
    ['dimensi.tinggi', 'tinggi', 'float'],
    ['dimensi.isiAir', 'isi_air', 'float'],
    ['jumlah', 'jumlah', 'int'],
    ['tanggalTebar', 'tanggal_tebar', 'date'],
    ['tebarHari', 'tebar_hari', 'int'],
    ['bobotAwal', 'bobot_awal', 'float'],
    ['bobotSekarang', 'bobot_sekarang', 'float'],
    ['targetBobot', 'target_bobot', 'float'],
    ['fcr', 'fcr', 'float'],
    ['survivalRate', 'survival_rate', 'float'],
    ['hargaBibit', 'harga_bibit', 'money'],
    ['hargaPakanKg', 'harga_pakan_kg', 'money'],
    ['hargaJualKg', 'harga_jual_kg', 'money'],
    ['biayaListrik', 'biaya_listrik', 'money'],
    ['biayaTenagaKerja', 'biaya_tenaga_kerja', 'money'],
    ['biayaLain', 'biaya_lain', 'money'],
    ['aeratorOn', 'aerator_on', 'bool'],
    ['sensor.suhu', 'sensor_suhu', 'float'],
    ['sensor.ph', 'sensor_ph', 'float'],
    ['sensor.do', 'sensor_do', 'float'],
    ['sensor.keruh', 'sensor_keruh', 'float'],
    ['sensor.amonia', 'sensor_amonia', 'float'],
    ['terpal.usiaBulan', 'terpal_usia_bulan', 'int'],
    ['terpal.terakhirDikurasHari', 'terpal_terakhir_dikuras_hari', 'int'],
    ['terpal.adaLipatan', 'terpal_ada_lipatan', 'bool'],
    ['feeding.takaran', 'pakan_takaran', 'float'],
    ['feeding.jadwal', 'pakan_jadwal', 'str:100'],
    ['feeding.hemat', 'pakan_hemat', 'float'],
    ['feeding.alasan', 'pakan_alasan', 'text'],
    ['disease.level', 'penyakit_level', 'str:20'],
    ['disease.confidence', 'penyakit_confidence', 'float'],
    ['disease.indikasi', 'penyakit_indikasi', 'text'],
    ['disease.saran', 'penyakit_saran', 'text'],
    ['disease.sumber', 'penyakit_sumber', 'str:255'],
    ['trend', 'trend_json', 'json'],
    ['histLong', 'hist_long_json', 'json'],
    ['growth', 'growth_json', 'json'],
    ['pengingat', 'pengingat_json', 'jsonobj'],
    ['foto', 'foto', 'foto'],
];

/** Daftar anak per kolam: kunci di objek JS => [tabel, field map] */
const POND_CHILDREN = [
    'kas' => ['pond_cash', [
        ['tanggal', 'tanggal', 'str:30'],
        ['tipe', 'tipe', 'str:10'],
        ['jumlah', 'jumlah', 'money'],
        ['keterangan', 'keterangan', 'str:255'],
    ]],
    'riwayatSiklus' => ['pond_cycles', [
        ['siklusKe', 'siklus_ke', 'str:60'],
        ['tanggalPanen', 'tanggal_panen', 'str:40'],
        ['totalBobotKg', 'total_bobot_kg', 'float'],
        ['totalBiaya', 'total_biaya', 'money'],
        ['totalPendapatan', 'total_pendapatan', 'money'],
        ['catatan', 'catatan', 'text'],
    ]],
    'feedLog' => ['pond_feed_logs', [
        ['tgl', 'tgl', 'str:30'],
        ['rencana', 'rencana', 'float'],
        ['realisasi', 'realisasi', 'float'],
        ['catatan', 'catatan', 'str:255'],
    ]],
    'selfCheckHistory' => ['pond_self_checks', [
        ['waktu', 'waktu', 'str:60'],
        ['jenis', 'jenis', 'str:60'],
        ['level', 'level', 'str:20'],
        ['indikasi', 'indikasi', 'text'],
    ]],
];

const HISTORY_FIELDS = [
    ['waktu', 'waktu', 'str:60'],
    ['aksi', 'aksi', 'str:40'],
    ['kolam', 'kolam', 'str:120'],
    ['keterangan', 'keterangan', 'text'],
];

/** Kunci yang hanya dikirim server (jangan disimpan balik ke extra_json) */
const SERVER_ONLY_KEYS = ['perangkatIoT', 'sensorWaktu'];

function path_get(array $a, string $path)
{
    foreach (explode('.', $path) as $k) {
        if (!is_array($a) || !array_key_exists($k, $a)) return null;
        $a = $a[$k];
    }
    return $a;
}

function path_set(array &$a, string $path, $value): void
{
    $keys = explode('.', $path);
    $ref = &$a;
    foreach ($keys as $i => $k) {
        if ($i === count($keys) - 1) {
            $ref[$k] = $value;
        } else {
            if (!isset($ref[$k]) || !is_array($ref[$k])) $ref[$k] = [];
            $ref = &$ref[$k];
        }
    }
}

function path_unset(array &$a, string $path): void
{
    $keys = explode('.', $path);
    $last = array_pop($keys);
    $ref = &$a;
    foreach ($keys as $k) {
        if (!isset($ref[$k]) || !is_array($ref[$k])) return;
        $ref = &$ref[$k];
    }
    unset($ref[$last]);
}

function to_db($v, string $type)
{
    if ($v === null) return null;
    [$base, $len] = array_pad(explode(':', $type), 2, null);
    switch ($base) {
        case 'str':
            return is_scalar($v) ? clean_str($v, (int)$len) : null;
        case 'text':
            return is_scalar($v) ? clean_str($v, 20000) : null;
        case 'int':
            return is_numeric($v) ? (int)round((float)$v) : null;
        case 'float':
            return (is_numeric($v) && is_finite((float)$v)) ? (float)$v : null;
        case 'money':
            return (is_numeric($v) && is_finite((float)$v)) ? round((float)$v, 2) : null;
        case 'bool':
            return $v ? 1 : 0;
        case 'date':
            return (is_string($v) && preg_match('/^\d{4}-\d{2}-\d{2}$/', $v) && strtotime($v)) ? $v : null;
        case 'json':
        case 'jsonobj':
            return json_encode($v, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_INVALID_UTF8_SUBSTITUTE);
        case 'foto':
            return (is_string($v) && strncmp($v, 'data:image/', 11) === 0 && strlen($v) <= MAX_FOTO_CHARS) ? $v : null;
    }
    return null;
}

function from_db($v, string $type)
{
    if ($v === null) return null;
    $base = explode(':', $type)[0];
    switch ($base) {
        case 'int':
            return (int)$v;
        case 'float':
        case 'money':
            $f = (float)$v;
            return (floor($f) == $f && abs($f) < 1e15) ? (int)$f : $f;
        case 'bool':
            return (bool)(int)$v;
        case 'json':
            return json_decode((string)$v, true);
        case 'jsonobj':
            $d = json_decode((string)$v, true);
            return (is_array($d) && $d) ? $d : new stdClass();
        default:
            return (string)$v;
    }
}

/** Objek JS → [baris DB, sisa field (extra)] */
function obj_to_row(array $obj, array $fields, array $dropKeys = []): array
{
    $row = [];
    $rest = $obj;
    $parents = [];
    foreach ($fields as [$path, $col, $type]) {
        $row[$col] = to_db(path_get($obj, $path), $type);
        path_unset($rest, $path);
        if (strpos($path, '.') !== false) $parents[substr($path, 0, strrpos($path, '.'))] = true;
    }
    foreach ($dropKeys as $k) unset($rest[$k]);
    // Objek induk (dimensi, sensor, ...) yang kini kosong tidak perlu disimpan di extra
    foreach (array_keys($parents) as $pp) {
        if (path_get($rest, $pp) === []) path_unset($rest, $pp);
    }
    $row['extra_json'] = $rest ? json_encode($rest, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_INVALID_UTF8_SUBSTITUTE) : null;
    return $row;
}

/** Baris DB → objek JS (field kosong/NULL tidak dikirim) */
function row_to_obj(array $row, array $fields): array
{
    $obj = [];
    if (!empty($row['extra_json'])) {
        $extra = json_decode($row['extra_json'], true);
        if (is_array($extra)) $obj = $extra;
    }
    foreach ($fields as [$path, $col, $type]) {
        if (!array_key_exists($col, $row)) continue;
        $v = from_db($row[$col], $type);
        if ($v !== null) path_set($obj, $path, $v);
    }
    return $obj;
}

function insert_row(string $table, array $row): void
{
    $cols = array_keys($row);
    $sql = sprintf(
        'INSERT INTO %s (%s) VALUES (%s)',
        $table,
        implode(',', $cols),
        implode(',', array_fill(0, count($cols), '?'))
    );
    db()->prepare($sql)->execute(array_values($row));
}

/* ===================== Muat & simpan seluruh data akun ===================== */

function load_state(int $userId): array
{
    $pdo = db();

    $st = $pdo->prepare('SELECT * FROM ponds WHERE user_id = ? ORDER BY urutan, id');
    $st->execute([$userId]);
    $rows = $st->fetchAll();

    $ponds = [];
    $byDbId = [];
    foreach ($rows as $r) {
        $p = ['id' => $r['client_id']];
        $p += row_to_obj($r, POND_FIELDS);
        foreach (array_keys(POND_CHILDREN) as $key) $p[$key] = [];
        if (!isset($p['pengingat'])) $p['pengingat'] = new stdClass();
        if ($r['sensor_waktu']) {
            $p['perangkatIoT'] = true;
            $p['sensorWaktu'] = $r['sensor_waktu'];
        }
        $ponds[] = $p;
        $byDbId[(int)$r['id']] = count($ponds) - 1;
    }

    if ($byDbId) {
        $ids = implode(',', array_map('intval', array_keys($byDbId)));
        foreach (POND_CHILDREN as $key => [$table, $fields]) {
            $rs = $pdo->query("SELECT * FROM {$table} WHERE pond_id IN ({$ids}) ORDER BY pond_id, urutan, id");
            foreach ($rs as $r) {
                $ponds[$byDbId[(int)$r['pond_id']]][$key][] = row_to_obj($r, $fields);
            }
        }
    }

    $st = $pdo->prepare('SELECT * FROM pond_history WHERE user_id = ? ORDER BY urutan, id');
    $st->execute([$userId]);
    $history = array_map(fn($r) => row_to_obj($r, HISTORY_FIELDS), $st->fetchAll());

    $st = $pdo->prepare('SELECT * FROM species_thresholds WHERE user_id = ?');
    $st->execute([$userId]);
    $thr = [];
    $lbl = [];
    foreach ($st->fetchAll() as $r) {
        $t = [];
        foreach (['suhu', 'ph', 'do', 'amonia', 'keruh'] as $k) {
            $t[$k] = [from_db($r[$k . '_min'], 'float'), from_db($r[$k . '_max'], 'float')];
        }
        $thr[$r['kode']] = $t;
        $lbl[$r['kode']] = $r['label'];
    }

    $st = $pdo->prepare('SELECT last_pond_id FROM users WHERE id = ?');
    $st->execute([$userId]);

    return [
        'ponds'            => $ponds,
        'pondHistory'      => $history,
        'lastPondId'       => $st->fetchColumn() ?: null,
        'speciesThreshold' => $thr ?: new stdClass(),
        'speciesLabel'     => $lbl ?: new stdClass(),
    ];
}

/**
 * Simpan seluruh data akun (ganti total) dalam satu transaksi.
 * Kolom sensor kolam yang punya perangkat IoT aktif TIDAK ditimpa oleh aplikasi.
 */
function save_state(int $userId, array $state): void
{
    $pdo = db();
    $ponds = $state['ponds'] ?? [];
    if (!is_array($ponds) || !array_is_list($ponds)) fail('Data kolam tidak valid.');
    if (count($ponds) > MAX_PONDS) fail('Jumlah kolam melebihi batas (' . MAX_PONDS . ').');

    $pdo->beginTransaction();
    try {
        $t = now();

        // Kolam yang dikendalikan perangkat IoT
        $st = $pdo->prepare('SELECT p.client_id FROM devices d JOIN ponds p ON p.id = d.pond_id WHERE p.user_id = ? AND d.aktif = 1');
        $st->execute([$userId]);
        $iot = array_flip($st->fetchAll(PDO::FETCH_COLUMN));
        $sensorCols = ['sensor_suhu', 'sensor_ph', 'sensor_do', 'sensor_keruh', 'sensor_amonia'];

        $keepIds = [];
        foreach (array_values($ponds) as $i => $p) {
            if (!is_array($p)) continue;
            $cid = clean_str($p['id'] ?? '', 40);
            if ($cid === '' || isset($keepIds[$cid])) continue;
            $keepIds[$cid] = true;

            $drop = array_merge(['id'], array_keys(POND_CHILDREN), SERVER_ONLY_KEYS);
            $row = obj_to_row($p, POND_FIELDS, $drop);
            $row['urutan'] = $i;
            $row['diperbarui'] = $t;

            $updCols = array_keys($row);
            if (isset($iot[$cid])) $updCols = array_diff($updCols, $sensorCols);

            $ins = array_merge(['user_id' => $userId, 'client_id' => $cid, 'dibuat' => $t], $row);
            $cols = array_keys($ins);
            $sql = sprintf(
                'INSERT INTO ponds (%s) VALUES (%s) ON DUPLICATE KEY UPDATE %s',
                implode(',', $cols),
                implode(',', array_fill(0, count($cols), '?')),
                implode(',', array_map(fn($c) => "{$c}=VALUES({$c})", $updCols))
            );
            $pdo->prepare($sql)->execute(array_values($ins));

            $q = $pdo->prepare('SELECT id FROM ponds WHERE user_id = ? AND client_id = ?');
            $q->execute([$userId, $cid]);
            $pondId = (int)$q->fetchColumn();

            foreach (POND_CHILDREN as $key => [$table, $fields]) {
                $pdo->prepare("DELETE FROM {$table} WHERE pond_id = ?")->execute([$pondId]);
                $list = $p[$key] ?? [];
                if (!is_array($list)) continue;
                foreach (array_slice(array_values($list), 0, MAX_LIST_ROWS) as $j => $item) {
                    if (!is_array($item)) continue;
                    $r = obj_to_row($item, $fields);
                    insert_row($table, ['pond_id' => $pondId, 'urutan' => $j] + $r);
                }
            }
        }

        // Hapus kolam yang sudah dihapus di aplikasi
        if ($keepIds) {
            $ph = implode(',', array_fill(0, count($keepIds), '?'));
            $pdo->prepare("DELETE FROM ponds WHERE user_id = ? AND client_id NOT IN ({$ph})")
                ->execute(array_merge([$userId], array_keys($keepIds)));
        } else {
            $pdo->prepare('DELETE FROM ponds WHERE user_id = ?')->execute([$userId]);
        }

        // Riwayat aksi kolam
        if (array_key_exists('pondHistory', $state)) {
            $pdo->prepare('DELETE FROM pond_history WHERE user_id = ?')->execute([$userId]);
            $hist = is_array($state['pondHistory']) ? array_values($state['pondHistory']) : [];
            foreach (array_slice($hist, 0, MAX_LIST_ROWS) as $j => $h) {
                if (!is_array($h)) continue;
                insert_row('pond_history', ['user_id' => $userId, 'urutan' => $j] + obj_to_row($h, HISTORY_FIELDS));
            }
        }

        // Ambang batas & label jenis ikan
        $thr = $state['speciesThreshold'] ?? null;
        if (is_array($thr) && $thr) {
            $lbl = is_array($state['speciesLabel'] ?? null) ? $state['speciesLabel'] : [];
            $pdo->prepare('DELETE FROM species_thresholds WHERE user_id = ?')->execute([$userId]);
            $n = 0;
            foreach ($thr as $kode => $th) {
                if (!is_array($th) || ++$n > 200) continue;
                $kode = clean_str($kode, 60);
                if ($kode === '') continue;
                $row = ['user_id' => $userId, 'kode' => $kode, 'label' => clean_str($lbl[$kode] ?? $kode, 100)];
                foreach (['suhu', 'ph', 'do', 'amonia', 'keruh'] as $k) {
                    $range = is_array($th[$k] ?? null) ? array_values($th[$k]) : [null, null];
                    $row[$k . '_min'] = to_db($range[0] ?? null, 'float');
                    $row[$k . '_max'] = to_db($range[1] ?? null, 'float');
                }
                insert_row('species_thresholds', $row);
            }
        }

        $last = isset($state['lastPondId']) ? clean_str($state['lastPondId'], 40) : null;
        $pdo->prepare('UPDATE users SET last_pond_id = ?, diperbarui = ? WHERE id = ?')
            ->execute([$last ?: null, $t, $userId]);

        $pdo->commit();
    } catch (Throwable $e) {
        $pdo->rollBack();
        throw $e;
    }
}

/** Ambil pilihan data state dari body permintaan (hanya kunci yang dikenal). */
function pick_state(array $src): array
{
    $out = [];
    foreach (['ponds', 'pondHistory', 'lastPondId', 'speciesThreshold', 'speciesLabel'] as $k) {
        if (array_key_exists($k, $src)) $out[$k] = $src[$k];
    }
    if (!isset($out['ponds'])) $out['ponds'] = [];
    return $out;
}

function create_user(string $nama, string $kelompok, string $telepon, string $password): int
{
    $t = now();
    db()->prepare('INSERT INTO users (nama, kelompok, telepon, password_hash, dibuat, diperbarui) VALUES (?,?,?,?,?,?)')
        ->execute([$nama, $kelompok, $telepon, password_hash($password, PASSWORD_DEFAULT), $t, $t]);
    return (int)db()->lastInsertId();
}

function find_user_by_name(string $nama): ?array
{
    $st = db()->prepare('SELECT * FROM users WHERE nama = ? LIMIT 1');
    $st->execute([$nama]);
    return $st->fetch() ?: null;
}

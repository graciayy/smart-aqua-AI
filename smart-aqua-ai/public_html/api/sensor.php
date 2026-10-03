<?php
/**
 * SMART AQUA AI — Data sensor IoT (ESP32)
 *
 * POST sensor.php   (dari perangkat; JSON atau form-urlencoded)
 *   {api_key, suhu, ph, do, keruh, amonia}   — field sensor boleh sebagian
 *   → {ok, aerator: true|false, interval_detik}
 *   Perangkat membaca "aerator" untuk menyalakan/mematikan relai sesuai tombol di aplikasi.
 *
 * GET  sensor.php?pond=<id kolam di aplikasi>&jam=24   (aplikasi, harus login)
 *   → riwayat pembacaan sensor kolam tersebut
 */
declare(strict_types=1);
require __DIR__ . '/lib.php';

$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';

if ($method === 'GET') {
    $u = require_user();
    $cid = clean_str($_GET['pond'] ?? '', 40);
    $jam = max(1, min(24 * 90, (int)($_GET['jam'] ?? 24)));
    $st = db()->prepare(
        'SELECT r.waktu, r.suhu, r.ph, r.oksigen AS `do`, r.keruh, r.amonia
           FROM sensor_readings r JOIN ponds p ON p.id = r.pond_id
          WHERE p.user_id = ? AND p.client_id = ? AND r.waktu >= ?
       ORDER BY r.waktu
          LIMIT 5000'
    );
    $st->execute([$u['id'], $cid, date('Y-m-d H:i:s', time() - $jam * 3600)]);
    $rows = array_map(function ($r) {
        foreach (['suhu', 'ph', 'do', 'keruh', 'amonia'] as $k) $r[$k] = $r[$k] === null ? null : (float)$r[$k];
        return $r;
    }, $st->fetchAll());
    json_out(['ok' => true, 'readings' => $rows]);
}

require_method('POST');

$ct = $_SERVER['CONTENT_TYPE'] ?? '';
if (stripos($ct, 'application/json') === 0) {
    $in = json_decode(file_get_contents('php://input') ?: '', true);
    if (!is_array($in)) fail('JSON tidak valid.');
} else {
    $in = $_POST;
}

$key = (string)($in['api_key'] ?? ($_SERVER['HTTP_X_API_KEY'] ?? ''));
if (strlen($key) < 16) fail('api_key tidak valid.', 401);

$st = db()->prepare(
    'SELECT d.id, d.pond_id, d.terakhir_kirim, p.aerator_on
       FROM devices d JOIN ponds p ON p.id = d.pond_id
      WHERE d.api_key_hash = ? AND d.aktif = 1 LIMIT 1'
);
$st->execute([hash('sha256', $key)]);
$dev = $st->fetch();
if (!$dev) fail('Perangkat tidak terdaftar atau nonaktif.', 401);

// Batasi frekuensi kiriman: minimal jeda 5 detik
if ($dev['terakhir_kirim'] && time() - strtotime($dev['terakhir_kirim']) < 5) {
    json_out(['ok' => false, 'error' => 'Terlalu cepat, tunggu beberapa detik.', 'aerator' => (bool)$dev['aerator_on'], 'interval_detik' => 60], 429);
}

// Rentang wajar tiap parameter (nilai di luar ini dianggap sensor error → diabaikan)
$limits = ['suhu' => [0, 50], 'ph' => [0, 14], 'do' => [0, 25], 'keruh' => [0, 3000], 'amonia' => [0, 50]];
$val = [];
foreach ($limits as $k => [$lo, $hi]) {
    $v = $in[$k] ?? null;
    $val[$k] = (is_numeric($v) && (float)$v >= $lo && (float)$v <= $hi) ? round((float)$v, 3) : null;
}
if (count(array_filter($val, fn($v) => $v !== null)) === 0) fail('Tidak ada nilai sensor yang valid.');

$t = now();
$pdo = db();
$pdo->beginTransaction();
$pdo->prepare('INSERT INTO sensor_readings (pond_id, device_id, waktu, suhu, ph, oksigen, keruh, amonia) VALUES (?,?,?,?,?,?,?,?)')
    ->execute([$dev['pond_id'], $dev['id'], $t, $val['suhu'], $val['ph'], $val['do'], $val['keruh'], $val['amonia']]);
$pdo->prepare(
    'UPDATE ponds SET
        sensor_suhu   = COALESCE(?, sensor_suhu),
        sensor_ph     = COALESCE(?, sensor_ph),
        sensor_do     = COALESCE(?, sensor_do),
        sensor_keruh  = COALESCE(?, sensor_keruh),
        sensor_amonia = COALESCE(?, sensor_amonia),
        sensor_waktu  = ?
      WHERE id = ?'
)->execute([$val['suhu'], $val['ph'], $val['do'], $val['keruh'], $val['amonia'], $t, $dev['pond_id']]);
$pdo->prepare('UPDATE devices SET terakhir_kirim = ? WHERE id = ?')->execute([$t, $dev['id']]);
$pdo->commit();

json_out(['ok' => true, 'aerator' => (bool)$dev['aerator_on'], 'interval_detik' => 60]);

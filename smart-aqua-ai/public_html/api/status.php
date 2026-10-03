<?php
/** Cek cepat setelah upload: buka https://domain-anda/api/status.php */
declare(strict_types=1);
require __DIR__ . '/lib.php';
$n = (int)db()->query('SELECT COUNT(*) FROM users')->fetchColumn();
json_out(['ok' => true, 'pesan' => 'Server & database terhubung.', 'jumlah_akun' => $n, 'php' => PHP_VERSION]);

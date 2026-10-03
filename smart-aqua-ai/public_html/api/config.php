<?php
/**
 * SMART AQUA AI — Konfigurasi server
 * ---------------------------------------------------------------
 * GANTI 4 nilai database di bawah sesuai yang dibuat di cPanel
 * (menu "MySQL Databases"). Di cPanel, nama database & user
 * biasanya berawalan nama akun hosting, mis. "polimdo_aqua".
 */
return [
    'db_host' => getenv('SAA_DB_HOST') ?: 'localhost',
    'db_port' => (int)(getenv('SAA_DB_PORT') ?: 3306),
    'db_name' => getenv('SAA_DB_NAME') ?: 'NAMA_DATABASE',
    'db_user' => getenv('SAA_DB_USER') ?: 'USER_DATABASE',
    'db_pass' => getenv('SAA_DB_PASS') ?: 'PASSWORD_DATABASE',

    // Lama login bertahan di satu perangkat (hari)
    'token_days' => 30,

    // Zona waktu Sulawesi Utara (WITA)
    'timezone' => 'Asia/Makassar',

    // true hanya saat uji coba — menampilkan pesan error teknis
    'debug' => false,
];

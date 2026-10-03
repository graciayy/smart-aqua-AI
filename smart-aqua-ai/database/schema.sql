-- =====================================================================
--  SMART AQUA AI — Skema Database (MySQL 5.7+ / MariaDB 10.3+)
--  Tim CAPCAY · Politeknik Negeri Manado
--  Impor lewat phpMyAdmin > Import (database harus sudah dibuat).
-- =====================================================================
SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

DROP TABLE IF EXISTS sensor_readings;
DROP TABLE IF EXISTS devices;
DROP TABLE IF EXISTS pond_history;
DROP TABLE IF EXISTS pond_self_checks;
DROP TABLE IF EXISTS pond_feed_logs;
DROP TABLE IF EXISTS pond_cycles;
DROP TABLE IF EXISTS pond_cash;
DROP TABLE IF EXISTS ponds;
DROP TABLE IF EXISTS species_thresholds;
DROP TABLE IF EXISTS auth_tokens;
DROP TABLE IF EXISTS users;

SET FOREIGN_KEY_CHECKS = 1;

-- ---------------------------------------------------------------------
-- Akun pengelola kolam (pembudidaya / kelompok tani)
-- ---------------------------------------------------------------------
CREATE TABLE users (
  id               INT UNSIGNED     NOT NULL AUTO_INCREMENT,
  nama             VARCHAR(100)     NOT NULL,
  kelompok         VARCHAR(150)     NOT NULL DEFAULT '',
  telepon          VARCHAR(30)      NOT NULL DEFAULT '',
  password_hash    VARCHAR(255)     NOT NULL,
  last_pond_id     VARCHAR(40)      NULL,
  gagal_login      TINYINT UNSIGNED NOT NULL DEFAULT 0,
  terkunci_sampai  DATETIME         NULL,
  dibuat           DATETIME         NOT NULL,
  diperbarui       DATETIME         NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_users_nama (nama)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Token login (cookie httpOnly, berlaku 30 hari), disimpan dalam bentuk hash
CREATE TABLE auth_tokens (
  id          INT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id     INT UNSIGNED NOT NULL,
  token_hash  CHAR(64)     NOT NULL,
  user_agent  VARCHAR(255) NOT NULL DEFAULT '',
  dibuat      DATETIME     NOT NULL,
  kedaluwarsa DATETIME     NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_token (token_hash),
  KEY idx_token_user (user_id),
  CONSTRAINT fk_token_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Ambang batas kualitas air per jenis ikan (per akun; jenis baru bisa ditambah)
CREATE TABLE species_thresholds (
  user_id     INT UNSIGNED NOT NULL,
  kode        VARCHAR(60)  NOT NULL,
  label       VARCHAR(100) NOT NULL,
  suhu_min    DOUBLE NULL, suhu_max    DOUBLE NULL,
  ph_min      DOUBLE NULL, ph_max      DOUBLE NULL,
  do_min      DOUBLE NULL, do_max      DOUBLE NULL,
  amonia_min  DOUBLE NULL, amonia_max  DOUBLE NULL,
  keruh_min   DOUBLE NULL, keruh_max   DOUBLE NULL,
  PRIMARY KEY (user_id, kode),
  CONSTRAINT fk_species_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- Kolam
-- ---------------------------------------------------------------------
CREATE TABLE ponds (
  id                            INT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id                       INT UNSIGNED NOT NULL,
  client_id                     VARCHAR(40)  NOT NULL COMMENT 'ID kolam di aplikasi (mis. p1, p_xxxx)',
  urutan                        INT          NOT NULL DEFAULT 0,
  nama                          VARCHAR(120) NULL,
  jenis                         VARCHAR(60)  NULL,
  lokasi                        VARCHAR(200) NULL,
  status                        VARCHAR(20)  NULL COMMENT 'aman | waspada | kritis',
  bentuk                        VARCHAR(20)  NULL COMMENT 'persegi | lingkaran',
  panjang                       DOUBLE NULL,
  lebar                         DOUBLE NULL,
  diameter                      DOUBLE NULL,
  tinggi                        DOUBLE NULL,
  isi_air                       DOUBLE NULL COMMENT 'fraksi 0..1',
  jumlah                        INT    NULL,
  tanggal_tebar                 DATE   NULL,
  tebar_hari                    INT    NULL,
  bobot_awal                    DOUBLE NULL,
  bobot_sekarang                DOUBLE NULL,
  target_bobot                  DOUBLE NULL,
  fcr                           DOUBLE NULL,
  survival_rate                 DOUBLE NULL,
  harga_bibit                   DECIMAL(15,2) NULL,
  harga_pakan_kg                DECIMAL(15,2) NULL,
  harga_jual_kg                 DECIMAL(15,2) NULL,
  biaya_listrik                 DECIMAL(15,2) NULL,
  biaya_tenaga_kerja            DECIMAL(15,2) NULL,
  biaya_lain                    DECIMAL(15,2) NULL,
  aerator_on                    TINYINT(1) NULL,
  sensor_suhu                   DOUBLE NULL,
  sensor_ph                     DOUBLE NULL,
  sensor_do                     DOUBLE NULL,
  sensor_keruh                  DOUBLE NULL,
  sensor_amonia                 DOUBLE NULL,
  sensor_waktu                  DATETIME NULL COMMENT 'diisi bila data datang dari perangkat IoT',
  terpal_usia_bulan             INT NULL,
  terpal_terakhir_dikuras_hari  INT NULL,
  terpal_ada_lipatan            TINYINT(1) NULL,
  pakan_takaran                 DOUBLE NULL,
  pakan_jadwal                  VARCHAR(100) NULL,
  pakan_hemat                   DOUBLE NULL,
  pakan_alasan                  TEXT NULL,
  penyakit_level                VARCHAR(20) NULL,
  penyakit_confidence           DOUBLE NULL,
  penyakit_indikasi             TEXT NULL,
  penyakit_saran                TEXT NULL,
  penyakit_sumber               VARCHAR(255) NULL,
  trend_json                    LONGTEXT NULL COMMENT 'tren 7 hari per parameter',
  hist_long_json                LONGTEXT NULL COMMENT 'riwayat 30 hari per parameter',
  growth_json                   TEXT NULL COMMENT 'riwayat bobot (gram)',
  pengingat_json                TEXT NULL,
  extra_json                    LONGTEXT NULL COMMENT 'cadangan untuk field tambahan dari aplikasi',
  foto                          MEDIUMTEXT NULL COMMENT 'data URL JPEG terkompres',
  dibuat                        DATETIME NOT NULL,
  diperbarui                    DATETIME NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_pond_client (user_id, client_id),
  CONSTRAINT fk_pond_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Buku kas per kolam
CREATE TABLE pond_cash (
  id          INT UNSIGNED NOT NULL AUTO_INCREMENT,
  pond_id     INT UNSIGNED NOT NULL,
  urutan      INT NOT NULL DEFAULT 0,
  tanggal     VARCHAR(30)  NULL,
  tipe        VARCHAR(10)  NULL COMMENT 'masuk | keluar',
  jumlah      DECIMAL(15,2) NULL,
  keterangan  VARCHAR(255) NULL,
  extra_json  TEXT NULL,
  PRIMARY KEY (id),
  KEY idx_cash_pond (pond_id, urutan),
  CONSTRAINT fk_cash_pond FOREIGN KEY (pond_id) REFERENCES ponds(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Riwayat siklus panen
CREATE TABLE pond_cycles (
  id                INT UNSIGNED NOT NULL AUTO_INCREMENT,
  pond_id           INT UNSIGNED NOT NULL,
  urutan            INT NOT NULL DEFAULT 0,
  siklus_ke         VARCHAR(60)  NULL,
  tanggal_panen     VARCHAR(40)  NULL,
  total_bobot_kg    DOUBLE NULL,
  total_biaya       DECIMAL(15,2) NULL,
  total_pendapatan  DECIMAL(15,2) NULL,
  catatan           TEXT NULL,
  extra_json        TEXT NULL,
  PRIMARY KEY (id),
  KEY idx_cycle_pond (pond_id, urutan),
  CONSTRAINT fk_cycle_pond FOREIGN KEY (pond_id) REFERENCES ponds(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Log pemberian pakan (rencana vs realisasi, gram)
CREATE TABLE pond_feed_logs (
  id          INT UNSIGNED NOT NULL AUTO_INCREMENT,
  pond_id     INT UNSIGNED NOT NULL,
  urutan      INT NOT NULL DEFAULT 0,
  tgl         VARCHAR(30)  NULL,
  rencana     DOUBLE NULL,
  realisasi   DOUBLE NULL,
  catatan     VARCHAR(255) NULL,
  extra_json  TEXT NULL,
  PRIMARY KEY (id),
  KEY idx_feed_pond (pond_id, urutan),
  CONSTRAINT fk_feed_pond FOREIGN KEY (pond_id) REFERENCES ponds(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Riwayat Cek Kondisi Kolam (pemeriksaan mandiri)
CREATE TABLE pond_self_checks (
  id          INT UNSIGNED NOT NULL AUTO_INCREMENT,
  pond_id     INT UNSIGNED NOT NULL,
  urutan      INT NOT NULL DEFAULT 0,
  waktu       VARCHAR(60) NULL,
  jenis       VARCHAR(60) NULL,
  level       VARCHAR(20) NULL,
  indikasi    TEXT NULL,
  extra_json  TEXT NULL,
  PRIMARY KEY (id),
  KEY idx_check_pond (pond_id, urutan),
  CONSTRAINT fk_check_pond FOREIGN KEY (pond_id) REFERENCES ponds(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Riwayat aksi kolam per akun (tambah / edit / hapus / duplikat)
CREATE TABLE pond_history (
  id          INT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id     INT UNSIGNED NOT NULL,
  urutan      INT NOT NULL DEFAULT 0,
  waktu       VARCHAR(60)  NULL,
  aksi        VARCHAR(40)  NULL,
  kolam       VARCHAR(120) NULL,
  keterangan  TEXT NULL,
  extra_json  TEXT NULL,
  PRIMARY KEY (id),
  KEY idx_hist_user (user_id, urutan),
  CONSTRAINT fk_hist_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- IoT: perangkat sensor (ESP32) & data pembacaannya
-- ---------------------------------------------------------------------
CREATE TABLE devices (
  id             INT UNSIGNED NOT NULL AUTO_INCREMENT,
  pond_id        INT UNSIGNED NOT NULL,
  nama           VARCHAR(100) NOT NULL DEFAULT 'ESP32',
  api_key_hash   CHAR(64)     NOT NULL COMMENT 'SHA2(api_key, 256)',
  aktif          TINYINT(1)   NOT NULL DEFAULT 1,
  terakhir_kirim DATETIME     NULL,
  dibuat         DATETIME     NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_device_key (api_key_hash),
  KEY idx_device_pond (pond_id),
  CONSTRAINT fk_device_pond FOREIGN KEY (pond_id) REFERENCES ponds(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE sensor_readings (
  id         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  pond_id    INT UNSIGNED NOT NULL,
  device_id  INT UNSIGNED NULL,
  waktu      DATETIME NOT NULL,
  suhu       DOUBLE NULL COMMENT '°C',
  ph         DOUBLE NULL,
  oksigen    DOUBLE NULL COMMENT 'DO, mg/L',
  keruh      DOUBLE NULL COMMENT 'NTU',
  amonia     DOUBLE NULL COMMENT 'mg/L',
  PRIMARY KEY (id),
  KEY idx_reading_pond_time (pond_id, waktu),
  CONSTRAINT fk_reading_pond   FOREIGN KEY (pond_id)   REFERENCES ponds(id)   ON DELETE CASCADE,
  CONSTRAINT fk_reading_device FOREIGN KEY (device_id) REFERENCES devices(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

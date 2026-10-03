-- =====================================================================
--  SMART AQUA AI — Skema Database (MySQL 5.7+ / MariaDB 10.3+)
--  Tim CAPCAY · Politeknik Negeri Manado
--  File LENGKAP: struktur tabel + 2 akun contoh. Impor lewat phpMyAdmin > Import.
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

-- ---------------------------------------------------------------------
-- DATA AWAL: 2 akun contoh (kata sandi: alo1234 / ikannilahitam)
--   Alo Airmadidi : Kolam Terpal 01-03 (Aman / Waspada / Kritis)
--   Tecno Polimdo : 5 kolam Polimdo (Koi, Nila Putih, Nila Hitam, Lele, Mas)
-- ---------------------------------------------------------------------
SET FOREIGN_KEY_CHECKS = 0;
INSERT INTO `users` (`id`, `nama`, `kelompok`, `telepon`, `password_hash`, `last_pond_id`, `gagal_login`, `terkunci_sampai`, `dibuat`, `diperbarui`) VALUES (1,'Alo Airmadidi','','','$2y$10$m3bAVSUDxIKaBkiMJ46qF.qmv7W4PWhcT6qrE9s1.dqBY9tTfI2Ia','p1',0,NULL,'2026-10-03 14:49:19','2026-10-03 14:49:19');
INSERT INTO `users` (`id`, `nama`, `kelompok`, `telepon`, `password_hash`, `last_pond_id`, `gagal_login`, `terkunci_sampai`, `dibuat`, `diperbarui`) VALUES (2,'Tecno Polimdo','','','$2y$10$O074Ggd7rFhpux2zyZxO7.zlhSQ0FJJRc4JCw1tjj3XaCOnr7MVte','p_mus0wqbn493',0,NULL,'2026-10-03 14:49:19','2026-10-03 14:49:19');
INSERT INTO `ponds` (`id`, `user_id`, `client_id`, `urutan`, `nama`, `jenis`, `lokasi`, `status`, `bentuk`, `panjang`, `lebar`, `diameter`, `tinggi`, `isi_air`, `jumlah`, `tanggal_tebar`, `tebar_hari`, `bobot_awal`, `bobot_sekarang`, `target_bobot`, `fcr`, `survival_rate`, `harga_bibit`, `harga_pakan_kg`, `harga_jual_kg`, `biaya_listrik`, `biaya_tenaga_kerja`, `biaya_lain`, `aerator_on`, `sensor_suhu`, `sensor_ph`, `sensor_do`, `sensor_keruh`, `sensor_amonia`, `sensor_waktu`, `terpal_usia_bulan`, `terpal_terakhir_dikuras_hari`, `terpal_ada_lipatan`, `pakan_takaran`, `pakan_jadwal`, `pakan_hemat`, `pakan_alasan`, `penyakit_level`, `penyakit_confidence`, `penyakit_indikasi`, `penyakit_saran`, `penyakit_sumber`, `trend_json`, `hist_long_json`, `growth_json`, `pengingat_json`, `extra_json`, `foto`, `dibuat`, `diperbarui`) VALUES (1,1,'p1',0,'Kolam Terpal 01','nila','Tetey, Minahasa Utara','aman',NULL,8,5,NULL,1.2,0.85,5000,NULL,42,8,238,300,1.3,0.91,900.00,12000.00,28000.00,2200000.00,1800000.00,900000.00,0,28.4,7.2,5.6,32,0.22,NULL,4,20,0,340,'07.00 & 16.00',18,'Sesuai fase pertumbuhan hari ke-42, suhu air stabil','rendah',0,NULL,NULL,'Sensor & pola konsumsi (otomatis)','{\"suhu\":[27.8,28,28.2,28.1,28.5,28.7,28.4],\"ph\":[7,7.05,7.1,7.05,7.15,7.2,7.18],\"do\":[6.2,6,5.9,5.7,5.8,5.7,5.6],\"keruh\":[24,26,25,29,31,33,32],\"amonia\":[0.15,0.16,0.18,0.17,0.19,0.2,0.22]}','{\"suhu\":[27.4,27.55,27.61,27.53,27.4,27.32,27.37,27.53,27.68,27.73,27.65,27.52,27.45,27.5,27.66,27.81,27.86,27.78,27.65,27.57,27.63,27.79,27.94,27.8,28,28.2,28.1,28.5,28.7,28.4],\"ph\":[6.95,7.07,7.1,7.02,6.89,6.81,6.85,6.97,7.09,7.12,7.04,6.9,6.83,6.86,6.99,7.11,7.13,7.05,6.92,6.84,6.88,7.01,7.12,7,7.05,7.1,7.05,7.15,7.2,7.18],\"do\":[6.5,6.62,6.64,6.53,6.37,6.27,6.29,6.41,6.52,6.54,6.43,6.27,6.17,6.19,6.31,6.43,6.44,6.33,6.18,6.08,6.1,6.22,6.34,6.2,6,5.9,5.7,5.8,5.7,5.6],\"keruh\":[20,20.49,20.74,20.71,20.55,20.53,20.79,21.28,21.76,22.01,21.98,21.82,21.8,22.07,22.56,23.04,23.29,23.25,23.09,23.07,23.34,23.84,24.32,24,26,25,29,31,33,32]}','[8,42,88,150,210,238]','[]',NULL,NULL,'2026-10-03 14:49:19','2026-10-03 14:49:19');
INSERT INTO `ponds` (`id`, `user_id`, `client_id`, `urutan`, `nama`, `jenis`, `lokasi`, `status`, `bentuk`, `panjang`, `lebar`, `diameter`, `tinggi`, `isi_air`, `jumlah`, `tanggal_tebar`, `tebar_hari`, `bobot_awal`, `bobot_sekarang`, `target_bobot`, `fcr`, `survival_rate`, `harga_bibit`, `harga_pakan_kg`, `harga_jual_kg`, `biaya_listrik`, `biaya_tenaga_kerja`, `biaya_lain`, `aerator_on`, `sensor_suhu`, `sensor_ph`, `sensor_do`, `sensor_keruh`, `sensor_amonia`, `sensor_waktu`, `terpal_usia_bulan`, `terpal_terakhir_dikuras_hari`, `terpal_ada_lipatan`, `pakan_takaran`, `pakan_jadwal`, `pakan_hemat`, `pakan_alasan`, `penyakit_level`, `penyakit_confidence`, `penyakit_indikasi`, `penyakit_saran`, `penyakit_sumber`, `trend_json`, `hist_long_json`, `growth_json`, `pengingat_json`, `extra_json`, `foto`, `dibuat`, `diperbarui`) VALUES (2,1,'p2',1,'Kolam Terpal 02','lele','Airmadidi, Minahasa Utara','waspada',NULL,6,4,NULL,1,0.7,8500,NULL,38,6,82,120,1.1,0.88,650.00,11000.00,22000.00,2600000.00,1800000.00,850000.00,1,29.6,7,3.1,58,0.78,NULL,9,45,1,410,'06.30 & 17.00',12,'Diturunkan karena DO di bawah ambang normal 2 hari terakhir','sedang',0.55,'Stres lingkungan akibat DO rendah','Tingkatkan aerasi & kurangi kepadatan sementara','Sensor & pola konsumsi (otomatis)','{\"suhu\":[28.8,29,29.2,29.3,29.5,29.6,29.6],\"ph\":[7.2,7.15,7.1,7.05,7,7,7],\"do\":[4.6,4.2,3.9,3.6,3.4,3.2,3.1],\"keruh\":[42,46,49,52,54,56,58],\"amonia\":[0.45,0.52,0.58,0.63,0.68,0.73,0.78]}','{\"suhu\":[27.2,27.47,27.59,27.52,27.38,27.32,27.45,27.71,27.98,28.09,28.03,27.89,27.83,27.96,28.23,28.49,28.6,28.53,28.39,28.34,28.47,28.74,29,28.8,29,29.2,29.3,29.5,29.6,29.6],\"ph\":[6.85,7,7.05,6.97,6.84,6.76,6.81,6.96,7.11,7.16,7.08,6.95,6.87,6.93,7.08,7.23,7.27,7.19,7.06,6.98,7.04,7.19,7.34,7.2,7.15,7.1,7.05,7,7,7],\"do\":[6.4,6.52,6.49,6.26,5.96,5.74,5.71,5.83,5.95,5.91,5.69,5.38,5.17,5.14,5.26,5.38,5.34,5.11,4.81,4.59,4.57,4.69,4.81,4.6,4.2,3.9,3.6,3.4,3.2,3.1],\"keruh\":[24,25.78,26.83,26.98,26.73,26.89,27.96,29.75,31.52,32.56,32.69,32.44,32.61,33.7,35.5,37.26,38.28,38.4,38.15,38.34,39.44,41.24,43,42,46,49,52,54,56,58]}','[6,28,48,64,74,82]','[]',NULL,NULL,'2026-10-03 14:49:19','2026-10-03 14:49:19');
INSERT INTO `ponds` (`id`, `user_id`, `client_id`, `urutan`, `nama`, `jenis`, `lokasi`, `status`, `bentuk`, `panjang`, `lebar`, `diameter`, `tinggi`, `isi_air`, `jumlah`, `tanggal_tebar`, `tebar_hari`, `bobot_awal`, `bobot_sekarang`, `target_bobot`, `fcr`, `survival_rate`, `harga_bibit`, `harga_pakan_kg`, `harga_jual_kg`, `biaya_listrik`, `biaya_tenaga_kerja`, `biaya_lain`, `aerator_on`, `sensor_suhu`, `sensor_ph`, `sensor_do`, `sensor_keruh`, `sensor_amonia`, `sensor_waktu`, `terpal_usia_bulan`, `terpal_terakhir_dikuras_hari`, `terpal_ada_lipatan`, `pakan_takaran`, `pakan_jadwal`, `pakan_hemat`, `pakan_alasan`, `penyakit_level`, `penyakit_confidence`, `penyakit_indikasi`, `penyakit_saran`, `penyakit_sumber`, `trend_json`, `hist_long_json`, `growth_json`, `pengingat_json`, `extra_json`, `foto`, `dibuat`, `diperbarui`) VALUES (3,1,'p3',2,'Kolam Terpal 03','mas','Kauditan, Minahasa Utara','kritis',NULL,5,4,NULL,1,0.9,3200,NULL,96,10,245,320,1.6,0.79,1100.00,12500.00,30000.00,2100000.00,1800000.00,1000000.00,0,31.8,9.1,1.8,92,1.35,NULL,14,70,1,0,'Ditunda',0,'Pakan dihentikan sementara — oksigen terlarut kritis, prioritaskan aerasi','tinggi',0.78,'Risiko jamur insang akibat oksigen kritis & amonia tinggi','Ganti air 30%, nyalakan aerator segera, puasakan pakan hari ini','Sensor & pola konsumsi (otomatis)','{\"suhu\":[29.5,30,30.4,30.9,31.2,31.5,31.8],\"ph\":[8.2,8.4,8.6,8.7,8.9,9,9.1],\"do\":[3.6,3.2,2.8,2.4,2.1,1.9,1.8],\"keruh\":[60,66,72,78,83,88,92],\"amonia\":[0.75,0.85,0.95,1.05,1.15,1.25,1.35]}','{\"suhu\":[26.3,26.71,26.92,26.88,26.73,26.69,26.91,27.32,27.74,27.94,27.9,27.74,27.71,27.93,28.35,28.76,28.96,28.91,28.76,28.73,28.95,29.37,29.78,29.5,30,30.4,30.9,31.2,31.5,31.8],\"ph\":[6.9,7.14,7.24,7.17,7.04,6.97,7.08,7.32,7.55,7.65,7.58,7.45,7.39,7.49,7.73,7.97,8.07,8,7.86,7.8,7.91,8.15,8.39,8.2,8.4,8.6,8.7,8.9,9,9.1],\"do\":[6.6,6.72,6.65,6.33,5.91,5.6,5.53,5.65,5.77,5.69,5.37,4.95,4.64,4.58,4.7,4.82,4.74,4.41,3.99,3.68,3.62,3.75,3.87,3.6,3.2,2.8,2.4,2.1,1.9,1.8],\"keruh\":[22,25.63,27.82,28.22,27.83,28.26,30.49,34.13,37.75,39.9,40.27,39.89,40.34,42.6,46.26,49.86,51.98,52.33,51.94,52.43,54.72,58.4,61.98,60,66,72,78,83,88,92]}','[10,60,120,175,215,245]','[]',NULL,NULL,'2026-10-03 14:49:19','2026-10-03 14:49:19');
INSERT INTO `ponds` (`id`, `user_id`, `client_id`, `urutan`, `nama`, `jenis`, `lokasi`, `status`, `bentuk`, `panjang`, `lebar`, `diameter`, `tinggi`, `isi_air`, `jumlah`, `tanggal_tebar`, `tebar_hari`, `bobot_awal`, `bobot_sekarang`, `target_bobot`, `fcr`, `survival_rate`, `harga_bibit`, `harga_pakan_kg`, `harga_jual_kg`, `biaya_listrik`, `biaya_tenaga_kerja`, `biaya_lain`, `aerator_on`, `sensor_suhu`, `sensor_ph`, `sensor_do`, `sensor_keruh`, `sensor_amonia`, `sensor_waktu`, `terpal_usia_bulan`, `terpal_terakhir_dikuras_hari`, `terpal_ada_lipatan`, `pakan_takaran`, `pakan_jadwal`, `pakan_hemat`, `pakan_alasan`, `penyakit_level`, `penyakit_confidence`, `penyakit_indikasi`, `penyakit_saran`, `penyakit_sumber`, `trend_json`, `hist_long_json`, `growth_json`, `pengingat_json`, `extra_json`, `foto`, `dibuat`, `diperbarui`) VALUES (4,2,'p_mus0wqbn493',0,'Kolam Koi','koi','Politeknik Negeri Manado, Kombos','aman','persegi',4,3,NULL,1,0.8,150,'2026-10-02',1,50,50,800,1.3,0.9,500.00,12000.00,25000.00,1500000.00,1500000.00,800000.00,0,24.91,7.72,6.38,3,0.03,NULL,1,3,0,0,'Belum ada jadwal',0,'Kolam baru — rekomendasi akan muncul setelah data terkumpul.','rendah',0,NULL,NULL,'Sensor & pola konsumsi (otomatis)','{\"suhu\":[25,25.09,25.12,25.05,24.95,24.88,24.91],\"ph\":[7.75,7.78,7.79,7.77,7.73,7.71,7.72],\"do\":[6.5,6.62,6.65,6.56,6.43,6.35,6.38],\"keruh\":[4,5,5,5,3,3,3],\"amonia\":[0.05,0.06,0.06,0.05,0.04,0.03,0.03]}','{\"suhu\":[25,25.12,25.15,25.06,24.93,24.85,24.88,25,25.12,25.15,25.06,24.93,24.85,24.89,25.01,25.12,25.14,25.06,24.93,24.85,24.89,25.01,25.12,25,25.09,25.12,25.05,24.95,24.88,24.91],\"ph\":[7.75,7.87,7.9,7.81,7.68,7.6,7.63,7.75,7.87,7.9,7.81,7.68,7.6,7.64,7.76,7.87,7.89,7.81,7.68,7.6,7.64,7.76,7.87,7.75,7.78,7.79,7.77,7.73,7.71,7.72],\"do\":[6.5,6.62,6.65,6.56,6.43,6.35,6.38,6.5,6.62,6.65,6.56,6.43,6.35,6.39,6.51,6.62,6.64,6.56,6.43,6.35,6.39,6.51,6.62,6.5,6.62,6.65,6.56,6.43,6.35,6.38],\"keruh\":[4,4.12,4.15,4.06,3.93,3.85,3.88,4,4.12,4.15,4.06,3.93,3.85,3.89,4.01,4.12,4.14,4.06,3.93,3.85,3.89,4.01,4.12,4,5,5,5,3,3,3]}','[50]','[]',NULL,NULL,'2026-10-03 14:49:19','2026-10-03 14:49:19');
INSERT INTO `ponds` (`id`, `user_id`, `client_id`, `urutan`, `nama`, `jenis`, `lokasi`, `status`, `bentuk`, `panjang`, `lebar`, `diameter`, `tinggi`, `isi_air`, `jumlah`, `tanggal_tebar`, `tebar_hari`, `bobot_awal`, `bobot_sekarang`, `target_bobot`, `fcr`, `survival_rate`, `harga_bibit`, `harga_pakan_kg`, `harga_jual_kg`, `biaya_listrik`, `biaya_tenaga_kerja`, `biaya_lain`, `aerator_on`, `sensor_suhu`, `sensor_ph`, `sensor_do`, `sensor_keruh`, `sensor_amonia`, `sensor_waktu`, `terpal_usia_bulan`, `terpal_terakhir_dikuras_hari`, `terpal_ada_lipatan`, `pakan_takaran`, `pakan_jadwal`, `pakan_hemat`, `pakan_alasan`, `penyakit_level`, `penyakit_confidence`, `penyakit_indikasi`, `penyakit_saran`, `penyakit_sumber`, `trend_json`, `hist_long_json`, `growth_json`, `pengingat_json`, `extra_json`, `foto`, `dibuat`, `diperbarui`) VALUES (5,2,'p_mus0wqbn331',1,'Kolam Nila Putih','nila_putih','Politeknik Negeri Manado, Kombos','aman','persegi',6,4,NULL,1,0.8,2000,'2026-10-02',1,8,8,300,1.3,0.9,500.00,12000.00,25000.00,1500000.00,1500000.00,800000.00,0,28.41,7.47,5.88,7,0.06,NULL,1,3,0,0,'Belum ada jadwal',0,'Kolam baru — rekomendasi akan muncul setelah data terkumpul.','rendah',0,NULL,NULL,'Sensor & pola konsumsi (otomatis)','{\"suhu\":[28.5,28.59,28.62,28.55,28.45,28.38,28.41],\"ph\":[7.5,7.53,7.54,7.52,7.48,7.46,7.47],\"do\":[6,6.12,6.15,6.06,5.93,5.85,5.88],\"keruh\":[8,9,9,9,7,7,7],\"amonia\":[0.08,0.09,0.09,0.08,0.07,0.06,0.06]}','{\"suhu\":[28.5,28.62,28.65,28.56,28.43,28.35,28.38,28.5,28.62,28.65,28.56,28.43,28.35,28.39,28.51,28.62,28.64,28.56,28.43,28.35,28.39,28.51,28.62,28.5,28.59,28.62,28.55,28.45,28.38,28.41],\"ph\":[7.5,7.62,7.65,7.56,7.43,7.35,7.38,7.5,7.62,7.65,7.56,7.43,7.35,7.39,7.51,7.62,7.64,7.56,7.43,7.35,7.39,7.51,7.62,7.5,7.53,7.54,7.52,7.48,7.46,7.47],\"do\":[6,6.12,6.15,6.06,5.93,5.85,5.88,6,6.12,6.15,6.06,5.93,5.85,5.89,6.01,6.12,6.14,6.06,5.93,5.85,5.89,6.01,6.12,6,6.12,6.15,6.06,5.93,5.85,5.88],\"keruh\":[8,8.12,8.15,8.06,7.93,7.85,7.88,8,8.12,8.15,8.06,7.93,7.85,7.89,8.01,8.12,8.14,8.06,7.93,7.85,7.89,8.01,8.12,8,9,9,9,7,7,7]}','[8]','[]',NULL,NULL,'2026-10-03 14:49:19','2026-10-03 14:49:19');
INSERT INTO `ponds` (`id`, `user_id`, `client_id`, `urutan`, `nama`, `jenis`, `lokasi`, `status`, `bentuk`, `panjang`, `lebar`, `diameter`, `tinggi`, `isi_air`, `jumlah`, `tanggal_tebar`, `tebar_hari`, `bobot_awal`, `bobot_sekarang`, `target_bobot`, `fcr`, `survival_rate`, `harga_bibit`, `harga_pakan_kg`, `harga_jual_kg`, `biaya_listrik`, `biaya_tenaga_kerja`, `biaya_lain`, `aerator_on`, `sensor_suhu`, `sensor_ph`, `sensor_do`, `sensor_keruh`, `sensor_amonia`, `sensor_waktu`, `terpal_usia_bulan`, `terpal_terakhir_dikuras_hari`, `terpal_ada_lipatan`, `pakan_takaran`, `pakan_jadwal`, `pakan_hemat`, `pakan_alasan`, `penyakit_level`, `penyakit_confidence`, `penyakit_indikasi`, `penyakit_saran`, `penyakit_sumber`, `trend_json`, `hist_long_json`, `growth_json`, `pengingat_json`, `extra_json`, `foto`, `dibuat`, `diperbarui`) VALUES (6,2,'p_mus0wqbn306',2,'Kolam Nila Hitam','nila_hitam','Politeknik Negeri Manado, Kombos','aman','persegi',6,4,NULL,1,0.8,2000,'2026-10-02',1,8,8,300,1.3,0.9,500.00,12000.00,25000.00,1500000.00,1500000.00,800000.00,0,28.41,7.47,5.88,7,0.06,NULL,1,3,0,0,'Belum ada jadwal',0,'Kolam baru — rekomendasi akan muncul setelah data terkumpul.','rendah',0,NULL,NULL,'Sensor & pola konsumsi (otomatis)','{\"suhu\":[28.5,28.59,28.62,28.55,28.45,28.38,28.41],\"ph\":[7.5,7.53,7.54,7.52,7.48,7.46,7.47],\"do\":[6,6.12,6.15,6.06,5.93,5.85,5.88],\"keruh\":[8,9,9,9,7,7,7],\"amonia\":[0.08,0.09,0.09,0.08,0.07,0.06,0.06]}','{\"suhu\":[28.5,28.62,28.65,28.56,28.43,28.35,28.38,28.5,28.62,28.65,28.56,28.43,28.35,28.39,28.51,28.62,28.64,28.56,28.43,28.35,28.39,28.51,28.62,28.5,28.59,28.62,28.55,28.45,28.38,28.41],\"ph\":[7.5,7.62,7.65,7.56,7.43,7.35,7.38,7.5,7.62,7.65,7.56,7.43,7.35,7.39,7.51,7.62,7.64,7.56,7.43,7.35,7.39,7.51,7.62,7.5,7.53,7.54,7.52,7.48,7.46,7.47],\"do\":[6,6.12,6.15,6.06,5.93,5.85,5.88,6,6.12,6.15,6.06,5.93,5.85,5.89,6.01,6.12,6.14,6.06,5.93,5.85,5.89,6.01,6.12,6,6.12,6.15,6.06,5.93,5.85,5.88],\"keruh\":[8,8.12,8.15,8.06,7.93,7.85,7.88,8,8.12,8.15,8.06,7.93,7.85,7.89,8.01,8.12,8.14,8.06,7.93,7.85,7.89,8.01,8.12,8,9,9,9,7,7,7]}','[8]','[]',NULL,NULL,'2026-10-03 14:49:19','2026-10-03 14:49:19');
INSERT INTO `ponds` (`id`, `user_id`, `client_id`, `urutan`, `nama`, `jenis`, `lokasi`, `status`, `bentuk`, `panjang`, `lebar`, `diameter`, `tinggi`, `isi_air`, `jumlah`, `tanggal_tebar`, `tebar_hari`, `bobot_awal`, `bobot_sekarang`, `target_bobot`, `fcr`, `survival_rate`, `harga_bibit`, `harga_pakan_kg`, `harga_jual_kg`, `biaya_listrik`, `biaya_tenaga_kerja`, `biaya_lain`, `aerator_on`, `sensor_suhu`, `sensor_ph`, `sensor_do`, `sensor_keruh`, `sensor_amonia`, `sensor_waktu`, `terpal_usia_bulan`, `terpal_terakhir_dikuras_hari`, `terpal_ada_lipatan`, `pakan_takaran`, `pakan_jadwal`, `pakan_hemat`, `pakan_alasan`, `penyakit_level`, `penyakit_confidence`, `penyakit_indikasi`, `penyakit_saran`, `penyakit_sumber`, `trend_json`, `hist_long_json`, `growth_json`, `pengingat_json`, `extra_json`, `foto`, `dibuat`, `diperbarui`) VALUES (7,2,'p_mus0wqbn153',3,'Kolam Lele','lele','Politeknik Negeri Manado, Kombos','aman','persegi',5,3,NULL,1,0.8,3000,'2026-10-02',1,5,5,120,1.3,0.9,500.00,12000.00,25000.00,1500000.00,1500000.00,800000.00,0,27.91,7.22,4.13,15,0.13,NULL,1,3,0,0,'Belum ada jadwal',0,'Kolam baru — rekomendasi akan muncul setelah data terkumpul.','rendah',0,NULL,NULL,'Sensor & pola konsumsi (otomatis)','{\"suhu\":[28,28.09,28.12,28.05,27.95,27.88,27.91],\"ph\":[7.25,7.28,7.29,7.27,7.23,7.21,7.22],\"do\":[4.25,4.37,4.4,4.31,4.18,4.1,4.13],\"keruh\":[16,17,17,17,15,15,15],\"amonia\":[0.15,0.17,0.17,0.16,0.14,0.13,0.13]}','{\"suhu\":[28,28.12,28.15,28.06,27.93,27.85,27.88,28,28.12,28.15,28.06,27.93,27.85,27.89,28.01,28.12,28.14,28.06,27.93,27.85,27.89,28.01,28.12,28,28.09,28.12,28.05,27.95,27.88,27.91],\"ph\":[7.25,7.37,7.4,7.31,7.18,7.1,7.13,7.25,7.37,7.4,7.31,7.18,7.1,7.14,7.26,7.37,7.39,7.31,7.18,7.1,7.14,7.26,7.37,7.25,7.28,7.29,7.27,7.23,7.21,7.22],\"do\":[4.25,4.37,4.4,4.31,4.18,4.1,4.13,4.25,4.37,4.4,4.31,4.18,4.1,4.14,4.26,4.37,4.39,4.31,4.18,4.1,4.14,4.26,4.37,4.25,4.37,4.4,4.31,4.18,4.1,4.13],\"keruh\":[16,16.12,16.15,16.06,15.93,15.85,15.88,16,16.12,16.15,16.06,15.93,15.85,15.89,16.01,16.12,16.14,16.06,15.93,15.85,15.89,16.01,16.12,16,17,17,17,15,15,15]}','[5]','[]',NULL,NULL,'2026-10-03 14:49:19','2026-10-03 14:49:19');
INSERT INTO `ponds` (`id`, `user_id`, `client_id`, `urutan`, `nama`, `jenis`, `lokasi`, `status`, `bentuk`, `panjang`, `lebar`, `diameter`, `tinggi`, `isi_air`, `jumlah`, `tanggal_tebar`, `tebar_hari`, `bobot_awal`, `bobot_sekarang`, `target_bobot`, `fcr`, `survival_rate`, `harga_bibit`, `harga_pakan_kg`, `harga_jual_kg`, `biaya_listrik`, `biaya_tenaga_kerja`, `biaya_lain`, `aerator_on`, `sensor_suhu`, `sensor_ph`, `sensor_do`, `sensor_keruh`, `sensor_amonia`, `sensor_waktu`, `terpal_usia_bulan`, `terpal_terakhir_dikuras_hari`, `terpal_ada_lipatan`, `pakan_takaran`, `pakan_jadwal`, `pakan_hemat`, `pakan_alasan`, `penyakit_level`, `penyakit_confidence`, `penyakit_indikasi`, `penyakit_saran`, `penyakit_sumber`, `trend_json`, `hist_long_json`, `growth_json`, `pengingat_json`, `extra_json`, `foto`, `dibuat`, `diperbarui`) VALUES (8,2,'p_mus0wqbn78',4,'Kolam Ikan Mas','mas','Politeknik Negeri Manado, Kombos','aman','persegi',5,4,NULL,1,0.8,1500,'2026-10-02',1,10,10,250,1.3,0.9,500.00,12000.00,25000.00,1500000.00,1500000.00,800000.00,0,25.91,7.22,5.88,6,0.04,NULL,1,3,0,0,'Belum ada jadwal',0,'Kolam baru — rekomendasi akan muncul setelah data terkumpul.','rendah',0,NULL,NULL,'Sensor & pola konsumsi (otomatis)','{\"suhu\":[26,26.09,26.12,26.05,25.95,25.88,25.91],\"ph\":[7.25,7.28,7.29,7.27,7.23,7.21,7.22],\"do\":[6,6.12,6.15,6.06,5.93,5.85,5.88],\"keruh\":[7,8,8,8,6,6,6],\"amonia\":[0.06,0.08,0.08,0.07,0.05,0.04,0.04]}','{\"suhu\":[26,26.12,26.15,26.06,25.93,25.85,25.88,26,26.12,26.15,26.06,25.93,25.85,25.89,26.01,26.12,26.14,26.06,25.93,25.85,25.89,26.01,26.12,26,26.09,26.12,26.05,25.95,25.88,25.91],\"ph\":[7.25,7.37,7.4,7.31,7.18,7.1,7.13,7.25,7.37,7.4,7.31,7.18,7.1,7.14,7.26,7.37,7.39,7.31,7.18,7.1,7.14,7.26,7.37,7.25,7.28,7.29,7.27,7.23,7.21,7.22],\"do\":[6,6.12,6.15,6.06,5.93,5.85,5.88,6,6.12,6.15,6.06,5.93,5.85,5.89,6.01,6.12,6.14,6.06,5.93,5.85,5.89,6.01,6.12,6,6.12,6.15,6.06,5.93,5.85,5.88],\"keruh\":[7,7.12,7.15,7.06,6.93,6.85,6.88,7,7.12,7.15,7.06,6.93,6.85,6.89,7.01,7.12,7.14,7.06,6.93,6.85,6.89,7.01,7.12,7,8,8,8,6,6,6]}','[10]','[]',NULL,NULL,'2026-10-03 14:49:19','2026-10-03 14:49:19');
INSERT INTO `pond_cash` (`id`, `pond_id`, `urutan`, `tanggal`, `tipe`, `jumlah`, `keterangan`, `extra_json`) VALUES (1,1,0,'28 Agu','keluar',350000.00,'Servis aerator',NULL);
INSERT INTO `pond_cash` (`id`, `pond_id`, `urutan`, `tanggal`, `tipe`, `jumlah`, `keterangan`, `extra_json`) VALUES (2,1,1,'15 Agu','masuk',500000.00,'Jual bibit sisa ke tetangga',NULL);
INSERT INTO `pond_cash` (`id`, `pond_id`, `urutan`, `tanggal`, `tipe`, `jumlah`, `keterangan`, `extra_json`) VALUES (3,2,0,'25 Agu','keluar',280000.00,'Beli kapur & garam ikan',NULL);
INSERT INTO `pond_cycles` (`id`, `pond_id`, `urutan`, `siklus_ke`, `tanggal_panen`, `total_bobot_kg`, `total_biaya`, `total_pendapatan`, `catatan`, `extra_json`) VALUES (1,1,0,'Siklus sebelumnya','20 Mei 2026',980,15200000.00,24500000.00,'Panen nila, kualitas air stabil sepanjang siklus',NULL);
INSERT INTO `pond_cycles` (`id`, `pond_id`, `urutan`, `siklus_ke`, `tanggal_panen`, `total_bobot_kg`, `total_biaya`, `total_pendapatan`, `catatan`, `extra_json`) VALUES (2,2,0,'Siklus sebelumnya','02 Jul 2026',610,9800000.00,12400000.00,'FCR sedikit tinggi karena DO sempat turun',NULL);
INSERT INTO `pond_cycles` (`id`, `pond_id`, `urutan`, `siklus_ke`, `tanggal_panen`, `total_bobot_kg`, `total_biaya`, `total_pendapatan`, `catatan`, `extra_json`) VALUES (3,3,0,'Siklus sebelumnya','15 Apr 2026',520,11000000.00,13600000.00,'Sempat ada kematian akibat kualitas air menurun',NULL);
INSERT INTO `pond_feed_logs` (`id`, `pond_id`, `urutan`, `tgl`, `rencana`, `realisasi`, `catatan`, `extra_json`) VALUES (1,1,0,'02 Sep',340,335,'Sesuai',NULL);
INSERT INTO `pond_feed_logs` (`id`, `pond_id`, `urutan`, `tgl`, `rencana`, `realisasi`, `catatan`, `extra_json`) VALUES (2,1,1,'01 Sep',335,335,'Sesuai',NULL);
INSERT INTO `pond_feed_logs` (`id`, `pond_id`, `urutan`, `tgl`, `rencana`, `realisasi`, `catatan`, `extra_json`) VALUES (3,1,2,'31 Agu',330,300,'Kurang — nafsu makan turun',NULL);
INSERT INTO `pond_feed_logs` (`id`, `pond_id`, `urutan`, `tgl`, `rencana`, `realisasi`, `catatan`, `extra_json`) VALUES (4,1,3,'30 Agu',325,325,'Sesuai',NULL);
INSERT INTO `pond_feed_logs` (`id`, `pond_id`, `urutan`, `tgl`, `rencana`, `realisasi`, `catatan`, `extra_json`) VALUES (5,2,0,'02 Sep',410,390,'Kurang — kualitas air menurun',NULL);
INSERT INTO `pond_feed_logs` (`id`, `pond_id`, `urutan`, `tgl`, `rencana`, `realisasi`, `catatan`, `extra_json`) VALUES (6,2,1,'01 Sep',420,420,'Sesuai',NULL);
INSERT INTO `pond_feed_logs` (`id`, `pond_id`, `urutan`, `tgl`, `rencana`, `realisasi`, `catatan`, `extra_json`) VALUES (7,2,2,'31 Agu',420,415,'Sesuai',NULL);
INSERT INTO `pond_feed_logs` (`id`, `pond_id`, `urutan`, `tgl`, `rencana`, `realisasi`, `catatan`, `extra_json`) VALUES (8,3,0,'02 Sep',0,0,'Ditunda — kondisi kritis',NULL);
INSERT INTO `pond_feed_logs` (`id`, `pond_id`, `urutan`, `tgl`, `rencana`, `realisasi`, `catatan`, `extra_json`) VALUES (9,3,1,'01 Sep',260,180,'Kurang — nafsu makan turun drastis',NULL);
INSERT INTO `pond_feed_logs` (`id`, `pond_id`, `urutan`, `tgl`, `rencana`, `realisasi`, `catatan`, `extra_json`) VALUES (10,3,2,'31 Agu',270,260,'Sesuai',NULL);
INSERT INTO `pond_self_checks` (`id`, `pond_id`, `urutan`, `waktu`, `jenis`, `level`, `indikasi`, `extra_json`) VALUES (1,1,0,'Kemarin, 08.15','nila','rendah','Tidak ada indikasi risiko berarti dari hasil pemeriksaan mandiri',NULL);
INSERT INTO `pond_self_checks` (`id`, `pond_id`, `urutan`, `waktu`, `jenis`, `level`, `indikasi`, `extra_json`) VALUES (2,2,0,'Hari ini, 06.40','lele','sedang','Indikasi risiko sedang — sebagian ikan megap-megap di permukaan dan nafsu makan sedikit menurun',NULL);
INSERT INTO `pond_self_checks` (`id`, `pond_id`, `urutan`, `waktu`, `jenis`, `level`, `indikasi`, `extra_json`) VALUES (3,2,1,'2 hari lalu, 07.10','lele','rendah','Tidak ada indikasi risiko berarti dari hasil pemeriksaan mandiri',NULL);
INSERT INTO `pond_self_checks` (`id`, `pond_id`, `urutan`, `waktu`, `jenis`, `level`, `indikasi`, `extra_json`) VALUES (4,3,0,'Hari ini, 05.55','mas','tinggi','Indikasi risiko tinggi — warna air kehitaman dan air berbau busuk (indikasi H2S/anaerobik)',NULL);
INSERT INTO `pond_self_checks` (`id`, `pond_id`, `urutan`, `waktu`, `jenis`, `level`, `indikasi`, `extra_json`) VALUES (5,3,1,'Kemarin, 18.20','mas','sedang','Indikasi risiko sedang — kekeruhan air tinggi',NULL);
INSERT INTO `species_thresholds` (`user_id`, `kode`, `label`, `suhu_min`, `suhu_max`, `ph_min`, `ph_max`, `do_min`, `do_max`, `amonia_min`, `amonia_max`, `keruh_min`, `keruh_max`) VALUES (1,'koi','Ikan Koi',22,28,7,8.5,5,8,0,0.3,0,20);
INSERT INTO `species_thresholds` (`user_id`, `kode`, `label`, `suhu_min`, `suhu_max`, `ph_min`, `ph_max`, `do_min`, `do_max`, `amonia_min`, `amonia_max`, `keruh_min`, `keruh_max`) VALUES (1,'lele','Ikan Lele',26,30,6.5,8,2.5,6,0,1,0,80);
INSERT INTO `species_thresholds` (`user_id`, `kode`, `label`, `suhu_min`, `suhu_max`, `ph_min`, `ph_max`, `do_min`, `do_max`, `amonia_min`, `amonia_max`, `keruh_min`, `keruh_max`) VALUES (1,'mas','Ikan Mas',24,28,6.5,8,4,8,0,0.4,0,35);
INSERT INTO `species_thresholds` (`user_id`, `kode`, `label`, `suhu_min`, `suhu_max`, `ph_min`, `ph_max`, `do_min`, `do_max`, `amonia_min`, `amonia_max`, `keruh_min`, `keruh_max`) VALUES (1,'nila','Ikan Nila',27,30,6.5,8.5,4,8,0,0.5,0,40);
INSERT INTO `species_thresholds` (`user_id`, `kode`, `label`, `suhu_min`, `suhu_max`, `ph_min`, `ph_max`, `do_min`, `do_max`, `amonia_min`, `amonia_max`, `keruh_min`, `keruh_max`) VALUES (1,'nila_hitam','Nila Hitam',27,30,6.5,8.5,4,8,0,0.5,0,40);
INSERT INTO `species_thresholds` (`user_id`, `kode`, `label`, `suhu_min`, `suhu_max`, `ph_min`, `ph_max`, `do_min`, `do_max`, `amonia_min`, `amonia_max`, `keruh_min`, `keruh_max`) VALUES (1,'nila_putih','Nila Putih',27,30,6.5,8.5,4,8,0,0.5,0,40);
INSERT INTO `species_thresholds` (`user_id`, `kode`, `label`, `suhu_min`, `suhu_max`, `ph_min`, `ph_max`, `do_min`, `do_max`, `amonia_min`, `amonia_max`, `keruh_min`, `keruh_max`) VALUES (2,'koi','Ikan Koi',22,28,7,8.5,5,8,0,0.3,0,20);
INSERT INTO `species_thresholds` (`user_id`, `kode`, `label`, `suhu_min`, `suhu_max`, `ph_min`, `ph_max`, `do_min`, `do_max`, `amonia_min`, `amonia_max`, `keruh_min`, `keruh_max`) VALUES (2,'lele','Ikan Lele',26,30,6.5,8,2.5,6,0,1,0,80);
INSERT INTO `species_thresholds` (`user_id`, `kode`, `label`, `suhu_min`, `suhu_max`, `ph_min`, `ph_max`, `do_min`, `do_max`, `amonia_min`, `amonia_max`, `keruh_min`, `keruh_max`) VALUES (2,'mas','Ikan Mas',24,28,6.5,8,4,8,0,0.4,0,35);
INSERT INTO `species_thresholds` (`user_id`, `kode`, `label`, `suhu_min`, `suhu_max`, `ph_min`, `ph_max`, `do_min`, `do_max`, `amonia_min`, `amonia_max`, `keruh_min`, `keruh_max`) VALUES (2,'nila','Ikan Nila',27,30,6.5,8.5,4,8,0,0.5,0,40);
INSERT INTO `species_thresholds` (`user_id`, `kode`, `label`, `suhu_min`, `suhu_max`, `ph_min`, `ph_max`, `do_min`, `do_max`, `amonia_min`, `amonia_max`, `keruh_min`, `keruh_max`) VALUES (2,'nila_hitam','Nila Hitam',27,30,6.5,8.5,4,8,0,0.5,0,40);
INSERT INTO `species_thresholds` (`user_id`, `kode`, `label`, `suhu_min`, `suhu_max`, `ph_min`, `ph_max`, `do_min`, `do_max`, `amonia_min`, `amonia_max`, `keruh_min`, `keruh_max`) VALUES (2,'nila_putih','Nila Putih',27,30,6.5,8.5,4,8,0,0.5,0,40);
SET FOREIGN_KEY_CHECKS = 1;

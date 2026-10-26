# Fondasi Penyimpanan Lokal Absensi (Tahap 1A)

Dokumen ini menjelaskan fondasi offline dan sinkronisasi foreground yang sudah
ditambahkan. Submit absensi sekarang menyimpan event ke antrean lokal lebih dulu,
lalu menjalankan worker sinkronisasi. Login offline, AuthGate, logout, beranda,
dan riwayat belum diubah. Tidak ada worker latar belakang; sinkronisasi hanya
dipicu oleh alur yang sedang berjalan di foreground.

## Lokasi data

Semua data berada di penyimpanan privat aplikasi Android.

| Data | Lokasi Android | Keterangan |
|---|---|---|
| Database antrean | `databases/attendance_outbox.db` | Nama file: `attendance_outbox.db` |
| Foto selfie | `files/attendance_outbox/<nama-file>.jpg` | Hanya nama file relatif yang disimpan di SQLite |
| Profil user terakhir | Secure Storage, key `aaj_cached_user_v1` | JSON profil, tanpa password/token |

`getApplicationSupportDirectory()` di Android menunjuk ke `filesDir`, sehingga
foto berada di `files/attendance_outbox`. SQLite hanya menyimpan
`photo_filename`, bukan path absolut dan bukan BLOB.

## Tabel `attendance_outbox`

`client_event_id` adalah PRIMARY KEY dan selalu berasal dari pemanggil. Kode
penyimpanan tidak membuat UUID baru.

Kolom utama:

- `client_event_id`, `owner_user_id`, `employee_id`, `device_uuid`
- `event_type`, `event_at`, `captured_at`
- `latitude`, `longitude`, `accuracy_meters`
- `photo_filename`
- `local_sequence`: urutan masuk lokal yang monoton dan unik
- `state`: `pending`, `syncing`, `synced`, `rejected`
- `attempt_count`, `next_attempt_at`, `sync_started_at`
- `last_error_code`, `last_error_message`
- `server_event_id`, `server_status`, `server_received_at`
- `created_at`, `updated_at`, `synced_at`

Aturan database:

- Query antrean selalu difilter dengan `owner_user_id`.
- FIFO memakai `local_sequence`. `event_at` hanya data bisnis dan tidak dipakai
  untuk menentukan urutan kirim.
- `local_sequence` diambil dari tabel `attendance_outbox_sequence` di dalam
  transaksi insert, sehingga dua event tidak mendapat nomor yang sama.
- Semua timestamp disimpan dalam UTC dengan format tetap enam digit mikrodetik,
  sehingga perbandingan teks antarwaktu konsisten.
- Event baru selalu masuk sebagai `pending` dengan `attempt_count = 0`.
- Event milik user lain tidak boleh dibaca atau diubah sebagai milik user aktif.
- Logout tidak menghapus antrean. Penghapusan antrean bukan bagian dari tahap
  ini.

## Siklus state

Transisi yang diizinkan:

- `pending` -> `syncing` lewat `claimNextForEmployee`
- `syncing` -> `synced` lewat `markSynced`
- `syncing` -> `pending` lewat `releaseForRetry`
- `syncing` -> `rejected` lewat `markRejected`
- `syncing` yang lease-nya kedaluwarsa -> `pending` lewat `recoverStaleClaims`

`claimNextForEmployee` memakai transaksi dan update bersyarat. Klaim hanya
berhasil bila event terdepan untuk employee tersebut masih `pending`. Bila event
terdepan sedang `syncing` atau `rejected`, klaim mengembalikan `null` agar event
setelahnya tidak menyalip. `attempt_count` naik tepat satu kali saat klaim.

`recoverStaleClaims` mengembalikan klaim yang melewati batas waktu ke `pending`,
mengosongkan `sync_started_at`, mengisi `next_attempt_at`, dan mencatat
`SYNC_LEASE_EXPIRED`. Dengan begitu proses yang berhenti di tengah jalan dapat
dipulihkan tanpa kehilangan event.

## Alur submit dan worker sinkronisasi

Urutan submit saat ini:

1. Validasi sesi harus terautentikasi dan memiliki employee.
2. Ambil GPS dan selfie.
3. Buat satu `client_event_id` baru dan `event_at` sekali.
4. Simpan foto dan event ke antrean lokal (`pending`) sebelum menyentuh jaringan.
5. Jalankan worker foreground untuk employee tersebut.
6. Tampilkan sukses hanya bila server memberi ack valid untuk event tersebut.

Worker memakai API state machine Tahap 1A, bukan SQL langsung dari controller:

- hanya satu event terdepan per employee yang diklaim pada satu waktu;
- urutan kirim selalu `local_sequence` (FIFO), bukan waktu event;
- event `syncing`/`rejected` di depan tidak boleh disalip event yang lebih baru;
- `recoverStaleClaims` dijalankan sebelum klaim untuk memulihkan lease kedaluwarsa;
- dua pemicu bersamaan untuk employee yang sama diserialisasi di proses ini;
- kegagalan satu employee tidak menghentikan employee lain;
- retry memakai `client_event_id`, `event_at`, GPS, `captured_at`, `device_uuid`,
  dan foto yang sama, sehingga backend menganggapnya idempotent.

Respons sukses harus `200` (replay) atau `201` (baru) dengan body event valid yang
`client_event_id` dan `event_type`-nya cocok. HTTP sukses tanpa body valid tidak
dianggap ack. Setelah ack valid, `markSynced` menyimpan id/status/waktu server
lebih dulu, baru foto lokal dihapus. Baris `synced` tetap disimpan untuk retensi
dan dapat dibersihkan lewat purge.

Klasifikasi kegagalan:

- retryable: network/timeout, `408`, `429`, `5xx`, body respons tidak valid;
- authentication: `401` atau sesi tidak aktif; antrean tidak dihapus dan tidak
  ditolak, worker berhenti sampai sesi valid kembali;
- permanent rejection: kode backend seperti `OUTSIDE_GEOFENCE`,
  `LOCATION_LOW_ACCURACY`, `ALREADY_CHECKED_IN`, `CHECK_IN_REQUIRED`,
  `ALREADY_CHECKED_OUT`, `DEVICE_REVOKED`, `ATTENDANCE_EVENT_CONFLICT`,
  `BRANCH_NOT_CONFIGURED`, `BRANCH_LOCATION_NOT_CONFIGURED`, dan
  `VALIDATION_ERROR`;
- user action: `DEVICE_NOT_FOUND`, `EMPLOYEE_REQUIRED`, dan 4xx tak dikenal yang
  tidak boleh otomatis dianggap penolakan permanen.

Backoff eksponensial dimulai dari 30 detik dan dibatasi 30 menit. `Retry-After`
dari server dipakai bila ada dan dibatasi maksimum 12 jam, kecuali `401` yang
langsung berhenti tanpa menunggu. Event `rejected` tetap berada di antrean dan
memblokir event yang lebih baru untuk employee tersebut agar urutan tidak rusak.

## Migrasi skema

Versi skema saat ini adalah 2. Skema versi 1 tidak memiliki `local_sequence` dan
`sync_started_at`. Migrasi 1 -> 2:

- menyalin seluruh baris lama tanpa menghapus data,
- mengisi `local_sequence` berdasarkan `rowid` lama (urutan insert),
- menormalkan timestamp lama ke format UTC yang baru,
- mempertahankan state, attempt, error, dan data server yang sudah ada,
- melanjutkan sequence setelah nomor terakhir.

Tidak ada drop-and-recreate otomatis. Database tidak dihapus saat upgrade.
Downgrade skema ditolak.

## Foto selfie

- Ditulis ke direktori privat aplikasi, bukan direktori publik.
- Format yang diterima: JPEG, PNG, dan WebP, sesuai `mime_types` backend.
- Ukuran maksimum: 5 MB (5120 KB), sesuai `ATTENDANCE_PHOTO_MAX_KB` backend.
- Penulisan memakai file sementara `.<nama-file>.tmp`, `flush`, lalu `rename`
  atomik ke nama final.
- Nama file final memakai `client_event_id`, timestamp mikrodetik, dan nonce
  acak. Dua penulisan tidak saling menimpa.
- Jika insert database gagal, file baru hasil penulisan tersebut dihapus hanya
  bila tidak direferensikan baris lain.
- Nama file divalidasi sama di store dan photo storage: tanpa path segment,
  tanpa `..`, dan bukan file `.tmp`.
- Pembersihan file yatim hanya menghapus file yang tidak direferensikan oleh
  antrean. Pemeriksaan referensi diulang sesaat sebelum menghapus, dan kegagalan
  I/O tidak boleh menghapus file yang masih dirujuk.
- File sementara dan file yatim hanya dihapus setelah berumur lebih dari satu
  jam. Ini mencegah pembersihan bertabrakan dengan penulisan yang sedang
  berjalan.

Pembersihan dan pemanggilan pembersihan saat startup akan dilakukan pada tahap
integrasi berikutnya, setelah koordinasi sinkronisasi tersedia.

## Retensi

`purgeAcknowledgedBefore` hanya menghapus event `synced` milik owner yang
diminta dan sudah tersinkron sebelum cutoff. Event `pending`, `syncing`, dan
`rejected` tidak ikut dihapus, begitu juga event milik user lain.

Penghapusan baris dilakukan lebih dulu. Setelah itu foto dihapus hanya bila
sudah tidak direferensikan baris mana pun. Bila penghapusan file gagal, file
tertinggal sebagai orphan dan dapat dibersihkan pada pemanggilan berikutnya.
Tidak ada pemanggilan purge otomatis pada tahap ini.

## Profil user offline

`SecureCachedUserStore` menyimpan `User.toJson()` di Secure Storage. Profil ini
hanya berisi data user dan employee yang diperlukan untuk menampilkan sesi
terakhir. Password dan token tidak disimpan di dalam profil maupun di SQLite.
Token tetap hanya berada di `TokenStore` yang sudah ada.

Belum ada perubahan pada `SessionController` atau `AuthGate` pada tahap ini.

## Backup Android

File berikut dikecualikan dari cloud backup dan device transfer:

- `attendance_outbox.db`
- `attendance_outbox.db-journal`
- `attendance_outbox.db-wal`
- `attendance_outbox.db-shm`
- direktori `attendance_outbox/` yang berisi foto selfie

Konfigurasi ada di:

- `android/app/src/main/res/xml/backup_rules.xml` (Android 11 ke bawah)
- `android/app/src/main/res/xml/data_extraction_rules.xml` (Android 12+)
- Atribut `android:fullBackupContent` dan `android:dataExtractionRules` pada
  `AndroidManifest.xml`

Tujuannya agar selfie privat dan antrean yang belum tersinkron tidak ikut
dicadangkan atau dipindahkan tanpa kendali aplikasi. Konsekuensinya, data
antrean lokal tidak dipulihkan dari backup; data absensi resmi tetap berasal
dari server setelah sinkronisasi.

## Test

Test lapisan lokal memakai SQLite FFI di host dan tidak membutuhkan emulator:

```bash
cd mobile
dart test test/features/attendance/data/local
dart test test/core/auth/cached_user_store_test.dart
```

Jika `libsqlite3.so` tidak berada di lokasi standar, arahkan library secara
eksplisit tanpa mengubah kode aplikasi:

```bash
SQLITE3_LIBRARY=/path/to/libsqlite3.so dart test test/features/attendance/data/local
```

Test lapisan lokal mencakup skema dan migrasi 1 -> 2, round-trip kolom, FIFO
berdasarkan `local_sequence`, klaim atomik dan dua klaim bersamaan, pemulihan
lease, pembatasan owner/employee pada semua transisi, penolakan transisi tidak
valid, kenaikan `attempt_count` tepat sekali, validasi foto/koordinat, pembersihan
foto yang masih dirujuk, purge yang aman, serta persistensi setelah database
dibuka ulang.

Test sinkronisasi mencakup enqueue sebelum jaringan, retry dengan id yang sama,
ack `200`/`201`, timeout setelah server menyimpan tanpa duplikat, FIFO
check-in/check-out, event `rejected` memblokir event lebih baru, isolasi antar
employee, dua pemicu bersamaan, pemulihan lease, jeda `401`, klasifikasi error,
backoff/`Retry-After`, dan penghapusan foto hanya setelah ack valid.

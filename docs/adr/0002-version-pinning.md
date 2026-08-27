# ADR 0002 — Pinning Versi Toolchain

Status: **Diterima** — 2026-08-27
Menggantikan tabel toolchain di [ADR 0001](0001-toolchain.md).

## Konteks

ADR 0001 menyalin angka dari dokumentasi umum TrinityCore. Setelah membaca kode
fork CPP secara langsung, sebagian angka itu salah, dan yang lebih penting:
**dependensi yang terlalu baru sama merepotkannya dengan yang terlalu tua.**

Requirement sebenarnya, dibaca dari sumber:

| Sumber di repo | Isi |
|---|---|
| `CMakeLists.txt` | `cmake_minimum_required(VERSION 3.18)` |
| `dep/boost/CMakeLists.txt` | `set(BOOST_REQUIRED_VERSION 1.78)` di Windows (1.74 non-Windows) |
| `cmake/compiler/msvc/settings.cmake` | MSVC **19.32** = Visual Studio 2022 **17.2**, plus `/permissive-` |

Kondisi mesin saat pemeriksaan pertama (`tools/check-prereqs.ps1`):

- Visual Studio Community **2026** 18.7.11822.327, MSVC 14.51 (v145) — prerelease
- Visual Studio Build Tools **2019** 16.11, MSVC 14.29 (v142) — di bawah floor
- Git 2.53.0 — OK
- CMake, Boost, OpenSSL, MySQL — belum ada
- Disk C: 206 GB bebas — cukup

## Keputusan

Semua dependensi **di-pin**, bukan diambil versi terbaru:

| Komponen | Pin | Alasan |
|---|---|---|
| CMake | **3.31.8** | CMake 4.x menolak proyek dengan `cmake_minimum_required < 3.5`; dep bundel di `dep/` masih ada yang setua itu. 3.31.8 adalah 3.x terakhir. |
| OpenSSL | **3.5.4** (`ShiningLight.OpenSSL.Dev`) | Fork ini menyasar API OpenSSL 1.1/3.x. winget menawarkan 4.0.2 sebagai default — terlalu baru, API-nya berubah. Paket **Light** tidak punya header sama sekali. |
| MySQL | **8.0.43** | Floor-nya 8.0.34. winget default 8.4.9, tapi 8.4 menghapus `mysql_native_password` dan menata ulang client lib — belum pernah diuji dengan codebase 2022 ini. |
| Boost | **1.83.0**, prebuilt `msvc-14.3-64` | Di atas floor 1.78, cukup lama untuk aman dari header yang dibuang Boost versi baru. Tidak tersedia di winget — harus diunduh manual. |
| Visual Studio | **2022 Community** (17.14) berdampingan dengan VS2026 | Lihat di bawah. |

### Kenapa memasang VS2022 padahal VS2026 sudah ada

VS2026 **lolos** gate versi (MSVC 19.51 > 19.32), jadi secara teknis bisa dicoba.
Tapi dua hal membuatnya berisiko:

1. `/permissive-` aktif. Compiler 2026 jauh lebih ketat terhadap kode 2022-era;
   kegagalan build akan berupa error konformansi yang tidak ada hubungannya dengan
   proyek kita, dan tidak ada CI upstream yang pernah menghadapinya.
2. Boost hanya merilis binary prebuilt sampai `msvc-14.3` (v143 / VS2022).
   Memakainya dengan v145 bergantung pada jaminan kompatibilitas ABI MSVC yang
   tidak didokumentasikan untuk kombinasi ini.

Biaya VS2022 hanya ruang disk (~15 GB dari 206 GB bebas) dan ia hidup berdampingan
tanpa mengganggu VS2026. Menukar 15 GB untuk menghilangkan seluruh kelas kegagalan
build yang tidak ada hubungannya dengan playerbot adalah pertukaran yang jelas
menguntungkan di fase fondasi.

VS Build Tools 2019 dibiarkan saja — tidak dipakai, tidak mengganggu.

## Konsekuensi

- `tools/install-prereqs.ps1` memasang versi ter-pin, bukan `latest`.
- `tools/check-prereqs.ps1` melaporkan tiga status: `OK`, `WARN` (jalan tapi berisiko),
  `MISSING`. Versi yang terlalu baru menghasilkan `WARN`, bukan `OK`.
- Kalau nanti build dengan VS2022 terbukti mulus, mencoba VS2026 sebagai eksperimen
  tetap terbuka — tapi bukan di fase fondasi.

---

## Revisi — 2026-08-27, setelah percobaan instalasi pertama

Percobaan pertama gagal di **empat** titik sekaligus. Semuanya berakar pada satu
asumsi yang salah: bahwa versi yang di-pin akan tetap bisa diunduh. Vendor menghapus
rilis lama, jadi **pin yang benar bisa jadi URL yang mati.**

| Komponen | Yang terjadi | Perbaikan |
|---|---|---|
| CMake | winget keluar dengan `-1978335189` padahal 3.31.8 **sudah terpasang** — skrip salah membacanya sebagai gagal | Kode itu (`APPINSTALLER_CLI_ERROR_UPDATE_NOT_APPLICABLE`) kini diperlakukan sebagai sukses, sama seperti `-1978335135` |
| OpenSSL | `slproweb.com/download/Win64OpenSSL-3_5_4.msi` → **404**. Diperiksa: slproweb kini hanya menyajikan **4.0.2**; seluruh lini 3.x dihapus dari server mereka | Ganti vendor ke **`FireDaemon.OpenSSL`**, yang masih menerbitkan 3.5.4 dan 3.6.2 (URL diverifikasi 200) |
| MySQL | `cdn.mysql.com` **404** untuk 8.0.43. Oracle hanya menyimpan rilis terkini tiap lini — yang ada sekarang **8.0.44**. Dan `dev.mysql.com` / `downloads.mysql.com` membalas **403** untuk unduhan skrip | Unduh **zip** `mysql-8.0.44-winx64.zip` dari `cdn.mysql.com` (200), bukan MySQL Installer. Zip memberi `include\mysql.h` + `lib\libmysql.lib` tanpa GUI dan tanpa akun Oracle |
| Boost | Terunduh, lalu installer gagal dengan *"file or directory is corrupted and unreadable"*. Ternyata filenya **HTML 0,14 MB** — halaman interstisial SourceForge, bukan installer | Ganti sumber ke **`archives.boost.io`** (arsip resmi Boost, diverifikasi 196,2 MB) |

### Aturan baru yang lahir dari sini

1. **Verifikasi setiap unduhan sebelum menjalankannya.** `Invoke-VerifiedDownload`
   di `install-prereqs.ps1` memeriksa ukuran minimum **dan** magic bytes (`MZ` untuk
   `.exe`, `PK` untuk `.zip`). Kegagalan Boost tadi menghasilkan pesan error yang
   menyesatkan justru karena halaman HTML diserahkan mentah-mentah ke `Start-Process`.
2. **Jangan pin ke versi yang vendornya rutin menghapus rilis lama.** Kalau URL mati,
   naikkan ke rilis terkini di lini yang sama (8.0.43 → 8.0.44), jangan lompat lini.
3. **Periksa kode keluar dengan benar.** "Sudah terpasang" bukan kegagalan.

### Lokasi instalasi

MySQL sengaja diletakkan di **`C:\MySQL\MySQL Server 8.0`** karena
`cmake/macros/FindMySQL.cmake` melakukan glob terhadap
`"$ENV{SystemDrive}/MySQL/MySQL Server *"` — jadi CMake menemukannya tanpa hint.
`build-core.ps1` tetap mengoper `MYSQL_INCLUDE_DIR` dan `MYSQL_LIBRARY` secara
eksplisit agar salinan lain di mesin tidak bisa memenangkan pencarian.

Konsekuensi: server MySQL belum terinisialisasi (zip, bukan installer).
`tools/bootstrap-db.ps1` yang akan menjalankan `mysqld --initialize-insecure`,
memasang service, dan membuat user `trinity`.

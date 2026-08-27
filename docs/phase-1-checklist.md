# Fase 1 — Checklist: Server Cataclysm polos bisa di-login

Target: **karakter berdiri di dunia dan `.gps` mengembalikan koordinat.** Tanpa bot.

## Status

| Langkah | Status |
|---|---|
| 1. Clone core | **selesai** — `9da95e6cc9`, branch `prabowow`, + 2 patch |
| 2. Build core | **selesai** — Release x64, Ninja, 4 menit 50 detik |
| 3. Ekstrak data client | **selesai** — dbc 333, maps 7.398, vmaps 17.652 (1,67 GB) |
| 4. Database | **selesai** — service `PraboWoWMySQL`, 4 DB terisi, TDB 278 MB terimpor |
| 5. Config | **selesai** — di-generate oleh `tools/configure-server.ps1` |
| 6. Realmlist (server) | **selesai** — sudah `127.0.0.1:8085` dari default |
| 7. Client | **selesai** — realmlist + Config.wtf diarahkan ke 127.0.0.1 (asli dibackup), di-patch lewat `client_launcher_64` |
| 8. Akun GM | **selesai** — `ADMIN`, gmlevel 3, via `tools/create-account.ps1` |
| 3b. mmaps | **selesai** — 5.086 file, 2,89 GB, 32 menit 46 detik (12 thread) |
| 9. Pathfinding | **aktif** — `mmap.enablePathFinding = 1`, worldserver konfirmasi `MMap data directory is: .../data/mmaps` |

**Kenapa akun dibuat lewat SQL, bukan konsol worldserver:** dua percobaan konsol gagal
karena dua sebab berbeda. Pertama, worldserver membaca seluruh stdin saat masih
inisialisasi, jadi perintah yang dikirim di muka sudah EOF sebelum `TC>` siap. Kedua,
startup-nya menulis ribuan baris kualitas data ke **stderr**, yang memenuhi buffer pipe
dan membuat pembaca naif menggantung. `tools/create-account.ps1` menghitung SRP6 sendiri
(`v = g^x mod N`, `x = SHA1(s || SHA1(UPPER(user):UPPER(pass)))`) — deterministik dan
tanpa konsol.

**Kejutan skema:** `auth.account_access` di fork ini memakai kolom
`AccountID` / `SecurityLevel` / `RealmID`, bukan `id` / `gmlevel` seperti TrinityCore lama.

**Bukti server naik penuh:**

```
World initialized in 0 minutes 9 seconds
TrinityCore rev. 94fa379ffb5c (prabowow branch) (Win64, Release, Static) ready...
```

`Server.log` bersih. `DBErrors.log` berisi 166 baris, semuanya kualitas data TDB beku
(`world_state` MapID/AreaID invalid, gossip menu, data proc spell) — bukan penghambat,
sudah diantisipasi di ADR 0001.

**Catatan perilaku:** worldserver berhenti sendiri (`Halting process...`) kalau stdin
bukan konsol sungguhan — thread CLI dapat EOF lalu shutdown bersih. Jadi untuk
dipakai normal ia harus dijalankan di terminal interaktif, bukan diarahkan ke file.

**Patch client — dua jalur, `client_launcher` lebih baik:**

| | |
|---|---|
| `connection_patcher` | membuat `Wow_Patched.exe` + `Battle.net_Patched.dll`; tidak mengubah asli, tapi menambah file di folder game |
| `client_launcher_64` | menyuntik `client_patcher_64.dll` ke memori proses — **tidak menyentuh file client sama sekali** |

`client_launcher` mengunduh ~13 modul auth Battle.net dari repo `AuthModules` milik CPP
ke `%ProgramData%\Blizzard Entertainment\Battle.net\Cache\`. Nama file = SHA256 isinya,
dan kode memverifikasi checksum tersebut, jadi integritasnya swa-periksa.

Semua detail di bawah sudah diverifikasi terhadap source `core/` yang ter-clone,
bukan dari dokumentasi umum TrinityCore.

## 1. Clone core — SELESAI

- Repo: `The-Cataclysm-Preservation-Project/TrinityCore`
- Ter-pin di commit `9da95e6cc9`, branch kerja **`prabowow`**
- Remote `upstream` sudah ditambahkan (sementara menunjuk URL yang sama dengan
  `origin`; ganti `origin` ke fork pribadi saat fork dibuat)

Fakta yang dikonfirmasi dari source:

| | |
|---|---|
| `cmake_minimum_required` | 3.18 |
| MSVC floor | 19.32 (VS2022 17.2) — mesin ini punya **19.51**, lolos |
| Boost | minimum **1.78**, `CONFIG` mode, static libs, komponen `filesystem thread program_options regex locale` |
| Opsi `TOOLS` | sudah default `1`, tidak perlu di-set manual |

## 2. Build core

```powershell
.\tools\build-core.ps1 -ConfigureOnly   # cek deteksi dependensi dulu
.\tools\build-core.ps1                  # build penuh + install ke server\
```

Binary yang dihasilkan (nama target dari `src/tools/*/CMakeLists.txt`):

`authserver`, `worldserver`, `mapextractor`, `vmap4extractor`, `vmap4assembler`,
`mmaps_generator`, `connection_patcher`, `client_launcher`, `client_patcher`

## 3. Ekstrak data client

Urutan wajib — vmap4assembler memakai output vmap4extractor, mmaps_generator memakai
maps + vmaps:

1. `mapextractor` menghasilkan `dbc/` + `maps/`
2. `vmap4extractor` menghasilkan file mentah, lalu `vmap4assembler` menghasilkan `vmaps/`
3. `mmaps_generator` menghasilkan `mmaps/` — **paling lama**, 1-3 jam di Ryzen 7 5700X

Salin keempat folder ke `server/data/`. Skrip: `tools/extract-client-data.ps1`.

## 4. Database — EMPAT database, bukan tiga

Koreksi terhadap rencana awal. `worldserver.conf.dist` mendefinisikan:

| Database | Config key |
|---|---|
| `auth` | `LoginDatabaseInfo` |
| `world` | `WorldDatabaseInfo` |
| `characters` | `CharacterDatabaseInfo` |
| `hotfixes` | `HotfixDatabaseInfo` |

`hotfixes` khas era Cataclysm dan **wajib** — tidak ada di WotLK, jadi mudah terlewat.

Asset TDB yang dicari core (dari `revision_data.h.in.cmake`, jadi ini definitif):

```
TDB_full_world_434.22011_2022_01_09.sql
TDB_full_hotfixes_434.22011_2022_01_09.sql
```

Ini rilis TDB terbaru yang ada (Januari 2022) — memang beku, dan itu sudah
diperhitungkan di ADR 0001. Biarkan `worldserver` menjalankan auto-updater-nya
sendiri pada start pertama; jangan impor manual.

## 5. Config

Salin `.conf.dist` ke `.conf`, set `DataDir`, keempat `*DatabaseInfo`, dan `LogsDir`.
Kredensial hidup di file yang di-gitignore.

## 6. Realmlist

`UPDATE auth.realmlist SET address = '127.0.0.1'` untuk fase solo.

## 7. Patch client

Cataclysm memverifikasi koneksi, jadi client harus di-patch. Core ini menyediakan
tiga tool untuk itu: `connection_patcher`, `client_launcher`, `client_patcher`.
Butuh `Wow.exe` dan `Battle.net.dll` yang bersih. Lalu `SET portal "127.0.0.1"`
di `Config.WTF`.

## 8. Akun

Di konsol worldserver: `account create <user> <pass>`, lalu
`account set gmlevel <user> 3 -1`.

## Gerbang lolos Fase 1

- [x] authserver + worldserver hidup tanpa error di log
- [x] client patched berhasil login, realm muncul
- [x] buat karakter, masuk dunia
- [x] `.gps` dan `.tele` berfungsi
- [ ] restart server, karakter persist

---

## Jebakan runtime: DLL yang tidak ikut ter-install

Dua dependensi runtime tidak disalin oleh `cmake --install`, dan **dua-duanya gagal
dengan cara yang menyamar sebagai masalah lain.** Keduanya kini ditangani otomatis
di akhir `tools/build-core.ps1`.

### 1. `libmysql.dll`

Gejala: `authserver.exe` dan `worldserver.exe` langsung keluar dengan
`-1073741515` (`0xC0000135`, DLL_NOT_FOUND). Terlihat seperti crash, padahal cuma
file hilang. Konsekuensi memasang MySQL dari ZIP, bukan dari installer.

### 2. OpenSSL: `legacy.dll` **dan** `libcrypto-3-x64.dll`

Gejala jauh lebih menyesatkan: server naik normal, `ready...`, lalu **mati saat
client menyambung**:

```
Exception code: C0000420 An assertion failure has occurred.
ARC4.cpp:31 in Trinity::Crypto::ARC4::ARC4  ASSERTION FAILED: result == 1
```

Rantai sebabnya:

1. Enkripsi paket dunia memakai **RC4**.
2. OpenSSL 3 memindahkan RC4 ke **legacy provider**, yang tidak dimuat default.
   `OpenSSLCrypto::threadsSetup()` menanganinya dengan
   `OSSL_PROVIDER_set_default_search_path(nullptr, <direktori worldserver.exe>)`
   lalu `OSSL_PROVIDER_load(nullptr, "legacy")` — jadi `legacy.dll` **harus** ada
   tepat di sebelah binary.
3. Menyalin `legacy.dll` saja **tidak cukup**, dan ini bagian yang menipu.
   `libcrypto-3-x64.dll` yang benar-benar dimuat worldserver ternyata milik
   **Git for Windows** (`C:\Program Files\Git\mingw64\bin\`), karena ada di PATH.
   Provider hanya bisa terpasang ke instance libcrypto tempat ia dibangun, jadi
   dengan libcrypto yang salah, legacy provider diam-diam tidak pernah teregistrasi.

Bukti bahwa provider-nya sendiri sehat:

```
> openssl.exe list -providers -provider legacy
  legacy   name: OpenSSL Legacy Provider   version: 3.6.2   status: active
```

**Perbaikan:** salin `libcrypto-3-x64.dll`, `libssl-3-x64.dll`, dan `legacy.dll` ke
direktori server. Windows mencari DLL di direktori aplikasi **sebelum** PATH, jadi
instalasi jadi swa-cukup dan kebal terhadap apa pun yang terpasang di mesin.

**Verifikasi:** koneksi TCP ke port 8085 kini dibalas 49 byte
`SMSG_AUTH_CHALLENGE` ("WORLD OF WARCRAFT CONNECTION - SERVER TO CLIENT")
dan server tetap hidup.

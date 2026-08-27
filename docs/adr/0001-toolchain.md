# ADR 0001 — Pilihan Core, Sumber AI Bot, dan Toolchain

Status: **Diterima** — 2026-08-27

## Konteks

Membangun private server WoW Cataclysm 4.3.4.15595 dengan playerbot sebagai
fitur utama. Kendala fundamental: **tidak ada playerbot matang untuk Cataclysm.**
Seluruh lineage ike3 (`mod-playerbots`, `cmangos/playerbots`,
`liyunfan1223/TrinityCore-Playerbots`) menargetkan 3.3.5 WotLK.

## Keputusan

### 1. Core: The-Cataclysm-Preservation-Project/TrinityCore

Fork TrinityCore untuk 4.3.4.15595. Aktif dirawat (~38k commit, CI GitHub Actions
+ AppVeyor). Branch kerja kita: `prabowow`, bercabang dari `master`.

Alternatif yang ditolak:
- **TrinityCore branch `4.3.4` asli** — beku, tidak menerima backport.
- **MaNGOSFour** — praktis terbengkalai.

Konsekuensi: world database terkunci di **TDB 434.22011 (Januari 2022)**.
Data dunia dan script boss Cata tidak lengkap; ini membatasi kualitas raid AI
di fase lanjut, dan itu keterbatasan core, bukan bot.

### 2. Sumber AI bot: mod-playerbots + compat layer

Ambil AI dari [`mod-playerbots/mod-playerbots`](https://github.com/mod-playerbots/mod-playerbots)
(~2.7k commit, aktif). AzerothCore sendiri adalah fork TrinityCore 3.3.5, jadi
API-nya berkerabat dekat. Kita tulis shim di `src/prabobots/compat/` sehingga file
AI yang di-port berubah seminimal mungkin dari upstream, dan perbaikan upstream
bisa di-sync berkala.

Alternatif yang ditolak:
- **`liyunfan1223/TrinityCore-Playerbots`** — API paling dekat (TrinityCore 3.3.5)
  sehingga port awal tercepat, tapi repo stale (turunan `conan513/SingleCore_TC`),
  AI generasi lama, tidak ada upstream aktif untuk di-sync. Umur pendek.
- **`trickerer/Trinity-Bots` (NPCBots)** — bot berbasis creature, bukan fake player.
  Tidak bisa jadi anggota party sungguhan dengan inventory/talent nyata.
- **Framework sendiri dari nol** — kode bersih tapi membuang bertahun-tahun tuning.

Catatan penting: `mod-playerbots` **bukan modul murni** — ia mensyaratkan fork core
AzerothCore sendiri (branch `Playerbot`). Artinya porting butuh dua sisi:
hook di core **dan** codebase AI.

### 3. Ruang lingkup dipangkas

Hanya **party/raid fill** dan **alt army pribadi**. `RandomPlayerbotMgr`,
world population, questing, grinding, AH, travel, dan BG AI dibuang.
Memangkas kira-kira sepertiga codebase, tepat di bagian yang paling sulit di-tune.

### 4. Toolchain

Mengikuti requirement resmi TrinityCore untuk Windows:

| Komponen | Minimum |
|---|---|
| Visual Studio 2022 Community | 17.4 (workload *Desktop development with C++*) |
| CMake | 3.24 x64 |
| Boost | 1.80 prebuilt `msvc-14.3-64` |
| OpenSSL | 3.x Win64 **full** (bukan Light) |
| MySQL Server | 8.0.34 (dengan dev components) |
| Git for Windows | terbaru |

Build selalu **Release x64** — Debug tidak sanggup menjalankan banyak bot.
Disk minimum 80 GB: source + build ≈ 15 GB, ekstraksi client (mmaps dominan) ≈ 40–50 GB.

## Konsekuensi

- Pekerjaan terberat ada di lapisan *content AI*: Cataclysm 4.0 menghapus rank spell,
  mengganti talent jadi tree 31-point dengan spec dikunci level 10, menambah mastery,
  dan resource baru (Holy Power, Eclipse, Soul Shard, Focus). Lapisan ini praktis
  ditulis ulang; lapisan *framework* bisa dipakai apa adanya.
- Risiko pemblokir paling awal: pembuatan `WorldSession` tanpa socket untuk login bot.
  Alur opcode TC 4.3.4 berbeda dari AC 3.3.5. Diprototipe lebih dulu sebelum
  kode AI apa pun ditulis.

> **Catatan:** tabel toolchain di ADR ini digantikan oleh [ADR 0002](0002-version-pinning.md) setelah requirement dibaca langsung dari kode fork. Angka yang benar: MSVC 19.32 (VS2022 17.2), Boost 1.78, CMake 3.18.

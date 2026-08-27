# PraboWoW — Private Server Cataclysm 4.3.4 + Playerbot

Server WoW Cataclysm **4.3.4.15595** dengan playerbot sebagai fitur utama.
Ini proyek **porting**, bukan instalasi modul: AI bot berasal dari `mod-playerbots`
(AzerothCore / WotLK 3.3.5) dan diadaptasi ke core TrinityCore 4.3.4.

## Ruang lingkup bot

Dipakai: **party/raid fill** + **alt army pribadi** (bot = karakter alt milik akun yang sama).
Dibuang total: `RandomPlayerbotMgr`, world population bots, questing, grinding,
auction house, travel, dan BG/Arena AI.

## Bahasa

- Dokumentasi, ADR, catatan porting, komunikasi: **Bahasa Indonesia**.
- Kode C++, nama simbol, komentar inline, commit message: **Inggris**.

Alasan: diff tetap bersih saat re-sync dengan upstream TrinityCore / mod-playerbots.

## Aturan keras

1. **`vendor/` tidak pernah diedit.** Isinya submodule ter-pin dan read-only.
   Semua adaptasi hidup di `src/prabobots/compat/`.
2. **Perubahan di `core/` = commit atomik berlabel.** Satu hook satu commit,
   prefix `[hook]`, supaya rebase ke upstream CPP tetap mungkin.
   Setiap hook wajib dicatat di `docs/porting-notes.md`.
3. **Jangan pernah commit data client.** `server/data/`, DBC, maps, vmaps, mmaps,
   dan binary client bersifat lokal — sudah ada di `.gitignore`.
4. **Rahasia tidak masuk repo.** File `.conf` aktif di-gitignore; hanya `.dist`
   dan overlay tanpa kredensial yang di-track.

## Layout

| Path | Isi |
|---|---|
| `core/` | submodule fork CPP TrinityCore, branch kerja `prabowow` |
| `vendor/mod-playerbots/` | submodule pinned — sumber AI (READ-ONLY) |
| `vendor/ac-playerbot-core/` | submodule pinned — dibaca hanya untuk diff hook AC (READ-ONLY) |
| `src/prabobots/compat/` | shim AzerothCore → TrinityCore |
| `src/prabobots/bot/` | PlayerbotAI, PlayerbotMgr, fake WorldSession |
| `src/prabobots/ai/` | engine + strategy/action/trigger/value hasil port |
| `src/prabobots/cata/` | overlay khusus Cataclysm (talent, spell, mastery, reforge) |
| `src/prabobots/commands/` | chat command `.bot` |
| `tools/` | skrip PowerShell: prereq check, build, extract client, bootstrap DB |
| `server/` | hasil install core (di-gitignore) |

## Perintah

```powershell
# verifikasi toolchain (read-only, aman dijalankan kapan saja)
.\tools\check-prereqs.ps1

# pasang toolchain versi ter-pin (BUTUH shell elevated)
.\tools\install-prereqs.ps1 -WhatIf      # lihat dulu apa yang akan dipasang
.\tools\install-prereqs.ps1 -DownloadBoost

# build core (Release x64)
.\tools\build-core.ps1

# ekstrak data dari client 4.3.4 milik user
.\tools\extract-client-data.ps1 -ClientPath "<path client>"

# bootstrap database
.\tools\bootstrap-db.ps1
```

Shell utama proyek ini **PowerShell** (Windows 11). Skrip ditulis untuk
Windows PowerShell 5.1 — tanpa `&&`, `||`, ternary, atau `??`.

## Build

Toolchain: **Visual Studio 2026 Insiders** (MSVC v145) dengan generator **Ninja**.
CMake di-pin di 3.31.8 dan **tidak boleh** dinaikkan ke 4.x — 4.x menolak
`cmake_minimum_required < 3.5` yang masih dipakai dep bundel TrinityCore.
Konsekuensinya CMake 3.31 tidak punya generator VS2026, karena itu Ninja.
Environment MSVC harus di-prime dulu dengan `vcvarsall.bat x64` (VS2026 18.10
sudah menghapus `vcvars64.bat`); lokasinya cari lewat `vswhere`, jangan di-hardcode.
Detail dan risiko: `docs/adr/0003-build-generator.md`.

Selalu **Release x64**. Debug terlalu lambat untuk menjalankan banyak bot.
CMake butuh `TOOLS=1` (extractor client) dan opsi `PRABOBOTS=1` untuk
mengaktifkan target bot; matikan untuk build core bersih saat debugging regresi.

## Status

Lihat `docs/adr/` untuk keputusan arsitektur dan `docs/porting-notes.md`
untuk checklist hook core.

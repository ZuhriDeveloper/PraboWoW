# Fase 2 — Checklist Milestone 1: sesi bot socketless

Target: **satu karakter alt di akun yang sama berdiri di dunia sebagai bot dan bertahan.**
Tanpa AI.

## Status

| Langkah | Status |
|---|---|
| 1. Vendor `mod-playerbots` | **selesai** — pin `2f7d9f7`, tanpa `branch` di `.gitmodules` |
| 2. Enam patch core | **selesai** — `70dd4ea` … `801c2a2` di branch `prabowow` |
| 3. Modul `src/prabobots` | **selesai** — 6 file, `prabobots.lib` ter-link |
| 4. Build `PRABOBOTS=1` | **selesai** — nol error, `worldserver.exe` ter-install |
| 5. Build `PRABOBOTS=0` bersih | **selesai** — nol error, nol warning, nol referensi prabobots |
| 6. Uji runtime in-game | **belum dijalankan** |

## Gerbang lolos Fase 2 Milestone 1

- [x] `PRABOBOTS=1` configure + build tanpa error
- [x] `PRABOBOTS=0` build tetap bersih (regresi untuk lima patch `game` tanpa syarat)
- [ ] `.bot add <Alt>` → bot in-world dalam ~1 detik
- [ ] `Server.log` **nol** baris `Prevented sending of`
- [ ] Bot punya nameplate, bisa di-target, buff nempel
- [ ] `.summon <Alt>` → bot pindah map dan tetap bisa di-target
- [ ] Bot bertahan **10+ menit** tanpa crash dan tanpa spike `WorldUpdateTime`
- [ ] `.bot remove` bersih; baris **owner** di `characters` masih `online = 1`
- [ ] Owner logout membersihkan bot-nya
- [ ] `.server shutdown 1` dengan bot aktif → exit 0 tanpa assertion

## Persiapan runtime

1. Dua karakter di akun `ADMIN` — owner dan minimal satu alt. Parkir alt di tempat yang
   diketahui.
2. Tambahkan kategori log ke `config\worldserver.conf` (lewat `tools/configure-server.ps1`,
   mengikuti preseden LOS: keputusan server hidup ada di luar submodule):

   ```
   Logger.playerbots = 4,Console Server
   ```

3. Jalankan `worldserver.exe` di **terminal interaktif sungguhan**. Ia halt sendiri kalau
   stdin bukan konsol (lihat `phase-1-checklist.md`).

## Urutan uji

| # | Perintah | Yang harus terlihat |
|---|---|---|
| 1 | `.bot list` | `No bots active.` |
| 2 | `.bot add <Alt>` | `Bot <Alt> logging in...` lalu kategori `playerbots` melaporkan `is in world (map X, zone Y)` |
| 3 | cek `Server.log` | Baris core `Account: 1 (IP: ) Login Character:[<Alt>]` — **IP kosong** adalah tanda tangan jalur socketless, dan baris itu datang dari `HandlePlayerLogin` asli |
| 4 | `grep "Prevented sending of"` | **Nol** hit. Kalau ada, `SetBotSession(true)` dipanggil terlambat |
| 5 | `.appear <Alt>` | Membuktikan registrasi `ObjectAccessor` |
| 6 | klik bot, `.pinfo <Alt>` | Nameplate ada, target-able, level/class benar |
| 7 | cast Power Word: Fortitude | Aura nempel → bot `Unit` penuh di grid, bukan objek hantu |
| 8 | `.summon <Alt>` | Bot tiba di sebelah dan tetap target-able. Kalau membeku di posisi lama, drive `HandleMoveWorldportAck` tidak jalan |
| 9 | tunggu 10+ menit | Masih berdiri, masih di `.bot list`, tidak ada spike `WorldUpdateTime` |
| 10 | `.bot remove <Alt>` | Hilang bersih; di MySQL baris bot ter-save dan baris **owner** masih `online = 1` |
| 11 | owner logout | `PlayerScript::OnLogout` membersihkan bot |
| 12 | `.server shutdown 1` | `Halting process...`, exit 0, tanpa assertion |
| 13 | restart, `.bot add` lagi | Sesi sebelumnya menutup bersih, tanpa lock basi |

## Jangan diuji milestone ini

**`.tele` sesama map.** `HandleMoveTeleportAck` menerima packet dan tidak bisa di-drive tanpa
argumen seperti `HandleMoveWorldportAck`, jadi teleport near akan menggantungkan bot dengan
`mSemaphoreTeleport_Near` menyala permanen. Ini pekerjaan milestone berikutnya.

## Jebakan yang sudah diketahui

**`sWorld->FindSession(accountId)` selalu mengembalikan owner, tidak pernah bot.** Empat call
site memakainya (`cs_account.cpp:745`, `cs_misc.cpp:1947`/`:2016`, `World.cpp:2915`), jadi
`.ban account` atau `.kick` yang menyasar akun bot akan mengenai owner. Bukan crash, tapi ini
gejala pertama dari "banyak sesi satu account id" dan akan berulang.

**File baru butuh re-configure.** `CollectSourceFiles` tidak memakai `CONFIGURE_DEPENDS`, jadi
`.cpp` yang baru ditambahkan tidak ikut ter-compile sampai CMake configure ulang.
`tools/build-core.ps1` selalu menjalankan `cmake -S -B`, jadi alur normal aman — tapi kalau
memanggil `ninja` langsung, ini jam pertama yang klasik hilang.

**Satu bot per karakter, banyak bot per akun.** `World::m_sessions` di-key account id, tapi
bot tidak masuk ke sana — `PlayerbotMgr` memakai container sendiri yang di-key **guid
karakter**, jadi batas 10 bot per akun murni kebijakan kita (`MaxBotsPerAccount`), bukan
batas core.

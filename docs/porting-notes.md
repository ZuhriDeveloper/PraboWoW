# Catatan Porting — Perubahan di `core/`

Setiap perubahan pada submodule `core/` dicatat di sini. Aturannya (CLAUDE.md #2):
satu perubahan = satu commit atomik berlabel di branch `prabowow`, supaya rebase ke
upstream CPP TrinityCore tetap mungkin.

Prefix commit:

| Prefix | Arti |
|---|---|
| `[build]` | penyesuaian sistem build, tidak mengubah perilaku runtime |
| `[hook]` | titik sisip untuk playerbot |
| `[fix]` | perbaikan bug upstream yang memblokir kita |
| `[tune]` | perilaku server yang sengaja dibedakan dari upstream, digerbangi config |

---

## `[build]` Gate `$(ConfigurationName)` di balik generator Visual Studio

**File:** `cmake/compiler/msvc/settings.cmake`
**Fase:** 1 (build pertama)

### Masalah

Build gagal saat generate, bukan saat compile:

```
ninja: error: build.ninja:230: bad $-escape (literal $ must be written as $$)
```

Baris pelakunya:

```
-D_BUILD_DIRECTIVE=\"$(ConfigurationName)\"
```

`$(ConfigurationName)` adalah variabel **MSBuild** dan hanya mengembang di bawah
generator Visual Studio. Kondisi aslinya hanya mengecualikan nmake:

```cmake
if(CMAKE_MAKE_PROGRAM MATCHES "nmake")
```

Ninja tidak cocok dengan pola itu, jadi ia jatuh ke cabang MSBuild dan menerima
string mentah. Tanda `$` telanjang lalu merusak escaping `build.ninja`.

Ini asumsi lama di upstream: **"MSVC berarti generator Visual Studio."** Asumsi itu
tidak berlaku untuk kita, karena CMake 3.31 tidak punya generator VS2026
(lihat ADR 0003).

### Perbaikan

Ganti kondisi menjadi berbasis generator, dan pakai `$<CONFIG>` untuk selain VS:

```cmake
if(CMAKE_GENERATOR MATCHES "Visual Studio")
  ... -D_BUILD_DIRECTIVE="$(ConfigurationName)")
else()
  ... -D_BUILD_DIRECTIVE="$<CONFIG>")
endif()
```

`$<CONFIG>` adalah generator expression CMake yang bekerja di generator single-config
maupun multi-config. Ini **bukan** pendekatan baru — `cmake/compiler/clang`, `gcc`,
`mingw`, dan `icc` semuanya sudah memakainya. Patch ini hanya menyamakan MSVC dengan
mereka untuk kasus non-VS.

### Risiko

Rendah. Jalur generator Visual Studio tidak berubah sama sekali, jadi build upstream
di CI mereka tetap berperilaku identik. Nilai `_BUILD_DIRECTIVE` hanya dipakai untuk
string versi (`GitRevision.cpp`) dan `ScriptReloadMgr`.

### Layak diusulkan ke upstream?

Ya. Ini perbaikan generik yang menguntungkan siapa pun yang memakai Ninja dengan MSVC,
dan tidak ada hubungannya dengan playerbot.

---

## `[fix]` Matikan `_CRT_SECURE_CPP_OVERLOAD_STANDARD_NAMES` untuk StormLib

**File:** `dep/StormLib/CMakeLists.txt`
**Fase:** 1 (ekstraksi data client)

### Masalah

`mapextractor.exe` mati seketika tanpa mencetak apa pun, exit code
`-1073741819` (`0xC0000005`). Nol output menyesatkan — `printf` ter-buffer, dan
buffernya hilang saat proses dibunuh.

Build `RelWithDebInfo` menghasilkan simbol, dan laporan `WheatyExceptionReport`
akhirnya menunjuk pelakunya:

```
strcpy_s+71
SFileFindFirstFile+BA   dep\StormLib\src\SFileFindFile.cpp line 420
ExtractDBCFiles+6F      src\tools\map_extractor\System.cpp line 1117
```

Bukan null-deref, melainkan **CRT invalid parameter handler** yang membunuh proses.

Penyebabnya kombinasi dua hal yang masing-masing wajar:

1. StormLib memakai **C struct hack**. `TMPQSearch` berakhir dengan
   `char szSearchMask[1]`, dan `SFileFindFirstFile` sengaja meng-over-allocate:

   ```c
   nSize = sizeof(TMPQSearch) + strlen(szMask) + 1;
   hs = STORM_ALLOC(char, nSize);
   strcpy(hs->szSearchMask, szMask);
   ```

2. `cmake/compiler/msvc/settings.cmake` mendefinisikan
   `_CRT_SECURE_CPP_OVERLOAD_STANDARD_NAMES` secara global. Define ini menulis
   ulang `strcpy` pada array berukuran tetap menjadi `strcpy_s` memakai **bound
   yang dideklarasikan**, bukan yang dialokasikan.

Jadi `strcpy_s` menerima ukuran tujuan **1** untuk sumber `"DBFilesClient\*dbc"`
(18 karakter) dan membunuh proses. Ruang ekstra hasil over-allocate tidak terlihat
oleh mekanisme penulisan ulang itu.

### Perbaikan

Opt out di level target, mengikuti **preseden yang sudah ada di repo ini**:
`dep/gsoap/CMakeLists.txt` melakukan hal yang persis sama.

```cmake
if (MSVC)
  target_compile_definitions(storm
    PRIVATE
      -D_CRT_SECURE_CPP_OVERLOAD_STANDARD_NAMES=0)
endif()
```

Dipilih di level define, bukan menambal satu `strcpy`, karena StormLib punya
**6 pemanggilan `strcpy`** — perbaikan ini menutup seluruh kelasnya sekaligus, dan
tidak menyentuh source pihak ketiga sama sekali.

### Verifikasi

```
Detected client build: 15595
Extracted 328 DBC files
Extracted 5 DB2 files
exit=0
```

### Risiko

Rendah. Hanya menonaktifkan penulisan ulang otomatis di dalam StormLib, yang memang
mengelola buffernya sendiri. Tidak ada kode pihak ketiga yang diubah. Peringatan
`C4996` yang mungkin muncul sudah dibungkam oleh `_CRT_SECURE_NO_WARNINGS` yang
tetap aktif.

### Layak diusulkan ke upstream?

Ya, dan kuat: `mapextractor` tidak bisa dipakai sama sekali di toolchain MSVC ini,
perbaikannya mengikuti preseden mereka sendiri, dan tidak ada kaitannya dengan playerbot.


---

## `[tune]` Jadikan doodad M2 memblokir line of sight spell

**File:** `src/server/game/Spells/Spell.cpp`, `src/server/game/World/World.h`,
`src/server/game/World/World.cpp`, `src/server/worldserver/worldserver.conf.dist`
**Config:** `LineOfSight.IgnoreM2` (default `.dist` tetap `1` = perilaku upstream)

### Masalah

Pemain melaporkan bisa menembak musuh dari balik pohon dan objek kayu di Northshire.
Bukan masalah data: vmaps lengkap (17652 file, 140 `.vmtree`, identik di VPS dan lokal)
dan `.gps` di lokasi kejadian melaporkan `VMap: 1`.

Pembongkaran tile `000_32_48` pada koordinat pemain (`X -8869.7, Y -116.65`) menunjukkan
sebabnya. Dalam radius 35 yard hanya ada **satu WMO** (`Nsabbey.wmo`, 13,2 yd) — sisanya
seluruhnya M2: `Elwynntreecanopy02/04`, `Elwynntreemid01`, `Stormwindgypsywagon01`,
`Elwynnpine01`, lalu barrel, crate, sack, jug, jar. Gameobject di sekitar hanya tiga
(satu Mailbox, dua Wooden Bench, ~40 yd), jadi bukan dynamic tree.

Sepuluh pemakaian `VMAP::ModelIgnoreFlags::M2` di `Spell.cpp` membuat **semua** pengecekan
LOS spell melewatkan model M2. Yang lain tidak: default parameter
`WorldObject::IsWithinLOS`/`IsWithinLOSInMap` adalah `ModelIgnoreFlags::Nothing`
(`Object.h:404-405`), jadi penglihatan creature sudah menghitung doodad. Hanya spell
yang keluar dari aturan.

### Perbaikan

Satu helper di `Spell.cpp` yang menyaring flag itu, dipakai oleh dua overload
`Spell::IsWithinLOS` (jalur untuk 9 dari 10 pemakaian) dan oleh satu pemakaian langsung
`corpse->IsWithinLOSInMap`:

```cpp
static VMAP::ModelIgnoreFlags ResolveLineOfSightIgnoreFlags(VMAP::ModelIgnoreFlags ignoreFlags)
{
    if (sWorld->getBoolConfig(CONFIG_LINE_OF_SIGHT_IGNORE_M2))
        return ignoreFlags;

    return VMAP::ModelIgnoreFlags(uint32(ignoreFlags) & ~uint32(VMAP::ModelIgnoreFlags::M2));
}
```

Menyaring bit `M2` saja, bukan mengembalikan `Nothing`, supaya flag lain yang mungkin
ditambahkan upstream tidak ikut hilang.

Default di `.dist` sengaja dibiarkan `1` supaya core telanjang tetap berperilaku upstream.
Yang membalikkannya adalah lapisan deploy: `LOS_IGNORE_M2=0` di `deploy/entrypoint.sh` dan
`$losIgnoreM2 = '0'` di `tools/configure-server.ps1`. Pola yang sama dengan rate loot —
keputusan server hidup ada di luar submodule.

### Yang TIDAK diperbaiki

**Terrain tetap tidak pernah memblokir.** `Map::isInLineOfSight`
(`src/server/game/Maps/Map.cpp:1577`) hanya menyusun `LINEOFSIGHT_CHECK_VMAP` (model
WMO/M2) dan `LINEOFSIGHT_CHECK_GOBJECT` (dynamic tree). Heightmap ADT tidak ikut sama
sekali, jadi bukit dan tanggul tembus berapa pun tingginya. Menambahkannya berarti
mengubah arsitektur collision, bukan menyetel flag.

### Risiko

Sedang, dan ini pertukaran yang disengaja. Hull collision M2 kasar, jadi berdiri rapat
dengan tong atau peti kecil bisa memunculkan `SPELL_FAILED_LINE_OF_SIGHT` yang terasa
salah. Itu alasan upstream mengabaikannya. Karena digerbangi config, membalikkannya cukup
`LOS_IGNORE_M2=1` di `.env` lalu restart container — tanpa rebuild image.

Perlu diperhatikan juga: perubahan ini mengenai bot. Bot memakai jalur `Spell` yang sama,
jadi target di balik pohon akan gagal di-cast dan strategy harus benar-benar mendekat.

### Layak diusulkan ke upstream?

Tidak. Ini keputusan rasa main, bukan bug. Yang mungkin layak adalah config-nya sendiri —
upstream saat ini mengunci perilaku itu dalam kode tanpa jalan keluar.

---

## `[script]` Gilneas chapter 3 — quest 24468 dan 24616

**File:** `core/src/server/scripts/EasternKingdoms/Gilneas/gilneas_chapter_3.cpp` (baru),
`core/src/server/scripts/EasternKingdoms/eastern_kingdoms_script_loader.cpp` (dua baris).
Sisi database ada di `sql/world/2026_08_29_06_00_gilneas_chapter_3_scripts.sql`.

### Kenapa

CPP hanya mengirim `gilneas_chapter_1.cpp` dan `gilneas_chapter_2.cpp`. Semua yang ada
setelah Greymane Manor tidak pernah ditulis, jadi rantai Gilneas berhenti di sana meskipun
datanya lengkap. Dua quest pertama sesudah 24438 "Exodus" mentok karena hal yang sama:
spell dan creature-nya ada, yang hilang cuma yang memicunya.

| Quest | Yang sudah ada di data | Yang hilang |
|---|---|---|
| 24468 Stranded at the Marsh | Crash Survivor `37067` (11 spawn, phase 186); `69854 Summon Swamp Crocolisk` → `37078`, dan `RequiredNpcOrGo1` menghitung kill `37078` | 37067 tanpa npcflag, tanpa `npc_spellclick_spells`, tanpa AI — pemain tidak punya apa pun untuk diklik |
| 24616 Losing Your Tail | `70794` trap, `70795` summon Dark Scout, `70797` talisman (start item 49944), `70796` Aimed Shot, dan `creature_text` untuk `37953` | tidak ada yang memanggil `70794`; target implisit `70797` tidak punya baris `conditions` |

### Isi

- `npc_gilneas_crash_survivor` (37067) — `MoveInLineOfSight` memicu penyergapan saat pemain
  yang memegang 24468 masuk 12 yard, meng-cast `69854`, lalu mengarahkan crocolisk ke pemain
  lewat `JustSummoned`. Credit datang dari kill-nya sendiri. `69854` berdurasi tak terbatas
  (SpellDuration index 21), jadi crocolisk yang ditinggalkan dibersihkan lewat timer.
- `npc_gilneas_dark_scout` (37953) — `IsSummonedBy` menghadap pemanggil, `Talk(0)`, lalu
  menyerang; Aimed Shot tiap 8 detik.
- `spell_gilneas_belysras_talisman` (70797) — memutus `70794` dan membangunkan scout.

### Penyimpangan yang disengaja

Retail memicu `70794` dari sesuatu di jalan sebelah utara Bradshaw Mill — trap itu sendiri
sudah force-cast `70795`, jadi scout-nya datang sendiri. Tidak ada yang meng-cast `70794` di
database ini, dan map 654 hanya punya sembilan areatrigger, tidak satu pun di jalan itu.
Selama penempatan itu belum ada, memakai talisman-lah yang memunculkan sang ranger
(`AfterCast` meng-cast `70795` kalau belum ada scout di sekitar). Sisanya — dialog, Aimed
Shot, dan kill credit lewat `RequiredNpcOrGo1` — tetap seperti aslinya.

`37953` juga masih membawa stat placeholder: level 1 dan faction 35 yang bersahabat dengan
semua orang, jadi dia tidak bisa diserang. Level 11 dan faction 83 diambil dari saudaranya
di chapter dan phase yang sama (Forsaken Infantry `37692`). Dua nilai itu hasil inferensi,
bukan sniff.

### Risiko

Rendah. Keduanya file baru plus dua baris registrasi di loader, tidak menyentuh logika
upstream mana pun, jadi rebase tetap bersih. Yang perlu diawasi saat uji: faction 2208 milik
`37078` harus benar-benar hostile, dan `MoveInLineOfSight` pada sebelas survivor berarti
sebelas AI aktif di rawa — dijaga dengan flag `_ambushing` supaya tidak spam summon.

### Layak diusulkan ke upstream?

Ya, kalau penempatan trap `70794` yang asli sudah didapat. Tanpa itu, penyimpangan di atas
membuatnya lebih cocok tinggal di fork.

---

## `[fix]` Terrain swap tunggal tidak divalidasi ke grid file

**File:** `core/src/server/game/Phasing/PhasingHandler.cpp`, fungsi `GetTerrainMapId`.

### Gejala

Di Greymane Manor pemain kena **fatigue di dalam ruangan**, tembus lantai saat relog, dan
`.debug phase` melaporkan `Flags 8` tanpa satu pun phase — padahal `spell_area` sudah benar.

### Kenapa

`GetTerrainMapId` punya jalan pintas: kalau phase shift hanya membawa satu visible map id,
id itu langsung dikembalikan tanpa memeriksa apakah swap-nya benar-benar punya grid file di
koordinat tersebut.

```cpp
if (phaseShift.VisibleMapIds.size() == 1)
    return phaseShift.VisibleMapIds.begin()->first;   // <- tanpa cek tile
```

Terrain swap tidak wajib menutupi seluruh map induknya. Di map 654 (Gilneas), dua baris
`terrain_swap_defaults` hanya punya **11 tile (638)** dan **4 tile (655)** melawan 60 tile
milik induknya. Syaratnya di `conditions` type 25:

| Swap | Aktif saat |
|---|---|
| 638 Gilneas default terrain | quest 14222 **belum** rewarded |
| 655 Gilneas - Duskmist Shore broken | quest 14386 **sudah** rewarded |

Begitu kondisi pemain menyisakan satu swap saja — dan itu keadaan normal, bukan kasus
langka — seluruh koordinat map diselesaikan terhadap terrain yang sebagian besar tidak ada.
Di manor (`-1583, 2555`, grid 34/27) tidak satu pun swap punya tile, jadi `GetGrid`
mengembalikan nullptr dan `getAreaInfo` tidak menemukan vmap: tanpa tinggi tanah, tanpa area
id, tanpa line of sight, tanpa data liquid — sementara client menggambar map induk seperti
biasa. Dari situ semuanya runtuh berurutan, termasuk `GetAreaId` yang jatuh ke area default
map sehingga zone id berhenti bernilai 4714 dan **seluruh aturan `spell_area` serta
`phase_area` zona itu ikut mati**.

### Perbaikan

Jalan pintasnya dibuang, biar loop yang sudah ada mengerjakannya: tiap visible map id dicek
dengan `HasChildTerrainGridFile`, dan kalau tidak ada yang menutupi tile itu, kembali ke map
induk — persis yang sudah dilakukan jalur multi-swap dengan benar.

### Risiko

Rendah. Biayanya satu lookup bitset per child terrain, dan map tanpa terrain swap tetap
keluar lebih dulu lewat cek `VisibleMapIds.empty()` di atasnya. Perlu diperhatikan bahwa
fungsi ini ada di jalur panas — dipanggil dari tinggi tanah, liquid, line of sight, dan
`PathGenerator` — tapi `_childTerrain` hanya berisi satu atau dua entri.

### Layak diusulkan ke upstream?

Ya. Jalan pintas ini ada juga di TrinityCore master, dan asumsinya (swap selalu menutupi
seluruh induk) tidak dipenuhi oleh data Gilneas milik CPP sendiri.

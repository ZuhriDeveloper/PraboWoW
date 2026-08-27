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

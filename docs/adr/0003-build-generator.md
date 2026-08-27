# ADR 0003 — Toolset Visual Studio Insiders dan Generator Ninja

Status: **Diterima** — 2026-08-27
Mengubah bagian "Kenapa memasang VS2022" di [ADR 0002](0002-version-pinning.md).

## Konteks

ADR 0002 merekomendasikan memasang Visual Studio 2022 Community berdampingan dengan
VS2026 Insiders yang sudah ada, demi mencocokkan binary prebuilt Boost `msvc-14.3`
dan menghindari error konformansi compiler baru.

Pemilik proyek menolak: **toolchain-nya adalah Visual Studio Insiders.** Itu keputusan
yang sah dan mengikat — rekomendasi di ADR 0002 tidak dijalankan.

Fakta yang relevan:

- Fork ini mensyaratkan MSVC **19.32** (VS2022 17.2) sebagai *lantai*, bukan plafon.
  VS2026 Insiders membawa MSVC **19.51** — lolos.
- CMake di-pin ke **3.31.8** (ADR 0002, karena CMake 4.x menolak
  `cmake_minimum_required < 3.5` yang masih dipakai dep bundel TrinityCore).
- CMake 3.31.8 lebih tua dari VS2026. Generator terbarunya adalah
  **"Visual Studio 17 2022"** — tidak ada generator untuk VS2026.

Jadi tidak ada satu pun generator Visual Studio yang bisa menyasar toolset terpasang.

## Keputusan

**Build memakai generator Ninja**, dijalankan dari environment developer VS Insiders.

Ninja tidak peduli pada dukungan generator: ia memakai `cl.exe` apa pun yang ada di
environment. Ini menghapus masalah generator sepenuhnya, dan sebagai bonus lebih cepat
dari MSBuild untuk codebase sebesar TrinityCore.

### Catatan: Insiders bergerak, jangan bergantung padanya

Rencana awal adalah memakai Ninja dan `vcvars64.bat` yang ikut terbawa di instalasi
Insiders. Di tengah pengerjaan, VS Insiders memperbarui dirinya sendiri dari
**18.7.11822.327 → 18.10.12120.281**, dan dua hal berubah:

- Komponen *C++ CMake tools* **dibuang** — `ninja.exe` yang tadinya ada di
  `Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja\` lenyap.
- Skrip per-arsitektur **`vcvars64.bat` dihapus**; yang tersisa hanya
  `vcvarsall.bat` yang menerima arsitektur sebagai argumen.

Pelajarannya: kanal Insiders berubah di bawah kaki kita, jadi build tidak boleh
bergantung pada apa pun yang kebetulan ikut dibundel VS.

| Kebutuhan | Sumber |
|---|---|
| Ninja | dipasang standalone: `winget install Ninja-build.Ninja` (1.13.2) |
| Environment MSVC | `...\18\Insiders\VC\Auxiliary\Build\vcvarsall.bat x64` |

Alur konfigurasi: jalankan `vcvarsall.bat x64` lebih dulu, lalu `cmake -G Ninja`.
`tools/check-prereqs.ps1` menerima `vcvarsall.bat` maupun `vcvars64.bat` supaya tidak
ikut rusak kalau Microsoft mengembalikannya.

**Jangan** menyelesaikan error generator dengan menaikkan CMake ke 4.x — itu menukar
satu masalah dengan masalah `cmake_minimum_required` yang lebih sulit.

## Risiko yang diterima

Dua hal yang sengaja ditunda sampai build pertama, bukan diantisipasi dengan menukar
toolchain:

1. **`/permissive-` + MSVC 19.51 terhadap kode 2022-era.** Compiler baru jauh lebih
   ketat. Kalau muncul error konformansi, perbaikannya adalah patch lokal di branch
   `prabowow` (dicatat di `docs/porting-notes.md`), bukan mengganti compiler.
2. ~~**Penamaan library Boost** (`-vc143` vs `-vc145`).~~ **Sudah terselesaikan —
   risiko ini tidak nyata.** Setelah `core/` di-clone dan `dep/boost/CMakeLists.txt`
   dibaca langsung, ternyata core sudah menanganinya sendiri: ia mengubah
   `MSVC_TOOLSET_VERSION` (145) menjadi `14.5`, lalu **menurunkan angka minor satu per
   satu** sambil menambahkan setiap kandidat ke `BOOST_SEARCH_HINTS`:

   ```
   lib64-msvc-14.5/cmake -> 14.4 -> 14.3 -> 14.2 -> ... -> 14.0
   ```

   Jadi Boost prebuilt di `lib64-msvc-14.3` tetap ditemukan oleh compiler v145 tanpa
   intervensi apa pun. Pencariannya memakai `CONFIG` mode, yang cocok karena installer
   prebuilt Boost memang mengirim `BoostConfig.cmake` di direktori itu.

   Yang tetap harus dipenuhi: `Boost_USE_STATIC_LIBS ON` (installer prebuilt Windows
   menyediakan static lib), komponen `filesystem thread program_options regex locale`,
   dan `BOOST_ROOT` yang ter-set.

VS Build Tools 2019 (MSVC 14.29) yang masih ada di mesin berada di bawah lantai 19.32,
tidak dipakai, dan diabaikan oleh `tools/check-prereqs.ps1`.

## Konsekuensi

- `tools/check-prereqs.ps1` menerima VS >= 17.2 **atau** >= 18.x sebagai `OK`, dan
  kini juga memeriksa keberadaan Ninja serta `vcvars64.bat`.
- `tools/install-prereqs.ps1` tidak lagi memasang Visual Studio. Tersedia switch
  opt-in `-InstallVisualStudio2022` murni sebagai jalan mundur kalau risiko nomor 1
  terbukti memblokir.
- `tools/install-prereqs.ps1` kini memasang **Ninja** (`Ninja-build.Ninja`).
- `tools/build-core.ps1` (Fase 1) harus memanggil `vcvarsall.bat x64` sebelum CMake,
  dan mendeteksi lokasinya lewat `vswhere` — bukan path yang di-hardcode, karena
  versi Insiders berganti.

# ADR 0004 — Arsitektur Fake Session Playerbot

Status: **Diterima** — 2026-08-30
Menjalankan risiko yang ditandai [ADR 0001](0001-toolchain.md) baris 75-77.

## Konteks

ADR 0001 menandai satu pemblokir yang harus diprototipe **sebelum kode AI apa pun ditulis**:

> Risiko pemblokir paling awal: pembuatan `WorldSession` tanpa socket untuk login bot.
> Alur opcode TC 4.3.4 berbeda dari AC 3.3.5.

Milestone ini mengerjakan tepat itu dan berhenti di situ: satu karakter alt login tanpa
socket, berdiri di dunia sebagai `Player` penuh, dan bertahan. **Nol AI.**

Ruang lingkupnya (ADR 0001) menentukan bentuknya: bot adalah **karakter alt di akun yang
sama** dengan owner. Itu satu kalimat di dokumen, tapi konsekuensinya menjalar ke mana-mana,
karena core mengasumsikan satu sesi per akun di beberapa tempat.

## Keputusan

### 1. `WorldSession` biasa dengan socket `nullptr` — bukan subclass

`PlayerbotMgr` memegang `std::unique_ptr<WorldSession>`.

Godaannya jelas: `FakeWorldSession : public WorldSession` terasa seperti bentuk yang benar.
Ditolak karena dua fakta yang terverifikasi di source:

1. **`WorldSession` punya nol method virtual dan destructor non-virtual.** Ia tidak `final`,
   jadi turunan bisa dikompilasi — tapi tidak ada satu pun yang bisa di-override. Alasan
   orang men-subclass tipe sesi adalah untuk mengganti `SendPacket`, `Update`, atau
   `KickPlayer`; di sini ketiganya mati. Subclass tanpa override hanyalah struct dengan
   langkah tambahan.
2. **UB-nya senyap dan compiler tidak bisa menolong.** `Player::GetSession()` menyebarkan
   `WorldSession*` ke praktis seluruh codebase. Begitu ada jalur mana pun yang `delete`
   lewat pointer base — milik kita di milestone berikutnya, atau milik upstream setelah
   rebase — destructor turunan tidak jalan, tanpa warning, tanpa crash di titik kesalahan.
   `World::AddSession_` dan `World::UpdateSessions` dua-duanya berisi `delete pSession`.
   Hari ini keduanya tidak bisa melihat bot, tapi itu properti disiplin kita soal
   `m_sessions`, bukan properti type system.

Konstruktornya sendiri sudah toleran socket null (`if (sock)` melewatkan lookup IP dan
tulisan DB), jadi tidak ada yang perlu diakali.

### 2. Sesi bot hidup di `PlayerbotMgr`, bukan `World::m_sessions`

`World::m_sessions` di-key **account id**, dan `World::AddSession_` men-kick lalu `delete`
sesi mana pun yang account id-nya sama. Karena bot berbagi akun dengan owner, mendaftarkan
sesi bot ke sana akan **membunuh sesi owner**. Ini bukan preferensi, ini larangan.

Konsekuensinya `PlayerbotMgr` mengambil peran `World::UpdateSessions` untuk bot: ia
memiliki container-nya, men-tick tiap sesi, dan membongkarnya.

### 3. Tick dari `WorldScript::OnUpdate`, dengan filter `ProcessUnsafe() == false`

`WorldSession::Update` memanggil `ProcessQueryCallbacks()` **tanpa syarat** — itu yang
menyelesaikan holder login async — sementara blok yang berakhir dengan

```cpp
if (!m_Socket[CONNECTION_TYPE_REALM])
    return false;              // Will remove this session from the world session map
```

seluruhnya digerbangi `updater.ProcessUnsafe()`. Jadi filter yang mengembalikan `false` dari
`ProcessUnsafe()` mendapat callback-nya tanpa pernah meminta dirinya dihapus. `PacketFilter`
adalah satu-satunya tipe di jalur ini yang memang dirancang untuk di-subclass (destructor
virtual, `Process` virtual, `ProcessUnsafe` virtual), dan `MapSessionFilter` sudah melakukan
hal yang sama untuk alasan struktural yang sama.

Artinya blocker "sesi dihapus di tick pertama" hilang **tanpa patch core**.

Urutan per world tick jinak dengan sendirinya: `UpdateSessions` (command chat jalan di sini)
→ `MapMgr::Update` → `OnWorldUpdate` (PlayerbotMgr). Penghapusan di-antre oleh command dan
dieksekusi di akhir, jadi sebuah sesi tidak pernah dihancurkan saat `Update`-nya sendiri ada
di stack.

### 4. Enam patch core, satu di antaranya `ifdef`

Detail tiap patch ada di `docs/porting-notes.md`. Yang penting dicatat di sini adalah
**pembatasannya**: lima dari enam ter-compile tanpa syarat, sehingga `PRABOBOTS=0` dan
`PRABOBOTS=1` menghasilkan library `game` yang identik. Hanya registrasi script yang
di-`ifdef`, karena tanpa guard simbolnya tidak ada dan `worldserver` gagal link.

Menghindari dua varian perilaku core lebih berharga daripada menghindari tiga baris kode
mati.

Satu keputusan yang perlu disorot: **`LoginBotPlayer` lahir di core**, bukan direplikasi di
prabobots. `LoginQueryHolder` lokal ke `CharacterHandler.cpp`, `m_playerLoading` private
tanpa setter, dan `ProcessQueryCallbacks` private. Mereplikasi `HandlePlayerLogin` di luar
justru menuntut **lebih banyak** permukaan core dipromosikan jadi public, lalu memelihara
salinan 300 baris yang membusuk diam-diam tiap rebase. Hook 18 baris yang gagal saat compile
jauh lebih murah dirawat.

### 5. Kepemilikan divalidasi di `PlayerbotMgr`, bukan di core

`LoginBotPlayer` sengaja melewati `IsLegitCharacterForAccount` — daftar `_legitCharacters`
diisi `HandleCharEnum`, yang tidak pernah jalan untuk bot. Sebagai gantinya
`PlayerbotMgr::AddBot` menegakkan aturannya sendiri, dan yang paling penting:

```cpp
if (cached->AccountId != accountId)   // aturan "akun yang sama" dari ADR 0001
```

Cek akun di `Player::LoadFromDB` adalah **backstop**, bukan gerbang — saat ia menyala,
sesinya sudah terlanjur dibuat dan harus dibongkar.

## Konsekuensi

- `src/prabobots` menjadi `add_subdirectory` **out-of-tree pertama** di proyek ini. Semua 43
  yang sudah ada adalah child relatif, jadi ini preseden baru dan butuh argumen binary dir
  eksplisit.
- Modul ini tidak bisa jadi script module (`GetScriptsBasePath` mengunci path), jadi
  registrasinya lewat `AddCustomScripts()`.
- `sWorld->FindSession(accountId)` akan **selalu** mengembalikan owner, tidak pernah bot.
  Empat call site memakainya, jadi `.ban account` / `.kick` yang menyasar akun bot akan
  mengenai owner. Ini gejala konkret pertama dari "banyak sesi satu account id" dan akan
  berulang di fitur lain.
- Teleport **near** belum tertangani. `HandleMoveWorldportAck()` public dan bisa di-drive
  tanpa argumen (far teleport), tapi `HandleMoveTeleportAck` menerima packet. Teleport
  sesama map akan menggantungkan bot dengan `mSemaphoreTeleport_Near` menyala permanen —
  pekerjaan milestone berikutnya.
- `KickPlayer()` no-op total untuk sesi socketless, jadi tidak ada jalur core yang bisa
  mengusir bot. Pembongkaran satu-satunya lewat `PlayerbotMgr` → `LogoutPlayer(true)`.
- `RBAC_PERM_COMMAND_GM` dipakai ulang untuk `.bot`. Permission khusus butuh patch `RBAC.h`
  plus dua tabel `auth`; keputusan kapan itu dilakukan sebaiknya diambil sebelum baris
  `world.command` ditulis, karena id RBAC-nya ikut ter-bake ke sana.

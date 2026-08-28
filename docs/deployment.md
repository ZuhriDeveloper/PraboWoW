# Deployment — PraboWoW di VPS 145.79.10.227

Runbook operasional. Untuk alasan di balik keputusannya, lihat `docs/adr/`.

## Infrastruktur

| Komponen | Lokasi | Alamat |
|---|---|---|
| VPS | Jakarta | `145.79.10.227` |
| Realm (client menyambung ke sini) | DNS A record | `wow.zuhri-dev.com` |
| authserver | container `renowow-auth-1` | TCP `3724` |
| worldserver | container `renowow-world-1` | TCP `8085` + `8086` |
| MySQL 8 | container `renowow-db-1` | hanya jaringan internal, **tidak dipublish** |
| Data client | bind mount host | `/srv/renowow/data` (5,2 GB, read-only di container) |
| Stack compose | repo `vps-infra` | `/srv/vps-infra/apps/renowow/` |

VPS ini **bukan milik PraboWoW sendiri** — sudah ada MateriaRO (rathena), stack `edge`
(Caddy + Watchtower), dan monitoring. Semuanya diatur repo `vps-infra`; PraboWoW masuk
sebagai satu app stack di situ.

**Caddy tidak terlibat.** Protokol WoW adalah TCP mentah, sedangkan Caddy hanya bisa
mem-proxy HTTP. Port game dipublish langsung ke host.

**Tiga port, bukan dua.** Selain `3724` (auth) dan `8085` (world), Cataclysm membuka
koneksi world **kedua** setelah pilih karakter, ke `InstanceServerPort` = **8086**.
`WorldSession::SendConnectToInstance` mengambil alamat dari realmlist lalu **menimpa
portnya** dengan nilai config itu (`WorldSession.cpp:794-795`). Port ini tidak punya padanan
di WotLK, jadi pengetahuan dari setup 3.3.5 tidak akan memunculkannya — dan gejalanya
menyesatkan: daftar realm dan layar karakter bekerja sempurna, karena keduanya hanya memakai
koneksi pertama.

**Port 3724/8085/8086 tidak dibuka oleh ufw, dan tidak perlu dibuka.** Docker menulis rule
iptables-nya sendiri yang dievaluasi *sebelum* ufw, jadi port yang dipublish container
sudah terjangkau begitu container naik — `ufw allow` untuk port itu tidak melakukan apa-apa
(baris di `bootstrap.sh` disimpan sebagai dokumentasi niat, bukan sebagai mekanisme).
Konsekuensi praktisnya ada di arah sebaliknya: untuk benar-benar **menutup** salah satunya,
`ufw deny` tidak akan bekerja — perlu rule DROP di chain `DOCKER-USER`, cara yang sama yang
dipakai `scripts/allow-cloudflare-ips.sh` untuk 80/443.

Yang masih bisa menghalangi adalah **firewall provider (Hostinger)**, yang berada di luar
host. Kalau `Test-NetConnection` gagal padahal container jelas listening, periksa panel.

**DNS harus "DNS only".** Kalau record `wow.zuhri-dev.com` di-proxy Cloudflare (awan
oranye), client tidak akan bisa menyambung — proxy Cloudflare hanya melayani HTTP.

## Alur deploy

```
push ke main ──▶ GitHub Actions ──▶ ghcr.io/zuhrideveloper/prabowow-server:latest + :<sha>
                                          │
                                   (TIDAK otomatis)
                                          │
                             VPS: docker compose pull && up -d
```

Stack ini **sengaja tidak dilabeli Watchtower**, sama seperti `apps/ragnarok`. Watchtower
terpusat di stack `edge` hanya menyentuh container berlabel
`com.centurylinklabs.watchtower.enable=true`, jadi dunia yang sedang hidup tidak akan
di-restart mendadak di tengah main.

## Lokasi file

| File | Path | Mengatur |
|---|---|---|
| Compose (kanonik) | repo ini: `deploy/docker-compose.prod.yml` | definisi container |
| Compose (di VPS) | `/srv/vps-infra/apps/renowow/docker-compose.yml` | mirror dari yang kanonik |
| Kredensial | `/srv/vps-infra/apps/renowow/.env` (chmod 600) | password DB, alamat realm, rate |
| Dockerfile | `deploy/Dockerfile` | isi image |
| Generator config | `deploy/entrypoint.sh` | isi `worldserver.conf` / `authserver.conf` |
| SQL kustom | `sql/world/*.sql` | ikut image, di-apply DBUpdater |
| Data client | `/srv/renowow/data` | dbc, maps, vmaps, mmaps |

**Tidak ada `.conf` yang diedit langsung di VPS.** Keduanya di-generate ulang dari
`.conf.dist` setiap container start. Mengedit file di dalam container akan hilang saat
restart berikutnya — ubah `.env` atau `entrypoint.sh`.

## Deploy pertama kali

### 0. Pre-flight

```bash
free -h; df -h /; swapon --show; docker stats --no-stream
```

Kapasitas host per Agustus 2026: **sisa 6 GB RAM, 80 GB disk**, dengan Ragnarok,
monitoring, dan app web sudah jalan.

| Kebutuhan | Perkiraan | Muat? |
|---|---|---|
| Disk — data client | 5,2 GB | ya |
| Disk — MySQL (4 database setelah impor TDB) | ~8 GB | ya |
| Disk — image + TDB sementara | ~1,5 GB | ya |
| **Disk total** | **~15 GB dari 80 GB** | longgar |
| RAM — worldserver dengan mmaps | dibatasi 3 GB | pas |
| RAM — MySQL 8 | dibatasi 1,2 GB | pas |
| RAM — authserver | dibatasi 256 MB | pas |
| **RAM total (plafon)** | **4,4 GB dari 6 GB** | sisa ~1,6 GB |

Disk longgar; **RAM yang ketat**. Angka default di `.env.example` sudah disetel untuk
6 GB itu: buffer pool MySQL 768M dan `performance_schema` dimatikan (menghemat 300-400 MB
untuk data yang tidak akan pernah dibaca di server satu pemain).

Kalau `swapon --show` kosong, pasang 4 GB swap sekali sebelum deploy. Bukan untuk dipakai
rutin — swap adalah bantalan supaya lonjakan sesaat (impor TDB, atau grid yang ramai
sekaligus) tidak berujung OOM killer yang bisa saja memilih MariaDB Ragnarok sebagai
korban, bukan container kita:

```bash
sudo fallocate -l 4G /swapfile && sudo chmod 600 /swapfile
sudo mkswap /swapfile && sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

**Kalau `world` kena OOM dan restart berulang, jangan naikkan `WORLD_MEM_LIMIT`** — tidak
ada ruang untuk dinaikkan. Yang benar adalah membuang mmaps: pathfinding mati, sekitar
satu gigabyte kembali, dan server tetap main.

### 1. DNS

A record `wow.zuhri-dev.com` → `145.79.10.227`, **DNS only** (awan abu-abu).

Cloudflare akan memperingatkan:

> This record exposes the IP address used in the A record on grafana.zuhri-dev.com.
> Enable the proxy status to protect your origin server

Peringatan itu benar secara teknis, dan **tetap harus diabaikan**. Alasannya:

- **Proxy Cloudflare tidak bisa dipakai di sini sama sekali.** Ia hanya meneruskan HTTP/S.
  Protokol WoW adalah TCP mentah di 3724/8085; kalau record di-proxy, client tidak akan
  tersambung — bukan "kurang aman", tapi tidak jalan. (Cloudflare Spectrum bisa mem-proxy
  TCP sembarang, tapi untuk port arbitrer itu paket Enterprise.)
- **IP-nya sudah lama terbuka.** MateriaRO di host yang sama mempublish TCP 6900/6121/5121
  tanpa proxy, dan `clientinfo.xml` yang dibagikan ke pemain berisi `145.79.10.227` sebagai
  teks biasa. Satu record abu-abu lagi tidak menambah kebocoran apa pun.
- **Yang sesungguhnya melindungi app web bukan penyembunyian IP,** melainkan
  `scripts/allow-cloudflare-ips.sh` di repo `vps-infra`: ia memasang rule di chain
  `DOCKER-USER` sehingga port 80/443 hanya menerima trafik dari IP range Cloudflare.
  Itu tetap berlaku walau IP-nya diketahui semua orang. Sudah terpasang di host ini
  (diverifikasi Agustus 2026), dan `DROP`-nya di-scope ke `--dport 80/443` — jadi port
  game kita lewat tanpa disentuh.

Yang **layak** dilakukan justru: pastikan skrip itu memang sudah dijalankan, dan batasi
SSH karena sekarang IP-nya jelas-jelas publik.

```bash
# Daftar ACCEPT saja tidak cukup: allowlist tanpa deny penutup adalah no-op.
# Harus ada tiga baris DROP (tcp 80, tcp 443, udp 443) -- dan SEMUANYA harus
# memakai `-i eth0`. Lihat catatan di bawah kalau ada yang tanpa interface.
sudo iptables -S DOCKER-USER | grep DROP

sudo ufw limit 22/tcp                      # rate-limit percobaan login SSH
```

> **Jebakan yang sudah pernah terjadi di host ini.** Rule DROP tanpa `-i eth0` memblokir
> **egress container**, bukan cuma trafik masuk. `DOCKER-USER` ada di chain `FORWARD` dan
> dilewati paket dua arah, jadi `--dport 443 -j DROP` yang polos juga membunuh setiap
> koneksi keluar container ke port 443 — Caddy gagal memperbarui sertifikat Let's Encrypt,
> Watchtower gagal menarik dari GHCR, dan entrypoint kita gagal mengunduh TDB dari GitHub.
> Semuanya gagal diam-diam. `scripts/allow-cloudflare-ips.sh` sudah menangani ini dengan
> menambahkan `-i $PUBLIC_IFACE`; kalau `grep DROP` masih memperlihatkan baris tanpa
> interface, itu sisa dari versi skrip yang lama. Bersihkan dengan menjalankan ulang
> skripnya (ia menghapus semua rule bertanda `cloudflare` lalu memasang ulang yang benar):
>
> ```bash
> sudo /srv/vps-infra/scripts/allow-cloudflare-ips.sh
> ```
>
> Verifikasi egress container pulih:
>
> ```bash
> docker run --rm curlimages/curl -sS -m 10 -o /dev/null -w '%{http_code}
' https://api.github.com/zen
> ```

### 2. Data client (paling lama)

Dari Windows:

```powershell
.\tools\upload-client-data.ps1
```

5,2 GB. Kalau ingin server cepat bisa dicoba, kirim yang penting dulu dan susulkan mmaps:

```powershell
.\tools\upload-client-data.ps1 -Folders dbc,maps,vmaps,Cameras
```

> **Jalankan dari sesi PowerShell, bukan `powershell -File`.** Skrip di `tools/` memakai
> `[CmdletBinding()]` dan `$PSScriptRoot` di default parameternya, dan kombinasi
> `[CmdletBinding()]` + `-File` membuat `$PSScriptRoot` kosong di dalam blok `param()` pada
> Windows PowerShell 5.1 — salah satu saja tidak bermasalah, butuh keduanya. Gejalanya:
> `Join-Path : Cannot bind argument to parameter 'Path' because it is an empty string`.
> `upload-client-data.ps1` sudah kebal (default-nya diselesaikan di badan skrip), tapi
> `bootstrap-db.ps1`, `build-core.ps1`, `configure-server.ps1`, `create-account.ps1`, dan
> `extract-client-data.ps1` masih memakai pola lama — jalankan semuanya dari sesi.

Skrip memakai rsync di dalam WSL kalau ada (resumable), dan jatuh ke tar-over-ssh kalau
tidak. Untuk membuatnya resumable, pasang rsync sekali di WSL:

```bash
wsl -e sudo apt-get update; wsl -e sudo apt-get install -y rsync
```

### 3. Stack

Di VPS:

```bash
cd /srv/vps-infra && git pull
cp apps/renowow/.env.example apps/renowow/.env && chmod 600 apps/renowow/.env
$EDITOR apps/renowow/.env          # isi DB_ROOT_PASSWORD, DB_PASSWORD, REALM_ADDRESS
bash scripts/bootstrap.sh          # idempoten; buat /srv/renowow/data + rule ufw
docker login ghcr.io               # kalau image-nya privat
```

Naikkan bertahap supaya tiap kegagalan punya satu sebab:

```bash
cd /srv/vps-infra
C="docker compose -f apps/renowow/docker-compose.yml --env-file apps/renowow/.env"

$C up -d db
$C ps                              # tunggu sampai db "healthy" (start_period 60 detik)

$C up -d world
$C logs -f world                   # start pertama LAMA -- lihat di bawah

$C up -d auth
```

**Start pertama `world` memakan waktu lama dan itu normal.** Urutannya:

1. entrypoint mengunduh TDB (~90 MB) dan mengekstraknya (~292 MB),
2. DBUpdater mengisi `auth` dan `characters` dari `sql/base/`,
3. DBUpdater mengimpor TDB ke `world` dan `hotfixes` — ini bagian paling lama,
4. update dari `sql/updates/` lalu `sql/custom/world/` (SQL milik proyek ini) diterapkan,
5. barulah `World initialized in ...` muncul.

### 4. Akun GM

`tools/create-account.ps1` menghitung SRP6 sendiri (`v = g^x mod N`,
`x = SHA1(s || SHA1(UPPER(user):UPPER(pass)))`) karena konsol worldserver tidak bisa
dipakai secara otomatis. Cara paling mudah di VPS adalah lewat konsol `TC>` yang memang
hidup di container:

```bash
docker attach renowow-world-1
# TC> account create NAMAAKUN password
# TC> account set gmlevel NAMAAKUN 3 -1
# lepas TANPA mematikan server: Ctrl-P lalu Ctrl-Q
```

> `Ctrl-C` di dalam `docker attach` mematikan worldserver. Selalu lepas dengan
> **Ctrl-P Ctrl-Q**.

Kalau lebih suka lewat SQL, ingat jebakan skema fork ini: `auth.account_access` memakai
kolom `AccountID` / `SecurityLevel` / `RealmID`, bukan `id` / `gmlevel`.

### 5. Client

`Config.WTF` → `SET portal "wow.zuhri-dev.com"`, lalu jalankan lewat
`client_launcher_64` seperti biasa (menyuntik `client_patcher_64.dll` ke memori, tidak
menyentuh file client).

## Update rutin

### Ganti rate, alamat realm, atau limit memori

```bash
cd /srv/vps-infra
$EDITOR apps/renowow/.env
docker compose -f apps/renowow/docker-compose.yml --env-file apps/renowow/.env up -d
```

Config di-render ulang saat container start, jadi tidak perlu apa-apa lagi.

### Tambah SQL world baru

Taruh file di `sql/world/`, commit, push. CI membangun image baru, lalu di VPS:

```bash
$C pull && $C up -d world
```

DBUpdater menerapkannya dan mencatat hash-nya di tabel `updates` — idempoten, tidak akan
diterapkan dua kali. Kalau file yang **sudah** pernah diterapkan diubah isinya, hash-nya
berubah dan updater otomatis menerapkannya ulang.

### Ganti kode C++ (nanti, saat playerbot masuk)

Push ke main, tunggu CI hijau (40-70 menit untuk build dingin, jauh lebih cepat kalau
cache Actions masih hangat), lalu `$C pull && $C up -d`.

### Rollback

Image ditandai dengan commit SHA:

```bash
$EDITOR apps/renowow/.env      # IMAGE_TAG=<sha>
$C up -d
```

## Operasi harian

```bash
cd /srv/vps-infra
C="docker compose -f apps/renowow/docker-compose.yml --env-file apps/renowow/.env"

$C ps
$C logs -f world
$C restart world
docker attach renowow-world-1          # konsol TC> ; lepas dengan Ctrl-P Ctrl-Q
docker stats --no-stream

# shell database
docker exec -it renowow-db-1 mysql -utrinity -p auth
```

Backup harian ikut `scripts/backup-db.sh` di repo `vps-infra` (cron 02:30). Yang di-dump
hanya `auth` dan `characters`; `world` dan `hotfixes` bisa dibangun ulang dari TDB dan
hanya membuat dump membengkak.

## Troubleshooting

| Gejala | Sebab | Perbaikan |
|---|---|---|
| Container `world` keluar beberapa detik setelah start, log berakhir `Halting process...` | thread CLI worldserver dapat EOF karena stdin bukan konsol sungguhan | pastikan `tty: true` **dan** `stdin_open: true` ada di compose |
| Server naik sampai `ready...` lalu mati **tepat saat client menyambung**, `ARC4.cpp:31 ASSERTION FAILED` | enkripsi paket dunia memakai RC4; OpenSSL 3 memindahkannya ke legacy provider yang tidak termuat | pastikan `/usr/lib/x86_64-linux-gnu/ossl-modules/legacy.so` ada di image (build sudah menguji ini) |
| Login berhasil tapi mentok di layar realm / character select | `realmlist.address` masih `127.0.0.1` | cek `REALM_ADDRESS` di `.env`, lalu `$C restart auth` |
| Bisa pilih karakter, lalu **"World server is down"** atau **"You have been disconnected"**; log berisi `non existent socket 1` dan `failed to connect 5 times to world socket` | Koneksi world **kedua** gagal. Dua sebab berbeda bisa menghasilkan gejala identik: **(a)** port `8086` tidak dipublish atau tertutup di firewall — port itulah yang dipakai, bukan 8085; **(b)** `realmlist` masih `127.0.0.1` saat worldserver start, karena ia meng-cache-nya sekali di `LoadRealmInfo()` (`worldserver/Main.cpp:277`). | Pastikan `8086` ada di `ports:` compose **dan** terbuka di firewall provider. Untuk (b), `$C restart world`. |
| Client tidak bisa menyambung ke 3724 sama sekali | firewall provider, atau DNS di-proxy Cloudflare | buka 3724/8085 di panel Hostinger; set record ke DNS only |
| `Database World is empty, auto populating` lalu error "File ... is missing" | unduhan TDB gagal | `docker volume rm renowow_tdb` lalu `$C up -d world` untuk mengunduh ulang |
| Impor TDB berhenti di tengah dengan error tanggal | `sql_mode` MySQL 8 menolak zero date | pastikan `--sql-mode=STRICT_TRANS_TABLES,NO_ENGINE_SUBSTITUTION` ada di compose |
| worldserver tidak bisa membaca maps | bind mount masih root-owned | `chown -R 1000:1000 /srv/renowow/data` (uid user `trinity` di image) |
| Creature dan bot bergerak lurus menembus dinding | mmaps belum ter-upload jadi pathfinding mati | upload `mmaps`, lalu `$C restart world`; entrypoint menyalakannya sendiri |
| `DBErrors.log` penuh (166 baris) | kualitas data TDB yang beku di Januari 2022 | diabaikan — sudah diperhitungkan di ADR 0001 |
| Banner server menulis `unknown (Archived branch)` | image dibangun dengan `WITHOUT_GIT=1` karena `core/.git` di luar build context | normal; commit sebenarnya ada di tag `:<sha>` dan label OCI image |

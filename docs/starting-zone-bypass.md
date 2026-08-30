# Bypass Starting Zone Goblin & Worgen

Karakter **Goblin** baru sekarang lahir di start Orc (Valley of Trials, Durotar) dan
karakter **Worgen** baru di start Human (Northshire, Elwynn Forest). Kezan/Lost Isles
dan Gilneas dilewati sepenuhnya, dan racial yang seharusnya diajarkan kedua zona itu
diberikan langsung saat login pertama.

Patch: [2026_08_30_00_00_goblin_worgen_start_at_orc_human.sql](../sql/world/2026_08_30_00_00_goblin_worgen_start_at_orc_human.sql)

Ini keputusan sadar-utang seperti [quest-auto-complete.md](quest-auto-complete.md),
bukan perbaikan. Tidak ada perubahan di `core/`.

## Kenapa

### Kezan + Lost Isles (`QuestSortID` 4737 + 4720)

116 quest, **nol** script C++ — tidak ada direktori script untuk kedua zona. Sembilan
NPC yang dipakai `creature_queststarter`/`creature_questender` tidak punya satu pun baris
di `creature`:

| Entry | Nama | Dampak |
|---|---|---|
| 34957 / 34958 / 34959 | Ace / Gobber / Izzy | objektif 14071 `Rolling with my Homies` |
| 35486 | First Bank of Kezan Vault | objektif 14122 `The Great Bank Heist` |
| 37114 | Steamwheedle Shark | objektif 24502 `Necessary Roughness` (quest ini juga tidak punya ender sama sekali) |
| 37598 | Gasbot | objektif 14125 |
| 36608 | Doc Zapnozzle | ender 14239 |
| 38928 | Sassy Hardwrench | **ender 24958 `Volcanoth!`, starter 25023 `Old Friends`** |
| 39199 | Assistant Greely | **starter/ender 25122, 25123, 25125** |

Dua baris terakhir memutus rantai total: `Volcanoth!` tidak bisa di-turn-in dan
`Light at the End of the Tunnel` tidak pernah ditawarkan.

### Gilneas (`QuestSortID` 4714 / 4755)

Sudah dicicil di patch 2026_08_28 dan 2026_08_29, masih belum tuntas, dan dua quest
sudah lebih dulu diparkir sebagai skip di [quest-auto-complete.md](quest-auto-complete.md).

## Kenapa dua tujuan itu aman

| Zona | Quest terbuka | Catatan |
|---|---|---|
| Durotar (`QuestSortID` 14) | 80 untuk Goblin | Hanya 3 tertutup (6365, 926, 14088) — gate Troll/Undead, tidak ada yang kritikal |
| Elwynn (`QuestSortID` 12) | 49 untuk Worgen | Rantai Northshire memang `AllowableRaces` 1 (human), tapi Blizzard mengirim set paralel non-human di `AllowableRaces` 8388606: 29078, 29079, 29080, 29081, 29082, 29083 |

Jadi **tidak ada** `AllowableRaces` yang perlu diubah.

## Racial

Racial ada di `SkillLineAbility.dbc`, skill **789** `Racial - Worgen` dan **790**
`Racial - Goblin`. `Player::LearnSkillRewardedSpells` hanya belajar otomatis kalau
`AcquireMethod` bernilai 1 atau 2; selain itu di-`continue`
([Player.cpp:23439](../core/src/server/game/Entities/Player/Player.cpp:23439)).

Blizzard memecah tiap racial jadi dua baris: Death Knight (`ClassMask` 32) dengan
`AcquireMethod` 2, dan kelas lain (`ClassMask` 1503) dengan `AcquireMethod` 0. DK tidak
pernah menjalani starting zone ras, jadi mereka dikasih langsung — sisanya diharapkan
mendapatkannya dari questline. Melewati questline berarti non-DK kekurangan permanen:

| Ras | Spell yang hilang |
|---|---|
| Worgen | 68975 Viciousness, 68976 Aberration, 68978 Flayer, 68992 Darkflight, 68996 Two Forms, 94293 Enable Worgen Altered Form |
| Goblin | 69046 Pack Hobgoblin |

Sisanya sudah `AcquireMethod` 2 dan tetap dipelajari normal — 79742/79749 Languages,
69001 Transform: Worgen, 87840 Running Wild, dan lima racial Goblin otomatis (69041,
69042, 69044, 69045, 69070). Tidak disentuh patch ini.

### Metodenya

`playercreateinfo_spell_custom` **tidak bisa dipakai**: `Player::LearnCustomSpells()`
langsung `return` kalau `CONFIG_START_ALL_SPELLS` mati
([Player.cpp:23273](../core/src/server/game/Entities/Player/Player.cpp:23273)), dan
`PlayerStart.AllSpells = 0` di `worldserver.conf`.

`playercreateinfo_cast_spell` tidak punya gate itu — di-cast saat login pertama, di
world, triggered ([CharacterHandler.cpp:1003](../core/src/server/game/Handlers/CharacterHandler.cpp:1003)),
persis kondisi yang dibutuhkan efek `LEARN_SPELL`.

Tiga spell yang dipakai adalah spell pengajar milik Blizzard sendiri, masing-masing
sudah diverifikasi terhadap `SpellEffect.dbc` hanya berisi
`SPELL_EFFECT_LEARN_SPELL` (36) — tanpa transform, teleport, atau aura:

| Spell | Nama | Mengajarkan |
|---|---|---|
| 72792 | Learn Worgen Racials 1 | 68975, 68978, 68976 |
| 95834 | Worgen Enabler Cheat [INTERNAl] | 94293, 68996, 68992 |
| 77534 | Pack Hobgoblin | 69046 |

## Efek samping yang diterima

- **Homebind ikut pindah.** `playercreateinfo` juga jadi fallback homebind
  ([Player.cpp:18951](../core/src/server/game/Entities/Player/Player.cpp:18951)), jadi
  hearthstone otomatis benar.
- **Death Knight tidak disentuh.** Baris `class`=6 tetap di Ebon Hold (map 609, zone 4298)
  untuk kedua ras.
- **Worgen default berwujud worgen** dan bisa toggle ke human lewat Two Forms. Itu kondisi
  pasca-questline, bukan kondisi tengah-Gilneas.
- **Cinematic intro tetap yang lama.** `CinematicSequenceID` ada di `ChrRaces.dbc` (data
  client), jadi Goblin masih menonton intro Kezan dan Worgen intro Gilneas sebelum
  mendarat di zona baru. Kosmetik; tidak diperbaiki karena butuh edit data client.
- **Gate map lama masih ada.** `Player::TeleportTo` mengunci Goblin di map 648 sampai quest
  25265 di-reward dan Worgen di map 654 sampai 26706
  ([Player.cpp:1477](../core/src/server/game/Entities/Player/Player.cpp:1477)). Gate ini
  tidak bisa kena lagi karena karakter tidak pernah lahir di sana, **tapi tetap jadi
  jebakan** kalau ada GM men-teleport pemain ke map itu — mereka akan terkunci.

## Karakter lama

Patch ini hanya mengubah karakter yang dibuat **setelah** di-apply. Saat patch ditulis
tidak ada karakter Goblin/Worgen di DB, jadi tidak ada migrasi. Kalau nanti ada yang
terlanjur, racial-nya bisa disusulkan lewat `.cast` tiga spell di atas.

## Apply

```bash
"C:\MySQL\MySQL Server 8.0\bin\mysql.exe" -h127.0.0.1 -utrinity -ptrinity world < sql/world/2026_08_30_00_00_goblin_worgen_start_at_orc_human.sql
```

Lalu restart worldserver — `playercreateinfo` dan `playercreateinfo_cast_spell` dibaca
saat load, tidak ada `.reload` untuk keduanya.

## Revert

```sql
UPDATE `playercreateinfo` SET `map`=648, `zone`=4765,
  `position_x`=-8423.81, `position_y`=1361.3, `position_z`=104.671, `orientation`=1.55428
WHERE `race`=9 AND `class`<>6;

UPDATE `playercreateinfo` SET `map`=654, `zone`=4756,
  `position_x`=-1451.53, `position_y`=1403.35, `position_z`=35.5561, `orientation`=0.333847
WHERE `race`=22 AND `class`<>6;

DELETE FROM `playercreateinfo_cast_spell` WHERE `spell` IN (72792,95834,77534);
```

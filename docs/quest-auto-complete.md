# Quest Auto-Complete

Daftar quest yang sengaja **di-skip** dengan cara dibuat selesai otomatis begitu
diterima, karena bug-nya butuh perbaikan yang tidak sebanding dengan nilainya
(script C++, vehicle chain, atau data sniff yang tidak kita punya).

Ini catatan sadar-utang, bukan solusi. Setiap baris di tabel bisa dibalik dengan
satu `UPDATE` kalau nanti akar masalahnya benar-benar diperbaiki.

## Metode: complete-on-accept

Tidak ada perubahan di `core/`. Yang diubah hanya kolom objektif di
`quest_template`:

| Jenis objektif | Kolom yang dikosongkan |
|---|---|
| Kill / cast / speak-to | `RequiredNpcOrGo<N>`, `RequiredNpcOrGoCount<N>` |
| Kumpulkan item | `RequiredItemId<N>`, `RequiredItemCount<N>` |
| Bunuh pemain | `RequiredPlayerKills` |

Alurnya di core:

1. Objektif kosong → `ObjectMgr::LoadQuests` tidak pernah men-set
   `QUEST_SPECIAL_FLAGS_DELIVER` ([ObjectMgr.cpp:4448](../core/src/server/game/Globals/ObjectMgr.cpp:4448))
   maupun `QUEST_SPECIAL_FLAGS_KILL|CAST|SPEAKTO` ([ObjectMgr.cpp:4509](../core/src/server/game/Globals/ObjectMgr.cpp:4509)).
2. `Player::CanCompleteQuest` lolos semua cek dan return `true`
   ([Player.cpp:14020](../core/src/server/game/Entities/Player/Player.cpp:14020)).
3. `Player::AddQuestAndCheckCompletion` memanggil `CompleteQuest` persis setelah
   `AddQuest` ([Player.cpp:14147](../core/src/server/game/Entities/Player/Player.cpp:14147)).

`QuestType` **selalu dibiarkan 2** (`QUEST_TYPE_NORMAL`). Quest tetap masuk log
dan tetap harus di-turn-in di NPC ender, jadi `RewardQuest` tetap jalan — itu yang
menjaga `RewardNextQuest`, reputasi, dan progres phase tetap utuh. Alternatif
`QuestType = 0` (`QUEST_TYPE_TURNIN`) membuat quest langsung lompat ke frame
reward di NPC starter; tidak dipakai di sini karena melewati NPC ender.

### Syarat yang harus dipenuhi

- `Quests.IgnoreAutoComplete` di `worldserver.conf` tidak berpengaruh untuk
  metode ini (hanya relevan untuk `QuestType = 0`), tapi biarkan `0`.
- Quest tidak boleh punya `QUEST_FLAGS_COMPLETION_EVENT` (0x2) atau
  `QUEST_FLAGS_COMPLETION_AREA_TRIGGER` (0x4) di `Flags` — kalau ada,
  `CanCompleteQuest` masih menunggu `q_status.Explored`.
- `TimeAllowed` harus 0, dan `RequiredMoney` di `quest_template_addon` tidak boleh
  membuat reward uang jadi negatif.
- Karakter yang **sudah** memegang quest sebelum patch di-apply tidak otomatis
  tertolong: statusnya sudah `INCOMPLETE` di `character_queststatus`. Mereka harus
  abandon lalu ambil ulang, atau di-rescue dengan `.quest complete <id>`.

### Apply

```bash
"C:\MySQL\MySQL Server 8.0\bin\mysql.exe" -h127.0.0.1 -utrinity -ptrinity world < sql/world/<file>.sql
```

Lalu `.reload quest_template` di konsol worldserver.

## Daftar quest

| Quest | Nama | Zona | Objektif asli | Akar masalah | Patch |
|---|---|---|---|---|---|
| 14400 | I Can't Wear This | Gilneas | 1× item 49279 | Item hanya keluar dari `gameobject_loot_template` entry **27591**. GO 27591 tidak punya baris di `gameobject_template` dan tidak punya spawn sama sekali → item mustahil didapat. | [2026_08_28_23_30_quest_14400_i_cant_wear_this.sql](../sql/world/2026_08_28_23_30_quest_14400_i_cant_wear_this.sql) |
| 14416 | The Hungry Ettin | Gilneas | 5× credit 36560 | Butuh rantai vehicle penuh: spellclick di 36540 → bar vehicle 68903 → summon 68908 → 36555 harus mengikuti pemain ke Lorna Crowley. 36555 tidak punya AI sama sekali di TDB. Perbaikan SmartAI-nya ada di [2026_08_28_23_00_quest_14416_hungry_ettin.sql](../sql/world/2026_08_28_23_00_quest_14416_hungry_ettin.sql) tapi dianggap terlalu rapuh untuk dipelihara. | [2026_08_28_23_45_quest_14416_autocomplete.sql](../sql/world/2026_08_28_23_45_quest_14416_autocomplete.sql) |

## Catatan per quest

### 14400 — I Can't Wear This

- Starter dan ender sama: Grandma Wahl (36458).
- **Masih terblokir dari hulu.** `PrevQuestID`-nya 14399 ("Grandma's Lost It
  Alright") rusak dengan pola identik: item 49280 hanya dari GO **27592**, yang
  juga tidak punya template maupun spawn. Selama 14399 belum ikut di-skip, 14400
  tidak akan pernah muncul di Grandma Wahl.
- 14401 ("Grandma's Cat") aman — item 49281 drop dari creature 36461 yang ada dan
  ter-spawn.
- `quest_poi` blob 0 (`ObjectiveIndex` 4) dibiarkan; itu marker sniff yang benar
  untuk lemari 27591 kalau nanti GO-nya jadi ditambahkan.

### 14416 — The Hungry Ettin

- Starter dan ender sama: Lorna Crowley (36457), phase 183.
- `NextQuestID` = 14402 ("Ready to Go"), jadi turn-in tetap wajib supaya rantai
  Gilneas lanjut.
- Baris `smart_scripts` untuk 36555 dari patch 23_00 dibiarkan hidup: tidak ada
  lagi yang men-summon 36555 selama auto-complete aktif, jadi tidak berefek, dan
  langsung berguna lagi begitu file ini di-revert.
- `ObjectiveText1` ('Mountain Horse rescued') dan `quest_poi` juga dibiarkan.

## Revert

Kembalikan nilai aslinya, lalu `.reload quest_template`:

```sql
-- 14400
UPDATE `quest_template` SET `RequiredItemId1`=49279, `RequiredItemCount1`=1 WHERE `ID`=14400;

-- 14416
UPDATE `quest_template` SET `RequiredNpcOrGo1`=36560, `RequiredNpcOrGoCount1`=5 WHERE `ID`=14416;
```

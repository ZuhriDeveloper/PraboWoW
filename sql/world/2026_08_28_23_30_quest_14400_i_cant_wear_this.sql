-- I Can't Wear This (quest 14400, Gilneas) - auto-complete on accept
--
-- Grandma Wahl (36458) both starts and ends 14400. The only objective is one of
-- item 49279, and the only source of that item in this world DB is
-- gameobject_loot_template entry 27591 (Chance 100, QuestRequired 1).
--
-- Gameobject 27591 does not exist:
--
--   SELECT COUNT(*) FROM gameobject_template WHERE entry=27591;  -> 0
--   SELECT COUNT(*) FROM gameobject         WHERE id=27591;      -> 0
--
-- No template, no spawn, and no script anywhere that hands the item out another
-- way. So 49279 is unobtainable and 14400 can never be completed. Spawning the
-- wardrobe properly needs sniffed template + placement data we do not have, so
-- this is deliberately skipped instead of fixed: the objective is dropped and the
-- quest completes the moment it is accepted.
--
-- How the skip works (no core change needed):
--
--   Clearing RequiredItemId1/RequiredItemCount1 means ObjectMgr never sets
--   QUEST_SPECIAL_FLAGS_DELIVER (ObjectMgr.cpp:4448), and 14400 has no
--   RequiredNpcOrGo, no RequiredPlayerKills, no TimeAllowed, and Flags=8
--   (SHARABLE only - no COMPLETION_EVENT/AREA_TRIGGER). Player::CanCompleteQuest
--   therefore falls through every objective check and returns true
--   (Player.cpp:14020-14060), so Player::AddQuestAndCheckCompletion calls
--   CompleteQuest immediately after AddQuest (Player.cpp:14147).
--
--   The quest still enters the log, still has to be turned in at Grandma Wahl,
--   and RewardQuest still fires normally - which keeps RewardNextQuest=14401 and
--   any phasing tied to the turn-in intact. That is why QuestType is left at 2
--   rather than being switched to 0 (QUEST_TYPE_TURNIN).
--
-- quest_poi rows for 14400 are left alone on purpose: blob 0 (ObjectiveIndex 4)
-- is the correct sniffed marker for the wardrobe and should survive for whenever
-- gameobject 27591 is actually added.
--
-- NOTE: PrevQuestID of 14400 is 14399 ("Grandma's Lost It Alright"), which is
-- broken the same way - its item 49280 comes from gameobject 27592, also missing
-- template and spawn. 14400 stays unreachable until 14399 gets the same
-- treatment. 14401 ("Grandma's Cat") is fine: item 49281 drops from creature
-- 36461, which exists and is spawned.

UPDATE `quest_template` SET
  `RequiredItemId1`=0,
  `RequiredItemCount1`=0
WHERE `ID`=14400;

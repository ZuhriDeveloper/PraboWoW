-- The Hungry Ettin (quest 14416, Gilneas) - auto-complete on accept
--
-- Supersedes the SmartAI repair in 2026_08_28_23_00_quest_14416_hungry_ettin.sql.
-- That patch is correct and still applies cleanly, but the quest only works if
-- the whole vehicle chain in front of it works too (spellclick on 36540, the
-- 68903 vehicle bar, the 68908 summon). Skipping is cheaper than keeping that
-- chain alive, so the objective is dropped here instead.
--
-- The objective is 5 credits on 36560 (Mountain Horse Credit), delivered by
-- creature 36555 following the player to Lorna Crowley (36457, who both starts
-- and ends 14416). Clearing RequiredNpcOrGo1/RequiredNpcOrGoCount1 means
-- ObjectMgr never sets QUEST_SPECIAL_FLAGS_KILL|CAST|SPEAKTO
-- (ObjectMgr.cpp:4509). 14416 has no required items, no RequiredPlayerKills, no
-- TimeAllowed, and Flags=8388616 (SHARABLE | SOR_WHITELIST - no
-- COMPLETION_EVENT, no COMPLETION_AREA_TRIGGER), so Player::CanCompleteQuest
-- returns true with nothing left to check (Player.cpp:14020-14060) and
-- Player::AddQuestAndCheckCompletion calls CompleteQuest right after AddQuest
-- (Player.cpp:14147).
--
-- QuestType stays 2 so the quest still enters the log and still has to be turned
-- in at Lorna Crowley, which keeps RewardQuest - and therefore NextQuestID=14402
-- and the phase 183 progression - firing normally.
--
-- Left untouched on purpose, so reverting is a one-line UPDATE:
--   * ObjectiveText1 ('Mountain Horse rescued') - unused once the objective slot
--     is empty, but it is the correct sniffed string.
--   * quest_poi rows for 14416 (blob 0 = objective, blob 1 = turn-in).
--   * the 36555 SmartAI rows from the 23_00 patch - dead weight while this is
--     active (nothing summons 36555 any more), harmless, and needed again the
--     moment this file is reverted.

UPDATE `quest_template` SET
  `RequiredNpcOrGo1`=0,
  `RequiredNpcOrGoCount1`=0
WHERE `ID`=14416;

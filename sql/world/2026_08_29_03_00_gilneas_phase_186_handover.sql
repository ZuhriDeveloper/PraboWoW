-- Gilneas - hand the player over from phase 183 to phase 186 after the manor
--
-- Adjusts the boundary set by 2026_08_29_02_00_quest_14465_merge_manor_phase.sql, which
-- parked `68483`.quest_end at 14467. That is one quest too early.
--
--
-- The actual chapter seam
--
-- The quest that leaves Greymane Manor is 24438 "Exodus" ("Board a carriage below Greymane
-- Manor"): given by King Genn Greymane (36743, guid 256017, phase 183, at the observatory
-- -1517.5, 2607.7, 203.6) and handed in to Prince Liam Greymane (37065, guid 256018,
-- phase 186, at the Stagecoach Crash Site -2222.1, 1809.6, 11.8). Its RewardNextQuest is
-- 24468 "Stranded at the Marsh", the first quest of the Stormglen chapter.
--
-- So the seam needs two things TDB never provided:
--
--   * phase 183 must survive long enough for Genn to hand out 24438 - ending it at 14467
--     makes him vanish the moment the telescope scene is rewarded, and Exodus becomes
--     unobtainable;
--   * phase 186 must already be live while 24438 is in the log, because the turn-in NPC
--     is himself in 186. Starting it at "24438 rewarded" would deadlock.
--
-- Holding both at once is safe here: the two phases are geographically disjoint on map 654
-- (183 spans y 2112..2708, 186 spans y 748..1998), there are no 186 spawns anywhere near
-- Duskhaven or the manor, and a cross-check of same-entry spawns within 15 yards across the
-- two phases returns nothing.
--
-- 69484 'Phase - Quest Zone-Specific 11' is the 186 counterpart of the 68481/68482/68483
-- family already used for this zone - same attributes, same infinite duration index 21,
-- aura 261 on TARGET_UNIT_CASTER, only the phase id differs.
--
-- The window closes at 24904 "The Battle for Gilneas City" (given by Lorna Crowley, 37783,
-- phase 186); 24902 "The Hunt For Sylvanas", which follows it, is already phase 187.

-- 1) keep King Genn around until Exodus is handed in
UPDATE `spell_area` SET `quest_end`=24438 WHERE `spell`=68483 AND `area`=4714;

-- 2) phase 186 for the Stormglen chapter (24438 taken .. 24904 rewarded)
DELETE FROM `spell_area` WHERE `spell`=69484 AND `area`=4714;
INSERT INTO `spell_area`
    (`spell`,`area`,`quest_start`,`quest_end`,`aura_spell`,`racemask`,`gender`,`flags`,`quest_start_status`,`quest_end_status`)
VALUES
    (69484,4714,24438,24904,0,0,2,3,74,43);

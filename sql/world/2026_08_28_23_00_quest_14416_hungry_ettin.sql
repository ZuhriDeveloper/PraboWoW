-- The Hungry Ettin (quest 14416, Gilneas) - rounded up horses never reach Lorna Crowley
--
-- The quest wants 5 credits on 36560 (Mountain Horse Credit) for horses brought to
-- Lorna Crowley (36457, one spawn, phase 183 - the same phase the whole 14416 -> 14463
-- -> 14402 -> 14465 stretch runs in).
--
-- How the mechanic is meant to work, all of it straight out of the DBCs:
--
--   creature_template 36540 (Mountain Horse) has VehicleId 527 and spell1 = 68903, so
--   "Round Up Horse" is the vehicle's action bar - Player::VehicleSpellInitialize sends
--   creature_template.spell1..8 as the bar (Player.cpp:20833). Spell 68903 carries
--   SPELL_ATTR6_ORIGINATE_FROM_CONTROLLER (0x40000), which the client enforces by
--   refusing the cast unless you are possessing the vehicle, plus
--   SPELL_ATTR6_ALLOW_WHILE_RIDING_VEHICLE (0x1000). Range index 3 = 0-20 yards.
--
--   68903 then triggers 68908 on the targeted horse, and 68908's second effect is
--   SPELL_EFFECT_SUMMON of creature 36555 at TARGET_DEST_TARGET_ANY (63), with
--   SummonProperties 2501 and a 20 minute duration (SpellDuration 40).
--
-- So "Round Up Horse cannot be used" is not a defect of 68903: the ability only exists
-- on the vehicle bar and the client will not fire it unless the player is actually
-- riding a Mountain Horse. Mounting was blocked by 36540's missing
-- UNIT_NPC_FLAG_SPELLCLICK, fixed in 2026_08_28_21_00_quest_14465_gate_and_horse.sql -
-- that fix needs a worldserver restart before the bar appears at all.
--
-- What is genuinely missing is everything after the summon. SummonProperties 2501 has
-- Control 1, Title 0 and Flags 0x2002, so TempSummon::InitStats does not build a
-- guardian - 36555 comes out as a plain temp summon. And 36555 carries no AIName, no
-- ScriptName and no smart_scripts rows, so the horse just stands where it was summoned:
-- it does not follow, it never reaches Lorna, and nothing ever credits 36560. There is
-- no C++ script for this quest either - core/src/server/scripts/EasternKingdoms/Gilneas
-- only covers 14154 and the Greymane/Crowley horse rides.
--
-- This wires the missing half in SmartAI:
--
--   * on JUST_SUMMONED, follow the summoner. SMART_TARGET_OWNER_OR_SUMMONER falls back
--     to TempSummon::GetSummoner (SmartScript.cpp:2839), which is the player - 68903 is
--     ORIGINATE_FROM_CONTROLLER, so the controller and not the ridden horse is the
--     caster of the triggered summon.
--   * within 10 yards of Lorna, credit 36560 to that same summoner and despawn.
--
-- The event is marked SMART_EVENT_FLAG_NOT_REPEATABLE (1) on purpose: distance events
-- re-arm on their repeat timer (SmartScript.cpp:3487), so without it a horse parked
-- next to Lorna would hand out a credit every second.
--
-- SMART_ACTION_FOLLOW can carry an arrival entry and credit of its own (params 3 and 4)
-- and that would have been the tidier shape, but it does not work in this core:
-- SmartAI::StopFollow zeroes _followGuid and _followCredit at SmartAI.cpp:908-911 and
-- only then reads them back at :920 and :924 to hand out the reward, so the reward is
-- always looked up with an empty guid and never lands. Three rows in this world DB rely
-- on that path; none of them are Gilneas. Left alone here - a core fix belongs in its
-- own commit.

UPDATE `creature_template` SET `AIName`='SmartAI' WHERE `entry`=36555;

DELETE FROM `smart_scripts` WHERE `source_type`=0 AND `entryorguid`=36555;
INSERT INTO `smart_scripts` (`entryorguid`,`source_type`,`id`,`link`,`event_type`,`event_phase_mask`,`event_chance`,`event_flags`,`event_param1`,`event_param2`,`event_param3`,`event_param4`,`event_param5`,`action_type`,`action_param1`,`action_param2`,`action_param3`,`action_param4`,`action_param5`,`action_param6`,`target_type`,`target_param1`,`target_param2`,`target_param3`,`target_x`,`target_y`,`target_z`,`target_o`,`comment`) VALUES
(36555,0,0,0,54,0,100,0,0,0,0,0,0,29,0,0,0,0,0,0,23,0,0,0,0,0,0,0,'Mountain Horse - On Just Summoned - Follow Summoner'),
(36555,0,1,2,75,0,100,1,0,36457,10,1000,0,33,36560,0,0,0,0,0,23,0,0,0,0,0,0,0,'Mountain Horse - Within 10 yards of Lorna Crowley - Quest Credit ''The Hungry Ettin'''),
(36555,0,2,0,61,0,100,0,0,0,0,0,0,41,1000,0,0,0,0,0,1,0,0,0,0,0,0,0,'Mountain Horse - Link - Despawn in 1 s');

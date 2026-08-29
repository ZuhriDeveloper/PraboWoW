-- Grandma's Cat (14401, Gilneas) - Chance cannot be clicked
--
-- Chance (36459) already carries the spellclick row the quest needs, and the client can
-- never reach it:
--
--   creature_template 36459 : npcflag 0, AIName '', ScriptName ''
--   npc_spellclick_spells   : 36459 -> 68743 'Interact Dummy', cast_flags 1
--   2 spawns, both PhaseId 183, stacked on the same spot (-2102.9, 2333.4, 8.4)
--
-- Without UNIT_NPC_FLAG_SPELLCLICK (0x01000000) the client never sends CMSG_SPELLCLICK, so
-- Unit::HandleSpellClick is never reached and right-clicking the cat does nothing at all.
-- Third instance of the same defect in this zone, after Mountain Horse 36540
-- (2026_08_28_21_00) and Drowning Watchman 36440 (2026_08_28_22_00); the closing note of
-- that second file already listed Chance as a suspect.
--
-- The flag alone is not enough here. 68743 "Interact Dummy" is a generic spell used all over
-- the game - a dummy effect plus effect 61 - so the behaviour has to live on the creature,
-- and 36459 has neither SmartAI nor a ScriptName. The quest objective is one of item 49281,
-- so the click has to hand that over.
--
-- The pattern is copied from Scalawag Frog (26503), which is the same idea - a critter you
-- spellclick to pick up as an item:
--
--   npcflag 16777216, AIName 'SmartAI'
--   conditions type 18 : CONDITION_QUESTTAKEN on its quest
--   smart_scripts      : SMART_EVENT_ON_SPELLCLICK -> SMART_ACTION_ADD_ITEM on the invoker
--
-- CONDITION_QUESTTAKEN is true only while the quest is INCOMPLETE, so the cat stops being
-- clickable the moment the item lands and the quest flips to COMPLETE. That is what keeps a
-- player from stacking copies, and it is why a second condition row is unnecessary.
--
-- Deliberately NOT copied from the frog: its script despawns the critter after pickup.
-- Chance has spawntimesecs 7200, so despawning would take the cat out of the world for two
-- hours and starve every other player on the quest. If you want the pickup to actually
-- remove him, lower spawntimesecs on guids 255872 and 255958 first and add
-- SMART_ACTION_FORCE_DESPAWN as a linked event.
--
-- Note that the quest is already completable without any of this: Lucius the Cruel (36461,
-- level 7, hostile, standing nine yards from the cat at -2111.5, 2329.9) drops item 49281 at
-- 100% with QuestRequired 0. Two sources for one objective item is odd but it is what TDB
-- ships, and it is left alone.

UPDATE `creature_template` SET
  `npcflag`=`npcflag`|16777216,
  `AIName`='SmartAI'
WHERE `entry`=36459;

DELETE FROM `conditions` WHERE `SourceTypeOrReferenceId`=18 AND `SourceGroup`=36459;
INSERT INTO `conditions`
    (`SourceTypeOrReferenceId`,`SourceGroup`,`SourceEntry`,`SourceId`,`ElseGroup`,
     `ConditionTypeOrReference`,`ConditionTarget`,`ConditionValue1`,`ConditionValue2`,`ConditionValue3`,
     `NegativeCondition`,`ErrorType`,`ErrorTextId`,`ScriptName`,`Comment`)
VALUES
    (18,36459,68743,0,0,9,0,14401,0,0,0,0,0,'',"Clicker has quest Grandma's Cat (14401) active");

DELETE FROM `smart_scripts` WHERE `entryorguid`=36459 AND `source_type`=0;
INSERT INTO `smart_scripts`
    (`entryorguid`,`source_type`,`id`,`link`,`event_type`,`event_phase_mask`,`event_chance`,`event_flags`,
     `event_param1`,`event_param2`,`event_param3`,`event_param4`,`event_param5`,
     `action_type`,`action_param1`,`action_param2`,`action_param3`,`action_param4`,`action_param5`,`action_param6`,
     `target_type`,`target_param1`,`target_param2`,`target_param3`,`target_x`,`target_y`,`target_z`,`target_o`,`comment`)
VALUES
    (36459,0,0,0,73,0,100,0,68743,0,0,0,0,56,49281,1,0,0,0,0,7,0,0,0,0,0,0,0,'Chance - On Spellclick - Add Item Chance to invoker');

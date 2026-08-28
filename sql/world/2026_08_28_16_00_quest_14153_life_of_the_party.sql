-- Life of the Party (quest 14113 goblin male / 14153 goblin female, Kezan)
--
-- The quest asks the player to entertain 10 Kezan Partygoers; quest_template
-- credits that against creature 35175. spell_area already grants 'Awesome Party
-- Ensemble' (66908) inside area 4765, which overrides the action bar with
-- Bubbly/Bucket/Dance/Fireworks/Hors D'oeuvres (66909-66913, OverrideSpellData 122).
-- Those five spells are plain SPELL_EFFECT_DUMMY on a unit target and nothing
-- server side reacted to them, so the objective could never advance:
--
--   * no spell effect in Spell.dbc grants kill credit for 35175, and no script
--     (C++ or SmartAI) handled the dummy effect;
--   * the stock smart_scripts for 35186 listened for 75042/75044/75046/75048/75050,
--     unrelated self-buff spells the client never casts here, so not even the
--     emotes and replies fired;
--   * those rows also pointed at creature_text groups 0-4, which are the idle
--     'I could use a refill' request lines, not the replies (groups 5-9).
--
-- This wires SMART_EVENT_SPELLHIT on the five party spells to emote + reply +
-- kill credit for 35175 on every targetable Kezan Partygoer. 35235 is left out:
-- it carries UNIT_FLAG_NOT_SELECTABLE and cannot be targeted by the player.
-- Pre-existing idle/gossip rows are kept verbatim.

-- Partygoers that had no AI at all.
UPDATE `creature_template` SET `AIName`='SmartAI' WHERE `entry` IN (35175,35202,35236,35238);

DELETE FROM `smart_scripts` WHERE `source_type`=0 AND `entryorguid` IN (35175,35185,35186,35201,35202,35236,35238);
INSERT INTO `smart_scripts` (`entryorguid`,`source_type`,`id`,`link`,`event_type`,`event_phase_mask`,`event_chance`,`event_flags`,`event_param1`,`event_param2`,`event_param3`,`event_param4`,`event_param5`,`action_type`,`action_param1`,`action_param2`,`action_param3`,`action_param4`,`action_param5`,`action_param6`,`target_type`,`target_param1`,`target_param2`,`target_param3`,`target_x`,`target_y`,`target_z`,`target_o`,`comment`) VALUES
(35175,0,0,1,8,0,100,0,66909,0,0,0,0,5,7,0,0,0,0,0,1,0,0,0,0,0,0,0,'Kezan Partygoer - On Spellhit ''Bubbly'' - Play Emote 7'),
(35175,0,1,0,61,0,100,0,0,0,0,0,0,33,35175,0,0,0,0,0,7,0,0,0,0,0,0,0,'Kezan Partygoer - Link - Quest Credit ''Life of the Party'''),
(35175,0,2,3,8,0,100,0,66910,0,0,0,0,5,17,0,0,0,0,0,1,0,0,0,0,0,0,0,'Kezan Partygoer - On Spellhit ''Bucket'' - Play Emote 17'),
(35175,0,3,0,61,0,100,0,0,0,0,0,0,33,35175,0,0,0,0,0,7,0,0,0,0,0,0,0,'Kezan Partygoer - Link - Quest Credit ''Life of the Party'''),
(35175,0,4,5,8,0,100,0,66911,0,0,0,0,5,10,0,0,0,0,0,1,0,0,0,0,0,0,0,'Kezan Partygoer - On Spellhit ''Dance'' - Play Emote 10'),
(35175,0,5,0,61,0,100,0,0,0,0,0,0,33,35175,0,0,0,0,0,7,0,0,0,0,0,0,0,'Kezan Partygoer - Link - Quest Credit ''Life of the Party'''),
(35175,0,6,7,8,0,100,0,66912,0,0,0,0,5,7,0,0,0,0,0,1,0,0,0,0,0,0,0,'Kezan Partygoer - On Spellhit ''Fireworks'' - Play Emote 7'),
(35175,0,7,0,61,0,100,0,0,0,0,0,0,33,35175,0,0,0,0,0,7,0,0,0,0,0,0,0,'Kezan Partygoer - Link - Quest Credit ''Life of the Party'''),
(35175,0,8,9,8,0,100,0,66913,0,0,0,0,5,7,0,0,0,0,0,1,0,0,0,0,0,0,0,'Kezan Partygoer - On Spellhit ''Hors D''oeuvres'' - Play Emote 7'),
(35175,0,9,0,61,0,100,0,0,0,0,0,0,33,35175,0,0,0,0,0,7,0,0,0,0,0,0,0,'Kezan Partygoer - Link - Quest Credit ''Life of the Party'''),
(35185,0,0,0,60,0,100,0,1000,5000,5000,25000,0,89,24,0,0,0,0,0,1,0,0,0,0,0,0,0,'Kezan Partygoer - On Update - Start Random Movement'),
(35185,0,1,2,8,0,100,0,66909,0,0,0,0,5,7,0,0,0,0,0,1,0,0,0,0,0,0,0,'Kezan Partygoer - On Spellhit ''Bubbly'' - Play Emote 7'),
(35185,0,2,0,61,0,100,0,0,0,0,0,0,33,35175,0,0,0,0,0,7,0,0,0,0,0,0,0,'Kezan Partygoer - Link - Quest Credit ''Life of the Party'''),
(35185,0,3,4,8,0,100,0,66910,0,0,0,0,5,17,0,0,0,0,0,1,0,0,0,0,0,0,0,'Kezan Partygoer - On Spellhit ''Bucket'' - Play Emote 17'),
(35185,0,4,0,61,0,100,0,0,0,0,0,0,33,35175,0,0,0,0,0,7,0,0,0,0,0,0,0,'Kezan Partygoer - Link - Quest Credit ''Life of the Party'''),
(35185,0,5,6,8,0,100,0,66911,0,0,0,0,5,10,0,0,0,0,0,1,0,0,0,0,0,0,0,'Kezan Partygoer - On Spellhit ''Dance'' - Play Emote 10'),
(35185,0,6,0,61,0,100,0,0,0,0,0,0,33,35175,0,0,0,0,0,7,0,0,0,0,0,0,0,'Kezan Partygoer - Link - Quest Credit ''Life of the Party'''),
(35185,0,7,8,8,0,100,0,66912,0,0,0,0,5,7,0,0,0,0,0,1,0,0,0,0,0,0,0,'Kezan Partygoer - On Spellhit ''Fireworks'' - Play Emote 7'),
(35185,0,8,0,61,0,100,0,0,0,0,0,0,33,35175,0,0,0,0,0,7,0,0,0,0,0,0,0,'Kezan Partygoer - Link - Quest Credit ''Life of the Party'''),
(35185,0,9,10,8,0,100,0,66913,0,0,0,0,5,7,0,0,0,0,0,1,0,0,0,0,0,0,0,'Kezan Partygoer - On Spellhit ''Hors D''oeuvres'' - Play Emote 7'),
(35185,0,10,0,61,0,100,0,0,0,0,0,0,33,35175,0,0,0,0,0,7,0,0,0,0,0,0,0,'Kezan Partygoer - Link - Quest Credit ''Life of the Party'''),
(35185,0,11,0,64,0,100,0,0,0,0,0,0,10,1,3,5,6,0,0,1,0,0,0,0,0,0,0,'Kezan Partygoer - On Gossip Hello - Play Random Emote (1, 3, 5, 6)'),
(35186,0,0,0,1,0,20,0,5000,15000,15000,25000,0,1,0,0,0,0,0,0,1,0,0,0,0,0,0,0,'Kezan Partygoer - Out of Combat - Say Line 0'),
(35186,0,1,0,1,0,20,0,5000,15000,15000,25000,0,1,1,0,0,0,0,0,1,0,0,0,0,0,0,0,'Kezan Partygoer - Out of Combat - Say Line 1'),
(35186,0,2,0,1,0,20,0,5000,15000,15000,25000,0,1,2,0,0,0,0,0,1,0,0,0,0,0,0,0,'Kezan Partygoer - Out of Combat - Say Line 2'),
(35186,0,3,0,1,0,20,0,5000,15000,15000,25000,0,1,3,0,0,0,0,0,1,0,0,0,0,0,0,0,'Kezan Partygoer - Out of Combat - Say Line 3'),
(35186,0,4,0,1,0,20,0,5000,15000,15000,25000,0,1,4,0,0,0,0,0,1,0,0,0,0,0,0,0,'Kezan Partygoer - Out of Combat - Say Line 4'),
(35186,0,5,6,8,0,100,0,66909,0,0,0,0,5,7,0,0,0,0,0,1,0,0,0,0,0,0,0,'Kezan Partygoer - On Spellhit ''Bubbly'' - Play Emote 7'),
(35186,0,6,7,61,0,100,0,0,0,0,0,0,1,5,0,1,0,0,0,7,0,0,0,0,0,0,0,'Kezan Partygoer - Link - Say Line 5 to Invoker'),
(35186,0,7,0,61,0,100,0,0,0,0,0,0,33,35175,0,0,0,0,0,7,0,0,0,0,0,0,0,'Kezan Partygoer - Link - Quest Credit ''Life of the Party'''),
(35186,0,8,9,8,0,100,0,66910,0,0,0,0,5,17,0,0,0,0,0,1,0,0,0,0,0,0,0,'Kezan Partygoer - On Spellhit ''Bucket'' - Play Emote 17'),
(35186,0,9,10,61,0,100,0,0,0,0,0,0,1,6,0,1,0,0,0,7,0,0,0,0,0,0,0,'Kezan Partygoer - Link - Say Line 6 to Invoker'),
(35186,0,10,0,61,0,100,0,0,0,0,0,0,33,35175,0,0,0,0,0,7,0,0,0,0,0,0,0,'Kezan Partygoer - Link - Quest Credit ''Life of the Party'''),
(35186,0,11,12,8,0,100,0,66911,0,0,0,0,5,10,0,0,0,0,0,1,0,0,0,0,0,0,0,'Kezan Partygoer - On Spellhit ''Dance'' - Play Emote 10'),
(35186,0,12,13,61,0,100,0,0,0,0,0,0,1,7,0,1,0,0,0,7,0,0,0,0,0,0,0,'Kezan Partygoer - Link - Say Line 7 to Invoker'),
(35186,0,13,0,61,0,100,0,0,0,0,0,0,33,35175,0,0,0,0,0,7,0,0,0,0,0,0,0,'Kezan Partygoer - Link - Quest Credit ''Life of the Party'''),
(35186,0,14,15,8,0,100,0,66912,0,0,0,0,5,7,0,0,0,0,0,1,0,0,0,0,0,0,0,'Kezan Partygoer - On Spellhit ''Fireworks'' - Play Emote 7'),
(35186,0,15,16,61,0,100,0,0,0,0,0,0,1,8,0,1,0,0,0,7,0,0,0,0,0,0,0,'Kezan Partygoer - Link - Say Line 8 to Invoker'),
(35186,0,16,0,61,0,100,0,0,0,0,0,0,33,35175,0,0,0,0,0,7,0,0,0,0,0,0,0,'Kezan Partygoer - Link - Quest Credit ''Life of the Party'''),
(35186,0,17,18,8,0,100,0,66913,0,0,0,0,5,7,0,0,0,0,0,1,0,0,0,0,0,0,0,'Kezan Partygoer - On Spellhit ''Hors D''oeuvres'' - Play Emote 7'),
(35186,0,18,19,61,0,100,0,0,0,0,0,0,1,9,0,1,0,0,0,7,0,0,0,0,0,0,0,'Kezan Partygoer - Link - Say Line 9 to Invoker'),
(35186,0,19,0,61,0,100,0,0,0,0,0,0,33,35175,0,0,0,0,0,7,0,0,0,0,0,0,0,'Kezan Partygoer - Link - Quest Credit ''Life of the Party'''),
(35186,0,20,0,64,0,100,0,0,0,0,0,0,10,1,3,5,6,0,0,1,0,0,0,0,0,0,0,'Kezan Partygoer - On Gossip Hello - Play Random Emote (1, 3, 5, 6)'),
(35201,0,0,0,60,0,100,0,1000,9000,10000,40000,0,5,18,0,0,0,0,0,1,0,0,0,0,0,0,0,'Kezan Partygoer - On Update - Play Emote 18'),
(35201,0,1,2,8,0,100,0,66909,0,0,0,0,5,7,0,0,0,0,0,1,0,0,0,0,0,0,0,'Kezan Partygoer - On Spellhit ''Bubbly'' - Play Emote 7'),
(35201,0,2,0,61,0,100,0,0,0,0,0,0,33,35175,0,0,0,0,0,7,0,0,0,0,0,0,0,'Kezan Partygoer - Link - Quest Credit ''Life of the Party'''),
(35201,0,3,4,8,0,100,0,66910,0,0,0,0,5,17,0,0,0,0,0,1,0,0,0,0,0,0,0,'Kezan Partygoer - On Spellhit ''Bucket'' - Play Emote 17'),
(35201,0,4,0,61,0,100,0,0,0,0,0,0,33,35175,0,0,0,0,0,7,0,0,0,0,0,0,0,'Kezan Partygoer - Link - Quest Credit ''Life of the Party'''),
(35201,0,5,6,8,0,100,0,66911,0,0,0,0,5,10,0,0,0,0,0,1,0,0,0,0,0,0,0,'Kezan Partygoer - On Spellhit ''Dance'' - Play Emote 10'),
(35201,0,6,0,61,0,100,0,0,0,0,0,0,33,35175,0,0,0,0,0,7,0,0,0,0,0,0,0,'Kezan Partygoer - Link - Quest Credit ''Life of the Party'''),
(35201,0,7,8,8,0,100,0,66912,0,0,0,0,5,7,0,0,0,0,0,1,0,0,0,0,0,0,0,'Kezan Partygoer - On Spellhit ''Fireworks'' - Play Emote 7'),
(35201,0,8,0,61,0,100,0,0,0,0,0,0,33,35175,0,0,0,0,0,7,0,0,0,0,0,0,0,'Kezan Partygoer - Link - Quest Credit ''Life of the Party'''),
(35201,0,9,10,8,0,100,0,66913,0,0,0,0,5,7,0,0,0,0,0,1,0,0,0,0,0,0,0,'Kezan Partygoer - On Spellhit ''Hors D''oeuvres'' - Play Emote 7'),
(35201,0,10,0,61,0,100,0,0,0,0,0,0,33,35175,0,0,0,0,0,7,0,0,0,0,0,0,0,'Kezan Partygoer - Link - Quest Credit ''Life of the Party'''),
(35201,0,11,0,64,0,100,0,0,0,0,0,0,10,1,3,5,6,0,0,1,0,0,0,0,0,0,0,'Kezan Partygoer - On Gossip Hello - Play Random Emote (1, 3, 5, 6)'),
(35202,0,0,1,8,0,100,0,66909,0,0,0,0,5,7,0,0,0,0,0,1,0,0,0,0,0,0,0,'Kezan Partygoer - On Spellhit ''Bubbly'' - Play Emote 7'),
(35202,0,1,0,61,0,100,0,0,0,0,0,0,33,35175,0,0,0,0,0,7,0,0,0,0,0,0,0,'Kezan Partygoer - Link - Quest Credit ''Life of the Party'''),
(35202,0,2,3,8,0,100,0,66910,0,0,0,0,5,17,0,0,0,0,0,1,0,0,0,0,0,0,0,'Kezan Partygoer - On Spellhit ''Bucket'' - Play Emote 17'),
(35202,0,3,0,61,0,100,0,0,0,0,0,0,33,35175,0,0,0,0,0,7,0,0,0,0,0,0,0,'Kezan Partygoer - Link - Quest Credit ''Life of the Party'''),
(35202,0,4,5,8,0,100,0,66911,0,0,0,0,5,10,0,0,0,0,0,1,0,0,0,0,0,0,0,'Kezan Partygoer - On Spellhit ''Dance'' - Play Emote 10'),
(35202,0,5,0,61,0,100,0,0,0,0,0,0,33,35175,0,0,0,0,0,7,0,0,0,0,0,0,0,'Kezan Partygoer - Link - Quest Credit ''Life of the Party'''),
(35202,0,6,7,8,0,100,0,66912,0,0,0,0,5,7,0,0,0,0,0,1,0,0,0,0,0,0,0,'Kezan Partygoer - On Spellhit ''Fireworks'' - Play Emote 7'),
(35202,0,7,0,61,0,100,0,0,0,0,0,0,33,35175,0,0,0,0,0,7,0,0,0,0,0,0,0,'Kezan Partygoer - Link - Quest Credit ''Life of the Party'''),
(35202,0,8,9,8,0,100,0,66913,0,0,0,0,5,7,0,0,0,0,0,1,0,0,0,0,0,0,0,'Kezan Partygoer - On Spellhit ''Hors D''oeuvres'' - Play Emote 7'),
(35202,0,9,0,61,0,100,0,0,0,0,0,0,33,35175,0,0,0,0,0,7,0,0,0,0,0,0,0,'Kezan Partygoer - Link - Quest Credit ''Life of the Party'''),
(35236,0,0,1,8,0,100,0,66909,0,0,0,0,5,7,0,0,0,0,0,1,0,0,0,0,0,0,0,'Kezan Partygoer - On Spellhit ''Bubbly'' - Play Emote 7'),
(35236,0,1,0,61,0,100,0,0,0,0,0,0,33,35175,0,0,0,0,0,7,0,0,0,0,0,0,0,'Kezan Partygoer - Link - Quest Credit ''Life of the Party'''),
(35236,0,2,3,8,0,100,0,66910,0,0,0,0,5,17,0,0,0,0,0,1,0,0,0,0,0,0,0,'Kezan Partygoer - On Spellhit ''Bucket'' - Play Emote 17'),
(35236,0,3,0,61,0,100,0,0,0,0,0,0,33,35175,0,0,0,0,0,7,0,0,0,0,0,0,0,'Kezan Partygoer - Link - Quest Credit ''Life of the Party'''),
(35236,0,4,5,8,0,100,0,66911,0,0,0,0,5,10,0,0,0,0,0,1,0,0,0,0,0,0,0,'Kezan Partygoer - On Spellhit ''Dance'' - Play Emote 10'),
(35236,0,5,0,61,0,100,0,0,0,0,0,0,33,35175,0,0,0,0,0,7,0,0,0,0,0,0,0,'Kezan Partygoer - Link - Quest Credit ''Life of the Party'''),
(35236,0,6,7,8,0,100,0,66912,0,0,0,0,5,7,0,0,0,0,0,1,0,0,0,0,0,0,0,'Kezan Partygoer - On Spellhit ''Fireworks'' - Play Emote 7'),
(35236,0,7,0,61,0,100,0,0,0,0,0,0,33,35175,0,0,0,0,0,7,0,0,0,0,0,0,0,'Kezan Partygoer - Link - Quest Credit ''Life of the Party'''),
(35236,0,8,9,8,0,100,0,66913,0,0,0,0,5,7,0,0,0,0,0,1,0,0,0,0,0,0,0,'Kezan Partygoer - On Spellhit ''Hors D''oeuvres'' - Play Emote 7'),
(35236,0,9,0,61,0,100,0,0,0,0,0,0,33,35175,0,0,0,0,0,7,0,0,0,0,0,0,0,'Kezan Partygoer - Link - Quest Credit ''Life of the Party'''),
(35238,0,0,1,8,0,100,0,66909,0,0,0,0,5,7,0,0,0,0,0,1,0,0,0,0,0,0,0,'Kezan Partygoer - On Spellhit ''Bubbly'' - Play Emote 7'),
(35238,0,1,0,61,0,100,0,0,0,0,0,0,33,35175,0,0,0,0,0,7,0,0,0,0,0,0,0,'Kezan Partygoer - Link - Quest Credit ''Life of the Party'''),
(35238,0,2,3,8,0,100,0,66910,0,0,0,0,5,17,0,0,0,0,0,1,0,0,0,0,0,0,0,'Kezan Partygoer - On Spellhit ''Bucket'' - Play Emote 17'),
(35238,0,3,0,61,0,100,0,0,0,0,0,0,33,35175,0,0,0,0,0,7,0,0,0,0,0,0,0,'Kezan Partygoer - Link - Quest Credit ''Life of the Party'''),
(35238,0,4,5,8,0,100,0,66911,0,0,0,0,5,10,0,0,0,0,0,1,0,0,0,0,0,0,0,'Kezan Partygoer - On Spellhit ''Dance'' - Play Emote 10'),
(35238,0,5,0,61,0,100,0,0,0,0,0,0,33,35175,0,0,0,0,0,7,0,0,0,0,0,0,0,'Kezan Partygoer - Link - Quest Credit ''Life of the Party'''),
(35238,0,6,7,8,0,100,0,66912,0,0,0,0,5,7,0,0,0,0,0,1,0,0,0,0,0,0,0,'Kezan Partygoer - On Spellhit ''Fireworks'' - Play Emote 7'),
(35238,0,7,0,61,0,100,0,0,0,0,0,0,33,35175,0,0,0,0,0,7,0,0,0,0,0,0,0,'Kezan Partygoer - Link - Quest Credit ''Life of the Party'''),
(35238,0,8,9,8,0,100,0,66913,0,0,0,0,5,7,0,0,0,0,0,1,0,0,0,0,0,0,0,'Kezan Partygoer - On Spellhit ''Hors D''oeuvres'' - Play Emote 7'),
(35238,0,9,0,61,0,100,0,0,0,0,0,0,33,35175,0,0,0,0,0,7,0,0,0,0,0,0,0,'Kezan Partygoer - Link - Quest Credit ''Life of the Party''');

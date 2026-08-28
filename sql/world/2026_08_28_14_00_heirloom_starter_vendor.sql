-- Custom NPC 900000 'Heirloom Quartermaster': sells the full heirloom set for free,
-- spawned at every racial starting point so a fresh alt is geared before it moves.
--
-- Three things here are load-bearing and easy to get wrong on a later custom NPC:
--
--   * `ExtendedCost` = 2, not 0. VendorItem::IsGoldRequired (Creature.cpp) only skips
--     the gold charge when ExtendedCost is set and the item lacks ITEM_FLAG2_DONT_IGNORE_BUY_PRICE.
--     ItemExtendedCost.db2 row 2 is the one entry with no requirement at all, and it
--     exists client-side, so the vendor window prices everything at 0. With ExtendedCost=0
--     the DB2 BuyPrice applies instead and the list turns lopsided: helms 1500g, cloaks
--     1200g, everything else free.
--
--   * `phaseUseFlags` = 1 (PHASE_USE_FLAGS_ALWAYS_VISIBLE). This core uses the modern
--     phasing system and never reads `phaseMask`, so the WotLK trick of phaseMask=65535
--     does nothing. Gilneas, Kezan, Echo Isles, Northshire and Ebon Hold are all phased.
--
--   * `zoneId`/`areaId` are left at 0 on purpose - ObjectMgr::LoadCreatures derives them
--     from the position and writes them back.
--
-- Reserved custom id blocks: creature_template entry 900000, creature guid 5000000-5000012.

-- Level 85, faction 35 (friendly to all), immune to PC and NPC: nothing can pull
-- or kill it in a starting zone.
DELETE FROM `creature_template` WHERE `entry`=900000;
INSERT INTO `creature_template` (`entry`, `name`, `femaleName`, `subname`, `minlevel`, `maxlevel`,
  `HealthScalingExpansion`, `faction`, `npcflag`, `speed_walk`, `speed_run`, `scale`, `BaseAttackTime`,
  `RangeAttackTime`, `unit_class`, `unit_flags`, `type`, `AIName`, `RegenHealth`, `ScriptName`) VALUES
(900000, 'Heirloom Quartermaster', '', 'Heirlooms', 85, 85, 3, 35, 128, 1, 1.14286, 1, 2000, 2000, 1, 768, 7, '', 1, '');

-- The model lives here, NOT in `creature_template`.`modelid1`: that column still
-- exists but ObjectMgr::LoadCreatureTemplateModels reads `creature_template_model`
-- instead, and a template with no row here fails to spawn with
--   "Creature (Entry: 900000) has no model defined in table `creature_template`, can't load."
-- Display 12935 is a goblin merchant (Gigget Zipcoil) - neutral enough to stand in
-- an Alliance and a Horde starting village alike. Probability 1, single model.
DELETE FROM `creature_template_model` WHERE `CreatureID`=900000;
INSERT INTO `creature_template_model` (`CreatureID`, `Idx`, `CreatureDisplayID`, `Probability`, `VerifiedBuild`) VALUES
(900000, 0, 12935, 1, 0);

-- Placed 2 yards along the direction the character faces on login, turned around to
-- face them. The z is the untouched playercreateinfo z, which is guaranteed valid ground.
DELETE FROM `creature` WHERE `id`=900000;
DELETE FROM `creature` WHERE `guid` BETWEEN 5000000 AND 5000012;
INSERT INTO `creature` (`guid`, `id`, `map`, `zoneId`, `areaId`, `spawnMask`, `phaseUseFlags`, `PhaseId`,
  `PhaseGroup`, `terrainSwapMap`, `modelid`, `equipment_id`, `position_x`, `position_y`, `position_z`,
  `orientation`, `spawntimesecs`, `wander_distance`, `currentwaypoint`, `curhealth`, `curmana`,
  `MovementType`, `npcflag`, `unit_flags`, `unit_flags2`, `ScriptName`, `VerifiedBuild`) VALUES
(5000000, 900000, 0, 0, 0, 1, 1, 0, 0, -1, 0, 0, -8913.7441, -135.7305, 80.5378, 1.99647, 300, 0, 0, 1, 0, 0, NULL, NULL, NULL, '', 0),  -- Human - Northshire Valley
(5000001, 900000, 1, 0, 0, 1, 1, 0, 0, -1, 0, 0, -618.4983, -4253.6699, 38.7180, 1.58063, 300, 0, 0, 1, 0, 0, NULL, NULL, NULL, '', 0),  -- Orc - Valley of Trials
(5000002, 900000, 0, 0, 0, 1, 1, 0, 0, -1, 0, 0, -6238.3312, 330.8213, 382.7580, 3.03557, 300, 0, 0, 1, 0, 0, NULL, NULL, NULL, '', 0),  -- Dwarf - Coldridge Valley
(5000003, 900000, 1, 0, 0, 1, 1, 0, 0, -1, 0, 0, 10312.9654, 831.3555, 1326.4100, 2.55473, 300, 0, 0, 1, 0, 0, NULL, NULL, NULL, '', 0),  -- Night Elf - Shadowglen
(5000004, 900000, 0, 0, 0, 1, 1, 0, 0, -1, 0, 0, 1700.2002, 1704.5909, 135.9280, 1.74680, 300, 0, 0, 1, 0, 0, NULL, NULL, NULL, '', 0),  -- Undead - Deathknell
(5000005, 900000, 1, 0, 0, 1, 1, 0, 0, -1, 0, 0, -2913.6407, -256.7514, 59.2693, 3.44397, 300, 0, 0, 1, 0, 0, NULL, NULL, NULL, '', 0),  -- Tauren - Camp Narache
(5000006, 900000, 0, 0, 0, 1, 1, 0, 0, -1, 0, 0, -4985.4140, 877.8552, 274.3100, 6.20552, 300, 0, 0, 1, 0, 0, NULL, NULL, NULL, '', 0),  -- Gnome - New Tinkertown
(5000007, 900000, 1, 0, 0, 1, 1, 0, 0, -1, 0, 0, -1169.6889, -5264.5978, 0.8477, 2.64786, 300, 0, 0, 1, 0, 0, NULL, NULL, NULL, '', 0),  -- Troll - Echo Isles
(5000008, 900000, 648, 0, 0, 1, 1, 0, 0, -1, 0, 0, -8423.7770, 1363.2997, 104.6710, 4.69587, 300, 0, 0, 1, 0, 0, NULL, NULL, NULL, '', 0),  -- Goblin - Kezan
(5000009, 900000, 530, 0, 0, 1, 1, 0, 0, -1, 0, 0, 10350.7353, -6358.9365, 33.4026, 2.17446, 300, 0, 0, 1, 0, 0, NULL, NULL, NULL, '', 0),  -- Blood Elf - Sunstrider Isle
(5000010, 900000, 530, 0, 0, 1, 1, 0, 0, -1, 0, 0, -3962.6213, -13929.4573, 100.6150, 5.22523, 300, 0, 0, 1, 0, 0, NULL, NULL, NULL, '', 0),  -- Draenei - Ammen Vale
(5000011, 900000, 654, 0, 0, 1, 1, 0, 0, -1, 0, 0, -1449.6404, 1404.0054, 35.5561, 3.47544, 300, 0, 0, 1, 0, 0, NULL, NULL, NULL, '', 0),  -- Worgen - Gilneas City
(5000012, 900000, 609, 0, 0, 1, 1, 0, 0, -1, 0, 0, 2354.4369, -5666.1953, 426.0280, 0.79326, 300, 0, 0, 1, 0, 0, NULL, NULL, NULL, '', 0);  -- Death Knight - Ebon Hold

-- 64 items: every quality-7 entry in Item-sparse.db2 that occupies an equipment slot
-- and has a ScalingStatDistribution, minus the three leftover "Test"/"Bug" rows.
DELETE FROM `npc_vendor` WHERE `entry`=900000;
INSERT INTO `npc_vendor` (`entry`, `slot`, `item`, `maxcount`, `incrtime`, `ExtendedCost`, `type`, `PlayerConditionID`) VALUES
-- Head
(900000, 1, 61931, 0, 0, 2, 1, 0),  -- Polished Helm of Valor
(900000, 2, 61935, 0, 0, 2, 1, 0),  -- Tarnished Raging Berserker's Helm
(900000, 3, 61936, 0, 0, 2, 1, 0),  -- Mystical Coif of Elements
(900000, 4, 61937, 0, 0, 2, 1, 0),  -- Stained Shadowcraft Cap
(900000, 5, 61942, 0, 0, 2, 1, 0),  -- Preened Tribal War Feathers
(900000, 6, 61958, 0, 0, 2, 1, 0),  -- Tattered Dreadmist Mask
(900000, 7, 69887, 0, 0, 2, 1, 0),  -- Burnished Helm of Might
-- Shoulder
(900000, 8, 42949, 0, 0, 2, 1, 0),  -- Polished Spaulders of Valor
(900000, 9, 42950, 0, 0, 2, 1, 0),  -- Champion Herod's Shoulder
(900000, 10, 42951, 0, 0, 2, 1, 0),  -- Mystical Pauldrons of Elements
(900000, 11, 42952, 0, 0, 2, 1, 0),  -- Stained Shadowcraft Spaulders
(900000, 12, 42984, 0, 0, 2, 1, 0),  -- Preened Ironfeather Shoulders
(900000, 13, 42985, 0, 0, 2, 1, 0),  -- Tattered Dreadmist Mantle
(900000, 14, 44099, 0, 0, 2, 1, 0),  -- Strengthened Stockade Pauldrons
(900000, 15, 44100, 0, 0, 2, 1, 0),  -- Pristine Lightforge Spaulders
(900000, 16, 44101, 0, 0, 2, 1, 0),  -- Prized Beastmaster's Mantle
(900000, 17, 44102, 0, 0, 2, 1, 0),  -- Aged Pauldrons of The Five Thunders
(900000, 18, 44103, 0, 0, 2, 1, 0),  -- Exceptional Stormshroud Shoulders
(900000, 19, 44105, 0, 0, 2, 1, 0),  -- Lasting Feralheart Spaulders
(900000, 20, 44107, 0, 0, 2, 1, 0),  -- Exquisite Sunderseer Mantle
(900000, 21, 69890, 0, 0, 2, 1, 0),  -- Burnished Pauldrons of Might
-- Chest
(900000, 22, 48677, 0, 0, 2, 1, 0),  -- Champion's Deathdealer Breastplate
(900000, 23, 48683, 0, 0, 2, 1, 0),  -- Mystical Vest of Elements
(900000, 24, 48685, 0, 0, 2, 1, 0),  -- Polished Breastplate of Valor
(900000, 25, 48687, 0, 0, 2, 1, 0),  -- Preened Ironfeather Breastplate
(900000, 26, 48689, 0, 0, 2, 1, 0),  -- Stained Shadowcraft Tunic
(900000, 27, 69889, 0, 0, 2, 1, 0),  -- Burnished Breastplate of Might
-- Chest (robe)
(900000, 28, 48691, 0, 0, 2, 1, 0),  -- Tattered Dreadmist Robe
-- Back
(900000, 29, 62038, 0, 0, 2, 1, 0),  -- Worn Stoneskin Gargoyle Cape
(900000, 30, 62039, 0, 0, 2, 1, 0),  -- Inherited Cape of the Black Baron
(900000, 31, 62040, 0, 0, 2, 1, 0),  -- Ancient Bloodmoon Cloak
(900000, 32, 69892, 0, 0, 2, 1, 0),  -- Ripped Sandstorm Cloak
-- Legs
(900000, 33, 62023, 0, 0, 2, 1, 0),  -- Polished Legplates of Valor
(900000, 34, 62024, 0, 0, 2, 1, 0),  -- Tarnished Leggings of Destruction
(900000, 35, 62025, 0, 0, 2, 1, 0),  -- Mystical Kilt of Elements
(900000, 36, 62026, 0, 0, 2, 1, 0),  -- Stained Shadowcraft Pants
(900000, 37, 62027, 0, 0, 2, 1, 0),  -- Preened Wildfeather Leggings
(900000, 38, 62029, 0, 0, 2, 1, 0),  -- Tattered Dreadmist Leggings
(900000, 39, 69888, 0, 0, 2, 1, 0),  -- Burnished Legplates of Might
-- Finger
(900000, 40, 50255, 0, 0, 2, 1, 0),  -- Dread Pirate Ring
(900000, 41, 62035, 0, 0, 2, 1, 0),  -- Antique Myrmidon's Signet
(900000, 42, 62036, 0, 0, 2, 1, 0),  -- Ornate Band of Accuria
(900000, 43, 62037, 0, 0, 2, 1, 0),  -- Gleaming Seal of the Archmagus
(900000, 44, 69891, 0, 0, 2, 1, 0),  -- Burnished Dark Iron Ring
-- Trinket
(900000, 45, 42991, 0, 0, 2, 1, 0),  -- Swift Hand of Justice
(900000, 46, 42992, 0, 0, 2, 1, 0),  -- Discerning Eye of the Beast
(900000, 47, 44097, 0, 0, 2, 1, 0),  -- Inherited Insignia of the Horde
(900000, 48, 44098, 0, 0, 2, 1, 0),  -- Inherited Insignia of the Alliance
-- One-hand
(900000, 49, 42944, 0, 0, 2, 1, 0),  -- Balanced Heartseeker
(900000, 50, 44091, 0, 0, 2, 1, 0),  -- Sharpened Scarlet Kris
(900000, 51, 44096, 0, 0, 2, 1, 0),  -- Battleworn Thrash Blade
(900000, 52, 48716, 0, 0, 2, 1, 0),  -- Venerable Mass of McGowan
-- Two-hand
(900000, 53, 38691, 0, 0, 2, 1, 0),  -- Ancestral Claymore
(900000, 54, 42943, 0, 0, 2, 1, 0),  -- Bloodied Arcanite Reaper
(900000, 55, 42947, 0, 0, 2, 1, 0),  -- Dignified Headmaster's Charge
(900000, 56, 44092, 0, 0, 2, 1, 0),  -- Reforged Truesilver Champion
(900000, 57, 44095, 0, 0, 2, 1, 0),  -- Grand Staff of Jordan
(900000, 58, 48718, 0, 0, 2, 1, 0),  -- Repurposed Lava Dredger
-- Main hand
(900000, 59, 42945, 0, 0, 2, 1, 0),  -- Venerable Dal'Rend's Sacred Charge
(900000, 60, 42948, 0, 0, 2, 1, 0),  -- Devout Aurastone Hammer
(900000, 61, 44094, 0, 0, 2, 1, 0),  -- The Blessed Hammer of Grace
(900000, 62, 69893, 0, 0, 2, 1, 0),  -- Bloodsoaked Skullforge Reaver
-- Ranged
(900000, 63, 42946, 0, 0, 2, 1, 0),  -- Charmed Ancient Bone Bow
-- Ranged (gun)
(900000, 64, 44093, 0, 0, 2, 1, 0);  -- Upgraded Dwarven Hand Cannon

-- The two faction insignias are race-locked items; show each only to its own side.
DELETE FROM `conditions` WHERE `SourceTypeOrReferenceId`=23 AND `SourceGroup`=900000;
INSERT INTO `conditions` (`SourceTypeOrReferenceId`, `SourceGroup`, `SourceEntry`, `SourceId`, `ElseGroup`, `ConditionTypeOrReference`, `ConditionTarget`, `ConditionValue1`, `ConditionValue2`, `ConditionValue3`, `NegativeCondition`, `ErrorType`, `ErrorTextId`, `ScriptName`, `Comment`) VALUES
(23, 900000, 44098, 0, 0, 6, 0, 469, 0, 0, 0, 0, 0, '', 'Inherited Insignia of the Alliance - Alliance only'),
(23, 900000, 44097, 0, 0, 6, 0, 67, 0, 0, 0, 0, 0, '', 'Inherited Insignia of the Horde - Horde only');

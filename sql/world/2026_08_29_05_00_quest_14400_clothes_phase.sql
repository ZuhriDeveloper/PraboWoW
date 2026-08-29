-- I Can't Wear This (14400, Gilneas) - the wardrobe exists, it is in the wrong phase
--
-- Corrects 2026_08_28_23_30_quest_14400_i_cant_wear_this.sql, which removed the quest's
-- only objective on the strength of this check:
--
--   SELECT COUNT(*) FROM gameobject_template WHERE entry=27591;  -> 0
--   SELECT COUNT(*) FROM gameobject         WHERE id=27591;      -> 0
--
-- 27591 is not a gameobject entry. It is a LOOT id: gameobject_loot_template.entry is what
-- GAMEOBJECT_TYPE_CHEST stores in gameobject_template.Data1 (chest.chestLoot), not the
-- object's own entry. Resolving it the other way round finds the object immediately:
--
--   gameobject_template 196472 "Grandma's Good Clothes"  type 3 CHEST  Data1 27591
--   gameobject          236357  (-2116.1, 2431.9, 13.0)  PhaseId 181
--
-- It is spawned, it holds item 49279, and it sits 15 yards from Grandma Wahl's house at
-- (-2116.9, 2416.7, 12.3). The only thing wrong with it is the phase.
--
-- Grandma Wahl (36458) has two spawns and both are PhaseId 183, and she is the only source
-- of 14400 - so a player can never hold this quest while in phase 181, and the wardrobe is
-- unreachable for the entire window in which the quest exists. Nothing else in the database
-- wants item 49279, so the 181 spawn serves no one.
--
-- The same file's closing note claims 14399 "Grandma's Lost It Alright" is broken the same
-- way. It is not: its item 49280 comes from loot 27592 = gameobject_template 196473
-- "Linen-Wrapped Book", spawned at (-2156.6, 2371.5, 10.9) in PhaseId 183, which is correct.
-- 14401 "Grandma's Cat" (49281 from Lucius the Cruel, phase 183) and 14404 "Not Quite
-- Shipshape" (49337/49338/49339 from 196810/196809/196808, all phase 183) are also fine.
--
-- So the objective goes back in and the wardrobe moves to the phase the quest is played in.

UPDATE `gameobject` SET `PhaseId`=183 WHERE `guid`=236357;

UPDATE `quest_template` SET
  `RequiredItemId1`=49279,
  `RequiredItemCount1`=1
WHERE `ID`=14400;

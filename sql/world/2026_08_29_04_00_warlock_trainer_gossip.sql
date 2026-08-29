-- Warlock trainers - restore the "I am interested in warlock training." gossip option
--
-- Reported as: the warlock Immolate quest is broken, the spell cannot be learned
-- from the trainer. The quest itself is fine; the trainer NPC is unreachable.
--
-- The Gilneas case, quest 14274 "Immolate" (worgen warlock, Military District):
-- Vitus Darkwalker (35869) starts and ends it, LogDescription is "Speak to Vitus
-- Darkwalker and learn Immolate. Practice casting Immolate on a Bloodfang Worgen."
-- The practice half already works - Bloodfang Worgen (35118) has smart_scripts rows
-- giving kill credit 44175 on spellhit 348 - but the spell can never be learned, so
-- the objective is unreachable and the chain stops before 14287 "Safety in Numbers".
--
--
-- Why the trainer is dead
--
-- Three tables have to agree for a trainer option to work:
--
--   creature_template_gossip  35869 -> MenuID 10702      (the menu the NPC opens)
--   gossip_menu_option        10702 -> no rows at all    (the menu is empty)
--   creature_trainer          35869 -> TrainerID 32, MenuID 0, OptionID 3
--
-- Because menu 10702 has no options, Player::PrepareGossipMenu falls back to the
-- generic menu 0 (Player.cpp:13387-13390) and shows its OptionID 3 "Train me!"
-- (OptionType 5, OptionNpcflag 16 - Vitus has npcflag 51, so the flag matches).
-- The option is visible and clickable, which is why this looks like a spell/quest
-- bug rather than a gossip bug.
--
-- The click is what fails. Player::OnGossipSelect resolves the trainer with
--
--   GetCreatureTrainerForGossipOption(entry, menuId, gossipListId)   Player.cpp:13633
--
-- where menuId is the menu actually opened - 10702, not the menu the fallback
-- borrowed the option from - and gossipListId is the DB OptionID echoed back by the
-- client (GossipDef.cpp:215, option.ClientOption = itr.first). So the lookup key is
-- (35869, 10702, 3) while creature_trainer only supplies (35869, 0, 3).
-- ObjectMgr::GetCreatureTrainerForGossipOption does an exact tuple lookup with no
-- fallback (ObjectMgr.cpp:9179), returns 0, and WorldSession::SendTrainerList bails
-- on GetTrainer(0) == nullptr with only a "network" debug line. Nothing opens.
--
-- The direct CMSG_TRAINER_LIST path does not save it either: that one asks for
-- (entry, 0, 0) (NPCHandler.cpp:112), which is not the row we have.
--
-- Trainers whose creature_trainer MenuID matches their own menu are unaffected -
-- Drusilla La Salle (459, menu 1503), Nartok (3156, 4643), Evol Fingers (34696,
-- 10681) - which is why the human, orc, undead and goblin warlocks can learn
-- Immolate and the worgen, dwarf, blood elf and troll ones cannot.
--
--
-- The fix
--
-- Give each of these menus the trainer option it should have had, and repoint
-- creature_trainer at (own menu, OptionID 0). This is exactly the shape of the
-- trainers that already work, e.g. gossip_menu_option (1503, 0, icon 3, broadcast
-- text 2544, OptionType 5, OptionNpcflag 16) + creature_trainer (459, 32, 1503, 0).
-- Broadcast text 2544 is the sniffed "I am interested in warlock training." line.
--
-- Adding a row to these menus also ends the menu-0 fallback for them, which is
-- intended: the trainer option is the only default option their npcflags (49/51 =
-- GOSSIP | QUESTGIVER | TRAINER | TRAINER_CLASS) could ever produce, and the quest
-- list is built from UNIT_NPC_FLAG_QUESTGIVER by PrepareQuestMenu, not from menu 0.
--
-- Scope: every warlock trainer (trainer_class 9) whose creature_trainer row is
-- unreachable - 17 NPCs over 13 menus. Each of the 13 menus is used only by warlock
-- trainers and each of the 17 NPCs has exactly one creature_trainer row, so no other
-- NPC is touched. Menu 2522 (Larn Caverndeep) has no gossip_menu row and therefore
-- keeps rendering with DEFAULT_GOSSIP_MESSAGE, exactly as it does today.
--
-- Not fixed here: the same mismatch exists on 218 more creature_trainer rows for
-- other classes and professions. They are a separate sweep - this file stays inside
-- the reported bug.
--
-- To revert: delete the gossip_menu_option rows below and restore creature_trainer
-- to MenuID 0 / OptionID 3 for the same 17 CreatureIDs.

-- 1) the missing trainer option on each warlock trainer menu
DELETE FROM `gossip_menu_option` WHERE `MenuID` IN (2522,4602,4608,10702,10840,11645,11831,12053,12526,12845,12882,12921,14138) AND `OptionID`=0;
INSERT INTO `gossip_menu_option`
    (`MenuID`,`OptionID`,`OptionIcon`,`OptionText`,`OptionBroadcastTextID`,`OptionType`,`OptionNpcflag`,`ActionMenuID`,`ActionPoiID`,`BoxCoded`,`BoxMoney`,`BoxText`,`BoxBroadcastTextID`,`VerifiedBuild`)
VALUES
    ( 2522,0,3,'I am interested in warlock training.',2544,5,16,0,0,0,0,NULL,0,0),  -- Larn Caverndeep
    ( 4602,0,3,'I am interested in warlock training.',2544,5,16,0,0,0,0,NULL,0,0),  -- Chintoka
    ( 4608,0,3,'I am interested in warlock training.',2544,5,16,0,0,0,0,NULL,0,0),  -- Maressa Milner, Bee Bruxworthy
    (10702,0,3,'I am interested in warlock training.',2544,5,16,0,0,0,0,NULL,0,0),  -- Vitus Darkwalker (Gilneas City)
    (10840,0,3,'I am interested in warlock training.',2544,5,16,0,0,0,0,NULL,0,0),  -- Vitus Darkwalker (Duskhaven, Stormglen)
    (11645,0,3,'I am interested in warlock training.',2544,5,16,0,0,0,0,NULL,0,0),  -- Voldreka
    (11831,0,3,'I am interested in warlock training.',2544,5,16,0,0,0,0,NULL,0,0),  -- Saripal Smolderbrew
    (12053,0,3,'I am interested in warlock training.',2544,5,16,0,0,0,0,NULL,0,0),  -- Kazrali the Witch, Evol Fingers
    (12526,0,3,'I am interested in warlock training.',2544,5,16,0,0,0,0,NULL,0,0),  -- Solbin Shadowcog
    (12845,0,3,'I am interested in warlock training.',2544,5,16,0,0,0,0,NULL,0,0),  -- Redia Vaunt
    (12882,0,3,'I am interested in warlock training.',2544,5,16,0,0,0,0,NULL,0,0),  -- Vitus Darkwalker (Stormwind)
    (12921,0,3,'I am interested in warlock training.',2544,5,16,0,0,0,0,NULL,0,0),  -- Summoner Durael
    (14138,0,3,'I am interested in warlock training.',2544,5,16,0,0,0,0,NULL,0,0);  -- Summoner Teli'Larien

-- 2) point each trainer at its own menu and that option
DELETE FROM `creature_trainer` WHERE `CreatureID` IN (15283,35869,36652,38797,42618,43455,44469,45720,48612,49718,49791,49895,50017,50028,50502,50732,53404);
INSERT INTO `creature_trainer` (`CreatureID`,`TrainerID`,`MenuID`,`OptionID`) VALUES
(15283, 32,14138,0),  -- Summoner Teli'Larien  - starts 10073 'Immolation' (blood elf)
(35869, 32,10702,0),  -- Vitus Darkwalker      - starts 14274 'Immolate' (worgen)
(36652,154,10840,0),  -- Vitus Darkwalker      - Duskhaven
(38797,154,10840,0),  -- Vitus Darkwalker      - Stormglen / Tempest's Reach
(42618, 32,11645,0),  -- Voldreka              - starts 26274 'The Arts of a Warlock' (troll)
(43455, 32,11831,0),  -- Saripal Smolderbrew   - starts 26904 'Harnessing the Flames' (dwarf)
(44469,154,10702,0),  -- Vitus Darkwalker      - Gilneas City, later phase
(45720,154,12053,0),  -- Kazrali the Witch
(48612,154, 4608,0),  -- Maressa Milner
(49718,154, 4608,0),  -- Bee Bruxworthy
(49791,154,12526,0),  -- Solbin Shadowcog
(49895,154,12053,0),  -- Evol Fingers
(50017,154,12921,0),  -- Summoner Durael
(50028,154, 4602,0),  -- Chintoka
(50502,154,12882,0),  -- Vitus Darkwalker      - Stormwind
(50732,154, 2522,0),  -- Larn Caverndeep
(53404,154,12845,0);  -- Redia Vaunt

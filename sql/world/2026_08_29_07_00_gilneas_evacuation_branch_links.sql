-- Duskhaven evacuation (Gilneas) - tie each branch quest back to its own branch
--
-- The evacuation is three parallel routes that all end at 14465 "To Greymane Manor", and
-- TDB does carry the mutual exclusion that picks one of them:
--
--   ExclusiveGroup 14400 : 14400 I Can't Wear This    | 14406 The Crowley Orchard
--   ExclusiveGroup 14401 : 14401 Grandma's Cat        | 14404 Not Quite Shipshape  | 14416 The Hungry Ettin
--   ExclusiveGroup 14402 : 14402 Ready to Go          | 14405 Escape By Sea        | 14463 Horses for Duskhaven
--
-- What it does not carry is the link from each quest back to the one before it in its own
-- route: PrevQuestID is 0 on all six of the second and third tier quests. Player::CanTakeQuest
-- therefore offers 14401, 14404 and 14416 side by side, from three different NPCs, to anyone
-- past level 4 - and whichever of the three a player touches first locks the other two
-- through SatisfyQuestExclusiveGroup, no matter which route they were actually on.
--
-- That is how a character that had done 14400 (the Grandma Wahl route) could pick up 14416
-- from the orchard route and permanently lose 14401, the quest that route was supposed to
-- lead to.
--
-- The links below restore the three routes:
--
--   14399 -+- 14400 -> 14401 -> 14402 -+-> 14465
--          +- 14406 -> 14416 -> 14463 -+
--             14403 -> 14404 -> 14405 -+
--
-- Five of the six come straight out of the data: quest_template.RewardNextQuest already
-- points 14400->14401, 14401->14402, 14406->14416, 14416->14463 and 14404->14405, so these
-- rows only state the same edges in the direction the availability check reads. The sixth,
-- 14403 -> 14404, has no RewardNextQuest to derive from and is taken from the quest givers
-- instead: 14403 is handed out by Gwen Armstead and turned in to Sebastian Hayward, who is
-- the one that starts 14404.
--
-- SatisfyQuestPreviousQuest treats a previous quest that sits in a positive exclusive group
-- as one-from-all and returns true as soon as it is rewarded, so nothing here can deadlock a
-- route that is already under way.

UPDATE `quest_template_addon` SET `PrevQuestID`=14400 WHERE `ID`=14401;
UPDATE `quest_template_addon` SET `PrevQuestID`=14401 WHERE `ID`=14402;
UPDATE `quest_template_addon` SET `PrevQuestID`=14403 WHERE `ID`=14404;
UPDATE `quest_template_addon` SET `PrevQuestID`=14404 WHERE `ID`=14405;
UPDATE `quest_template_addon` SET `PrevQuestID`=14406 WHERE `ID`=14416;
UPDATE `quest_template_addon` SET `PrevQuestID`=14416 WHERE `ID`=14463;

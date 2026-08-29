-- Gilneas chapter 3 - database side of gilneas_chapter_3.cpp
--
-- Wires up the two quests that had every piece of data except the script that drives them:
-- 24468 "Stranded at the Marsh" and 24616 "Losing Your Tail". The core only shipped
-- gilneas_chapter_1.cpp and gilneas_chapter_2.cpp, so everything past Greymane Manor was
-- unscripted.
--
--
-- 1) Quest 24468 - Stranded at the Marsh
--
-- 11 Crash Survivors (37067) sit in the Hailwood Marsh in phase 186, and the quest counts
-- five kills of 37078 while displaying "Crash Survivor rescued"
-- (quest_template.RequiredNpcOrGo1 = 37078, ObjectiveText1). 37078 has no spawns of its own
-- because it is summoned - spell 69854 "Summon Swamp Crocolisk" exists for exactly that.
--
-- What was missing is the trigger: 37067 has npcflag 0, no npc_spellclick_spells row, no
-- AIName and no ScriptName, and the quest hands out no item, so a player had nothing to
-- interact with. npc_gilneas_crash_survivor springs the ambush when a player carrying the
-- quest comes within 12 yards, and the crocolisk kill is the rescue.

UPDATE `creature_template` SET `ScriptName`='npc_gilneas_crash_survivor' WHERE `entry`=37067;

--
-- 2) Quest 24616 - Losing Your Tail
--
-- The encounter is authored across three spells that nothing ever connected:
--
--   70794 Freezing Trap Effect  stun + force-cast 95845 + force-cast 70795
--   70795 Summon Dark Scout     summons 37953 at TARGET_DEST_CASTER_FRONT, 5 min duration
--   70797 Belysra's Talisman    the quest start item (49944); EFFECT_1 is a dummy aimed at
--                               TARGET_UNIT_NEARBY_ENTRY
--   70796 Aimed Shot            the scout's ability
--
-- and creature_text already holds her line: "How did you--?!  It doesn't matter -- I don't
-- need a trap to defeat you."
--
-- Two data gaps had to be closed on top of the script.
--
-- TARGET_UNIT_NEARBY_ENTRY carries no entry in the spell itself; TrinityCore resolves it
-- from a CONDITION_SOURCE_TYPE_SPELL_IMPLICIT_TARGET row. Without one the dummy effect
-- never picks a target. SourceGroup 2 is the effect mask for EFFECT_1.
--
-- 37953 also still carries placeholder stats - minlevel/maxlevel 1 and faction 35, which is
-- friendly to everyone, so she could not be attacked at all. Level and faction are set from
-- her siblings in the same chapter and phase (Forsaken Infantry 37692 is level 10-11 with
-- faction 83, in phase 186 in the Blackwald). Those two values are inferred, not sniffed;
-- everything else about her is left untouched, unit_class 8 included.

UPDATE `creature_template` SET
  `ScriptName`='npc_gilneas_dark_scout',
  `minlevel`=11,
  `maxlevel`=11,
  `faction`=83
WHERE `entry`=37953;

DELETE FROM `conditions` WHERE `SourceTypeOrReferenceId`=13 AND `SourceEntry`=70797;
INSERT INTO `conditions`
    (`SourceTypeOrReferenceId`,`SourceGroup`,`SourceEntry`,`SourceId`,`ElseGroup`,
     `ConditionTypeOrReference`,`ConditionTarget`,`ConditionValue1`,`ConditionValue2`,`ConditionValue3`,
     `NegativeCondition`,`ErrorType`,`ErrorTextId`,`ScriptName`,`Comment`)
VALUES
    (13,2,70797,0,0,31,0,3,37953,0,0,0,0,'',"Belysra's Talisman targets Dark Scout");

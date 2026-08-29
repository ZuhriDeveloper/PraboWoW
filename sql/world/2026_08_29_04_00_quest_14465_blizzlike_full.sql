-- To Greymane Manor (14465) - complete, self-contained setup for the Duskhaven -> manor leg
--
-- Consolidates and supersedes the 2026_08_28_21_00 / 2026_08_29_00_30 / 01_15 / 02_00 /
-- 03_00 files. Every statement here sets an absolute end state rather than a delta, so it
-- lands correctly no matter which of those earlier files actually reached a given database.
--
--
-- What was still broken
--
-- The horse, the gates and the phase content were all fixed by the earlier files, and yet
-- the manor stayed empty. `.debug phase` on the test character printed `Flags 8`
-- (PhaseShiftFlags::Unphased) and no `Phases:` line at all - PhasingHandler::PrintToChat
-- only emits that line when PhaseShift::Phases is non-empty, so the character held no
-- phase whatsoever, and every NPC at the manor is phased.
--
-- The reason is the shape of the Gilneas phase rules, not the manor data. Phase 183 is
-- granted by `spell_area` 68483 keyed on **quest 14386 "Leader of the Pack" being
-- rewarded** - a quest four steps back in a chain (14375 -> 14321 -> 14386) that any
-- character which was jumped, GM-advanced or partially progressed will not satisfy. Such a
-- character can be handed 14465 and still be completely unphased, which is exactly what
-- happened: the only thing that ever lit the courtyard up was `69254 Carriage Ride` from
-- the horse, so the NPCs existed while mounted and vanished the moment the player stepped
-- off. That is the "NPCs keep appearing and disappearing" report.
--
-- The fix is to key the phase to the quest that actually needs it. `spell_area` rows are
-- OR-ed, not AND-ed: SpellInfo::CheckLocation returns SPELL_CAST_OK as soon as a single row
-- fits (SpellInfo.cpp, the "DB base check" block) and Player::UpdateZoneDependentAuras
-- casts on the first fitting row, so a second row for 68483 is an alternative condition,
-- never a restriction on the first. Adding one keyed on 14465 also means the phase is
-- applied the instant the quest is accepted, through Player::SendQuestUpdate
-- (Player.cpp:15369) - mSpellAreaForQuestMap is indexed by questStart, so no relog, no zone
-- change and no aura bookkeeping is involved.
--
--
-- 1) Gwen Armstead hands out the ride when 14465 is accepted
--
--   69256 Forcecast Summon Swift Mountain Horse  SPELL_EFFECT_FORCE_CAST -> 69255
--   69255 Summon Swift Mountain Horse            SUMMON 36741, SummonProperties 827
--   69254 Carriage Ride                          CONTROL_VEHICLE (+ a phase 184 that is
--                                                now redundant, see section 2)
--
-- 14465 does not carry QUEST_FLAGS_PLAYER_CAST_ACCEPT and 69256 targets
-- TARGET_UNIT_TARGET_ANY, so Player::AddQuest makes Gwen the caster and the player the
-- target (Player.cpp:14307) - the forcecast then has the player cast 69255 himself, which
-- is what puts the summon at his feet and him in the saddle rather than her.
--
-- 36741 must be a vehicle: Spell::EffectSummonType only casts the ride spell when
-- `summon->IsVehicle()`. 527 is the vehicle the Mountain Horse of the previous quest
-- already uses (seat 6086, CAN_ENTER_OR_EXIT | CAN_CONTROL). speed_run is raised to match
-- that same horse - TDB has 36741 at 1.14286, which is an unsniffed default and leaves a
-- mount named "Swift" slower than the one from the quest before it, on a quest whose whole
-- content is the ride.

UPDATE `quest_template_addon` SET `SourceSpellID`=69256 WHERE `ID`=14465;
UPDATE `creature_template`    SET `VehicleId`=527, `speed_run`=1.71429 WHERE `entry`=36741;

-- 2) One phase for the whole leg
--
-- Phase 184 held nothing but manor courtyard content (Queen Mia, Princess Tess, 28
-- Duskhaven Villagers, crows, benches, chairs, the gate). Splitting the manor off into a
-- second phase bought nothing and cost everything, because the only mechanism that granted
-- it was the aura on a horse the player is meant to dismount. Everything moves into 183,
-- the phase the whole chapter already runs in.
--
-- 36962 "Injured Villager" is authored once per snapshot, 4.2 - 8.8 yards apart, so the
-- sparse pre-camp pair is dropped to avoid four of them. `creature_addon` is the only table
-- referencing those guids.

UPDATE `creature`   SET `PhaseId`=183 WHERE `map`=654 AND `PhaseId`=184;
UPDATE `gameobject` SET `PhaseId`=183 WHERE `map`=654 AND `PhaseId`=184;
DELETE FROM `creature_addon` WHERE `guid` IN (256015,256016);
DELETE FROM `creature`       WHERE `guid` IN (256015,256016);

-- 3) Grant phase 183 to anyone actually on this quest
--
-- Row one is the untouched retail condition. Row two is the alternative: hold 14465 in any
-- state and you are in the Duskhaven/manor world, however you came by the quest. Both close
-- at 24438 "Exodus" being rewarded, which is the quest that leaves the manor.
--
-- Statuses follow the mask the other Gilneas rows use: 64 = REWARDED,
-- 74 = COMPLETE|INCOMPLETE|REWARDED, 43 = anything but REWARDED.
--
-- LoadSpellAreas does not treat these as duplicates - its check bails out as soon as
-- questStart differs (SpellMgr.cpp) - and 69077 goes away because phase 184 is now empty.

DELETE FROM `spell_area` WHERE `spell` IN (68483,69077) AND `area`=4714;
INSERT INTO `spell_area`
    (`spell`,`area`,`quest_start`,`quest_end`,`aura_spell`,`racemask`,`gender`,`flags`,`quest_start_status`,`quest_end_status`)
VALUES
    (68483,4714,14386,24438,0,0,2,3,64,43),
    (68483,4714,14465,24438,0,0,2,3,74,43);

-- 4) Hand over to phase 186 for the next chapter
--
-- 24438 "Exodus" is given by King Genn (phase 183, observatory) and handed in to Prince
-- Liam Greymane (phase 186, Stagecoach Crash Site -2222.1, 1809.6, 11.8), so 186 has to be
-- live while Exodus is in the log or the turn-in NPC cannot be seen. Holding 183 and 186
-- together is safe: on map 654 they are disjoint (183 spans y 2112..2708, 186 spans
-- y 748..1998) with no 186 spawn anywhere near the manor. The window closes at 24904
-- "The Battle for Gilneas City", after which phase 187 takes over.

DELETE FROM `spell_area` WHERE `spell`=69484 AND `area`=4714;
INSERT INTO `spell_area`
    (`spell`,`area`,`quest_start`,`quest_end`,`aura_spell`,`racemask`,`gender`,`flags`,`quest_start_status`,`quest_end_status`)
VALUES
    (69484,4714,24438,24904,0,0,2,3,74,43);

-- 5) Both gates, both leaves, open and out of the way
--
-- Each of these four entries has exactly one spawn and all four are gates on this route.
-- They are spawned in GO_STATE_ACTIVE so m_prevGoState is ACTIVE and any reset returns them
-- to open, and flagged GO_FLAG_NOT_SELECTABLE so nothing can trigger a close - both DOOR
-- leaves carry door.autoClose = 3, which GameObjectTemplate::GetAutoCloseTime hands back
-- raw in milliseconds (GameObjectData.h:587), making them impossible to open by clicking.

UPDATE `gameobject` SET `state`=0 WHERE `guid` IN (235520,236492,235514,236493);
UPDATE `gameobject_template_addon` SET `flags`=`flags`|16 WHERE `entry` IN (196399,196863,196401,196864);

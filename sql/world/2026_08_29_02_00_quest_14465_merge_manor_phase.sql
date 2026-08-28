-- Greymane Manor (quests 14465 -> 14467, Gilneas) - collapse phase 184 into phase 183
--
-- Supersedes the phase half of 2026_08_29_00_30_quest_14465_horse_and_manor_phase.sql.
-- The horse half of that file (quest_template_addon.SourceSpellID = 69256 on 14465,
-- creature_template 36741 VehicleId = 527) is correct and stays, and so do the two gate
-- leaves opened on 2026-08-28/29.
--
--
-- Why
--
-- `.debug phase` on the test character printed `Flags 8` (PhaseShiftFlags::Unphased,
-- PhaseShift.h:31) and **no `Phases:` line at all** - PhasingHandler::PrintToChat only
-- emits that line when PhaseShift::Phases is non-empty, so the character was holding no
-- phase whatsoever. Within 150 yards of Queen Mia there are 40 creature spawns and every
-- one of them is phased (36 in phase 184, 4 in phase 183, none unphased), so the only
-- thing that ever made the courtyard appear was `69254 Carriage Ride`, the aura the
-- summoned horse casts back on its rider. Mount up and the manor exists; step off the
-- saddle, or let the 360 s summon expire, and all 36 NPCs blink out. That is the
-- "NPCs keep switching phase" report.
--
-- The structural cause is that every Gilneas phase is handed out by a `spell_area` aura,
-- and those are only re-evaluated on login, on zone change, or on a quest status change
-- (Player::UpdateZoneDependentAuras, Player.cpp:24459; Player::SendQuestUpdate,
-- Player.cpp:15369). Nothing re-checks them while the player simply walks around, which
-- is exactly when the manor needs to stay visible.
--
-- Rather than add a second, differently-fragile mechanism, this drops the second phase
-- entirely: everything in 184 moves to 183, the phase the whole Duskhaven chapter already
-- runs in. One phase, no aura in the visibility path, nothing left that can half-apply.
-- The cost is that the refugee camp becomes visible from the moment 14386 is rewarded
-- instead of at 14465 - which reads fine, since the evacuation is the story of that
-- entire chapter.
--
--
-- 1) Merge phase 184 into phase 183
--
-- Phase 184 holds nothing but manor courtyard content: Queen Mia (36606), Princess Tess
-- (36742), 28 Duskhaven Villagers (36453), 13 Gilnean Crows (50260), 2 Injured Villagers
-- (36962), the manor gate 196864, 7 Benches and 14 Rocking Chairs. All of them use
-- `PhaseId` with `PhaseGroup` = 0, so one UPDATE per table covers it.
--
-- Cross-checking 183 against 184 on map 654 found no gameobject pair within 10 yards and
-- no creature of a different entry within 3 yards, so the merge introduces no overlap
-- other than the one handled below.

UPDATE `creature`   SET `PhaseId`=183 WHERE `map`=654 AND `PhaseId`=184;  -- 45 rows
UPDATE `gameobject` SET `PhaseId`=183 WHERE `map`=654 AND `PhaseId`=184;  -- 22 rows

-- 2) Drop the duplicated Injured Villagers
--
-- 36962 is authored twice, once per snapshot, 4.2 - 8.8 yards apart:
--
--   phase 183: guid 256015 (-1592.5, 2585.3), guid 256016 (-1588.8, 2582.0)
--   phase 184: guid 256007 (-1595.3, 2582.2), guid 256011 (-1591.1, 2576.7)
--
-- Keep the refugee-camp pair that comes with Mia and the villagers, drop the sparse
-- pre-camp pair. `creature_addon` is the only table referencing those two guids -
-- `pool_members` and `game_event_creature` have no rows for them, and 36962 is neither a
-- quest starter nor an ender.

DELETE FROM `creature_addon` WHERE `guid` IN (256015,256016);
DELETE FROM `creature`       WHERE `guid` IN (256015,256016);

-- 3) Remove the now-dead phase 184 rule
--
-- With no objects left in 184, spell 69077 grants an empty phase and would only confuse
-- the next person reading this. `69254 Carriage Ride` still puts a rider in 184; that is
-- now inert, which is the point - visibility must not depend on staying mounted.

DELETE FROM `spell_area` WHERE `spell`=69077 AND `area`=4714 AND `quest_start`=14465;

-- 4) Keep phase 183 alive long enough for King Genn
--
-- 68483 currently ends at `quest_end` = 14466. King Genn Greymane (36743, guid 256017,
-- phase 183) is the ender of 14466 *and* both giver and ender of 14467 "Alas, Gilneas!",
-- so the moment 14466 is rewarded the phase drops and the next quest giver vanishes on
-- the spot. Moving the boundary to 14467 lets the observatory scene be reached.

UPDATE `spell_area` SET `quest_end`=14467 WHERE `spell`=68483 AND `area`=4714;

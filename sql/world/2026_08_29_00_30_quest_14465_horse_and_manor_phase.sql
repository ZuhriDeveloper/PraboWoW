-- To Greymane Manor (quest 14465, Gilneas) - follow-up to 2026_08_28_21_00
--
-- The earlier pass fixed the two things that were visible from Duskhaven: the gate
-- on the road out of town and the spellclick flag on Mountain Horse (36540). Both
-- of those are still correct and are left alone. What it missed is that the whole
-- Greymane Manor half of the quest lives in phase 184, which nothing in this DB
-- ever grants, and that the ride Gwen Armstead is supposed to hand out is a quest
-- source spell, not one of the roadside horses from 14463.
--
--
-- 1) Gwen Armstead never gives the horse
--
-- 36540 is the horse chain for "Horses for Duskhaven" (14463): 20 spawns strung
-- along the road at x -2260..-2085, i.e. Lorna Crowley's leg of the trip. None of
-- them are anywhere near Gwen (-1901.8, 2255.9), so making them spellclickable did
-- nothing for 14465.
--
-- The 14465 ride is a different creature and is handed out on quest accept:
--
--   69256 'Forcecast Summon Swift Mountain Horse'  SPELL_EFFECT_FORCE_CAST -> 69255
--   69255 'Summon Swift Mountain Horse'            SUMMON 36741, properties 827
--   69254 'Carriage Ride'                          SPELL_AURA_PHASE 184 + CONTROL_VEHICLE
--
-- SummonProperties 827 is category 4 (vehicle) and `summon_properties_parameters`
-- already types it as RideSpell (ParamType 4), so Spell::EffectSummonType reads the
-- effect's base points - 69254 - and casts it caster->summon (SpellEffects.cpp, the
-- `extraArgs.RideSpell` branch). That is the whole mechanism: the player ends up in
-- the seat *and* picks up phase 184 from effect 0 of 69254, which targets the caster.
--
-- Two things were missing.
--
--   * quest_template_addon.SourceSpellID for 14465 was 0. Setting it to 69256 makes
--     Player::AddQuest fire it: 14465 does not carry QUEST_FLAGS_PLAYER_CAST_ACCEPT
--     (Flags 2359304) and 69256 targets TARGET_UNIT_TARGET_ANY, so Gwen is the caster
--     and the player is the target (Player.cpp:14307) - exactly what a forcecast
--     wants. 69255 is then cast by the player, so the summon is at the player's feet
--     and the player, not Gwen, is the one who mounts.
--   * 36741 had VehicleId 0. EffectSummonType only casts the ride spell when
--     `summon->IsVehicle()`, so without it the horse would spawn and just stand
--     there - and, worse, no phase 184. 527 is the vehicle the Mountain Horse
--     already uses (seat 6086, CAN_ENTER_OR_EXIT | CAN_CONTROL), which is the right
--     shape for a rideable horse; TDB has no sniffed vehicle for 36741 at all.
--
--
-- 2) Nothing at Greymane Manor is reachable
--
-- This is what the "gate does not open" report actually is. Everything past the
-- manor drive is in phase 184:
--
--   creature 256006  Queen Mia Greymane    PhaseId 184   <- questender 14465, queststarter 14466
--   creature 256009  Princess Tess         PhaseId 184
--   creature x28     Duskhaven Villager    PhaseId 184
--   gameobject 236493 (196864, BUTTON)     PhaseId 184   <- the manor gate, state 1 = shut
--
-- and the only phase a player holds during 14465 is 183, from spell 68483 via
-- spell_area (area 4714, 14386 rewarded .. 14466 not rewarded), plus 105 from
-- phase_area. `spell_area` has rows for 68481/68482/68483 (Zone-Specific 06/07/08 ->
-- phases 181/182/183) but none for 69077 'Phase - Quest Zone-Specific 09' -> 184.
-- 69077 is byte-identical to 68483 apart from the phase id: same attributes, same
-- infinite duration index 21, aura 261 on TARGET_UNIT_CASTER.
--
-- So the player rides up to the manor, sees no gate, no queen and no villagers, and
-- has no way to hand in 14465 or pick up 14466. Adding the missing rule with the
-- window "14465 taken .. 14466 not rewarded" covers both quests:
--
--   quest_start_status 74 = COMPLETE|INCOMPLETE|REWARDED (14465 has no objectives,
--                           so it flips to COMPLETE the moment it is accepted)
--   quest_end_status   43 = the not-rewarded set the other three Gilneas rows use
--
-- Phases are additive - PhaseShift::CanSee only ever grants sight - so handing the
-- player 184 on top of 183 hides nothing.
--
-- This also means the phase is not tied to staying on the horse. 69254 rides on the
-- summon, and 69255's summon duration is only 360000 ms (index 41), so dismounting
-- or dawdling for six minutes would otherwise drop the player out of 184 and strand
-- them in an empty courtyard.
--
--
-- 3) The manor gate itself
--
-- Same treatment as the Duskhaven gate in the previous file, for the same reason:
-- spawn it open so m_prevGoState is ACTIVE and any reset returns it to open, and
-- flag it unselectable so nothing can trigger the 5000 ms autoclose. 196864 has
-- exactly one spawn and it is this gate, so the template addon is safe to touch.
-- The 196401 leaf stacked on the same spot stays untouched: PhaseGroup 379 is
-- {169,170,171,172}, none of which a player holds during 14465/14466.

-- 1) Gwen hands out the Swift Mountain Horse on accept, and the horse is a vehicle
UPDATE `quest_template_addon` SET `SourceSpellID`=69256 WHERE `ID`=14465;
UPDATE `creature_template` SET `VehicleId`=527 WHERE `entry`=36741;

-- 2) grant phase 184 for the Greymane Manor leg (14465 taken .. 14466 rewarded)
DELETE FROM `spell_area` WHERE `spell`=69077 AND `area`=4714 AND `quest_start`=14465;
INSERT INTO `spell_area`
    (`spell`,`area`,`quest_start`,`quest_end`,`aura_spell`,`racemask`,`gender`,`flags`,`quest_start_status`,`quest_end_status`)
VALUES
    (69077,4714,14465,14466,0,0,2,3,74,43);

-- 3) open the Greymane Manor gate and take it out of the click targets
UPDATE `gameobject` SET `state`=0 WHERE `guid`=236493;
UPDATE `gameobject_template_addon` SET `flags`=`flags`|16 WHERE `entry`=196864;

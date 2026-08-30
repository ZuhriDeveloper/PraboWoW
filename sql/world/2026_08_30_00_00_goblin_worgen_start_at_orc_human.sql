-- Goblin and Worgen - start in the Orc / Human starting zone instead of Kezan / Gilneas
--
-- The two Cataclysm starting experiences are not shippable on this core:
--
--   Kezan + Lost Isles (QuestSortID 4737 + 4720) : 116 quests, 0 C++ scripts.
--     There is no src/server/scripts directory for either zone at all, and the data is
--     holed in the places that matter. Nine quest givers referenced by
--     creature_queststarter / creature_questender have zero rows in `creature`:
--       34957 Ace, 34958 Gobber, 34959 Izzy   - all three are the objectives of
--                                               14071 'Rolling with my Homies'
--       35486 First Bank of Kezan Vault       - objective of 14122 'The Great Bank Heist'
--       37114 Steamwheedle Shark              - objective of 24502 'Necessary Roughness',
--                                               which additionally has no questender row
--       37598 Gasbot                          - objective of 14125
--       36608 Doc Zapnozzle                   - ender of 14239
--       38928 Sassy Hardwrench                - ender of 24958, starter of 25023
--       39199 Assistant Greely                - starter/ender of 25122, 25123, 25125
--     The last two break the chain outright: nothing can hand in 'Volcanoth!' and nothing
--     offers 'Light at the End of the Tunnel'.
--
--   Gilneas (QuestSortID 4714 / 4755) : partially repaired over the 2026_08_28 and
--     2026_08_29 patches, still incomplete, and two quests are already parked in
--     docs/quest-auto-complete.md as deliberate skips.
--
-- Rather than keep paying down both zones, new Goblins are dropped in the Orc start
-- (Valley of Trials, Durotar) and new Worgen in the Human start (Northshire, Elwynn
-- Forest), and both are handed the racials their starting zone would have taught them.
--
-- Why those two destinations work without further data edits:
--   Durotar  (QuestSortID 14) : 80 quests accept Goblin, 3 do not (6365, 926, 14088 -
--                               Troll/Undead-gated, none of them chain-critical).
--   Elwynn   (QuestSortID 12) : 49 quests accept Worgen. The Northshire chain is
--                               human-gated (AllowableRaces 1) but Blizzard ships a
--                               parallel non-human set at AllowableRaces 8388606 -
--                               29078 'Beating Them Back!', 29079 'Lions for Lambs',
--                               29080 'Join the Battle!', 29081 'They Sent Assassins',
--                               29082 'Fear No Evil', 29083 'The Rear is Clear'.
--                               So no AllowableRaces edits are needed here.
--
-- Player::TeleportTo gates Goblins inside map 648 until quest 25265 is rewarded and
-- Worgen inside map 654 until 26706 is rewarded (Player.cpp:1477-1487). Neither gate can
-- fire any more because characters never spawn on those maps. It still applies to anyone
-- teleported there by a GM afterwards - that is a known, accepted trap.

-- ---------------------------------------------------------------------------------------
-- 1. Create position
-- ---------------------------------------------------------------------------------------
-- Values are copied verbatim from the race whose start is being reused, so both races land
-- exactly where Orcs / Humans do. `playercreateinfo` is also the homebind fallback -
-- Player::_LoadHomeBind takes info->mapId/areaId/positionX/Y/Z when a character has no
-- character_homebind row (Player.cpp:18951-18956) - so the hearthstone follows for free.
--
-- class 6 (Death Knight) is excluded on purpose: every race starts DKs at Ebon Hold
-- (map 609, zone 4298) and those rows must stay untouched.

UPDATE `playercreateinfo` SET
  `map`=1, `zone`=14,
  `position_x`=-618.518, `position_y`=-4251.67, `position_z`=38.718, `orientation`=4.72222
WHERE `race`=9 AND `class`<>6;

UPDATE `playercreateinfo` SET
  `map`=0, `zone`=9,
  `position_x`=-8914.57, `position_y`=-133.909, `position_z`=80.5378, `orientation`=5.13806
WHERE `race`=22 AND `class`<>6;

-- ---------------------------------------------------------------------------------------
-- 2. Racials the skipped starting zone would have taught
-- ---------------------------------------------------------------------------------------
-- Racial abilities come from SkillLineAbility.dbc, skill 789 'Racial - Worgen' and skill
-- 790 'Racial - Goblin'. Player::LearnSkillRewardedSpells only auto-learns rows whose
-- AcquireMethod is AutomaticCharLevel (1) or AutomaticSkillRank (2); everything else is
-- skipped (Player.cpp:23439-23446).
--
-- Blizzard split each racial into two rows: one for Death Knights (ClassMask 32) with
-- AcquireMethod 2, and one for every other class (ClassMask 1503) with AcquireMethod 0.
-- DKs never run a racial starting zone, so they are handed the racials directly; everyone
-- else is expected to earn them from the questline. Skipping the questline therefore
-- leaves a non-DK Goblin/Worgen permanently short:
--
--   Worgen : 68975 Viciousness, 68976 Aberration, 68978 Flayer,
--            68992 Darkflight, 68996 Two Forms, 94293 Enable Worgen Altered Form
--   Goblin : 69046 Pack Hobgoblin
--
-- Everything else on those two skill lines is already AcquireMethod 2 for ClassMask 0/1535
-- and is learned normally - 79742/79749 Languages, 69001 Transform: Worgen, 87840 Running
-- Wild, and the five automatic Goblin racials (69041 Rocket Barrage, 69042 Time is Money,
-- 69044 Best Deals Anywhere, 69045 Better Living Through Chemistry, 69070 Rocket Jump).
-- None of those are touched here.
--
-- `playercreateinfo_spell_custom` is NOT usable for this: Player::LearnCustomSpells()
-- returns immediately unless CONFIG_START_ALL_SPELLS is set (Player.cpp:23273-23276), and
-- worldserver.conf ships PlayerStart.AllSpells = 0. `playercreateinfo_cast_spell` has no
-- such guard - it is cast on the character's first login, in world, triggered
-- (CharacterHandler.cpp:1003-1005), which is exactly when a LEARN_SPELL effect works.
--
-- The three spells below are Blizzard's own teaching spells, each verified against
-- SpellEffect.dbc to contain nothing but SPELL_EFFECT_LEARN_SPELL (36) - no transform, no
-- teleport, no aura:
--
--   72792 'Learn Worgen Racials 1'         -> 68975, 68978, 68976
--   95834 'Worgen Enabler Cheat [INTERNAl]'-> 94293, 68996, 68992
--   77534 'Pack Hobgoblin'                 -> 69046
--
-- ClassMask 1503 = every class except Death Knight, matching the DBC rows being
-- compensated for. Casting these on a DK would be a harmless no-op, but excluding them
-- keeps the intent readable.
--
-- Note the resulting Worgen default state: the character is in worgen form and can toggle
-- to human with Two Forms. That is the post-questline state, not the mid-Gilneas one.

DELETE FROM `playercreateinfo_cast_spell` WHERE `spell` IN (72792,95834,77534);
INSERT INTO `playercreateinfo_cast_spell` (`raceMask`,`classMask`,`spell`,`note`) VALUES
    (256,     1503, 77534, 'Goblin - Pack Hobgoblin (69046), normally from the Kezan chain'),
    (2097152, 1503, 72792, 'Worgen - Viciousness/Flayer/Aberration, normally from the Gilneas chain'),
    (2097152, 1503, 95834, 'Worgen - Altered Form/Two Forms/Darkflight, normally from the Gilneas chain');

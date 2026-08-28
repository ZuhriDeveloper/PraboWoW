-- Sacrifices (quest 14212) - Crowley's Horse survivability
--
-- Same treatment as King Greymane's Horse in
-- 2026_08_28_17_00_quest_14293_horse_health.sql: the ride goes straight through
-- the Bloodfang packs in Gilneas City and the mount is a level 5 creature, so it
-- dies well before the escort finishes.
--
-- 35231 is the horse ridden for 14212 (VehicleId 463, summoned by spell 67001).
-- 44428 is the later-chapter twin (VehicleId 1025, spell 82992) and gets the same
-- value so the two rides behave alike. 44427 is left alone - it has no VehicleId
-- and no script, it is the prop horse standing next to Lord Darius Crowley.
--
-- HealthModifier 20 -> 600, matching 35905 so all three quest mounts are equally
-- hard to lose.

UPDATE `creature_template` SET `HealthModifier`=600 WHERE `entry` IN (35231,44428);

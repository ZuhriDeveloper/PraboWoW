-- Save Krennan Aranas (quest 14293) - King Greymane's Horse survivability
--
-- The horse (35905) is a level 5 vehicle that carries the player past the
-- Bloodfang packs in Gilneas City. It dies to them, and when it does the
-- worldserver segfaults - observed on the VPS at the end of
-- greymanesHorsePath1, no `Halting process...` and no `ASSERTION FAILED`
-- in the log, the process simply stops.
--
-- STOPGAP, not the fix. This only makes the horse hard enough to kill that
-- the ride finishes; the crash in the death path is still there and still
-- needs the stack trace to be located. Do not close the crash bug on this.
--
-- HealthModifier 6 -> 600 (100x). Crowley's horse (35231 / 44428) ships at 20
-- for the same kind of ride, so 6 was low even before the crash mattered.

UPDATE `creature_template` SET `HealthModifier`=600 WHERE `entry`=35905;

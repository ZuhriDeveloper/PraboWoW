/*
 * PraboWoW playerbot module -- logging compatibility shim.
 *
 * mod-playerbots logs through AzerothCore's fmt-style LOG_INFO("playerbots", "{}", x).
 * This core is printf-style TC_LOG_INFO("playerbots", "%s", x). Ported files route through
 * these macros so the call sites keep one shape and the whole module shares one log
 * category, which can then be configured from worldserver.conf:
 *
 *     Logger.playerbots = 4,Console Server
 *
 * Follow the LOS precedent and set that in the deploy overlay
 * (tools/configure-server.ps1, deploy/entrypoint.sh) rather than in .dist -- live server
 * decisions live outside the submodule.
 */

#ifndef PRABOBOTS_LOG_H
#define PRABOBOTS_LOG_H

#include "Log.h"

#define PRABOBOTS_LOG_CATEGORY "playerbots"

#define PRABOBOTS_LOG_INFO(...)  TC_LOG_INFO(PRABOBOTS_LOG_CATEGORY, __VA_ARGS__)
#define PRABOBOTS_LOG_ERROR(...) TC_LOG_ERROR(PRABOBOTS_LOG_CATEGORY, __VA_ARGS__)
#define PRABOBOTS_LOG_DEBUG(...) TC_LOG_DEBUG(PRABOBOTS_LOG_CATEGORY, __VA_ARGS__)

#endif // PRABOBOTS_LOG_H

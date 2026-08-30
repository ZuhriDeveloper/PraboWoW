/*
 * PraboWoW playerbot module -- packet filter for bot sessions.
 */

#ifndef PRABOBOTS_BOT_PACKET_FILTER_H
#define PRABOBOTS_BOT_PACKET_FILTER_H

#include "WorldSession.h"

/*
 * Lets PlayerbotMgr tick a socketless session without the core deleting it.
 *
 * WorldSession::Update calls ProcessQueryCallbacks() unconditionally -- that is what
 * completes the async login holder -- but the block below it, guarded by
 * updater.ProcessUnsafe(), ends in:
 *
 *     if (!m_Socket[CONNECTION_TYPE_REALM])
 *         return false;                  // Will remove this session from the world session map
 *
 * Returning false from ProcessUnsafe() keeps the tick out of that block entirely, so a bot
 * session gets its callbacks without ever asking to be destroyed. MapSessionFilter does the
 * same thing for the Map::Update path, for the same structural reason.
 *
 * PacketFilter is the one type here that is genuinely designed for subclassing: virtual
 * destructor, virtual Process, virtual ProcessUnsafe. WorldSession is not, which is why
 * PlayerbotMgr holds a plain WorldSession rather than deriving from it.
 */
class BotPacketFilter final : public PacketFilter
{
public:
    explicit BotPacketFilter(WorldSession* session) : PacketFilter(session) { }

    // Nothing is queued into a bot session yet. When packet injection arrives we want the
    // bot's own synthetic packets processed, not filtered by rules that exist to guard
    // against a hostile socket we do not have.
    bool Process(WorldPacket* /*packet*/) override { return true; }

    bool ProcessUnsafe() const override { return false; }
};

#endif // PRABOBOTS_BOT_PACKET_FILTER_H

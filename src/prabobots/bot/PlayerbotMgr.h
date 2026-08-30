/*
 * PraboWoW playerbot module -- bot session ownership and lifecycle.
 */

#ifndef PRABOBOTS_PLAYERBOT_MGR_H
#define PRABOBOTS_PLAYERBOT_MGR_H

#include "Define.h"
#include "ObjectGuid.h"
#include "Common.h"

#include <memory>
#include <string>
#include <unordered_map>
#include <vector>

class Player;
class WorldSession;

enum class BotState : uint8
{
    LoginQueued,        // session created, waiting on the async login holder
    InWorld,            // Player exists and is in a map
    Failed              // login did not complete; queued for removal
};

struct PlayerbotEntry
{
    std::unique_ptr<WorldSession> Session;
    ObjectGuid BotGuid;
    ObjectGuid OwnerGuid;
    uint32     AccountId = 0;
    BotState   State     = BotState::LoginQueued;
    uint32     WaitedMs  = 0;
};

/*
 * Owns every bot session in the world.
 *
 * Bot sessions are deliberately kept out of World::m_sessions. That map is keyed by account
 * id, and World::AddSession_ kicks and deletes any existing session sharing an account id --
 * since a bot is an alt on the owner's own account (ADR 0001), inserting one would destroy
 * the owner's session. So this class stands in for World::UpdateSessions where bots are
 * concerned, driven from WorldScript::OnUpdate.
 *
 * Once a bot Player is in a map the core also ticks its session from Map::Update. Both that
 * path and ours use a filter with ProcessUnsafe() == false, so neither can delete the
 * session; real players are double-ticked the same way by design.
 */
class PlayerbotMgr
{
public:
    static PlayerbotMgr* instance();

    PlayerbotMgr(PlayerbotMgr const&) = delete;
    PlayerbotMgr& operator=(PlayerbotMgr const&) = delete;

    // outError is filled with a player-facing reason when these return false.
    bool AddBot(Player* owner, std::string const& botName, std::string& outError);
    bool RequestRemoveBot(std::string const& botName, std::string& outError);

    void RequestRemoveAllBotsOf(uint32 accountId);
    void RemoveAllBots();

    void Update(uint32 diff);

    bool IsBot(ObjectGuid guid) const;
    std::vector<PlayerbotEntry const*> GetBotsOf(uint32 accountId) const;

    static constexpr uint32 MaxBotsPerAccount = 10;
    static constexpr uint32 LoginTimeoutMs    = 30 * IN_MILLISECONDS;

private:
    PlayerbotMgr() = default;
    ~PlayerbotMgr();

    WorldSession* CreateBotSession(uint32 accountId, uint8 accountExpansion, LocaleConstant locale) const;
    void DestroyBot(PlayerbotEntry& entry);

    std::unordered_map<ObjectGuid, PlayerbotEntry> _bots;
    std::vector<ObjectGuid> _pendingRemoval;
};

#define sPlayerbotMgr PlayerbotMgr::instance()

#endif // PRABOBOTS_PLAYERBOT_MGR_H

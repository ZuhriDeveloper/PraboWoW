/*
 * PraboWoW playerbot module -- bot session ownership and lifecycle.
 */

#include "PlayerbotMgr.h"

#include "AccountMgr.h"
#include "BotPacketFilter.h"
#include "CharacterCache.h"
#include "ObjectAccessor.h"
#include "Player.h"
#include "PrabobotsLog.h"
#include "WorldSession.h"

#include <utility>

PlayerbotMgr* PlayerbotMgr::instance()
{
    static PlayerbotMgr instance;
    return &instance;
}

PlayerbotMgr::~PlayerbotMgr()
{
    // WorldScript::OnShutdown is the intended teardown, while maps and the database are
    // still alive. This is only the backstop for an unexpected exit path.
    _bots.clear();
}

WorldSession* PlayerbotMgr::CreateBotSession(uint32 accountId, uint8 accountExpansion, LocaleConstant locale) const
{
    std::string accountName;
    AccountMgr::GetName(accountId, accountName);

    // SEC_PLAYER regardless of what the owner holds -- a bot must never inherit GM rights.
    WorldSession* session = new WorldSession(accountId, std::move(accountName), nullptr, SEC_PLAYER,
        accountExpansion, /*mute_time*/ 0, locale, /*recruiter*/ 0, /*isARecruiter*/ false);

    // Must precede LoginBotPlayer: every packet the core sends before this is set would be
    // logged as an error against a socket that does not exist.
    session->SetBotSession(true);

    // Defence in depth. WorldSession::Update's idle-connection check is what would otherwise
    // fire on the first tick, and the core patch that null-guards it is the real fix -- but
    // leaving m_timeOutTime at 0 here would also make IsConnectionIdle() permanently true.
    session->ResetTimeOutTime(false);

    return session;
}

bool PlayerbotMgr::AddBot(Player* owner, std::string const& botName, std::string& outError)
{
    if (!owner)
    {
        outError = "No owner character.";
        return false;
    }

    WorldSession* ownerSession = owner->GetSession();
    if (ownerSession->IsBotSession())
    {
        outError = "A bot cannot add bots.";
        return false;
    }

    uint32 const accountId = ownerSession->GetAccountId();

    if (GetBotsOf(accountId).size() >= MaxBotsPerAccount)
    {
        outError = "Bot limit for this account reached.";
        return false;
    }

    CharacterCacheEntry const* cached = sCharacterCache->GetCharacterCacheByName(botName);
    if (!cached)
    {
        outError = "No such character.";
        return false;
    }

    // LoginBotPlayer deliberately skips IsLegitCharacterForAccount, so ownership is enforced
    // here instead. Player::LoadFromDB rejects a mismatched account too, but by then the
    // session already exists and has to be torn down -- this is the gate, that is the backstop.
    if (cached->AccountId != accountId)
    {
        outError = "That character is not on your account.";
        return false;
    }

    if (cached->Guid == owner->GetGUID())
    {
        outError = "You cannot add yourself as a bot.";
        return false;
    }

    if (ObjectAccessor::FindConnectedPlayer(cached->Guid))
    {
        outError = "That character is already online.";
        return false;
    }

    if (IsBot(cached->Guid))
    {
        outError = "That character is already a bot.";
        return false;
    }

    PlayerbotEntry entry;
    entry.Session.reset(CreateBotSession(accountId, ownerSession->GetAccountExpansion(), ownerSession->GetSessionDbLocaleIndex()));
    entry.BotGuid   = cached->Guid;
    entry.OwnerGuid = owner->GetGUID();
    entry.AccountId = accountId;
    entry.State     = BotState::LoginQueued;

    if (!entry.Session->LoginBotPlayer(cached->Guid))
    {
        outError = "Could not start the login query for that character.";
        PRABOBOTS_LOG_ERROR("AddBot: LoginBotPlayer failed for %s (%s)", botName.c_str(), cached->Guid.ToString().c_str());
        return false;
    }

    PRABOBOTS_LOG_INFO("AddBot: %s (%s) queued by %s on account %u",
        botName.c_str(), cached->Guid.ToString().c_str(), owner->GetName().c_str(), accountId);

    _bots.emplace(cached->Guid, std::move(entry));
    return true;
}

bool PlayerbotMgr::RequestRemoveBot(std::string const& botName, std::string& outError)
{
    CharacterCacheEntry const* cached = sCharacterCache->GetCharacterCacheByName(botName);
    if (!cached)
    {
        outError = "No such character.";
        return false;
    }

    auto itr = _bots.find(cached->Guid);
    if (itr == _bots.end())
    {
        outError = "That character is not an active bot.";
        return false;
    }

    _pendingRemoval.push_back(cached->Guid);
    return true;
}

void PlayerbotMgr::RequestRemoveAllBotsOf(uint32 accountId)
{
    for (auto const& botPair : _bots)
        if (botPair.second.AccountId == accountId)
            _pendingRemoval.push_back(botPair.first);
}

void PlayerbotMgr::RemoveAllBots()
{
    for (auto& botPair : _bots)
        DestroyBot(botPair.second);

    _bots.clear();
    _pendingRemoval.clear();
}

void PlayerbotMgr::DestroyBot(PlayerbotEntry& entry)
{
    // LogoutPlayer does the whole job: saves the character, Map::RemovePlayerFromMap ->
    // ObjectAccessor::RemoveObject, and clears the session's player pointer. KickPlayer would
    // be the obvious call but it is a complete no-op for a socketless session -- it only sets
    // forceExit inside an if (m_Socket[i]).
    if (entry.Session && entry.Session->GetPlayer())
    {
        PRABOBOTS_LOG_INFO("RemoveBot: logging out %s", entry.BotGuid.ToString().c_str());
        entry.Session->LogoutPlayer(true);
    }
}

void PlayerbotMgr::Update(uint32 diff)
{
    // Drained first, and populated only from the chat command handler, which runs earlier in
    // the tick (World::UpdateSessions). So a session is never destroyed while its own Update
    // is on the stack.
    for (ObjectGuid const& guid : _pendingRemoval)
    {
        auto itr = _bots.find(guid);
        if (itr == _bots.end())
            continue;

        DestroyBot(itr->second);
        _bots.erase(itr);
    }
    _pendingRemoval.clear();

    for (auto& botPair : _bots)
    {
        PlayerbotEntry& entry = botPair.second;
        WorldSession* session = entry.Session.get();

        BotPacketFilter filter(session);
        session->Update(diff, filter);

        Player* player = session->GetPlayer();

        // Session plumbing, not AI. Player::TeleportTo across maps sets mSemaphoreTeleport_Far
        // and waits for a CMSG_MOVE_WORLDPORT_ACK that will never arrive from a bot. The core
        // exposes HandleMoveWorldportAck() for exactly this ("for server-side calls") and
        // LogoutPlayer drives it in the same loop shape. Without it, .summon hangs a bot
        // permanently.
        if (player)
            while (player->IsBeingTeleportedFar())
                session->HandleMoveWorldportAck();

        switch (entry.State)
        {
            case BotState::LoginQueued:
                entry.WaitedMs += diff;

                if (player && player->IsInWorld())
                {
                    entry.State = BotState::InWorld;
                    PRABOBOTS_LOG_INFO("Bot %s is in world (map %u, zone %u)",
                        player->GetName().c_str(), player->GetMapId(), player->GetZoneId());
                }
                else if (!player && !session->PlayerLoading())
                {
                    // m_playerLoading is set by LoginBotPlayer and cleared only on success or
                    // on a LoadFromDB failure, so this is a precise failure signal.
                    entry.State = BotState::Failed;
                    PRABOBOTS_LOG_ERROR("Bot %s failed to load", entry.BotGuid.ToString().c_str());
                    _pendingRemoval.push_back(entry.BotGuid);
                }
                else if (entry.WaitedMs > LoginTimeoutMs)
                {
                    entry.State = BotState::Failed;
                    PRABOBOTS_LOG_ERROR("Bot %s timed out after %u ms waiting to log in",
                        entry.BotGuid.ToString().c_str(), entry.WaitedMs);
                    _pendingRemoval.push_back(entry.BotGuid);
                }
                break;

            case BotState::InWorld:
                if (!player)
                {
                    PRABOBOTS_LOG_ERROR("Bot %s lost its player unexpectedly", entry.BotGuid.ToString().c_str());
                    entry.State = BotState::Failed;
                    _pendingRemoval.push_back(entry.BotGuid);
                }
                break;

            case BotState::Failed:
                break;
        }
    }
}

bool PlayerbotMgr::IsBot(ObjectGuid guid) const
{
    return _bots.find(guid) != _bots.end();
}

std::vector<PlayerbotEntry const*> PlayerbotMgr::GetBotsOf(uint32 accountId) const
{
    std::vector<PlayerbotEntry const*> result;
    for (auto const& botPair : _bots)
        if (botPair.second.AccountId == accountId)
            result.push_back(&botPair.second);

    return result;
}

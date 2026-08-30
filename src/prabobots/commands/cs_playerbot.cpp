/*
 * PraboWoW playerbot module -- .bot chat commands and script registration.
 */

#include "Chat.h"
#include "ObjectAccessor.h"
#include "Player.h"
#include "PlayerbotMgr.h"
#include "PrabobotsLog.h"
#include "RBAC.h"
#include "ScriptMgr.h"
#include "WorldSession.h"

using namespace Trinity::ChatCommands;

class playerbot_commandscript : public CommandScript
{
public:
    playerbot_commandscript() : CommandScript("playerbot_commandscript") { }

    std::vector<ChatCommand> GetCommands() const override
    {
        // RBAC_PERM_COMMAND_GM is reused deliberately for this milestone. A dedicated
        // RBAC_PERM_COMMAND_BOT would need an RBAC.h enum patch plus rows in
        // auth.rbac_permissions and auth.rbac_linked_permissions -- worth doing before bots
        // are ever offered to non-GM players, but not to prove a session works.
        //
        // allowConsole is false throughout: every handler needs an owner character.
        static std::vector<ChatCommand> botCommandTable =
        {
            { "add",    rbac::RBAC_PERM_COMMAND_GM, false, &HandleBotAddCommand,    "" },
            { "remove", rbac::RBAC_PERM_COMMAND_GM, false, &HandleBotRemoveCommand, "" },
            { "list",   rbac::RBAC_PERM_COMMAND_GM, false, &HandleBotListCommand,   "" },
        };

        static std::vector<ChatCommand> commandTable =
        {
            { "bot",    rbac::RBAC_PERM_COMMAND_GM, false, nullptr, "", botCommandTable },
        };

        return commandTable;
    }

    static bool HandleBotAddCommand(ChatHandler* handler, std::string const& name)
    {
        std::string error;
        if (!sPlayerbotMgr->AddBot(handler->GetSession()->GetPlayer(), name, error))
        {
            handler->SendSysMessage(error.c_str());
            handler->SetSentErrorMessage(true);
            return false;
        }

        handler->PSendSysMessage("Bot %s logging in...", name.c_str());
        return true;
    }

    static bool HandleBotRemoveCommand(ChatHandler* handler, std::string const& name)
    {
        std::string error;
        if (!sPlayerbotMgr->RequestRemoveBot(name, error))
        {
            handler->SendSysMessage(error.c_str());
            handler->SetSentErrorMessage(true);
            return false;
        }

        handler->PSendSysMessage("Bot %s queued for removal.", name.c_str());
        return true;
    }

    static bool HandleBotListCommand(ChatHandler* handler)
    {
        uint32 const accountId = handler->GetSession()->GetAccountId();
        std::vector<PlayerbotEntry const*> bots = sPlayerbotMgr->GetBotsOf(accountId);

        if (bots.empty())
        {
            handler->SendSysMessage("No bots active.");
            return true;
        }

        handler->PSendSysMessage("Active bots (%u):", uint32(bots.size()));
        for (PlayerbotEntry const* entry : bots)
        {
            Player* player = entry->Session ? entry->Session->GetPlayer() : nullptr;
            char const* state = "logging in";
            if (entry->State == BotState::InWorld)
                state = "in world";
            else if (entry->State == BotState::Failed)
                state = "failed";

            if (player)
                handler->PSendSysMessage("  %s - %s (map %u, zone %u)",
                    player->GetName().c_str(), state, player->GetMapId(), player->GetZoneId());
            else
                handler->PSendSysMessage("  %s - %s", entry->BotGuid.ToString().c_str(), state);
        }

        return true;
    }
};

class playerbot_worldscript : public WorldScript
{
public:
    playerbot_worldscript() : WorldScript("playerbot_worldscript") { }

    // Dispatched from ScriptMgr::OnWorldUpdate, after World::UpdateSessions and after
    // MapMgr::Update. Removals queued by a chat command earlier in the same tick are
    // therefore drained here, never while the session's own Update is on the stack.
    void OnUpdate(uint32 diff) override
    {
        sPlayerbotMgr->Update(diff);
    }

    // Fired from Main.cpp after the world update loop returns but before the map manager and
    // database scope guards run, so bot characters are still saveable here. Without this,
    // bot Players survive into Map teardown.
    void OnShutdown() override
    {
        PRABOBOTS_LOG_INFO("Shutdown: removing all bots");
        sPlayerbotMgr->RemoveAllBots();
    }
};

class playerbot_playerscript : public PlayerScript
{
public:
    playerbot_playerscript() : PlayerScript("playerbot_playerscript") { }

    void OnLogout(Player* player) override
    {
        // Guarded so a bot's own logout does not queue removal of its siblings.
        if (player->GetSession()->IsBotSession())
            return;

        sPlayerbotMgr->RequestRemoveAllBotsOf(player->GetSession()->GetAccountId());
    }
};

// Called from core/src/server/scripts/Custom/custom_script_loader.cpp behind
// #ifdef TRINITY_PRABOBOTS.
void AddPlayerbotScripts()
{
    new playerbot_commandscript();
    new playerbot_worldscript();
    new playerbot_playerscript();
}

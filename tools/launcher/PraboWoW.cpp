// PraboWoW.exe — one-click launcher handed to players.
//
// It exists so nobody has to be walked through editing Config.wtf. The player drops three
// files into their own 4.3.4 client folder and double-clicks this one:
//
//     PraboWoW.exe              <- this program
//     client_launcher_64.exe    <- built from TrinityCore, injects the patch
//     client_patcher_64.dll     <- the patch itself
//
// What it does, in order: verify it is sitting in a real client folder, point
// WTF\Config.wtf at our realm (backing the original up once), then hand off to
// client_launcher_64.exe. It NEVER touches Wow-64.exe — the patch lives in memory only.
//
// It deliberately does not ship, contain, or download any Blizzard game data. The player
// supplies their own 4.3.4.15595 client; client_launcher verifies that build and refuses
// anything else.
//
// Built by tools/build-launcher.ps1 with /MT, so it runs on a bare Windows install with no
// Visual C++ redistributable.

#include <windows.h>

#include <cstdio>
#include <filesystem>
#include <fstream>
#include <string>
#include <vector>

namespace fs = std::filesystem;

#ifndef PRABOWOW_REALM
#define PRABOWOW_REALM "wow.zuhri-dev.com"
#endif

namespace
{
    constexpr char const* kRealm = PRABOWOW_REALM;

    constexpr wchar_t const* kClientExe    = L"Wow-64.exe";
    constexpr wchar_t const* kLauncherExe  = L"client_launcher_64.exe";
    constexpr wchar_t const* kPatcherDll   = L"client_patcher_64.dll";
    constexpr wchar_t const* kBackupSuffix = L".prabowow-backup";

    void Fail(std::string const& message)
    {
        std::printf("\n  PROBLEM: %s\n\n  Press Enter to close...", message.c_str());
        (void)std::getchar();
    }

    fs::path OwnDirectory()
    {
        std::vector<wchar_t> buffer(MAX_PATH);
        for (;;)
        {
            DWORD const written = GetModuleFileNameW(nullptr, buffer.data(), static_cast<DWORD>(buffer.size()));
            if (written == 0)
                return {};
            // Truncation is reported by filling the buffer exactly; grow and retry.
            if (written < buffer.size() - 1)
                break;
            buffer.resize(buffer.size() * 2);
        }
        return fs::path(buffer.data()).parent_path();
    }

    bool StartsWithNoCase(std::string const& line, char const* prefix)
    {
        size_t i = 0;
        for (; prefix[i] != '\0'; ++i)
        {
            if (i >= line.size())
                return false;
            if (std::tolower(static_cast<unsigned char>(line[i])) != std::tolower(static_cast<unsigned char>(prefix[i])))
                return false;
        }
        return true;
    }

    // Rewrites only the `SET portal` line and leaves every other setting alone, the same rule
    // the server-side config generators follow: touch what we own, preserve what we do not.
    // Returns false only on I/O failure; "already correct" is a success.
    bool PointConfigAtRealm(fs::path const& clientDir, bool& changed)
    {
        changed = false;

        fs::path const wtfDir  = clientDir / L"WTF";
        fs::path const config  = wtfDir / L"Config.wtf";
        std::string const want = std::string("SET portal \"") + kRealm + "\"";

        std::error_code ec;
        fs::create_directories(wtfDir, ec);
        if (ec)
            return false;

        std::vector<std::string> lines;
        bool replaced = false;

        if (fs::exists(config))
        {
            std::ifstream in(config);
            if (!in)
                return false;

            std::string line;
            while (std::getline(in, line))
            {
                if (!line.empty() && line.back() == '\r')
                    line.pop_back();

                if (StartsWithNoCase(line, "SET portal"))
                {
                    if (line == want)
                        lines.push_back(line);      // already ours; keep byte-for-byte
                    else
                    {
                        lines.push_back(want);
                        changed = true;
                    }
                    replaced = true;
                }
                else
                    lines.push_back(line);
            }
        }

        if (!replaced)
        {
            lines.push_back(want);
            changed = true;
        }

        if (!changed)
            return true;

        // Back up the player's original exactly once. A second run must not overwrite the
        // backup with a file we already modified -- that would destroy the only copy of
        // their real settings.
        fs::path const backup = config.wstring() + kBackupSuffix;
        if (fs::exists(config) && !fs::exists(backup))
        {
            fs::copy_file(config, backup, ec);
            if (ec)
                return false;
        }

        std::ofstream out(config, std::ios::binary | std::ios::trunc);
        if (!out)
            return false;
        for (std::string const& line : lines)
            out << line << "\r\n";

        return out.good();
    }

    bool RunLauncher(fs::path const& clientDir)
    {
        fs::path const launcher = clientDir / kLauncherExe;

        // client_launcher takes the game DIRECTORY, not the path to the exe -- its --path
        // help text says "Path to the Wow.exe" but the code treats it as a folder and
        // appends the executable name itself.
        std::wstring commandLine = L"\"" + launcher.wstring() + L"\" --path \"" + clientDir.wstring() + L"\"";

        STARTUPINFOW startupInfo{};
        startupInfo.cb = sizeof(startupInfo);
        PROCESS_INFORMATION processInfo{};

        BOOL const ok = CreateProcessW(
            launcher.c_str(), commandLine.data(), nullptr, nullptr, FALSE,
            0, nullptr, clientDir.c_str(), &startupInfo, &processInfo);

        if (!ok)
            return false;

        CloseHandle(processInfo.hThread);
        CloseHandle(processInfo.hProcess);
        return true;
    }
}

int main()
{
    std::printf("PraboWoW launcher\n");
    std::printf("realm: %s\n\n", kRealm);

    fs::path const clientDir = OwnDirectory();
    if (clientDir.empty())
    {
        Fail("could not determine which folder this program is in.");
        return 1;
    }

    std::printf("client folder: %ls\n", clientDir.c_str());

    // Check all three up front and name the missing one. "It doesn't work" is the most
    // expensive answer a player can give, so the failure has to name its own fix.
    struct Requirement { wchar_t const* file; char const* hint; };
    Requirement const required[] = {
        { kClientExe,   "This is not a World of Warcraft folder, or it is a 32-bit client.\n"
                        "           Put PraboWoW.exe in the folder that contains Wow-64.exe." },
        { kLauncherExe, "Missing. Copy it from the server owner along with client_patcher_64.dll." },
        { kPatcherDll,  "Missing. It must sit in this same folder, next to client_launcher_64.exe." },
    };

    for (Requirement const& req : required)
    {
        if (!fs::exists(clientDir / req.file))
        {
            std::string name;
            for (wchar_t const* p = req.file; *p; ++p)
                name.push_back(static_cast<char>(*p));
            Fail(name + " was not found here.\n           " + req.hint);
            return 1;
        }
    }

    bool changed = false;
    if (!PointConfigAtRealm(clientDir, changed))
    {
        Fail("could not write WTF\\Config.wtf.\n"
             "           If the client is installed under Program Files, either move it\n"
             "           elsewhere or run this once as Administrator.");
        return 1;
    }

    if (changed)
        std::printf("Config.wtf now points at %s (original saved as Config.wtf%ls)\n", kRealm, kBackupSuffix);
    else
        std::printf("Config.wtf already points at %s\n", kRealm);

    std::printf("\nStarting the game...\n");

    if (!RunLauncher(clientDir))
    {
        Fail("client_launcher_64.exe would not start.\n"
             "           Antivirus software sometimes blocks it, because it injects the\n"
             "           patch into the game's memory. Allow it and try again.");
        return 1;
    }

    // The first ever run downloads ~13 Battle.net auth modules; say so, or the wait looks
    // like a hang. The filenames are SHA256 digests of their own contents and the launcher
    // verifies them, so the download is self-checking.
    std::printf("\nThe launcher window will do the rest.\n");
    std::printf("On the very first run it downloads a few authentication modules --\n");
    std::printf("that needs an internet connection and happens only once.\n");

    return 0;
}

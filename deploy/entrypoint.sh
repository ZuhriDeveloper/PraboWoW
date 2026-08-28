#!/usr/bin/env bash
#
# Container entrypoint — the Linux twin of tools/configure-server.ps1.
#
# It renders worldserver.conf / authserver.conf from the shipped .conf.dist at every start,
# rewriting ONLY the keys this project needs and leaving the other ~1400 lines untouched, so
# upgrading the core is a matter of rebuilding rather than hand-merging a config. Values come
# from environment variables instead of script parameters, so credentials live in the VPS
# .env file and never in the image.
#
# Keep the override list below in sync with tools/configure-server.ps1. Two lists that drift
# apart is exactly the failure this comment exists to prevent.
#
# Usage (set by compose):  entrypoint.sh worldserver | authserver

set -euo pipefail

ROLE="${1:-worldserver}"

# ── Inputs ───────────────────────────────────────────────────────────────────────────────
DB_HOST="${DB_HOST:-db}"
DB_PORT="${DB_PORT:-3306}"
DB_USER="${DB_USER:-trinity}"
DB_PASSWORD="${DB_PASSWORD:?DB_PASSWORD is required}"

DATA_DIR="${DATA_DIR:-/trinity/data}"
LOGS_DIR="${LOGS_DIR:-/trinity/logs}"
TDB_DIR="${TDB_DIR:-/trinity/tdb}"
CONF_DIR="${CONF_DIR:-/trinity/etc}"
DIST_DIR="${DIST_DIR:-/opt/trinitycore/etc}"
BIN_DIR="${BIN_DIR:-/opt/trinitycore/bin}"
SOURCE_DIR="${SOURCE_DIR:-/opt/trinitycore}"

RATE_XP="${RATE_XP:-5}"
RATE_DROP_ITEM="${RATE_DROP_ITEM:-5}"
RATE_DROP_MONEY="${RATE_DROP_MONEY:-5}"

REALM_ID="${REALM_ID:-1}"
REALM_ADDRESS="${REALM_ADDRESS:-}"
REALM_LOCAL_ADDRESS="${REALM_LOCAL_ADDRESS:-$REALM_ADDRESS}"
REALM_PORT="${REALM_PORT:-8085}"

NO_MMAPS="${NO_MMAPS:-0}"
TDB_AUTO_DOWNLOAD="${TDB_AUTO_DOWNLOAD:-1}"
TDB_VERSION="${TDB_VERSION:-434.22011}"
TDB_ASSET="${TDB_ASSET:-TDB_full_434.22011_2022_01_09.7z}"
TDB_WORLD_SQL="TDB_full_world_434.22011_2022_01_09.sql"
TDB_HOTFIXES_SQL="TDB_full_hotfixes_434.22011_2022_01_09.sql"

log() { printf '[entrypoint] %s\n' "$*"; }
die() { printf '[entrypoint] FATAL: %s\n' "$*" >&2; exit 1; }

mkdir -p "$CONF_DIR" "$LOGS_DIR" "$TDB_DIR"

# ── Config rendering ─────────────────────────────────────────────────────────────────────

# Rewrite one setting line. Anchored at the start of the line so the commented documentation
# block above each setting (every line of it starts with '#') survives untouched. A key that
# has no setting line is a hard error: it means the core's config format changed and this
# script is silently no longer configuring the server.
set_conf() {
    local file=$1 key=$2 value=$3 escaped

    grep -qE "^${key}[[:space:]]*=" "$file" \
        || die "$(basename "$file") has no setting line for '${key}'. The core config format changed; update this script."

    escaped=$(printf '%s' "$value" | sed -e 's/[\\&|]/\\&/g')
    sed -i -E "s|^${key}[[:space:]]*=.*|${key} = ${escaped}|" "$file"
}

db_info() { printf '"%s;%s;%s;%s;%s"' "$DB_HOST" "$DB_PORT" "$DB_USER" "$DB_PASSWORD" "$1"; }

# Pathfinding is decided by what is on disk, not by a flag someone has to remember to pass.
# tools/configure-server.ps1 carries the same rule and the same reasoning: an earlier version
# had a switch that defaulted to off, so regenerating silently turned pathfinding back off —
# the world still loaded, but every creature moved in straight lines through walls, and the
# symptom showed up nowhere near the cause.
mmaps_value=0
mmaps_reason="no mmaps in ${DATA_DIR}/mmaps"
if [ "$NO_MMAPS" = "1" ]; then
    mmaps_reason="disabled explicitly with NO_MMAPS=1"
elif [ -n "$(find "$DATA_DIR/mmaps" -type f -print -quit 2>/dev/null)" ]; then
    mmaps_value=1
    mmaps_reason="mmaps detected"
fi

render_world_conf() {
    local dist="$DIST_DIR/worldserver.conf.dist" conf="$CONF_DIR/worldserver.conf"
    [ -f "$dist" ] || die "missing $dist"
    cp "$dist" "$conf"

    set_conf "$conf" 'DataDir'               "\"$DATA_DIR\""
    set_conf "$conf" 'LogsDir'               "\"$LOGS_DIR\""
    set_conf "$conf" 'LoginDatabaseInfo'     "$(db_info auth)"
    set_conf "$conf" 'WorldDatabaseInfo'     "$(db_info world)"
    set_conf "$conf" 'CharacterDatabaseInfo' "$(db_info characters)"
    set_conf "$conf" 'HotfixDatabaseInfo'    "$(db_info hotfixes)"
    set_conf "$conf" 'mmap.enablePathFinding' "$mmaps_value"
    set_conf "$conf" 'RealmID'               "$REALM_ID"

    set_conf "$conf" 'Rate.XP.Kill'    "$RATE_XP"
    set_conf "$conf" 'Rate.XP.Quest'   "$RATE_XP"
    set_conf "$conf" 'Rate.XP.Explore' "$RATE_XP"

    set_conf "$conf" 'Rate.Drop.Item.Poor'       "$RATE_DROP_ITEM"
    set_conf "$conf" 'Rate.Drop.Item.Normal'     "$RATE_DROP_ITEM"
    set_conf "$conf" 'Rate.Drop.Item.Uncommon'   "$RATE_DROP_ITEM"
    set_conf "$conf" 'Rate.Drop.Item.Rare'       "$RATE_DROP_ITEM"
    set_conf "$conf" 'Rate.Drop.Item.Epic'       "$RATE_DROP_ITEM"
    set_conf "$conf" 'Rate.Drop.Item.Legendary'  "$RATE_DROP_ITEM"
    set_conf "$conf" 'Rate.Drop.Item.Artifact'   "$RATE_DROP_ITEM"
    set_conf "$conf" 'Rate.Drop.Item.Referenced' "$RATE_DROP_ITEM"
    set_conf "$conf" 'Rate.Drop.Money'           "$RATE_DROP_MONEY"

    # Container-only keys, no counterpart in configure-server.ps1: on Windows the DBUpdater
    # finds the source tree and the mysql client through CMake's built-in paths, but this
    # image has neither a build tree nor a CMake install, so both must be pointed at by hand.
    local mysql_bin
    mysql_bin=$(command -v mysql) \
        || die "the mysql client is missing from this image; DBUpdater shells out to it to import .sql files"

    set_conf "$conf" 'SourceDirectory' "\"$SOURCE_DIR\""
    set_conf "$conf" 'MySQLExecutable' "\"$mysql_bin\""
}

render_auth_conf() {
    local dist="$DIST_DIR/authserver.conf.dist" conf="$CONF_DIR/authserver.conf"
    [ -f "$dist" ] || die "missing $dist"
    cp "$dist" "$conf"

    set_conf "$conf" 'LogsDir'           "\"$LOGS_DIR\""
    set_conf "$conf" 'LoginDatabaseInfo' "$(db_info auth)"
}

# ── TDB base data ────────────────────────────────────────────────────────────────────────

# The world and hotfixes databases are populated from the TDB release, and DBUpdater looks
# for those .sql files as bare filenames relative to the PROCESS WORKING DIRECTORY (verified
# in core/src/server/database/Updater/DBUpdater.cpp:108) — which is why the image sets
# WORKDIR to $TDB_DIR. The auth and characters base files come from $SOURCE_DIR/sql/base and
# are already in the image.
ensure_tdb() {
    if [ -f "$TDB_DIR/$TDB_WORLD_SQL" ] && [ -f "$TDB_DIR/$TDB_HOTFIXES_SQL" ]; then
        log "TDB already present in $TDB_DIR"
        return
    fi
    if [ "$TDB_AUTO_DOWNLOAD" != "1" ]; then
        log "TDB missing and TDB_AUTO_DOWNLOAD=0 — worldserver will refuse to populate empty databases"
        return
    fi

    local url="https://github.com/The-Cataclysm-Preservation-Project/TrinityCore/releases/download/TDB${TDB_VERSION}/${TDB_ASSET}"
    log "downloading TDB ${TDB_ASSET} (~90 MB compressed, ~292 MB unpacked)"
    curl --fail --location --silent --show-error --retry 3 --output "$TDB_DIR/$TDB_ASSET" "$url" \
        || die "TDB download failed from $url"

    log "extracting TDB"
    7z x -y -o"$TDB_DIR" "$TDB_DIR/$TDB_ASSET" > /dev/null || die "TDB extraction failed"
    rm -f "$TDB_DIR/$TDB_ASSET"

    [ -f "$TDB_DIR/$TDB_WORLD_SQL" ] || die "extracted archive does not contain $TDB_WORLD_SQL"
}

# ── Realm address ────────────────────────────────────────────────────────────────────────

# What the client is told to connect to after authenticating — and, just as importantly, the
# address worldserver hands out for the SECOND connection Cataclysm opens after character
# select (WorldSession::SendConnectToInstance). Without this the realm advertises 127.0.0.1
# and login dies with "failed to connect 5 times to world socket".
#
# worldserver reads realmlist exactly ONCE, in LoadRealmInfo() at startup, and caches it
# (worldserver/Main.cpp:277). The row therefore has to be correct BEFORE worldserver starts,
# which is why the world role calls this synchronously up front instead of leaving it to the
# auth container. authserver re-reads the list while it runs, so a stale row there heals
# itself; in worldserver it does not — which is how this was found. Login worked all the way
# to the character screen, then aborted.
#
# $1 = number of 10-second attempts. The world role passes a small number: on a first-ever
# boot the auth database does not exist yet, because worldserver itself is about to create
# it, and blocking here would deadlock.
sync_realmlist() {
    [ -n "$REALM_ADDRESS" ] || { log "REALM_ADDRESS not set — leaving realmlist alone"; return; }

    local attempts=${1:-60} attempt
    for attempt in $(seq 1 "$attempts"); do
        if mysql --host="$DB_HOST" --port="$DB_PORT" --user="$DB_USER" --password="$DB_PASSWORD" \
                 --batch --skip-column-names auth \
                 -e "UPDATE realmlist SET address='$REALM_ADDRESS', localAddress='$REALM_LOCAL_ADDRESS', port=$REALM_PORT WHERE id=$REALM_ID;" \
                 2>/dev/null; then
            log "realmlist id=$REALM_ID -> $REALM_ADDRESS:$REALM_PORT (attempt $attempt)"
            return
        fi
        sleep 10
    done
    log "WARNING: realmlist not updated after ${attempts} attempts."
    log "         On a FIRST EVER boot that is expected — the auth database does not exist yet."
    log "         The auth container writes the row once it does; then restart THIS container"
    log "         once so worldserver re-reads it, or character login aborts with"
    log "         'failed to connect 5 times to world socket'."
}

# ── Start ────────────────────────────────────────────────────────────────────────────────

log "role      : $ROLE"
log "data      : $DATA_DIR"
log "mmaps     : $([ "$mmaps_value" = 1 ] && echo on || echo off) ($mmaps_reason)"
log "database  : $DB_USER@$DB_HOST:$DB_PORT"

case "$ROLE" in
    worldserver)
        log "rates     : xp ${RATE_XP}x, item drop ${RATE_DROP_ITEM}x, money ${RATE_DROP_MONEY}x"
        render_world_conf
        ensure_tdb
        # Synchronous and deliberately short: worldserver caches realmlist at startup, so the
        # row must be right before the exec below — but on a first-ever boot there is no auth
        # database to write to yet, and waiting would deadlock against worldserver's own
        # DBUpdater, which is the thing that creates it.
        sync_realmlist 3
        cd "$TDB_DIR"
        exec "$BIN_DIR/worldserver" -c "$CONF_DIR/worldserver.conf"
        ;;
    authserver)
        render_auth_conf
        sync_realmlist &
        exec "$BIN_DIR/authserver" -c "$CONF_DIR/authserver.conf"
        ;;
    *)
        # Escape hatch for `docker compose run --rm world bash` and one-off mysql commands.
        exec "$@"
        ;;
esac

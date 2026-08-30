# syntax=docker/dockerfile:1
#
# PraboWoW server image — authserver + worldserver in ONE image.
#
# Two binaries, one image on purpose: a full TrinityCore build costs 40-70 minutes on a
# GitHub runner, and two Dockerfiles would pay that twice. The compose stack runs the same
# image twice with a different `command` (see deploy/docker-compose.prod.yml).
#
# The image deliberately contains NO client-derived data (dbc/maps/vmaps/mmaps). That data
# is copyrighted and 5.2 GB; it is bind-mounted from the host at /trinity/data.
#
# Build context is the REPO ROOT (needs core/ and sql/):
#   docker build -f deploy/Dockerfile -t prabowow-server .

# ── Stage 1: build ───────────────────────────────────────────────────────────────────────
FROM ubuntu:22.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive

# Dependency list is taken from core/.github/workflows/gcc-build.yml — that is the set the
# upstream fork's own CI proves green on this exact base, so it is authoritative. Ubuntu
# 22.04's default gcc IS 11, so no update-alternatives dance is needed here.
#
# Do not move this base image backwards. core/dep/boost/CMakeLists.txt:44 requires Boost
# >= 1.74 on non-Windows and looks it up in CONFIG mode; Ubuntu 22.04 ships exactly 1.74
# with the BoostConfig.cmake files that CONFIG mode needs. An older distro fails to
# configure, and the failure reads as "No BOOST_ROOT environment variable could be found"
# rather than as a version problem.
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        cmake \
        ninja-build \
        libboost-all-dev \
        libssl-dev \
        libmysqlclient-dev \
        libreadline-dev \
        libncurses-dev \
        zlib1g-dev \
        libbz2-dev \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY core/ /src/core/

# The playerbot module lives OUTSIDE the core submodule (CLAUDE.md rule 1: the core fork
# and vendor/ stay clean), so it needs its own copy and an explicit source dir below.
# Note this is src/prabobots -- NOT vendor/mod-playerbots, which is read-only reference
# material that is never compiled and stays excluded by .dockerignore.
COPY src/prabobots/ /src/prabobots/

# TOOLS=0 deviates from CLAUDE.md's "CMake butuh TOOLS=1" on purpose: the extractors
# (mapextractor, vmap4extractor, mmaps_generator, client_launcher) only ever run on the
# Windows machine that owns the client MPQs. Building them here would add CI minutes and
# image size for binaries this container can never use.
#
# WITHOUT_GIT=1 because core/.git is a gitlink pointing outside the build context, so
# genrev.cmake cannot resolve a revision anyway. The consequence is visible: the server
# banner reads "unknown (Archived branch)" instead of a commit hash. The real commit is
# recorded in the image's OCI labels and in the :<sha> tag instead. This does NOT affect
# the TDB filename, which revision_data.h.in.cmake defines statically.

# Bots are ON for the VPS image. Build a bot-free core with --build-arg PRABOBOTS=0;
# five of the six core patches compile unconditionally either way, so the two images
# differ only by the prabobots target and its script registration.
ARG PRABOBOTS=1

# PRABOBOTS_SOURCE_DIR must be passed explicitly. Its default is relative to the core
# tree (${CMAKE_SOURCE_DIR}/../src/prabobots), which resolves to /src/src/prabobots here
# and does not exist -- CMake would stop at the FATAL_ERROR in src/server/CMakeLists.txt.
RUN cmake -S /src/core -B /build -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DSERVERS=1 \
        -DTOOLS=0 \
        -DPRABOBOTS="${PRABOBOTS}" \
        -DPRABOBOTS_SOURCE_DIR=/src/prabobots \
        -DSCRIPTS=static \
        -DUSE_COREPCH=1 \
        -DUSE_SCRIPTPCH=1 \
        -DWITHOUT_GIT=1 \
        -DBUILD_TESTING=0 \
        -DCMAKE_INSTALL_PREFIX=/opt/trinitycore \
    && cmake --build /build --parallel "$(nproc)" \
    && cmake --install /build \
    && rm -rf /build

# ── Stage 2: runtime ─────────────────────────────────────────────────────────────────────
FROM ubuntu:22.04 AS runtime

ENV DEBIAN_FRONTEND=noninteractive

# Runtime libraries only (no -dev). The boost list mirrors the components requested in
# core/dep/boost/CMakeLists.txt:47 (filesystem, thread, program_options, regex, locale);
# system and iostreams are cheap insurance, and the ldd check further down is the real gate.
#
# Plus three tools the server itself shells out to:
#   mysql-client — DBUpdater invokes the `mysql` binary to import .sql files (MySQLExecutable)
#   curl + p7zip  — entrypoint downloads and unpacks the TDB archive on first start
#
# libssl3 matters twice over. World packet encryption uses RC4, which OpenSSL 3 moved into
# the LEGACY provider; the core loads it at runtime from the ossl-modules directory. On
# Windows this exact thing failed as `ARC4.cpp:31 ASSERTION FAILED` at client connect (see
# docs/phase-1-checklist.md). The check below fails the build rather than shipping an image
# that only breaks when a real player connects.
RUN apt-get update && apt-get install -y --no-install-recommends \
        libboost-filesystem1.74.0 \
        libboost-thread1.74.0 \
        libboost-program-options1.74.0 \
        libboost-regex1.74.0 \
        libboost-locale1.74.0 \
        libboost-system1.74.0 \
        libboost-iostreams1.74.0 \
        libmysqlclient21 \
        libssl3 \
        zlib1g \
        libbz2-1.0 \
        libreadline8 \
        mysql-client \
        p7zip-full \
        curl \
        ca-certificates \
        tzdata \
    && rm -rf /var/lib/apt/lists/* \
    && test -f /usr/lib/x86_64-linux-gnu/ossl-modules/legacy.so

COPY --from=builder /opt/trinitycore/bin /opt/trinitycore/bin
COPY --from=builder /opt/trinitycore/etc /opt/trinitycore/etc

# The whole core/sql tree, `old/` included (576 MB, ~120 MB as a compressed layer).
# Dropping `old/` looks tempting but is wrong: the `updates_include` table shipped inside
# the base/TDB dumps points at $/sql/old/4.3.4/<db>, and every archived update recorded in
# the `updates` table would become an orphaned reference — thousands of warnings on every
# single start, plus a "Cleanup is disabled! ... dirty files" error, because there are far
# more of them than Updates.CleanDeadRefMaxCount allows to clean.
COPY core/sql /opt/trinitycore/sql

# This project's own world SQL rides along as a custom update. `updates_include` already
# lists $/sql/custom/world, so DBUpdater applies these on start and records each file's
# hash in the `updates` table — idempotent, and never applied twice.
COPY sql/world/ /opt/trinitycore/sql/custom/world/

COPY deploy/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Fail the build on a missing shared library instead of at container start, where it would
# look like a crash. This is the Linux twin of the DLL trap documented in Fase 1.
RUN ldd /opt/trinitycore/bin/worldserver > /tmp/ldd.txt \
    && ldd /opt/trinitycore/bin/authserver >> /tmp/ldd.txt \
    && ! grep -q 'not found' /tmp/ldd.txt \
    && rm /tmp/ldd.txt

# Non-root. uid/gid are pinned to 1000 because the host bind mount at /srv/renowow must be
# chowned to match (see tools/upload-client-data.ps1 and docs/deployment.md).
RUN groupadd --gid 1000 trinity \
    && useradd --uid 1000 --gid 1000 --create-home --shell /bin/bash trinity \
    && mkdir -p /trinity/data /trinity/logs /trinity/tdb /trinity/etc \
    && chown -R trinity:trinity /trinity

USER trinity

# Working directory is /trinity/tdb and that is NOT cosmetic. DBUpdater resolves the world
# and hotfixes base files (TDB_full_world_*.sql) as a BARE FILENAME relative to the process
# working directory — not relative to SourceDirectory. Verified in
# core/src/server/database/Updater/DBUpdater.cpp:108 + revision_data.h.in.cmake:12.
WORKDIR /trinity/tdb

EXPOSE 3724 8085

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["worldserver"]

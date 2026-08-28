#!/bin/bash
# Runs ONCE, on the very first start of an empty mysql data volume (the official image
# executes everything in /docker-entrypoint-initdb.d/ at that point).
#
# Why this is needed at all: the core's DBUpdater populates empty databases, but it cannot
# CREATE them — the mysql image only grants MYSQL_USER rights on the single MYSQL_DATABASE,
# and handing the server a root login instead would be worse. So the four databases are
# created here and granted up front, exactly as tools/bootstrap-db.ps1 does on Windows,
# including the utf8mb4 charset.
#
# Four databases, not three: `hotfixes` is Cataclysm-specific (HotfixDatabaseInfo) and does
# not exist in WotLK setups, so it is the easy one to forget.
set -euo pipefail

for db in auth world characters hotfixes; do
    mysql --protocol=socket -uroot -p"$MYSQL_ROOT_PASSWORD" <<-SQL
		CREATE DATABASE IF NOT EXISTS \`${db}\`
		    DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
		GRANT ALL PRIVILEGES ON \`${db}\`.* TO '${MYSQL_USER}'@'%';
	SQL
done

mysql --protocol=socket -uroot -p"$MYSQL_ROOT_PASSWORD" -e "FLUSH PRIVILEGES;"

echo "[init] created auth, world, characters, hotfixes for user '${MYSQL_USER}'"

#!/usr/bin/env bash
# Cold-backup the world: warn players over RCON, stop the server, tar
# world+config while nothing is running, start it back up. Run as the
# minecraft user (needs the sudoers rule in systemd/minecraft-backup-sudoers
# installed so it can stop/start its own unit without a password).
set -euo pipefail

SERVER_DIR="/srv/minecraft/liminalindustries"
BACKUP_DIR="/srv/minecraft/backups"
RETAIN=30
RCON_PORT=25576
SERVICE="minecraftserver-liminalindustries"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "$BACKUP_DIR"

PASS_FILE=$(mktemp)

rcon() {
    python3 "$SCRIPT_DIR/rcon.py" --port "$RCON_PORT" --password-file "$PASS_FILE" "$@"
}

# The systemd unit sets this on the java process's environment.
server_process_running() {
    grep -zqs "^MC_SERVER_MARKER=liminalindustries$" /proc/[0-9]*/environ 2>/dev/null
}

WAS_RUNNING=false
STARTED=false
if server_process_running; then
    WAS_RUNNING=true
fi

# If we're the one who stopped it, make sure it comes back even if something
# below fails partway through.
restart_if_needed() {
    if [ "$WAS_RUNNING" = true ] && [ "$STARTED" = false ]; then
        sudo systemctl start "$SERVICE" || true
    fi
    rm -f "$PASS_FILE"
}
trap restart_if_needed EXIT

sed -n 's/^rcon.password=//p' "$SERVER_DIR/server.properties" > "$PASS_FILE"

if [ "$WAS_RUNNING" = true ]; then
    warn() { rcon "say Server restarting for backup in $1..." >/dev/null 2>&1 || true; }
    warn "5 minutes"
    sleep 120
    warn "3 minutes"
    sleep 60
    warn "2 minutes"
    sleep 60
    warn "1 minute"
    sleep 30
    warn "30 seconds"
    sleep 20
    warn "10 seconds"
    sleep 5
    warn "5 seconds"
    sleep 5

    sudo systemctl stop "$SERVICE"
    # Give it a moment to actually exit before we start reading its files.
    for _ in $(seq 1 30); do
        server_process_running || break
        sleep 1
    done
fi

# Small state files (and the schematics dir) worth keeping alongside the
# world/config - not in git, not reproducible from the mod bundle. Only include
# ones that actually exist so a never-created file (e.g. no one's ever been
# banned) doesn't hard-fail tar.
EXTRA_FILES=()
for f in server.properties whitelist.json ops.json banned-players.json banned-ips.json user_jvm_args.txt usercache.json usernamecache.json schematics; do
    [ -e "$SERVER_DIR/$f" ] && EXTRA_FILES+=("$f")
done

set +e
tar -C "$SERVER_DIR" -czf "$BACKUP_DIR/liminalindustries-world-$(date +%Y%m%d-%H%M%S).tar.gz" \
    world config "${EXTRA_FILES[@]}"
tar_status=$?
set -e

if [ "$WAS_RUNNING" = true ]; then
    sudo systemctl start "$SERVICE"
    STARTED=true
fi

ls -1t "$BACKUP_DIR"/liminalindustries-world-*.tar.gz | tail -n "+$((RETAIN + 1))" | xargs -r rm -f

if [ "$tar_status" -gt 1 ]; then
    echo "tar failed with fatal exit code $tar_status" >&2
    exit "$tar_status"
fi

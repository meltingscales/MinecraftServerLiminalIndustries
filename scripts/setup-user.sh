#!/usr/bin/env bash
# Create the segregated `minecraft` system user + /srv/minecraft. Run as root.
set -euo pipefail

SERVER_DIR=/srv/minecraft

if ! id minecraft &>/dev/null; then
    useradd --system --create-home --home-dir "$SERVER_DIR" --shell /usr/bin/bash minecraft
else
    usermod --shell /usr/bin/bash minecraft
fi

mkdir -p "$SERVER_DIR"
chown -R minecraft:minecraft "$SERVER_DIR"
chmod 750 "$SERVER_DIR"

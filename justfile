server_dir := "/srv/minecraft/liminalindustries"
backup_dir := "/srv/minecraft/backups"
service := "minecraftserver-liminalindustries"
unit := "systemd/" + service + ".service"
rcon_port := "25576"
game_port := "25566"

default:
    @just --list

# create the segregated `minecraft` user + /srv/minecraft
setup-user:
    sudo bash scripts/setup-user.sh

# unzip the (single) *.zip bundle in this dir into ./bundle, flattening a
# wrapping top-level folder if the zip has one (this pack's does)
extract:
    #!/usr/bin/env bash
    set -euo pipefail
    rm -rf bundle
    mkdir bundle
    unzip -q "$(ls *.zip)" -d bundle
    entries=(bundle/*/)
    if [ "${#entries[@]}" -eq 1 ] && [ -d "${entries[0]}" ]; then
        shopt -s dotglob
        mv "${entries[0]}"* bundle/
        rmdir "${entries[0]}"
    fi

# deploy a server bundle (extracted dir containing run.sh, mods/, etc) to /srv/minecraft/liminalindustries
deploy src="bundle": (verify-mods src + "/mods")
    sudo rsync -a --delete "{{src}}/" "{{server_dir}}/"
    sudo chown -R minecraft:minecraft "{{server_dir}}"
    sudo chmod +x "{{server_dir}}/run.sh"
    printf -- '-Xmx6G\n-Xms6G\n' | sudo tee "{{server_dir}}/user_jvm_args.txt" >/dev/null
    sudo chown minecraft:minecraft "{{server_dir}}/user_jvm_args.txt"
    sudo install -m 644 "{{unit}}" /etc/systemd/system/{{service}}.service
    sudo systemctl daemon-reload

# check {{src}}/*.jar against manifests/mods.sha256
verify-mods src="bundle/mods":
    cd "{{src}}" && sha256sum -c "{{justfile_directory()}}/manifests/mods.sha256"

# regenerate manifests/mods.sha256 from the live server's mods dir, after updating the mod list there
# (needs sudo - mods/ is root:minecraft 750, not readable by a plain user)
update-mod-hashes:
    sudo bash -c 'cd "{{server_dir}}/mods" && sha256sum *.jar' | sort -k2 > "{{justfile_directory()}}/manifests/mods.sha256"

# install/update whitelist.json on the deployed server, then reload it live
install-whitelist:
    sudo install -m 644 whitelist.json "{{server_dir}}/whitelist.json"
    sudo chown minecraft:minecraft "{{server_dir}}/whitelist.json"
    python3 scripts/rcon.py --port {{rcon_port}} whitelist reload

# install + enable the daily world backup timer (midnight, keeps last 30).
# Re-run this any time scripts/backup.sh, the backup service/timer unit, or
# the backup sudoers rule change - it's the one recipe that (re)installs all
# of them, so it's always safe to just re-run after editing any of those.
setup-backups:
    sudo install -m 755 scripts/backup.sh /usr/local/bin/minecraftserverbackup-liminalindustries.sh
    sudo install -m 644 scripts/rcon.py /usr/local/bin/rcon.py
    sudo install -m 644 systemd/minecraftserverbackup-liminalindustries.service /etc/systemd/system/minecraftserverbackup-liminalindustries.service
    sudo install -m 644 systemd/minecraftserverbackup-liminalindustries.timer /etc/systemd/system/minecraftserverbackup-liminalindustries.timer
    sudo install -m 440 systemd/minecraft-backup-sudoers /etc/sudoers.d/minecraft-backup-liminalindustries
    sudo visudo -c
    sudo systemctl daemon-reload
    sudo systemctl enable --now minecraftserverbackup-liminalindustries.timer

enable:
    sudo systemctl enable {{service}}

start:
    sudo systemctl start {{service}}

stop:
    sudo systemctl stop {{service}}

restart:
    sudo systemctl restart {{service}}

status:
    systemctl status {{service}}

# interactive RCON console (prompts for rcon.password from server.properties)
rcon:
    python3 scripts/rcon.py --port {{rcon_port}}

# check the game port is actually up and accepting connections (Server List Ping)
ping host="127.0.0.1" port=game_port:
    python3 scripts/mcping.py --host {{host}} --port {{port}}

# DESTRUCTIVE: force a chunk to regenerate (wipes it). Stop the server first, take a backup.
# region_dir defaults to the overworld; pass world/DIM-1/region (nether) or world/DIM1/region (the end) for other dimensions.
delete-chunk chunk_x chunk_z region_dir=(server_dir + "/world/region"):
    sudo python3 scripts/delete-chunk.py --region-dir "{{region_dir}}" {{chunk_x}} {{chunk_z}}

# restore world/ from a backup tar.gz - renames the current world/ aside first (doesn't delete it). Stop the server first.
restore-world backup_file:
    sudo bash -c '[ -d "{{server_dir}}/world" ] && mv "{{server_dir}}/world" "{{server_dir}}/world.pre-restore-$(date +%Y%m%d-%H%M%S)"' || true
    sudo tar -C "{{server_dir}}" -xzf "{{backup_file}}" world
    sudo chown -R minecraft:minecraft "{{server_dir}}/world"

logs:
    journalctl -u {{service}} -f

# list world backups on disk, newest first, with sizes
list-backups:
    ls -lht "{{backup_dir}}"

# Liminal Industries mc modded server

Modpack: [Liminal Industries on CurseForge](https://www.curseforge.com/minecraft/modpacks/liminal-industries)

host (tunneled via [playit.gg](https://playit.gg) — no router port forwarding needed):

    meltyliminalindustries.playit.plus:44940

playit.gg agent runs on the server and exposes it publicly; players just connect to the
assigned address directly, no client install required.

## Quickstart

Drop the server bundle zip (and `world.tar.gz`, if the world is separate) in the repo root, then:

```
just extract                        # unzips *.zip into ./bundle
tar -xzf world.tar.gz -C bundle     # only if world isn't already inside the zip
just verify-mods                    # sha256sum bundle/mods/*.jar against manifests/mods.sha256
just setup-user                     # creates the minecraft system user + /srv/minecraft
just deploy                         # rsyncs bundle/ -> /srv/minecraft/liminalindustries, installs the unit
just enable                         # systemctl enable minecraftserver-liminalindustries
just start                          # systemctl start minecraftserver-liminalindustries
just status                         # confirm it's running
```

Before the first `just deploy`, edit `bundle/server.properties` and set:

```
server-port=25566
query.port=25566
```

(the bundle ships with `25565`, which collides with any other Minecraft server already
running on this host).

Also edit `bundle/config/voicechat/voicechat-server.properties` and set:

```
port=24456
```

(the bundle ships with Simple Voice Chat's default `24454`, which also collides with
another server's voice chat on this host — the bind failure races with startup and
kills the whole JVM, not just voice chat, showing up as a boot loop).

`just deploy` chmods `run.sh` executable itself, but if you ever install the unit by hand
(`sudo install -m 644 systemd/minecraftserver-liminalindustries.service /etc/systemd/system/`), make sure
`/srv/minecraft/liminalindustries/run.sh` is `+x` first — zip extraction drops the exec bit, which
shows up as systemd `203/EXEC` on start.

`just deploy` also overwrites `user_jvm_args.txt` on every deploy, pinning `-Xmx6G -Xms6G`
regardless of what the bundle shipped with (the default bundle ships it commented out, i.e.
JVM-default heap). Adjust the value in the `deploy` recipe if the host's RAM changes.

Forge 1.20.1 requires Java 17, but `run.sh` execs bare `java`, which resolves to whatever
the host's default JVM is. `systemd/minecraftserver-liminalindustries.service` pins
`PATH=/usr/lib/jvm/java-17-openjdk/bin:...` to force it — without that, a newer default
JVM makes Mixin crash on boot with `Unsupported class file major version <N>`.

## Console access

systemd runs `run.sh` directly with stdin closed, so there's no interactive stdin to type into.
Server commands (`/op`, `/whitelist`, `/say`, etc) go over RCON instead:

1. In `server.properties` (on the deployed server), set:
   ```
   enable-rcon=true
   rcon.port=25576
   rcon.password=<a-generated-secret>
   ```
   Restart the service to pick it up — RCON settings are only read at startup.
   `25576` (not `25575`) so it doesn't collide with another server's RCON port on this host.
2. `just rcon` connects with `scripts/rcon.py` (stdlib-only Source RCON client, no extra package
   needed) and prompts for the password interactively.

If the game is exposed to the internet, don't also forward the RCON port — connect from a
shell on the server itself (e.g. over SSH).

## Known issues

- **World renders pitch black on first join.** Not a server bug — log out and back in again,
  reported to fix it. See
  [Appocryptha/Liminal-Industries#215](https://github.com/Appocryptha/Liminal-Industries/issues/215#issuecomment-3764003407).

## specs

- justfile
- systemd setup
- segregated `minecraft` user with a specific directory (`/srv/minecraft/`), shared across any
  other Minecraft server repos set up the same way on this host
- Forge 1.20.1-47.4.13
- modded
  - mod bundle is sha256sum verified with a manifest
- game port `25566`, rcon port `25576`, voice chat port `24456` (all offset from the defaults so
  multiple servers can coexist on one host)

## layout

- `justfile` — setup-user, deploy, verify-mods, start/stop/restart/status/logs/rcon
- `systemd/minecraftserver-liminalindustries.service` — unit installed to `/etc/systemd/system/`, runs as the `minecraft` user
- `systemd/minecraftserverbackup-liminalindustries.{service,timer}` — daily cold-backup timer
- `systemd/minecraft-backup-sudoers` — installed to `/etc/sudoers.d/minecraft-backup-liminalindustries`
  (suffixed so it doesn't collide with another server's sudoers drop-in on the same host)
- `scripts/setup-user.sh` — creates the `minecraft` system user + `/srv/minecraft`
- `scripts/backup.sh` — cold-backup: warns players over RCON, stops the service, tars
  `world`+`config`+small state files, restarts, prunes to the last 30
- `scripts/rcon.py` — interactive RCON console client, used by `just rcon`
- `scripts/mcping.py` — Server List Ping check, used by `just ping`
- `scripts/delete-chunk.py` — DESTRUCTIVE chunk-regeneration tool, used by `just delete-chunk`
- `manifests/mods.sha256` — sha256sum manifest for the 146 mod jars in the current bundle
- `whitelist.json` — tracked in git; `just install-whitelist` deploys it and reloads it live

Server bundle (mods, world, jars — currently the untracked `*.zip`/`*.tar.gz` in this dir) is not
committed to git; run `just extract` to unzip it into `./bundle`, then `just deploy`, which
verifies mod hashes against the manifest before syncing to `/srv/minecraft/liminalindustries`.

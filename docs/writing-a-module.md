# Writing a module

A module is one file, `modules/NAME.sh`, sourced into `rez`. It declares metadata and implements `mod_*` functions. Everything else (setup menus, boot, cron, backups, monitoring, status) discovers modules through this contract, so adding one never means editing the core. The only other change is adding the name to `REZ_MODULE_ORDER` in `lib/modules.sh` (start order: dependencies first).

## Skeleton

```bash
# shellcheck shell=bash
# example: one-line description of what it is and why it's here.

MOD_NAME=example                 # must equal the file name
MOD_DESC="Example service (short, shown in menus)"
MOD_ROOT=no                      # no | optional | required
MOD_DEPENDS="base"               # space-separated
MOD_PORTS="8080"                 # shown in the setup review
MOD_ARCHES="arm64 armv7 amd64"   # omit if it runs everywhere
MOD_MIN_RAM_MB=0                 # MemTotal needed (0 = no limit)
MOD_NEEDS_EXTERNAL=0             # 1 = needs an SD card / external storage
MOD_RAM_EST_MB=20                # for the setup estimate
MOD_DISK_EST_MB=30
MOD_SERVICE=1                    # 0 for modules with no long-running process
MOD_TESTED="what was tested where, honestly"

EX_DIR=$REZ_DATA_DIR/example
_port() { cfg_get example.port 8080; }

mod_configure() {                # questions; answers go in the config file
  cfg_set example.port "$(cfg_get example.port "$(ui_input "Example" "Port" 8080)")"
}

mod_install() {                  # idempotent: running it twice must be safe
  local tgz
  tgz=$(fetch_pinned example)    # pinned version + sha256 in lib/versions.sh
  ensure_dir 700 "$EX_DIR"
  # ... extract, write config with atomic_write, create users with secret_ensure ...
}

mod_start()  { svc_start example example "serve" -- "$EX_DIR/example" serve --port "$(_port)"; }
mod_stop()   { svc_stop example example "serve"; }
mod_status() { svc_status_line example example "serve" "port $(_port)"; }
mod_health() { svc_running example example "serve" && port_open 127.0.0.1 "$(_port)"; }

mod_backup()        { mkdir -p "$1"; sqlite3 "$EX_DIR/db.sqlite3" ".backup '$1/db.sqlite3'"; }
mod_restore_check() { [[ "$(sqlite3 "$1/db.sqlite3" 'PRAGMA integrity_check;')" == ok ]]; }
mod_cron()          { echo "0 4 * * * $(rez_cmd) example cleanup >>$REZ_LOG_DIR/example.log 2>&1"; }
mod_uninstall()     { run_cmd rm -f "$EX_DIR/example"; [[ "${REZ_PURGE:-0}" == 1 ]] && run_cmd rm -rf "$EX_DIR"; return 0; }
mod_info()          { printf 'Example:    http://%s:%s\n' "$(device_host)" "$(_port)"; }
mod_cli()           { case "${1:-}" in cleanup) echo cleaning ;; *) die "usage: rez example cleanup" ;; esac; }
```

`install` and `status` are required. Services (`MOD_SERVICE=1`) also need `start`, `stop` and `health`. Everything else is optional. `tests/bats/modules.bats` enforces this.

## Rules

**Processes.** Always use `svc_start` / `svc_stop` / `svc_running` with an EXE name and an argument regex. They match `/proc/<pid>/cmdline`, ignore stale pidfiles, skip commands that only mention the service (`ssh`, `grep`, `bash -c "..."`), and never start a second copy. Don't use `pgrep -f` or `kill -0` on a pidfile.

- EXE is the basename of one of the first three argv entries (so `python3 -m copyparty` matches `copyparty`, and so does a proot-wrapped binary).
- `SVC_SUPERVISE=1` wraps the command in `lib/supervise.sh` (restart with backoff, alert on crash loops). Use it for anything that must not stay down.
- `SVC_ENV=("KEY=value")` passes environment. Put secrets there or in files, never on the command line (`/proc/<pid>/cmdline` is readable).
- Prefix low-priority work with `nice -n 10`.

**Root.** Ask `REZ_HAS_ROOT` (never call `su` to find out) and run root commands with `as_root`. Root-only modules set `MOD_ROOT=required`. Never reboot, never flash.

**Downloads.** Only through `fetch_pinned` / `fetch_verified` with a checksum in `lib/versions.sh`. No checksum, no download.

**Config and secrets.** `cfg_get key default` / `cfg_set key value` (keys `module.something`). Secrets via `secret_ensure NAME` (generated once, mode 600) or `secret_set`. Never print secrets except in an explicit `show-password` command.

**Dry run.** Wrap commands that change the system in `run_cmd`, write files with `atomic_write`, so `rez --dry-run` shows instead of doing.

**Binding.** Listen on `$(service_bind)`: `127.0.0.1` with built-in Tailscale, all interfaces otherwise.

**Android quirks.**
- Go and musl binaries need to be told where CA certificates are: pass `SVC_ENV=("${TLS_ENV[@]}")` (Termux's bundle, Android's store as fallback).
- Ports below 1024 need root.
- At boot, `termux-exec` isn't loaded: use full paths (`$PREFIX/bin/python3`), not `#!/usr/bin/env` tricks.
- Use `mem_available_mb`, never `free`.
- Need a normal Linux filesystem? Run inside Debian with `proot_exec` / `PROOT_CMD`.

**Health output.** If `mod_health` fails, print one short line saying why. The monitor puts it in the alert.

## Testing

- Add the module to `REZ_MODULE_ORDER`, then run `bats tests/bats` (contract test).
- Dry run: `REZ_ALLOW_NON_TERMUX=1 bin/rez --dry-run --yes setup --modules base,example`.
- If it can run in a container, add checks to `tests/termux-docker/integration.sh`.
- Fill in `MOD_TESTED` and the table in [testing.md](testing.md) honestly.

#!/data/data/com.termux/files/usr/bin/sh
# resurrect startup, run by Termux:Boot. Written by `rez setup`; rewritten on
# every `rez install`/`rez cron sync`, so do not edit it.
#
# Termux:Boot runs EVERY file in ~/.termux/boot/. Keep this the only one and
# never put backup copies of it next to it. `rez boot` holds a lock, so a
# second copy exits at once, and starts each service only if it is not
# already running.
#
# Full paths on purpose: at boot PATH is minimal and termux-exec (which
# makes #!/usr/bin/env work) is not loaded.
exec /data/data/com.termux/files/usr/bin/bash @REZ_ROOT@/bin/rez boot

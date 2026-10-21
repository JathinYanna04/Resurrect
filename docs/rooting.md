# Rooting (optional)

**Everything in resurrect works without root.** Root only adds two things:

| Feature | Without root | With root |
|---|---|---|
| AdGuard Home | DNS on a high port (5335). Clients use a small forwarder ([dns-and-adguard.md](dns-and-adguard.md)) | DNS on the real port 53, started by Magisk at boot, independent of Termux |
| Battery charge limit (ACC) | Not available. Keep the phone plugged into a smart plug or timer, or accept faster battery wear | Charging pauses at 80 % and resumes at 70 % (configurable) |

If neither matters to you, don't root. Rooting widens what a compromised app could do, and some apps refuse to run on rooted phones.

**resurrect never roots your phone for you.** This is a manual, step-by-step outline; your device's own guide always wins.

## Before you start

- Rooting with Magisk needs an **unlocked bootloader**. Unlocking **erases all data**, can void the warranty, and is impossible on some devices. See the warnings in [custom-rom.md](custom-rom.md#read-this-first).
- Back up first: `rez backup run`, then copy the archive to another device.
- You need a computer with adb and fastboot: https://developer.android.com/tools/releases/platform-tools
- You need the **exact** firmware (or custom ROM) image currently installed on the phone, because you'll patch its boot image. A boot image from a different build can stop the phone from booting.

## Outline (Magisk)

The official guide is the source of truth: https://topjohnwu.github.io/Magisk/install.html

1. Unlock the bootloader using your manufacturer's or ROM's official method.
2. Get the `boot.img` (or `init_boot.img` on newer devices; the Magisk guide explains which) from the exact build installed on the phone.
3. Install the Magisk app from its official GitHub releases: https://github.com/topjohnwu/Magisk/releases
4. In the Magisk app, patch the image. Copy the patched file to the computer.
5. Flash the patched image with fastboot, exactly as the Magisk guide says for your device type.
6. Reboot. The first boot after rooting can take longer than usual (a couple of minutes, sometimes with a reboot). Don't panic and restore immediately.
7. Open Termux and run `su -c id`. Magisk asks whether to grant Termux root. Grant it.

KernelSU is an alternative on supported kernels: https://kernelsu.org/guide/installation.html

**Keep the original, unpatched image.** Flashing it back with fastboot is how you undo root (or recover from a boot loop).

## Using root in resurrect

```sh
rez setup --root ask        # or: rez install adguard acc
```

Setup asks before it calls `su` (your root manager shows a prompt) and remembers the answer.

- **AdGuard root mode** installs AdGuard Home into `/data/adb/resurrect/adguard` and a launcher in `/data/adb/service.d/`, which Magisk runs at every boot. Its pidfile is only trusted when `/proc/<pid>/cmdline` really is AdGuard Home: after a reboot Android reuses PIDs, and a root `kill -0` succeeds on any process.
- **ACC** is a Magisk module. resurrect downloads the pinned, checksum-verified release and, only after you confirm, asks Magisk to install it. **It never reboots for you.** Reboot when convenient, then run `rez acc apply`. Change limits with `rez acc set 85 75`.

## Undo

- `rez uninstall acc` (charging goes back to normal), `rez uninstall adguard`.
- To remove root completely: Magisk app > Uninstall Magisk > Complete uninstall, or flash the original boot image with fastboot.

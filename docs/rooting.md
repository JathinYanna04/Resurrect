# Rooting

This guide explains what root adds to resurrect, outlines how rooting with Magisk works, and shows how to turn on the root-only features afterwards. It is for people who already know they want root. **Everything in resurrect works without root**, and resurrect never roots a device for you.

> [!CAUTION]
> **Rooting can permanently damage your device and erase your data.**
>
> - Rooting with Magisk needs an **unlocked bootloader**. Unlocking **erases everything on the device**, can void your warranty, and is impossible on some devices. See the full list of risks in [custom-rom.md](custom-rom.md).
> - Flashing a boot image from a different build can stop the device from booting.
> - Root widens what a compromised app can do, and some apps refuse to run on rooted devices.
>
> This page is an outline, not a guide for your device. Your device's own instructions and the official Magisk documentation always win.

## What root adds

| Feature | No root | Root |
|---|---|---|
| AdGuard Home | DNS on port 5335. Computers use a small forwarder ([dns-and-adguard.md](dns-and-adguard.md)) | DNS on port 53, started by Magisk at every boot, independent of Termux |
| Battery charge limit (`acc`) | Not available. Accept faster battery wear, or use a smart plug on a schedule | Charging pauses at 80 % and resumes below 70 % (configurable) |

If neither matters to you, don't root.

## Prerequisites

- A backup, copied off the device: `rez backup run`, then see [backups.md](backups.md#copy-backups-off-the-device).
- A computer with [Android platform tools](https://developer.android.com/tools/releases/platform-tools) (`adb` and `fastboot`).
- The **exact** firmware or custom ROM build currently installed on the device. You will patch its boot image.
- The original, unpatched boot image kept somewhere safe. Flashing it back is how you undo root or recover from a boot loop.

## Rooting with Magisk: outline

The [official Magisk installation guide](https://topjohnwu.github.io/Magisk/install.html) is the source of truth. The general steps are:

1. Unlock the bootloader with your manufacturer's or ROM's official method.
2. Get `boot.img`, or `init_boot.img` on newer devices (the Magisk guide explains which), from the exact build installed on the device.
3. Install the Magisk app from its [official GitHub releases](https://github.com/topjohnwu/Magisk/releases).
4. In the Magisk app, patch the image, then copy the patched file to your computer.
5. Flash the patched image with `fastboot`, exactly as the Magisk guide describes for your device type.
6. Reboot. The first boot after rooting can take a few minutes, sometimes with an extra reboot. Don't restore anything in a panic.
7. Open Termux and run `su -c id`. Magisk asks whether to grant Termux root. Grant it. The output starts with `uid=0(root)`.

[KernelSU](https://kernelsu.org/guide/installation.html) is an alternative on supported kernels. resurrect detects both.

## Turn on root in resurrect

### 1. Let resurrect check root

```bash
rez setup --root ask
```

Setup asks before it calls `su`, so your root manager shows a permission prompt. The answer is saved as `device.root` and later commands never prompt again. In the module checklist, keep the modules you already have and add the root features. Installing existing modules again is safe.

Use `--root yes` for a non-interactive run that fails if root is not granted.

### 2. AdGuard Home on port 53

On a new install, setup asks whether to run AdGuard Home in root mode when root is available. If AdGuard Home is already installed without root, switch it like this:

1. Stop the current instance: `rez stop adguard`.
2. In `~/.config/resurrect/resurrect.conf`, set `adguard.mode=root`.
3. Install it again: `rez install adguard`.

Root mode installs AdGuard Home into `/data/adb/resurrect/adguard/` and a launcher at `/data/adb/service.d/resurrect-adguard.sh`, which Magisk runs at every boot. The launcher waits for Android to finish booting, and only trusts its pidfile if `/proc/<pid>/cmdline` really is AdGuard Home; [dns-and-adguard.md](dns-and-adguard.md#case-study-a-tailnet-wide-dns-outage) explains why. Root mode writes a fresh configuration, so filters and settings from the no-root instance don't carry over.

### 3. Battery charge limit

```bash
rez install acc
```

resurrect downloads the pinned, checksum-verified [ACC](https://github.com/VR-25/acc) release, shows what it will do, and asks Magisk to install the module only after you confirm. **It never reboots for you.** Reboot when convenient, then apply the limits:

```bash
rez acc apply
```

Expected output:

```text
 ok charge limit set: pause at 80 %, resume below 70 %
```

To change the limits (the resume level must be at least 20 % and below the pause level):

```bash
rez acc set 85 75
rez acc status
```

The `monitor` module alerts if the device charges well above the limit, or stops charging well below the resume level, which usually means the charger is unplugged.

## Undo

| To remove | Do this |
|---|---|
| The charge limit | `rez uninstall acc`. resurrect asks before it uninstalls ACC, and charging returns to normal |
| AdGuard Home in root mode | `rez uninstall adguard` removes the launcher and binary. Add `--purge` to delete `/data/adb/resurrect/adguard/` too |
| Root itself | In the Magisk app, choose **Uninstall Magisk > Complete uninstall**, or flash the original boot image with `fastboot` |

After removing root, set `device.root=no` in the config file.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `--root yes, but root was not granted` | The root manager denied Termux, or the prompt timed out after 30 seconds | Open the Magisk app, allow Termux under Superuser, and run setup again |
| `acc cannot be installed here: needs root` | resurrect doesn't know about root yet | Run `rez setup --root ask` first |
| `Magisk could not install the module` | `magisk --install-module` failed | Install the downloaded zip from the Magisk app; the error message shows its path |
| `ACC is not active yet (reboot pending?)` | ACC needs a reboot after installing | Reboot, then `rez acc apply`. `rez acc status` shows `REBOOT PENDING` until then |
| Root-mode AdGuard Home doesn't start | The launcher failed | Read `su -c 'tail /data/adb/resurrect/adguard/agh.log'`, then `rez adguard reinstall` |
| The device boot-loops after flashing | Wrong or damaged boot image | Flash the original image back with `fastboot` |

> [!NOTE]
> The root features (`acc` and AdGuard Home's root mode) have not been tested on a real device yet. See [testing.md](testing.md).

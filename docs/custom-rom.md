# Custom ROMs (optional)

resurrect runs on the Android your phone already has. You do not need a custom ROM. This page is for people who want one anyway: an old phone stuck on an Android version without security updates can often run a newer, maintained system, and a lighter system leaves more RAM for your services.

**resurrect never unlocks bootloaders, never flashes anything and never reboots into fastboot or recovery.** `rez device` only reads system properties and prints links. Everything below is something you do yourself, by hand, following your device's official instructions.

## Read this first

- **Unlocking the bootloader erases all data on the phone.** Back up first (`rez backup run`, then copy the archive off the phone).
- **It can void your warranty.** Some manufacturers refuse to unlock at all; others need an online request and a waiting period. Carrier-locked phones often can't be unlocked.
- **You can brick the device.** Flashing a file for a different model or variant, or interrupting a flash, can leave it unbootable. Some bricks are recoverable with vendor tools; some are not.
- **Some apps stop working.** Banking, payment, some streaming and some games check device integrity and may refuse to run on an unlocked or custom system.
- **Variants matter.** The same marketing name often covers several models (Wi-Fi vs LTE, regional versions). Install only builds for your exact model number and codename.

If any of that is a deal-breaker, stop here. Stock Android works fine with resurrect.

## 1. Identify the device

```sh
rez device
```

This prints the manufacturer, model, **codename** (the name ROM projects use, e.g. `ro.product.device`), Android version, current ROM and the bootloader state as reported by system properties. Note the codename and the exact model number (Settings > About phone).

## 2. Check for official support

Look the device up by codename, then by model name, because projects don't always use the same names:

| Project | Device list | Notes |
|---|---|---|
| LineageOS | https://wiki.lineageos.org/devices/ | The largest selection; each device page has its own install guide |
| /e/OS | https://doc.e.foundation/devices | Based on LineageOS, de-Googled |
| postmarketOS | https://wiki.postmarketos.org/wiki/Devices | Real Linux instead of Android; very different from resurrect's approach |
| GrapheneOS | https://grapheneos.org/faq#supported-devices | Google Pixel phones only |

"Unofficial" builds on forums (for example XDA, https://xdaforums.com) exist for many more devices. They can be excellent or abandoned and risky; check how recently they were updated and read the whole thread before you try one.

## 3. Follow only the official guide for your device

Each device page on the projects above has its own guide: which bootloader unlock method applies, which recovery to use, which firmware version must be installed first. Follow it exactly, in order. General tools you'll meet:

- Android platform tools (adb and fastboot): https://developer.android.com/tools/releases/platform-tools
- Your manufacturer's official unlock instructions, where they exist.

Do not mix steps from different guides or different devices.

## 4. After installing a new ROM

1. Install Termux and Termux:Boot from F-Droid or GitHub (not Google Play).
2. Run the resurrect installer again (see the README).
3. Restore your data: `rez backup extract FILE DIR`, then follow [backups.md](backups.md).

## Root

A custom ROM doesn't give you root by itself, and resurrect doesn't need it. If you want the root-only extras (AdGuard on port 53, battery charge limit), see [rooting.md](rooting.md).

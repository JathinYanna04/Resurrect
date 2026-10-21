# Custom ROMs

This guide is for people who want to replace their device's Android with a maintained custom ROM, such as LineageOS. resurrect does not need one: it runs on the Android your device already has. A custom ROM can still be worth it for an old device stuck on an Android version without security updates, and a lighter system leaves more RAM for your services. Everything here is optional and manual.

> [!CAUTION]
> **Installing a custom ROM can permanently damage your device and erase your data.**
>
> - **Unlocking the bootloader erases everything on the device.** Back up first.
> - **It can void your warranty.** Some manufacturers refuse to unlock at all; others require an online request and a waiting period. Carrier-locked devices often can't be unlocked.
> - **You can brick the device.** Flashing a file built for a different model or variant, or interrupting a flash, can leave it unable to boot. Some bricks can be recovered with vendor tools; some can't.
> - **Some apps stop working.** Banking, payment, some streaming apps and some games check device integrity and may refuse to run on an unlocked bootloader or a custom ROM.
>
> If any of this is a deal-breaker, stop here. Stock Android works fine with resurrect.

**resurrect never unlocks bootloaders, never flashes anything and never reboots into fastboot or recovery.** `rez device` only reads system properties and prints links. Every step below is something you do yourself, following your device's official instructions.

## Prerequisites

- A backup of everything on the device, copied to another device. For resurrect's data:

  ```bash
  rez backup run
  ```

  Then copy the archive off the device (see [backups.md](backups.md#copy-backups-off-the-device)). Shared files, synced folders and media are not in that archive; back them up too.
- A computer with [Android platform tools](https://developer.android.com/tools/releases/platform-tools) (`adb` and `fastboot`).
- A good USB cable and a charged battery. A flash interrupted by a dead battery is a common cause of bricks.

## 1. Identify the device

```bash
rez device
```

The output starts with the device report and the bootloader state, then lists the options for your device:

```text
resurrect 0.1.1 device report
Device:      <manufacturer> <model> (codename: <codename>)
Android:     <version> (SDK <n>), patch <date>
ROM:         stock (<build id>)
...
Bootloader:  locked (read from system properties; may be wrong on some vendors)
```

Note the **codename**, the name ROM projects use for the device, and the exact model number from Settings > About phone (or About tablet). The same marketing name often covers several variants (Wi-Fi and LTE, regional versions) with different codenames.

## 2. Check for official support

Look the device up by codename first, then by model name, because projects don't always use the same names. `rez device` prints a direct LineageOS link for your codename.

| Project | Device list | Notes |
|---|---|---|
| LineageOS | [wiki.lineageos.org/devices](https://wiki.lineageos.org/devices/) | The largest selection. Each device page has its own install guide |
| /e/OS | [doc.e.foundation/devices](https://doc.e.foundation/devices) | Based on LineageOS, without Google services |
| GrapheneOS | [grapheneos.org](https://grapheneos.org/faq#supported-devices) | Google Pixel devices only |
| postmarketOS | [wiki.postmarketos.org](https://wiki.postmarketos.org/wiki/Devices) | A real Linux distribution instead of Android. resurrect does not run on it |

Unofficial builds on forums such as [XDA](https://xdaforums.com) exist for many more devices. They range from excellent to abandoned and risky. Check when they were last updated and read the whole thread before you try one.

## 3. Follow only the official guide for your device

Each device page on the projects above has its own install guide: how to unlock the bootloader, which recovery to use, which firmware version must be installed first. Follow it exactly, in order, for your exact model and variant.

> [!WARNING]
> Never mix steps from different guides or different devices, and never flash a file that isn't listed for your exact codename.

Your manufacturer's official unlock instructions, where they exist, take precedence over anything else.

## 4. Reinstall resurrect

1. Install Termux and Termux:Boot from F-Droid or GitHub (not Google Play), and open Termux:Boot once.
2. Restore resurrect and your data by following [Restore on a new device](backups.md#restore-on-a-new-device).
3. Run `rez doctor`.

A custom ROM doesn't give you root by itself, and resurrect doesn't need it. If you want the root-only features (AdGuard Home on port 53 and the battery charge limit), see [rooting.md](rooting.md).

## Troubleshooting

| Symptom | What to do |
|---|---|
| `rez device` shows `Bootloader: unknown` | Some vendors don't expose the state through system properties. Check in the bootloader menu or with your manufacturer's tools |
| No official build for your device | Stay on stock Android. resurrect works on it, and an unofficial build is a risk only you can judge |
| The device doesn't boot after flashing | Stop and follow your ROM's recovery instructions for your exact device. Don't flash other files hoping one works |
| Banking or payment apps refuse to run | Expected on many unlocked devices. There is no reliable fix |
| Termux packages fail after a new ROM | Make sure Termux comes from F-Droid or GitHub, then run `pkg update` |

Questions about a specific device belong in that ROM's own community. resurrect can't help with flashing.

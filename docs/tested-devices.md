# Tested devices

This page lists real devices that people have run resurrect on, and how it went. It helps you judge whether your own device will work before you start. Every entry comes from a device report; nothing here is guessed from specifications.

> [!NOTE]
> **No device reports yet.** resurrect 0.1.1 has been tested in the official Termux container only (see [testing.md](testing.md)). Be the first: your report tells the next person whether their old device will work.

## Reported devices

| Device | Codename | Android / ROM | Arch | RAM | Root | Profile | Working | Problems | Version | Report |
|---|---|---|---|---|---|---|---|---|---|---|
| | | | | | | | | | | |

## Send a device report

### Prerequisites

- resurrect installed on the device, ideally running for at least a day.
- A GitHub account.

### Steps

1. Collect the device details. The output contains no serial numbers, IDs or network addresses, so it is safe to share:

   ```bash
   rez device --report
   ```

   ```text
   resurrect 0.1.1 device report
   Device:      <manufacturer> <model> (codename: <codename>)
   Android:     <version> (SDK <n>), patch <date>
   ROM:         stock (<build id>)
   Arch:        aarch64 (arm64)
   RAM:         total <n> MB, available <n> MB
   ...
   ```

2. Check the state of every module:

   ```bash
   rez status
   rez doctor
   ```

3. Open a [device report](https://github.com/JathinYanna04/Resurrect/issues/new?template=device-report.yml) and paste both outputs. The most useful details are:
   - which modules worked and which didn't,
   - MemAvailable after a day of running,
   - whether everything came back after a reboot,
   - vendor battery or "auto-start" settings you had to change.

Remove passwords, tokens and addresses from anything you paste. A maintainer adds the device to the table above.

## Troubleshooting

| Problem | What to do |
|---|---|
| `rez device --report` fails | Paste the error into the report instead; it is useful too |
| You can't tell whether a module works | Run `rez health`, which prints `ok` or `FAIL` for each module |
| Your device isn't supported at all | Report it anyway. Knowing what doesn't work helps too |

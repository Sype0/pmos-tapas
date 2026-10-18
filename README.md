# pmos-tapas

Mainline Linux bring-up for the Xiaomi Redmi Note 12 4G (`tapas`,
Snapdragon 685 / SM6225 "Khaje"), towards running postmarketOS on it.

**Status: builds on GitHub Actions, not yet booted on a device.**

## Why mainline

The earlier attempt ([linux-android-xiaomi-tapas](https://github.com/Sype0/linux-android-xiaomi-tapas),
Droidian) kept the Android GKI kernel. On tapas every driver, including
USB, UFS and the display, is a vendor module, so a boot that went wrong
before those modules were loaded had no screen and no USB to debug with.

This one builds a mainline kernel (7.1.5) with everything needed for
bring-up built in:

- the screen shows the kernel log from the start (the bootloader's
  framebuffer, `simple-framebuffer` + fbcon);
- a root shell on USB serial (CDC ACM) from the initramfs;
- the kernel log is kept in RAM (ramoops at the stock location), so after a
  crash and a warm reset the next boot prints the end of it on the screen.

The SoC support comes from the Redmi 10C mainline port by Damir00109
([Damir00109/Redmi10c](https://github.com/Damir00109/Redmi10c), commit
`ebe10a8`): `patches/0001-sm6225-redmi10c-mainline.patch` and
`config/base.config` are taken from there unchanged. The Redmi 10C has the
same SoC, and the stock tapas device tree (the dump in
[Mu-Silicium](https://github.com/Project-Silicium/Mu-Silicium/blob/main/Resources/DTBs/tapas.dts))
shows the same UFS rails and reset, SD card rails, volume keys and USB PHY.

## Images

The workflow publishes them on the
[releases page](https://github.com/Sype0/pmos-tapas/releases/tag/latest):

| File | Enabled |
| --- | --- |
| `boot-tapas.img` | framebuffer, USB serial, keys, UFS, SD card |
| `boot-tapas-safe.img` | framebuffer, USB serial, keys |

Both are Android boot images v1 with the DTB appended to the gzipped kernel,
the format Mu-Silicium boots tapas with. The kernel command line is built in
(`config/tapas.config`); the bootloader's is ignored.

## Testing

Needs an unlocked bootloader and another device with `fastboot` (a PC, or a
second phone with Termux and `android-tools`).

`fastboot boot` only loads the image into RAM: nothing on the phone is
changed, and a reboot goes back to Android.

1. Turn the phone off, hold Volume Down + Power to enter fastboot, connect
   USB.
2. `fastboot boot boot-tapas.img`
3. The screen should fill with kernel messages, then lines starting with
   `tapas:` from the init: USB state and the block devices found.
4. The phone shows up as a USB serial port (`/dev/ttyACM0` on Linux, a COM
   port on Windows, or use a USB serial terminal app on Android). Open it at
   115200 for a root shell.
5. To leave: hold Power until it restarts (Volume Down + Power for fastboot).

What to report back:

- how far the screen gets (a photo of the last lines), or if it stays on the
  bootloader logo / goes back to fastboot;
- if it restarts by itself: boot `boot-tapas.img` again right away, the init
  prints the end of the previous log as `prev:` lines and keeps it in
  `/tmp/last_kmsg`;
- if `boot-tapas.img` does not get far, the same with `boot-tapas-safe.img`.

## Root filesystem

If a filesystem labelled `tapas_root` with an init exists (SD card or a
spare partition), the initramfs switches to it after 10 seconds. Run `stay`
in the USB serial shell before then to stay in the initramfs.

## Building locally

`scripts/build.sh [out-dir]` on an arm64 or x86_64 Linux host (cross builds
use `aarch64-linux-gnu-`; set `BUSYBOX` to a static aarch64 busybox). See
`.github/workflows/build.yml` for the packages.

## Layout

| Path | |
| --- | --- |
| `dts/` | tapas device trees, added to `arch/arm64/boot/dts/qcom` |
| `patches/` | applied to linux-stable `v7.1.5` |
| `config/base.config` | Redmi 10C kernel config |
| `config/tapas.config` | changes on top of it |
| `initramfs/init` | bring-up init (busybox) |
| `scripts/build.sh` | builds everything |

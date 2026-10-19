# pmos-tapas

Mainline Linux bring-up for the Xiaomi Redmi Note 12 4G (`tapas`,
Snapdragon 685 / SM6225 "Khaje"), towards running postmarketOS on it.

**Status: builds on GitHub Actions, not yet booted on a device.**

## Why mainline

The earlier attempt ([linux-android-xiaomi-tapas](https://github.com/Sype0/linux-android-xiaomi-tapas),
Droidian) kept the Android GKI kernel. On tapas every driver, including
USB, UFS and the display, is a vendor module, so a boot that went wrong
before those modules were loaded had no screen and no USB to debug with.

This one builds a mainline kernel with everything needed for bring-up
built in:

- the screen shows the kernel log from the start (the bootloader's
  framebuffer, `simple-framebuffer` + fbcon);
- a root shell on USB serial (CDC ACM) from the initramfs;
- the kernel log is kept in RAM (ramoops at the stock location), so after a
  crash and a warm reset the next boot prints the end of it on the screen.

The kernel is the [sm6225-mainline](https://gitlab.postmarketos.org/sm6225-mainline)
one (`linux-v.7.2.1`, branch `stable-sm6225`, 7.2.9), the SM6225 kernel
postmarketOS packages for the Redmi Note 11 (`spes`), with its pmaports
config as `config/base.config`. The tapas device tree is laid out like the
spes one, which shares most of the board (PMIC, charger, Type-C controller,
I2C buses); the regulator ranges come from the stock tapas device tree
([dump in Mu-Silicium](https://github.com/Project-Silicium/Mu-Silicium/blob/main/Resources/DTBs/tapas.dts)).

## How it boots

Xiaomi's bootloader (ABL) on tapas only takes **boot images v4**: v1 and v2
images are ignored, which is why the first images of this repo (v1 with an
appended DTB) did not get anywhere. Both
[topaz-woa](https://github.com/MakrSas/topaz-woa) (Windows) and
[ios-topaz](https://github.com/MakrSas/ios-topaz) boot this phone from v4
images.

For a v4 image ABL hands the kernel the DTB from `vendor_boot` (the
downstream one) and the vendor ramdisk, not ours. So the image's kernel is a
small shim (`shim/start.S`) with our DTB and the real kernel behind it: ABL
starts the shim like a kernel, the shim drops ABL's DTB and starts the
mainline kernel with ours. The initramfs is built into the kernel.

The shim draws bands of 48 rows from the top of the screen as it goes, so a
photo of the first seconds tells how far it got:

| Band | Shows |
| --- | --- |
| none, back to the logo or fastboot | ABL did not start the image |
| 0 blue | the shim runs |
| 1, 2 bits | where ABL loaded the image (bits 63..32, 31..0) |
| 3 yellow blocks | one per 2 MB of kernel copied to 0x80000000 |
| 4 green | jumping into the kernel; the kernel log should follow |
| 5 red | the image is broken (bad descriptor) |
| 5 magenta / cyan / white / orange | exception (sync / IRQ / FIQ / SError), details in 6-9 |
| 6, 7, 8, 9 bits | ESR_EL1, FAR_EL1 (63..32, 31..0), ELR_EL1 minus the load address |
| 10, 11 bits | SCTLR_EL1 and CurrentEL at entry |

Bits are 32 squares, most significant first: bright is 1, dark is 0,
alternating nibbles in white/grey and orange/navy.

ABL loads the image low in RAM, where the kernel (with its BSS) would run
into the hypervisor and the other carveouts from 0x45700000 up, so the shim
always copies it to the free bank at 0x80000000.

Since ABL does not see our DTB, it does not fill in the memory node: the
device tree has the layout ABL reports on the **6 GB** model. Other RAM
sizes need their own (ABL prints it in the `logfs` partition,
`UefiLog*.txt`, "RAM Partitions").

## Images

The workflow publishes them on the
[releases page](https://github.com/Sype0/pmos-tapas/releases/tag/latest):

| File | Enabled |
| --- | --- |
| `boot-tapas.img` | framebuffer, USB serial, keys, UFS, SD card |
| `boot-tapas-safe.img` | framebuffer, USB serial, keys |

The kernel command line is built in (`config/tapas.config`).

## Testing

Needs an unlocked bootloader and another device with `fastboot` (a PC, or a
second phone with Termux and `android-tools`).

1. Turn the phone off, hold Volume Down + Power to enter fastboot, connect
   USB.
2. Boot the image from RAM, nothing is written to the phone:

   ```
   fastboot boot boot-tapas-safe.img
   ```

   (`fastboot boot` did not work with the old v1 images; it does with v4 on
   this bootloader.)
3. Watch the bar at the top (table above), then the kernel log, then lines
   starting with `tapas:` from the init: USB state and the block devices
   found.
4. The phone shows up as a USB serial port (`/dev/ttyACM0` on Linux, a COM
   port on Windows, or use a USB serial terminal app on Android). Open it at
   115200 for a root shell.
5. If the safe image gets there, the same with `boot-tapas.img` (UFS and SD
   card).

Back to Android: hold Volume Down + Power until fastboot shows up, then
`fastboot reboot`. Nothing was changed on the phone.

If `fastboot boot` is refused, flash the image to the boot partition of the
**inactive** slot instead (`fastboot getvar current-slot`; if it says `b`):

```
fastboot flash boot_a boot-tapas-safe.img
fastboot set_active a
fastboot reboot
```

and go back with `fastboot set_active b` and `fastboot reboot`.

What to report back:

- the colour of the bar and how far the screen gets (a photo of the last
  lines), or if it stays on the bootloader logo / goes back to fastboot;
- if it restarts by itself: boot it again, the init prints the end of the
  previous log as `prev:` lines and keeps it in `/tmp/last_kmsg`.

## Root filesystem

If a filesystem labelled `tapas_root` with an init exists (SD card or a
spare partition), the initramfs switches to it after 10 seconds. Run `stay`
in the USB serial shell before then to stay in the initramfs.

## Building locally

`scripts/build.sh [out-dir]` on an arm64 Linux host with clang, lld and
llvm (set `BUSYBOX` to a static aarch64 busybox). See
`.github/workflows/build.yml` for the packages.

## Layout

| Path | |
| --- | --- |
| `dts/` | tapas device trees, added to `arch/arm64/boot/dts/qcom` |
| `config/base.config` | sm6225-mainline pmaports kernel config |
| `config/tapas.config` | changes on top of it |
| `initramfs/init` | bring-up init (busybox) |
| `shim/` | boot shim between ABL and the kernel |
| `scripts/build.sh` | builds everything |
| `scripts/pack-shim.py` | puts the DTB and the kernel behind the shim |
| `scripts/mkbootimg.py` | AOSP mkbootimg, as shipped by Mu-Silicium (Ubuntu's package lacks its `gki` module) |

#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Append a DTB and a kernel Image to the boot shim (see shim/start.S).

    pack-shim.py SHIM_BIN DTB KERNEL_IMAGE OUT
"""
import struct
import sys

DESC_OFF = 0x1000
DTB_OFF = 0x2000
KERNEL_OFF = 0x200000
DESC_MAGIC = 0x4D494853  # "SHIM"


def main():
    shim_path, dtb_path, kernel_path, out_path = sys.argv[1:5]
    shim = open(shim_path, "rb").read()
    dtb = open(dtb_path, "rb").read()
    kernel = open(kernel_path, "rb").read()

    if len(shim) > DESC_OFF:
        sys.exit(f"shim is {len(shim)} bytes, more than {DESC_OFF:#x}")
    if dtb[:4] != b"\xd0\x0d\xfe\xed":
        sys.exit(f"{dtb_path} is not a DTB")
    if DTB_OFF + len(dtb) > KERNEL_OFF:
        sys.exit(f"DTB is {len(dtb)} bytes, too big")
    # Uncompressed arm64 Image: magic at 0x38, image_size (memory incl. BSS) at 16
    if kernel[0x38:0x3C] != b"ARM\x64":
        sys.exit(f"{kernel_path} is not an uncompressed arm64 Image")
    kernel_mem = struct.unpack_from("<Q", kernel, 16)[0] or len(kernel)

    # Padded to 4K like the images known to boot on this ABL
    out = bytearray((KERNEL_OFF + len(kernel) + 0xFFF) & ~0xFFF)
    out[: len(shim)] = shim
    struct.pack_into("<6Q", out, DESC_OFF, DESC_MAGIC, KERNEL_OFF, len(kernel),
                     kernel_mem, DTB_OFF, len(dtb))
    out[DTB_OFF : DTB_OFF + len(dtb)] = dtb
    out[KERNEL_OFF : KERNEL_OFF + len(kernel)] = kernel
    # The shim's header: image_size = the file, as in the v4 images that
    # topaz-woa (Mu-Silicium) and ios-topaz boot on this ABL. Whatever ABL
    # places right after it (its DTB, the vendor ramdisk) is not used.
    struct.pack_into("<Q", out, 16, len(out))
    open(out_path, "wb").write(out)
    print(f"{out_path}: {len(out)} bytes (kernel {len(kernel)}, in memory {kernel_mem}; dtb {len(dtb)})")


if __name__ == "__main__":
    main()

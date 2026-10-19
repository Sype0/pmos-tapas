#!/bin/sh
# Build the tapas bring-up boot images.
#
#   scripts/build.sh [out-dir]
#
# Needs: make, clang, lld, llvm, bc, bison, flex, libssl-dev, libelf-dev,
# cpio, gzip, curl, python3 and a static aarch64 busybox (BUSYBOX=/path,
# default: the one in PATH).
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=$(mkdir -p "${1:-$ROOT/out}" && cd "${1:-$ROOT/out}" && pwd)
WORK=${WORK:-$ROOT/work}
# sm6225-mainline kernel, branch stable-sm6225 (7.2.9)
KERNEL_COMMIT=b8463e4b9111517f89da970d1e1145b851ce8d48
KERNEL_URL=https://gitlab.postmarketos.org/sm6225-mainline/kernels/linux-v.7.2.1/-/archive/$KERNEL_COMMIT.tar.gz
SRC=$WORK/linux-$KERNEL_COMMIT
KOUT=$WORK/kernel-out
DTS_DIR=arch/arm64/boot/dts/qcom
VARIANTS="tapas tapas-safe"
# Built with LLVM like the sm6225-mainline pmaports package
KMAKE="make -C $SRC O=$KOUT ARCH=arm64 LLVM=1"

mkdir -p "$WORK"

# Kernel sources
if [ ! -d "$SRC" ]; then
	curl -fL --retry 3 "$KERNEL_URL" | tar -xz -C "$WORK"
	mv "$WORK/linux-v.7.2.1-$KERNEL_COMMIT" "$SRC"
fi
cp "$ROOT"/dts/*.dts "$SRC/$DTS_DIR/"
for v in $VARIANTS; do
	grep -q "sm6225-xiaomi-$v.dtb" "$SRC/$DTS_DIR/Makefile" ||
		echo "dtb-\$(CONFIG_ARCH_QCOM) += sm6225-xiaomi-$v.dtb" >>"$SRC/$DTS_DIR/Makefile"
done

# Initramfs: busybox and the bring-up init. Built into the kernel, because
# ABL drops the boot image's ramdisk.
BUSYBOX=${BUSYBOX:-$(command -v busybox)}
file -L "$BUSYBOX" | grep -Eq 'ARM aarch64.*static(ally|-pie) linked' ||
	{ echo "$BUSYBOX is not a static aarch64 busybox" >&2; exit 1; }
# Applets the init needs for the network shell and the register dumps
for applet in telnetd udhcpd ifconfig devmem setsid cttyhack dd od tr; do
	"$BUSYBOX" --list | grep -qx "$applet" ||
		{ echo "$BUSYBOX has no $applet" >&2; exit 1; }
done
# A gen_init_cpio list, so /dev/console exists without root
cat >"$WORK/initramfs.list" <<EOF
dir /bin 755 0 0
file /bin/busybox $(readlink -f "$BUSYBOX") 755 0 0
file /init $ROOT/initramfs/init 755 0 0
dir /dev 755 0 0
nod /dev/console 600 0 0 c 5 1
EOF

# Config
mkdir -p "$KOUT"
cp "$ROOT/config/base.config" "$KOUT/.config"
{
	cat "$ROOT/config/tapas.config"
	echo "CONFIG_INITRAMFS_SOURCE=\"$WORK/initramfs.list\""
} >"$WORK/tapas.config"
"$SRC/scripts/kconfig/merge_config.sh" -m -O "$KOUT" "$KOUT/.config" "$WORK/tapas.config"
$KMAKE olddefconfig
# merge_config only warns when a value does not stick, fail instead
grep -v '^#' "$WORK/tapas.config" | grep . | while IFS= read -r opt; do
	grep -qxF "$opt" "$KOUT/.config" || { echo "Config option not applied: $opt" >&2; exit 1; }
done

# Kernel (uncompressed: the shim jumps into it) and device trees
$KMAKE -j"$(nproc)" Image $(for v in $VARIANTS; do echo "qcom/sm6225-xiaomi-$v.dtb"; done)
KREL=$(cat "$KOUT/include/config/kernel.release")

# Boot shim (shim/start.S)
clang --target=aarch64-linux-gnu -c "$ROOT/shim/start.S" -o "$WORK/shim.o"
ld.lld -T "$ROOT/shim/shim.ld" --build-id=none -o "$WORK/shim.elf" "$WORK/shim.o"
llvm-objcopy -O binary "$WORK/shim.elf" "$WORK/shim.bin"

# Boot images v4 (Xiaomi's ABL ignores v1/v2): the "kernel" is the shim with
# our DTB and the kernel behind it. The ramdisk is never used, but ABL wants
# one, so it gets an empty cpio.
(mkdir -p "$WORK/empty" && cd "$WORK/empty" && find . | cpio -o -H newc -R 0:0 --quiet | gzip -9n) >"$WORK/empty.cpio.gz"
for v in $VARIANTS; do
	python3 "$ROOT/scripts/pack-shim.py" "$WORK/shim.bin" "$KOUT/$DTS_DIR/sm6225-xiaomi-$v.dtb" \
		"$KOUT/arch/arm64/boot/Image" "$WORK/shim-$v.bin"
	python3 "$ROOT/scripts/mkbootimg.py" \
		--header_version 4 \
		--kernel "$WORK/shim-$v.bin" \
		--ramdisk "$WORK/empty.cpio.gz" \
		--os_version 13.0.0 --os_patch_level 2026-10 \
		--cmdline "" \
		--output "$OUT/boot-$v.img"
	cp "$KOUT/$DTS_DIR/sm6225-xiaomi-$v.dtb" "$OUT/"
done

cp "$KOUT/.config" "$OUT/kernel.config"
cp "$KOUT/System.map" "$OUT/"
echo "$KREL" >"$OUT/kernel.release"
(cd "$OUT" && sha256sum boot-*.img *.dtb >SHA256SUMS)
ls -la "$OUT"

#!/bin/sh
# Build the tapas bring-up boot images.
#
#   scripts/build.sh [out-dir]
#
# Needs: git, make, gcc (aarch64 native, or aarch64-linux-gnu- cross),
# bc, bison, flex, libssl-dev, cpio, gzip, python3 and a static aarch64
# busybox (BUSYBOX=/path, default: the one in PATH).
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=$(mkdir -p "${1:-$ROOT/out}" && cd "${1:-$ROOT/out}" && pwd)
WORK=${WORK:-$ROOT/work}
KERNEL_TAG=v7.1.5
KERNEL_REPO=https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git
SRC=$WORK/linux
KOUT=$WORK/kernel-out
DTS_DIR=arch/arm64/boot/dts/qcom
VARIANTS="tapas tapas-safe"

if [ "$(uname -m)" != aarch64 ]; then
	export CROSS_COMPILE=${CROSS_COMPILE:-aarch64-linux-gnu-}
fi
export ARCH=arm64

mkdir -p "$WORK"

# Kernel sources
if [ ! -d "$SRC" ]; then
	git clone --depth 1 --branch "$KERNEL_TAG" "$KERNEL_REPO" "$SRC"
	for p in "$ROOT"/patches/*.patch; do
		echo "Applying ${p##*/}"
		git -C "$SRC" apply --whitespace=nowarn "$p"
	done
fi
cp "$ROOT"/dts/*.dts "$SRC/$DTS_DIR/"
for v in $VARIANTS; do
	grep -q "sm6225-xiaomi-$v.dtb" "$SRC/$DTS_DIR/Makefile" ||
		echo "dtb-\$(CONFIG_ARCH_QCOM) += sm6225-xiaomi-$v.dtb" >>"$SRC/$DTS_DIR/Makefile"
done

# Config
mkdir -p "$KOUT"
cp "$ROOT/config/base.config" "$KOUT/.config"
"$SRC/scripts/kconfig/merge_config.sh" -m -O "$KOUT" "$KOUT/.config" "$ROOT/config/tapas.config"
make -C "$SRC" O="$KOUT" olddefconfig
# merge_config only warns when a value does not stick, fail instead
grep -v '^#' "$ROOT/config/tapas.config" | grep . | while IFS= read -r opt; do
	grep -qxF "$opt" "$KOUT/.config" || { echo "Config option not applied: $opt" >&2; exit 1; }
done

# Kernel and device trees
make -C "$SRC" O="$KOUT" -j"$(nproc)" Image.gz $(for v in $VARIANTS; do echo "qcom/sm6225-xiaomi-$v.dtb"; done)
KREL=$(cat "$KOUT/include/config/kernel.release")

# Initramfs: busybox and the bring-up init
BUSYBOX=${BUSYBOX:-$(command -v busybox)}
file -L "$BUSYBOX" | grep -Eq 'ARM aarch64.*static(ally|-pie) linked' ||
	{ echo "$BUSYBOX is not a static aarch64 busybox" >&2; exit 1; }
IR=$WORK/initramfs
rm -rf "$IR"
mkdir -p "$IR/bin"
cp -L "$BUSYBOX" "$IR/bin/busybox"
install -m 755 "$ROOT/initramfs/init" "$IR/init"
(cd "$IR" && find . | sort | cpio -o -H newc -R 0:0 --quiet | gzip -9n) >"$WORK/initramfs.cpio.gz"

# Boot images: header v1 with the DTB appended to the gzipped kernel, the
# format the tapas bootloader is known to take (Mu-Silicium boots this way)
for v in $VARIANTS; do
	cat "$KOUT/arch/arm64/boot/Image.gz" "$KOUT/$DTS_DIR/sm6225-xiaomi-$v.dtb" >"$WORK/Image.gz-dtb-$v"
	python3 "$ROOT/scripts/mkbootimg.py" \
		--header_version 1 \
		--kernel "$WORK/Image.gz-dtb-$v" \
		--ramdisk "$WORK/initramfs.cpio.gz" \
		--pagesize 4096 \
		--base 0x0 --kernel_offset 0x8000 --ramdisk_offset 0x1000000 --tags_offset 0x100 \
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

#!/system/bin/sh
# Build the tapas root filesystem image (ext4, label tapas_root) on a rooted
# Android phone, as root: an Alpine minirootfs, then postmarketOS packages
# from the pmOS repo with apk in a chroot (no pmbootstrap there).
# Copy the result to the SD card as tapas/rootfs.img.
#
#   mkrootfs-android.sh <alpine-minirootfs-3.24.x-aarch64.tar.gz> <repo>/rootfs <out.img>
set -e
TAR=$1 FILES=$2 IMG=$3
W=/data/local/tmp/tapas-rootfs
M=$W/mnt
SIZE_MB=2048

cleanup() {
	for d in dev/pts dev proc sys; do umount "$M/$d" 2>/dev/null || true; done
	umount "$M" 2>/dev/null || true
}
trap cleanup EXIT

mkdir -p "$W" "$M"
cleanup
rm -f "$IMG"
dd if=/dev/zero of="$IMG" bs=1M count=0 seek=$SIZE_MB 2>/dev/null
mke2fs -q -t ext4 -L tapas_root -O ^metadata_csum_seed "$IMG"
mount -t ext4 -o loop,rw "$IMG" "$M"
tar -xzpf "$TAR" -C "$M"

mount -o bind /dev "$M/dev"
mount -o bind /dev/pts "$M/dev/pts"
mount -t proc proc "$M/proc"
mount -t sysfs sysfs "$M/sys"
echo "nameserver 1.1.1.1" >"$M/etc/resolv.conf"

cat >"$M/etc/apk/repositories" <<'EOF'
https://mirror.postmarketos.org/postmarketos/v26.06
https://dl-cdn.alpinelinux.org/alpine/v3.24/main
https://dl-cdn.alpinelinux.org/alpine/v3.24/community
EOF

C="chroot $M /usr/bin/env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin HOME=/root TERM=linux"
# The pmOS signing keys come from the pmOS repo itself
$C /sbin/apk update --allow-untrusted
$C /sbin/apk add --allow-untrusted postmarketos-keys
$C /sbin/apk update
$C /sbin/apk add alpine-base openrc busybox-extras busybox-openrc openssh \
	e2fsprogs util-linux dosfstools doas nano htop pciutils usbutils \
	kmod tzdata iw bash

# Board files: gadget network, services, fstab, inittab
cp -R "$FILES"/. "$M"/
chmod 755 "$M/etc/local.d/tapas-usb.start"

echo tapas >"$M/etc/hostname"
printf '127.0.0.1\tlocalhost tapas\n::1\t\tlocalhost tapas\n' >"$M/etc/hosts"
$C /bin/sh -c '
set -e
ln -sf /usr/share/zoneinfo/Europe/Istanbul /etc/localtime
adduser -D -s /bin/bash -G wheel user
echo "user:147147" | chpasswd
echo "root:147147" | chpasswd
echo "permit persist :wheel" >/etc/doas.d/wheel.conf
# postmarketos-base comes in for alpine-base and brings udev
for s in devfs dmesg; do rc-update add $s sysinit; done
for s in hwclock modules sysctl hostname bootmisc syslog; do rc-update add $s boot; done
for s in local sshd crond; do rc-update add $s default; done
for s in mount-ro killprocs savecache; do rc-update add $s shutdown; done
# No swap file inside a loop image on FAT
rc-update del swapfile default || true
'
rm -f "$M/etc/resolv.conf"
echo "nameserver 1.1.1.1" >"$M/etc/resolv.conf"
sync
du -sh -x "$M" 2>/dev/null | sed 's/^/rootfs used: /'

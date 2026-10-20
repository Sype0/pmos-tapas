#!/system/bin/sh
# Build the tapas root filesystem image (ext4, label tapas_root) on a rooted
# Android phone, as root: an Alpine minirootfs, then postmarketOS packages
# from the pmOS repo with apk in a chroot (no pmbootstrap there).
# Write the result straight onto the SD card's partition (MBR type 0x83, so
# Android leaves it alone) and grow it there:
#   dd if=out.img of=/dev/block/mmcblk1p1 bs=4M conv=fsync
#   e2fsck -fy /dev/block/mmcblk1p1 && resize2fs /dev/block/mmcblk1p1
# (tapas/rootfs.img on a FAT card still works, but FAT caps it at 4 GiB.)
#
#   mkrootfs-android.sh <alpine-minirootfs-3.24.x-aarch64.tar.gz> <repo>/rootfs <out.img>
set -e
TAR=$1 FILES=$2 IMG=$3
W=/data/local/tmp/tapas-rootfs
M=$W/mnt
SIZE_MB=3072

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
# Plasma Mobile on the bootloader's framebuffer (simpledrm), rendered by the
# Adreno (freedreno); greetd logs straight into it
$C /sbin/apk add postmarketos-ui-plasma-mobile mesa-dri-gallium \
	greetd greetd-openrc qmlkonsole
# Modem (rmtfs, tqftpserv, UIM slot selection; pd-mapper is in the kernel)
# and Bluetooth tools
$C /sbin/apk add msm-modem msm-modem-uim-selection-openrc rmtfs-openrc \
	rmtfs-udev tqftpserv tqftpserv-openrc qrtr bluez-btmgmt bluez-btmon

# Board files: gadget network, services, fstab, inittab, Plasma settings.
# The checkout's modes depend on its umask: make everything readable.
cp -R "$FILES"/. "$M"/
(cd "$FILES" && find . -mindepth 1) | while read -r p; do chmod go+rX "$M/$p"; done
chmod 755 "$M"/etc/local.d/*.start "$M"/etc/init.d/tapas-*

# Stock firmware from this phone's vendor partitions: GPU, modem (with the
# Wi-Fi firmware it runs and its carrier configs), IPA, ADSP and the speaker
# amplifier's profiles, Bluetooth, and the
# Wi-Fi board files as an ath10k board-2.bin. firmware-5.bin (ath10k
# features) is the linux-firmware one for this Wi-Fi generation.
FW=$M/lib/firmware
D=$FW/qcom/sm6225/xiaomi/tapas
A=$FW/ath10k/WCN3990/hw1.0/xiaomi-tapas
mkdir -p "$D" "$FW/qca" "$A"
cp /vendor/firmware/a630_sqe.fw /vendor/firmware/a610_zap.* "$FW/qcom/"
cp /vendor/firmware_mnt/image/modem.* /vendor/firmware_mnt/image/wlanmdsp.mbn \
	/vendor/firmware_mnt/image/adsp.* /vendor/firmware/ipa_fws.* "$D/"
cp /vendor/firmware/aw87xxx_acf.bin "$FW/"
cp -R /vendor/firmware_mnt/image/modem_pr "$D/"
cp /vendor/bt_firmware/image/cmbtfw1[23].tlv /vendor/bt_firmware/image/cmnv1[23]*.bin "$FW/qca/"
${PYTHON:-python3} "$(dirname "$0")/ath10k-bd.py" /vendor/firmware_mnt/image "$A/board-2.bin"
cp /vendor/firmware_mnt/image/bdwlan.bin "$A/board.bin"
$C /usr/bin/wget -q -O /lib/firmware/ath10k/WCN3990/hw1.0/xiaomi-tapas/firmware-5.bin \
	https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/ath10k/WCN3990/hw1.0/qcm2290/firmware-5.bin
chown -R 0:0 "$FW"
chmod -R u=rwX,go=rX "$FW"
# Bluetooth address for tapas-bdaddr.start
mkdir -p "$M/etc/tapas"
settings get secure bluetooth_address >"$M/etc/tapas/bdaddr"

echo tapas >"$M/etc/hostname"
printf '127.0.0.1\tlocalhost tapas\n::1\t\tlocalhost tapas\n' >"$M/etc/hosts"
$C /bin/sh -c '
set -e
ln -sf /usr/share/zoneinfo/Europe/Istanbul /etc/localtime
adduser -D -s /bin/bash -G wheel user
for g in audio input video netdev plugdev feedbackd; do addgroup user $g; done
echo "user:147147" | chpasswd
echo "root:147147" | chpasswd
echo "permit persist :wheel" >/etc/doas.d/wheel.conf
sed -i "s|^#\?rc_logger=.*|rc_logger=\"YES\"|" /etc/rc.conf
# postmarketos-base comes in for alpine-base and brings udev
for s in devfs dmesg tapas-klog; do rc-update add $s sysinit; done
for s in swclock modules sysctl hostname bootmisc syslog tapas-late-probe; do rc-update add $s boot; done
for s in local sshd crond rmtfs tqftpserv msm-modem-uim-selection; do rc-update add $s default; done
# Autologin into Plasma Mobile with greetd (rootfs/etc/greetd/config.toml)
# instead of the tinydm that postmarketos-ui-plasma-mobile-openrc enables
sed -i "s|^#\?cfgfile=.*|cfgfile=\"/etc/greetd/config.toml\"|" /etc/conf.d/greetd
rc-update del tinydm default || true
rc-update add greetd default
for s in mount-ro killprocs savecache; do rc-update add $s shutdown; done
# No swap file inside a loop image on FAT
rc-update del swapfile default || true
'
rm -f "$M/etc/resolv.conf"
echo "nameserver 1.1.1.1" >"$M/etc/resolv.conf"
sync
du -sh -x "$M" 2>/dev/null | sed 's/^/rootfs used: /'

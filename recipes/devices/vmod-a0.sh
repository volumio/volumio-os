#!/usr/bin/env bash
# shellcheck disable=SC2034

## Setup for Volumio VMOD-A0
DEVICE_SUPPORT_TYPE="O" # First letter (Community Porting|Supported Officially|OEM)
DEVICE_STATUS="P"       # First letter (Planned|Test|Maintenance)

# Base system
BASE="Debian"
ARCH="armhf"
BUILD="armv7"
UINITRD_ARCH="arm64"

### Device information
DEVICENAME="VMOD-A0"
# This is useful for multiple devices sharing the same/similar kernel
DEVICEFAMILY="rockpi"
# tarball from DEVICEFAMILY repo to use
#DEVICEBASE=${DEVICE} # Defaults to ${DEVICE} if unset
DEVICEREPO="https://github.com/volumio/platform-${DEVICEFAMILY}.git"

### What features do we want to target
# TODO: Not fully implement
VOLVARIANT=no # Custom Volumio (Motivo/Primo etc)
MYVOLUMIO=no
VOLINITUPDATER=yes
DISABLE_DISPLAY=yes

## Partition info
BOOT_START=17
BOOT_END=273
IMAGE_END=3985     # BOOT_END + 3712 MiB (/img squashfs)
BOOT_TYPE=msdos          # msdos or gpt
BOOT_USE_UUID=yes        # Add UUID to fstab
INIT_TYPE="initv3"

# Modules that will be added to intramsfs
MODULES=("fuse" "nls_cp437" "overlay" "overlayfs" "squashfs")
# Packages that will be installed
PACKAGES=("abootimg" "bluetooth" "bluez" "bluez-firmware" "bluez-tools" "fbset" "linux-base" "lirc" "mc" "triggerhappy")

### Device customisation
# Copy the device specific files (Image/DTS/etc..)
write_device_files() {
	log "Running write_device_files" "ext"

	cp -dR "${PLTDIR}/${DEVICE}/boot" "${ROOTFSMNT}"
	cp -pdR "${PLTDIR}/${DEVICE}/lib/modules" "${ROOTFSMNT}/lib"
	cp -pdR "${PLTDIR}/${DEVICE}/lib/firmware" "${ROOTFSMNT}/lib"
}

write_device_bootloader() {
	log "Running write_device_bootloader" "ext"

	dd if="${PLTDIR}/${DEVICE}/u-boot/idbloader.bin" of="${LOOP_DEV}" seek=64 conv=notrunc status=none
	dd if="${PLTDIR}/${DEVICE}/u-boot/uboot.img" of="${LOOP_DEV}" seek=16384 conv=notrunc status=none
	dd if="${PLTDIR}/${DEVICE}/u-boot/trust.bin" of="${LOOP_DEV}" seek=24576 conv=notrunc status=none
}

# Will be called by the image builder for any customisation
device_image_tweaks() {
	:
}

### Chroot tweaks
# Will be run in chroot (before other things)
device_chroot_tweaks() {
	:
}

# Will be run in chroot - Pre initramfs
device_chroot_tweaks_pre() {
	log "Performing device_chroot_tweaks_pre" "ext"
	log "Fixing armv8 deprecated instruction emulation with armv7 rootfs"
	cat <<-EOF >> /etc/sysctl.conf
		abi.cp15_barrier=2
	EOF

	log "Creating boot parameters from template" "cfg"
	sed -i "s/rootdev=UUID=/rootdev=UUID=${UUID_BOOT}/g" /boot/armbianEnv.txt
	sed -i "s/imgpart=UUID=/imgpart=UUID=${UUID_IMG}/g" /boot/armbianEnv.txt
	sed -i "s/bootpart=UUID=/bootpart=UUID=${UUID_BOOT}/g" /boot/armbianEnv.txt
	sed -i "s/datapart=UUID=/datapart=UUID=${UUID_DATA}/g" /boot/armbianEnv.txt

	log "Adding gpio group and udev rules" "info"
	groupadd -f --system gpio
	usermod -aG gpio volumio
	# Works with newer kernels as well
	cat <<-EOF > /etc/udev/rules.d/99-gpio.rules
		SUBSYSTEM=="gpio*", PROGRAM="/bin/sh -c 'find -L /sys/class/gpio/ -maxdepth 2 -exec chown root:gpio {} \; -exec chmod 770 {} \; || true'"
	EOF

	log "Fix for Volumio Remote updater"
	sed -i '10i\RestartSec=5' /lib/systemd/system/volumio-remote-updater.service

	log "UDEV Rule and script to set fixed MAC addresses"
	cat <<-EOF > /etc/udev/rules.d/05-fixMACaddress.rules
		#If a network interface is being assigned a new, different address on each boot,
		#or the MAC address is based on a disk image (rather than a hardware serial #),
		#enable the corresponding line below to derive that interface's MAC address from
		#the RK3308 SOC's unique serial number.
		KERNEL=="wlan0", ACTION=="add" RUN+="/usr/bin/fixEtherAddr %k 0a"
		KERNEL=="p2p0", ACTION=="add" RUN+="/usr/bin/fixEtherAddr %k 0e"
		KERNEL=="eth0", ACTION=="add" RUN+="/usr/bin/fixEtherAddr %k 06"
	EOF

	cat <<-'EOF' > /usr/bin/fixEtherAddr
		#!/bin/sh

		#Assign specified interface a fixed, unique Ethernet MAC address constructed
		#from given prefix byte followed by five byte RK3308 CPU serial number
		#Ethernet prefix byte value less 2 should be exactly divisible by 4
		#e.g. (prefix - 2) % 4 == 0

		[ '$2' ] || {
		  echo 'Specify network interface and first Ethernet address byte in hex' >&2
		  exit 1
		}

		cpuSerialNum() {
		#output first 5 bytes of CPU Serial number in hex with a space between each
		#nvmem on RK3308 does not handle multiple simultaneous readers :-(
		  nvmem=/sys/bus/nvmem/devices/rockchip-otp0/nvmem
		  serNumOffset=20
		  /usr/bin/flock -w2 $nvmem /usr/bin/od -An -vtx1 -j $serNumOffset -N 5 $nvmem
		}

		Id=`cpuSerialNum` && { #fail if Rockchip nvmem not available
		  /sbin/ip link set $1 address $2:`echo $Id | tr ' ' :`
		}
	EOF

	chmod a+x /usr/bin/fixEtherAddr

}

# Will be run in chroot - Post initramfs
device_chroot_tweaks_post() {
	# log "Running device_chroot_tweaks_post" "ext"
	:
}

# Will be called by the image builder post the chroot, before finalisation
device_image_tweaks_post() {
	log "Running device_image_tweaks_post" "ext"
	log "Creating uInitrd from 'volumio.initrd'" "info"
	if [[ -f "${ROOTFSMNT}"/boot/volumio.initrd ]]; then
		mkimage -v -A "${UINITRD_ARCH}" -O linux -T ramdisk -C none -a 0 -e 0 -n uInitrd -d "${ROOTFSMNT}"/boot/volumio.initrd "${ROOTFSMNT}"/boot/uInitrd
		rm "${ROOTFSMNT}"/boot/volumio.initrd
	fi
	if [[ -f "${ROOTFSMNT}"/boot/boot.cmd ]]; then
		log "Creating boot.scr" "cfg"
		mkimage -A arm -T script -C none -d "${ROOTFSMNT}"/boot/boot.cmd "${ROOTFSMNT}"/boot/boot.scr
	fi
}

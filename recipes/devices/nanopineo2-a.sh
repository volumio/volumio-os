#!/usr/bin/env bash
# shellcheck disable=SC2034

## Setup for NanoPi NEO2 device board
DEVICE_SUPPORT_TYPE="O" # First letter (Community Porting|Supported Officially|OEM)
DEVICE_STATUS="P"       # First letter (Planned|Test|Maintenance)

# Base system
BASE="Debian"
ARCH="armhf"
BUILD="armv7"
UINITRD_ARCH="arm64" # Instruct mkimage to use the correct architecture on arm{64} devices

### Device information
DEVICENAME="NanoPi NEO2" # Pretty name
# This is useful for multiple devices sharing the same/similar kernel
DEVICEFAMILY="nanopi-a"
# tarball from DEVICEFAMILY repo to use
#DEVICEBASE=${DEVICE} # Defaults to ${DEVICE} if unset
DEVICEREPO="https://github.com/volumio/platform-${DEVICEFAMILY}"
DEVICEREPO_BRANCH="master" # Branch to use for the device repo or empty for main

### What features do we want to target
# TODO: Not fully implement
VOLVARIANT=no # Custom Volumio (Motivo/Primo etc)
MYVOLUMIO=no
VOLINITUPDATER=yes
DISABLE_DISPLAY=yes

## Partition info
BOOT_START=17
BOOT_END=273
IMAGE_END=3985           # BOOT_END + 3712 MiB (/img squashfs)
BOOT_TYPE=msdos          # msdos or gpt
BOOT_USE_UUID=yes        # Add UUID to fstab
INIT_TYPE="initv3"

# Modules that will be added to intramsfs
MODULES=("fuse" "nls_cp437" "nls_iso8859_1" "overlay" "overlayfs" "squashfs")
# Packages that will be installed
PACKAGES=("abootimg" "bluetooth" "bluez" "bluez-firmware" "bluez-tools" "device-tree-compiler" "fbset" "linux-base" "lirc" "mc" "triggerhappy")

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
  dd if="${PLTDIR}/${DEVICE}/u-boot/u-boot-sunxi-with-spl.bin" of="${LOOP_DEV}" bs=1024 seek=8 conv=notrunc
}

# Will be called by the image builder for any customisation
device_image_tweaks() {
	# log "Performing device_image_tweaks" "ext"
  :
}

# Will be run in chroot - Pre initramfs
device_chroot_tweaks_pre() {
  log "Performing device_chroot_tweaks_pre" "ext"

  log "Fixing armv8 deprecated instruction emulation with armv7 rootfs"
  cat <<-EOF >>/etc/sysctl.conf
abi.cp15_barrier=2
EOF

  log "Creating boot parameters from template"
  sed -i "s/rootdev=UUID=/rootdev=UUID=${UUID_BOOT}/g" /boot/armbianEnv.txt
  sed -i "s/imgpart=UUID=/imgpart=UUID=${UUID_IMG}/g" /boot/armbianEnv.txt
  sed -i "s/bootpart=UUID=/bootpart=UUID=${UUID_BOOT}/g" /boot/armbianEnv.txt
  sed -i "s/datapart=UUID=/datapart=UUID=${UUID_DATA}/g" /boot/armbianEnv.txt

  log "Adding gpio group and udev rules"
  groupadd -f --system gpio
  usermod -aG gpio volumio
  # Works with newer kernels as well
  cat <<-EOF >/etc/udev/rules.d/99-gpio.rules
	SUBSYSTEM=="gpio*", PROGRAM="/bin/sh -c 'find -L /sys/class/gpio/ -maxdepth 2 -exec chown root:gpio {} \; -exec chmod 770 {} \; || true'"
	EOF
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
    log "Creating boot.scr"
    mkimage -A arm -T script -C none -d "${ROOTFSMNT}"/boot/boot.cmd "${ROOTFSMNT}"/boot/boot.scr
  fi
}

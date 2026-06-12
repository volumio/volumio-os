#!/usr/bin/env bash
# shellcheck disable=SC2034

### Setup for <OEM_PI> device
DEVICE_SUPPORT_TYPE="S" # First letter (Community Porting|Supported Officially|OEM)
DEVICE_STATUS="M"       # First letter (Planned|Test|Maintenance)

# Import the base family configuration
# shellcheck source=./recipes/devices/pi.sh
source "${SRC}"/recipes/devices/pi.sh

# Enable kiosk
KIOSKMODE=yes
KIOSKBROWSER=chromium

## Partition info (same as pi.sh)
BOOT_START=1
BOOT_END=385           # 384 MiB boot partition, aligned
IMAGE_END=4673         # BOOT_END + 4288 MiB (/img squashfs)

# =========================================================================
# KERNEL SLIMMING — keep only Pi 3 (v7+) and Pi 5 (v8+)
# pi-kiosk is used exclusively by Orchard (PecanPi), which ships Pi 3 and
# Pi 5 boards only. Devices in the field were flashed with Volumio 3.x and
# cannot be repartitioned by OTA: the full Pi kernel set does not fit the
# 3.x partition layout. Slimming here shrinks both OTA artifacts:
# kernel_current.tar (/boot content, must fit the 3.x boot partition) and
# the squashfs (/lib/modules).
# =========================================================================

# Keep a reference to the stock Pi post-tweaks (plymouth services,
# raspi-config blocker) so we can extend it without duplicating it.
eval "$(declare -f device_image_tweaks_post | sed 's/^device_image_tweaks_post/pi_device_image_tweaks_post/')"

# Will be called by the image builder post the chroot, before finalisation
device_image_tweaks_post() {
	pi_device_image_tweaks_post

	# Runs after all chroot tweaks and before squashfs/kernel_current.tar
	# creation, so everything removed here never reaches the OTA payload.
	log "pi-kiosk: slimming kernel set down to Pi3 (v7+) and Pi5 (v8+)" "info"

	# Kernel module directories: keep only -v7+ and -v8+
	for kdir in "${ROOTFSMNT}"/lib/modules/*; do
		[[ ! -d "$kdir" ]] && continue
		kbase=$(basename "$kdir")
		case "$kbase" in
		*-v7+ | *-v8+) ;; # keep: Pi3 (32bit userland) and Pi5 (64bit kernel)
		*)
			log "pi-kiosk: removing kernel modules ${kbase}" "info"
			rm -rf "$kdir"
			;;
		esac
	done

	# Kernel images: keep kernel7.img (Pi3) and kernel8.img (Pi5)
	log "pi-kiosk: removing unneeded kernel images" "info"
	rm -f "${ROOTFSMNT}"/boot/kernel.img   # Pi 0/1
	rm -f "${ROOTFSMNT}"/boot/kernel7l.img # Pi 4/400/CM4

	# Device trees: keep Pi3 (bcm2710-rpi-3-*) and Pi5 (bcm2712*-rpi-5-*)
	log "pi-kiosk: trimming device trees" "info"
	for dtb in "${ROOTFSMNT}"/boot/*.dtb; do
		[[ ! -f "$dtb" ]] && continue
		dtbase=$(basename "$dtb")
		case "$dtbase" in
		bcm2710-rpi-3-*.dtb | bcm2712*-rpi-5-*.dtb) ;; # keep
		*)
			rm -f "$dtb"
			;;
		esac
	done

	# Pi4-only EEPROM bootloader images (Pi5 uses bootloader-2712)
	log "pi-kiosk: removing Pi4 bootloader firmware" "info"
	rm -rf "${ROOTFSMNT}"/lib/firmware/raspberrypi/bootloader-2711

	log "pi-kiosk kernel slimming done" "okay" "$(du -sh "${ROOTFSMNT}"/boot | cut -f1) in /boot"
}

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
# KERNEL SLIMMING — keep the boards pi-kiosk actually ships on:
# Pi 3 (v7+), CM4/Pi4 (v8+, BCM2711) and Pi 5 (v8+). Custom DTB and GPU firmware MUST be kept for CM4/Pi4 (bcm2711) and Pi5 (bcm2712).
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
		*-v7+ | *-v8+) ;; # keep: Pi3 (v7+), CM4/Pi5 (v8+, 64-bit kernel)
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

	# Device trees: keep Pi3 (bcm2710-rpi-3-*), CM4/Pi4 (bcm2711-*) and Pi5 (bcm2712*-rpi-5-*)
	log "pi-kiosk: trimming device trees" "info"
	for dtb in "${ROOTFSMNT}"/boot/*.dtb; do
		[[ ! -f "$dtb" ]] && continue
		dtbase=$(basename "$dtb")
		case "$dtbase" in
		bcm2710-rpi-3-*.dtb | bcm2711-*.dtb | bcm2712*-rpi-5-*.dtb) ;; # keep (bcm2711 = CM4/Pi4)
		*)
			rm -f "$dtb"
			;;
		esac
	done

	# KEEP start4*.elf / fixup4*.dat — this IS the GPU firmware for CM4/Pi4
	# (BCM2711).
	# removing it leaves the device     with no GPU firmware -> black screen + no audio.

	# KEEP bootloader-2711 — required for CM4 (BCM2711) EEPROM updates.

	log "pi-kiosk kernel slimming done" "okay" "$(du -sh "${ROOTFSMNT}"/boot | cut -f1) in /boot"
}

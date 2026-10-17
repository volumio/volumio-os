#!/usr/bin/env bash
# shellcheck disable=SC2034

### Setup for pi-kiosk device
DEVICE_SUPPORT_TYPE="S" # First letter (Community Porting|Supported Officially|OEM)
DEVICE_STATUS="M"       # First letter (Planned|Test|Maintenance)

# Import the base family configuration
# shellcheck source=./recipes/devices/pi.sh
source "${SRC}"/recipes/devices/pi.sh

# Enable kiosk
KIOSKMODE=yes
KIOSKBROWSER=vivaldi

## Partition info (same as pi.sh)
BOOT_START=1
BOOT_END=385           # 384 MiB boot partition, aligned
IMAGE_END=4673         # BOOT_END + 4288 MiB (/img squashfs)

# =========================================================================
# BOOT SLIMMING — pi-kiosk is compatible with Pi 5 and CM5 only.
#
# Both are BCM2712, which has no 32-bit kernel at all, so the image keeps one
# kernel flavour (v8+ / kernel8.img) and one device tree family (bcm2712*).
# arm_64bit is deliberately left alone: the firmware on this SoC ignores it,
# and pi.sh's seed of 0 is what the shipping Pi 5 image already boots with.
#
# A Volumio 3 unit keeps its 95 MiB boot partition across an OTA, so every
# file dropped here is headroom for that upgrade.
# =========================================================================

# Keep a reference to the stock Pi post-tweaks (plymouth services,
# raspi-config blocker) so we can extend it without duplicating it.
eval "$(declare -f device_image_tweaks_post | sed 's/^device_image_tweaks_post/pi_device_image_tweaks_post/')"

# Will be called by the image builder post the chroot, before finalisation
device_image_tweaks_post() {
	pi_device_image_tweaks_post

	# Runs after all chroot tweaks and before squashfs/kernel_current.tar
	# creation, so everything removed here never reaches the OTA payload.
	log "pi-kiosk: slimming the boot set down to Pi 5 / CM5 (v8+)" "info"

	# Kernel module directories: keep only -v8+
	for kdir in "${ROOTFSMNT}"/lib/modules/*; do
		[[ ! -d "$kdir" ]] && continue
		kbase=$(basename "$kdir")
		case "$kbase" in
		*-v8+) ;; # keep: Pi 5 / CM5 (64-bit kernel)
		*)
			log "pi-kiosk: removing kernel modules ${kbase}" "info"
			rm -rf "$kdir"
			;;
		esac
	done

	# Kernel images: keep kernel8.img. pi.sh already drops kernel_2712.img,
	# the 16 KB-page image BCM2712 would otherwise prefer, and kernel8.img is
	# the fallback it then loads.
	log "pi-kiosk: removing unneeded kernel images" "info"
	rm -f "${ROOTFSMNT}"/boot/kernel.img   # Pi 0/1
	rm -f "${ROOTFSMNT}"/boot/kernel7.img  # Pi 2/3
	rm -f "${ROOTFSMNT}"/boot/kernel7l.img # Pi 4/400/CM4

	# Device trees: keep every BCM2712 board, which covers Pi 5 and both CM5
	# carriers.
	log "pi-kiosk: trimming device trees" "info"
	for dtb in "${ROOTFSMNT}"/boot/*.dtb; do
		[[ ! -f "$dtb" ]] && continue
		dtbase=$(basename "$dtb")
		case "$dtbase" in
		bcm2712*.dtb) ;; # keep: Pi 5, CM5
		*)
			rm -f "$dtb"
			;;
		esac
	done

	# GPU firmware: BCM2712 loads the kernel from its own EEPROM and reads
	# none of start*.elf, fixup*.dat or bootcode.bin. Those files exist for
	# Pi 0-4, which this image no longer boots, and they are the largest
	# thing in /boot.
	log "pi-kiosk: removing GPU firmware no BCM2712 board reads" "info"
	rm -f "${ROOTFSMNT}"/boot/bootcode.bin
	rm -f "${ROOTFSMNT}"/boot/start*.elf
	rm -f "${ROOTFSMNT}"/boot/fixup*.dat

	# EEPROM images for the BCM2711 bootloader, which only a CM4 flashes.
	rm -rf "${ROOTFSMNT}"/boot/bootloader-2711

	log "pi-kiosk boot slimming done" "okay" "$(du -sh "${ROOTFSMNT}"/boot | cut -f1) in /boot"
}

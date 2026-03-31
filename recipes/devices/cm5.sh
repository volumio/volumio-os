#!/usr/bin/env bash
# shellcheck disable=SC2034

## Setup for Raspberry Pi
DEVICE_SUPPORT_TYPE="O" # First letter (Community Porting|Supported Officially|OEM)
DEVICE_STATUS="T"       # First letter (Planned|Test|Maintenance)

# Base system
BASE="Raspbian"
ARCH="armhf"
BUILD="arm"

### Build image with initramfs debug info?
DEBUG_IMAGE="no" # yes/no or empty. Also changes SHOW_SPLASH in cmdline.txt

### Device information
# Used to identify devices (VOLUMIO_HARDWARE) and keep backward compatibility
#VOL_DEVICE_ID="pi"
DEVICENAME="CM5"
# This is useful for multiple devices sharing the same/similar kernel
#DEVICEFAMILY="raspberry"

# Install to disk tools including PiInstaller
#DEVICEREPO="https://github.com/volumio/platform-${DEVICEFAMILY}.git"

### What features do we want to target
# TODO: Not fully implemented
VOLVARIANT=no # Custom Volumio (Motivo/Primo etc)
MYVOLUMIO=no
VOLINITUPDATER=yes
KIOSKMODE=yes
KIOSKBROWSER=vivaldi

## Partition info
BOOT_START=1
BOOT_END=385           # 384 MiB boot partition, aligned
IMAGE_END=4673         # BOOT_END + 4288 MiB (/img squashfs)
BOOT_TYPE=msdos        # Keep msdos for Pi SD boot
BOOT_USE_UUID=yes      # Use UUIDs in fstab for /boot mount
INIT_TYPE="initv3"     # Volumio init type
INIT_UUID_TYPE="pi"    # Use block device GPEN or PARTUUID fallback

## Plymouth theme management
PLYMOUTH_THEME="volumio-adaptive"		# Choices are: {volumio-player, volumio-text, volumio-adaptive}
INIT_PLYMOUTH_DISABLE="no"		# yes/no or empty. Removes plymouth initialization in init if "yes" is selected
UPDATE_PLYMOUTH_SERVICES_FOR_KMS_DRM="no"		# yes/no or empty. Replaces default plymouth systemd services if "yes" is selected

# Modules that will be added to initramfs
MODULES=(
  # Core filesystem and storage modules
  "fuse" 
  "nls_iso8859_1" 
  "nvme" 
  "nvme_core" 
  "overlay" 
  "squashfs" 
  "uas"  
  # ALSA sound subsystem - required for vc4/HDMI audio during boot
  # Base ALSA module - must load before any other sound modules
  "snd"
  # ALSA timer and PCM support
  "snd-timer"
  "snd-pcm"
  "snd-pcm-dmaengine"
  "snd-compress"
  # ASoC core - required by vc4 for HDMI audio
  "snd-soc-core"
  # Audio codecs - Pi hardware audio support
  # HDMI audio codec - all Pi models with HDMI
  "snd-soc-hdmi-codec"
  # I2S audio interface - all Pi models
  "snd-soc-bcm2835-i2s"
  # I2C and SPI controllers - required for display panel communication
  # I2C controller for Pi 0-4
  "i2c-bcm2835"
  # I2C controller for Pi 5
  "i2c-brcmstb"
  # SPI controller - all Pi models
  "spi-bcm2835"
  # Pi 5 RP1 I/O controller - must load before RP1 peripherals
  # RP1 firmware base
  "rp1-fw"
  # RP1 mailbox interface
  "rp1-mailbox"
  # RP1 PIO support
  "rp1-pio"
  # PWM controller - required for DSI panel backlight
  "pwm-bcm2835"
  # Display infrastructure - required for Plymouth splash
  # Backlight control for display panels
  "backlight"
  # Panel orientation detection
  "drm_panel_orientation_quirks"
  # DRM/KMS foundation - required for Plymouth graphical boot
  "drm" 
  "drm_kms_helper"
  # Display helper for vc4
  "drm_display_helper"
  # DMA helper for vc4
  "drm_dma_helper"
  # HDMI CEC support
  "cec"
  # VideoCore IV GPU driver - Pi 0-4
  "vc4"
  # DSI display panels - touchscreen support during boot
  # Official Pi 7" touchscreen
  "panel-raspberrypi-touchscreen"
  # Official Pi Touch Display 2
  "panel-ilitek-ili9881c"
  # Waveshare DSI displays
  "panel-waveshare-dsi"
  "panel-waveshare-dsi-v2"
  # SPI/FBTFT displays - legacy framebuffer support
  "fbtft"
  "fb_ili9340" 
  "fb_ili9341"
  "fb_ili9488"
  "fb_st7735r" 
  "fb_st7789v"
  "fb_hx8357d"
  # Touch controller drivers
  "goodix"
  "ads7846"
)

# Packages that will be installed
PACKAGES=( # Bluetooth packages
	"bluez" "bluez-firmware" "pi-bluetooth"
	# Foundation stuff
	"raspberrypi-sys-mods"
	# Framebuffer stuff
	"fbset"	
	# "rpi-eeprom"\ Needs raspberrypi-bootloader that we hold back
	# GPIO stuff
	# "wiringpi" # --> Not in repo, grabbing from github release
)

#Pi Specific
RpiRepo="https://github.com/raspberrypi/rpi-firmware"
RpiUpdateRepo="raspberrypi/rpi-update"
## We ended with 10 versions od 6.12.34 kernels from master branch.
## Using older branch to avoid boot failures
RpiUpdateBranch="master"
# RpiUpdateBranch="1dd909e2c8c2bae7adb3eff3aed73c3a6062e8c8"

declare -A PI_KERNELS=(
	#[KERNEL_VERSION]="SHA|Branch|Rev"
	[6.6.62]="9a9bda382acec723c901e5ae7c7f415d9afbf635|master|1816"
	[6.12.47]="6d1da66a7b1358c9cd324286239f37203b7ce25c|master|1904"
	[6.12.74]="7a35bddc777d8992bdfe42f8e3d043582df2f5f8|master|1948"
	[6.12.75]="98655d3ccedba33aeadd0e550229f1496c5bf6f9|master|1949"
)
# Version we want
KERNEL_VERSION="6.12.75"

### Device customisation
# Copy the device specific files (Image/DTS/etc..)
write_device_files() {
	:
}

write_device_bootloader() {
	#TODO: Look into moving bootloader stuff here
	:
}

# Will be called by the image builder for any customisation
device_image_tweaks() {
	# log "Custom dtoverlay pre and post" "ext"
	# mkdir -p "${ROOTFSMNT}/opt/vc/bin/"
	# cp -rp "${SRC}"/volumio/opt/vc/bin/* "${ROOTFSMNT}/opt/vc/bin/"

	log "Fixing hostapd.conf" "info"
	cat <<-EOF >"${ROOTFSMNT}/etc/hostapd/hostapd.conf"
		interface=wlan0
		driver=nl80211
		channel=4
		hw_mode=g
		wmm_enabled=0
		macaddr_acl=0
		ignore_broadcast_ssid=0
		# Auth
		auth_algs=1
		wpa=2
		wpa_key_mgmt=WPA-PSK
		rsn_pairwise=CCMP
		# Volumio specific
		ssid=Volumio
		wpa_passphrase=volumio2
	EOF

	log "Adding archive.raspberrypi debian repo" "info"
	cat <<-EOF >"${ROOTFSMNT}/etc/apt/sources.list.d/raspi.list"
		deb http://archive.raspberrypi.com/debian/ ${SUITE} main
		# Uncomment line below then 'apt-get update' to enable 'apt-get source'
		#deb-src http://archive.raspberrypi.com/debian/ ${SUITE} main
		# https://github.com/volumio/volumio-os/issues/45 - mesa libs unmet dependencies
		deb http://archive.raspberrypi.com/debian/ ${SUITE} untested

	EOF

	# raspberrypi-{kernel,bootloader} packages update kernel & firmware files
	# and break Volumio. Installation may be triggered by manual or
	# plugin installs explicitly or through dependencies like
	# chromium, sense-hat, picamera,...
	# Using Pin-Priority < 0 prevents installation
	log "Blocking raspberrypi-bootloader and raspberrypi-kernel" "info"
	cat <<-EOF >"${ROOTFSMNT}/etc/apt/preferences.d/raspberrypi-kernel"
		Package: raspberrypi-bootloader
		Pin: release *
		Pin-Priority: -1

		Package: raspberrypi-kernel
		Pin: release *
		Pin-Priority: -1

		Package: libraspberrypi0
		Pin: release *
		Pin-Priority: -1
	EOF

	log "Fetching rpi-update" "info"
	curl -L --output "${ROOTFSMNT}/usr/bin/rpi-update" "https://raw.githubusercontent.com/${RpiUpdateRepo}/${RpiUpdateBranch}/rpi-update" &&
		chmod +x "${ROOTFSMNT}/usr/bin/rpi-update"

	log "Installing raspi-config blocker (Volumio OS does not support raspi-config)" "info"
	cp "${SRC}/volumio/bin/raspi-config-disabled" "${ROOTFSMNT}/usr/bin/raspi-config"
	chmod +x "${ROOTFSMNT}/usr/bin/raspi-config"

	# ============================================================================
	# RPI-UPDATE BUG FIX
	# ============================================================================
	# PROBLEM: rpi-update has a bug in its module filtering logic.
	# The script uses: VERSION=$(echo $BASEDIR | cut -sd "-" -f2)
	# This extracts ONLY field 2 when splitting by "-":
	#   6.12.47-v8+      -> VERSION="v8+"     (correct)
	#   6.12.47-v8-16k+  -> VERSION="v8"      (WRONG! should be "v8-16k")
	#   6.12.47-v8-rt+   -> VERSION="v8"      (WRONG! should be "v8-rt")
	#
	# RESULT: WANT_16K=0 and WANT_64BIT_RT=0 flags are ignored because the
	# filter never sees "v8-16k+" or "v8-rt+", only "v8".
	#
	# DECISION: Patch rpi-update before execution to fix the extraction logic.
	# This ensures filtering works correctly at the source, reducing unnecessary
	# downloads and filesystem operations.
	# ============================================================================
	log "Patching rpi-update to fix module filtering bug" "info"
	sed -i 's/VERSION=$(echo $BASEDIR | cut -sd "-" -f2)/VERSION=$(echo $BASEDIR | cut -sd "+" -f1 | cut -sd "-" -f2-)/' "${ROOTFSMNT}/usr/bin/rpi-update"
	# NEW LOGIC: Extract everything between first "-" and the "+"
	#   6.12.47-v8+      -> VERSION="v8"
	#   6.12.47-v8-16k+  -> VERSION="v8-16k"
	#   6.12.47-v8-rt+   -> VERSION="v8-rt"
	# Now the filtering logic will correctly identify and skip unwanted variants.

	# For bleeding edge, check what is the latest on offer
	# Things *might* break, so you are warned!
	if [[ ${RPI_USE_LATEST_KERNEL:-no} == yes ]]; then
		branch=master
		log "Using bleeding edge Rpi kernel" "info" "$branch"
		RpiRepoApi=${RpiRepo/github.com/api.github.com\/repos}
		RpiRepoRaw=${RpiRepo/github.com/raw.githubusercontent.com}
		log "Fetching latest kernel details from ${RpiRepo}" "info"
		RpiGitSHA=$(curl --silent "${RpiRepoApi}/branches/${branch}")
		readarray -t RpiCommitDetails <<<"$(jq -r '.commit.sha, .commit.commit.message' <<<"${RpiGitSHA}")"
		log "Rpi latest kernel -- ${RpiCommitDetails[*]}" "info"
		# Parse required info from `uname_string`
		uname_string=$(curl --silent "${RpiRepoRaw}/${RpiCommitDetails[0]}/uname_string")
		RpiKerVer=$(awk '{print $3}' <<<"${uname_string}")
		KERNEL_VERSION=${RpiKerVer/+/}
		RpiKerRev=$(awk '{print $1}' <<<"${uname_string##*#}")
		PI_KERNELS[${KERNEL_VERSION}]+="${RpiCommitDetails[0]}|${branch}|${RpiKerRev}"
		# Make life easier
		log "Using rpi-update SHA:${RpiCommitDetails[0]} Rev:${RpiKerRev}" "${KERNEL_VERSION}" "dbg"
		log "[${KERNEL_VERSION}]=\"${RpiCommitDetails[0]}|${branch}|${RpiKerRev}\"" "dbg"
	fi

	### Kernel installation
	IFS=\| read -r KERNEL_COMMIT KERNEL_BRANCH KERNEL_REV <<<"${PI_KERNELS[$KERNEL_VERSION]}"

	# using rpi-update to fetch and install kernel and firmware
	log "Adding kernel ${KERNEL_VERSION} using rpi-update" "info"
	log "Fetching SHA: ${KERNEL_COMMIT} from branch: ${KERNEL_BRANCH}" "info"

	# ============================================================================
	# RPI-UPDATE FLAGS CONFIGURATION
	# ============================================================================
	# TARGET: CM5 needs ONLY one kernel variant:
	#   1. kernel8.img with -v8+ modules (64-bit, standard 4KB pages)
	#
	# BACKGROUND: CM5 uses the same BCM2712 SoC as Pi 5. The 32-bit kernel
	# (v7l+) does NOT work on BCM2712. On the standard pi image, when used
	# on CM5, the v8+ kernel is selected. We are not using the 16KB page
	# kernel (v8-16k+ / kernel_2712.img) at this time - sticking with the
	# proven v8+ configuration.
	#
	# FLAG DECISIONS:
	#   WANT_32BIT=0      - 32-bit kernel does not work on BCM2712
	#   WANT_64BIT=1      - Required for v8+ modules (standard 64-bit)
	#   WANT_64BIT_RT=0   - Exclude realtime kernels (not needed)
	#   WANT_16K=0        - Exclude 16KB page kernel (not using large pages yet)
	#   WANT_PI2=0        - Exclude Pi 2 firmware (not CM5 hardware)
	#   WANT_PI4=0        - Exclude Pi 4 firmware (not CM5 hardware)
	#   WANT_PI5=1        - Enable Pi 5/CM5 firmware, device trees, and DTBs
	# ============================================================================
	RpiUpdate_args=(
		"UPDATE_SELF=0"
		"ROOT_PATH=${ROOTFSMNT}"
		"BOOT_PATH=${ROOTFSMNT}/boot"
		"SKIP_WARNING=1"
		"SKIP_BACKUP=1"
		"SKIP_CHECK_PARTITION=1"
		"WANT_32BIT=0"      # EXCLUDE 32-bit (does not work on BCM2712)
		"WANT_64BIT=1"      # Install standard 64-bit kernel (v8+)
		"WANT_64BIT_RT=0"   # EXCLUDE realtime kernel (v8-rt+)
		"WANT_16K=0"        # EXCLUDE 16KB page kernel (not using large pages yet)
		"WANT_PI2=0"        # EXCLUDE Pi 2 support
		"WANT_PI4=0"        # EXCLUDE Pi 4 support
		"WANT_PI5=1"        # Enable Pi 5/CM5 firmware and device trees
	)
	env "${RpiUpdate_args[@]}" "${ROOTFSMNT}"/usr/bin/rpi-update "${KERNEL_COMMIT}"
}

# Will be run in chroot (before other things)
device_chroot_tweaks() {
	log "Running device_image_tweaks" "ext"
}

# Will be run in chroot - Pre initramfs
# TODO Try and streamline this!
device_chroot_tweaks_pre() {
	# !Warning!
	# This will break proper plymouth on DSI screens at boot time.
	# initramfs plymouth hook will not copy drm gpu drivers for list!.
	# log "Changing initramfs module config to 'modules=list' to limit volumio.initrd size" "cfg"
	# sed -i "s/MODULES=most/MODULES=list/g" /etc/initramfs-tools/initramfs.conf

	## Define parameters

	## Reconfirm our kernel version
	#shellcheck disable=SC2012 #We know it's going to be alphanumeric only!
	mapfile -t kver < <(ls -t /lib/modules | sort)
	log "Found ${#kver[@]} kernel version(s)" "${kver[*]}"
	ksemver=${kver[0]%%-*} && ksemver=${ksemver%%+*}
	[[ ${ksemver} != "${KERNEL_VERSION}" ]] && [[ ${RPI_USE_RPI_UPDATE} == yes ]] &&
		log "Installed kernel doesn't match requested version!" "wrn" "${ksemver} != ${KERNEL_VERSION}"
	KERNEL_VERSION=${ksemver}
	IFS=\. read -ra KERNEL_SEMVER <<<"${KERNEL_VERSION}"

	# List of custom firmware -
	# github archives that can be extracted directly
	declare -A CustomFirmware=(
		[vfirmware]="https://raw.githubusercontent.com/volumio/volumio3-os-static-assets/master/firmwares/bookworm/firmware-volumio.tar.gz"
		[PiCustom]="https://raw.githubusercontent.com/volumio/volumio-rpi-custom/main/output/modules-rpi-${KERNEL_VERSION}-custom.tar.gz"
		[RPiUserlandTools]="https://github.com/volumio/volumio3-os-static-assets/raw/master/tools/rpi-softfp-vc.tar.gz"
	)

	# Define the kernel version (already parsed earlier)

	# ============================================================================
	# POST-INSTALLATION CLEANUP - DEFENSE IN DEPTH
	# ============================================================================
	# RATIONALE: Even with the rpi-update patch above, we implement aggressive
	# cleanup as a safety net. This ensures that if:
	#   1. The patch fails to apply
	#   2. Future rpi-update versions change the filtering logic
	#   3. Modules are installed through other mechanisms
	# ...we still end up with ONLY the kernel variants we want.
	#
	# DECISION: Remove unwanted variants by pattern matching rather than
	# relying solely on rpi-update flags. This is more robust.
	# ============================================================================

	log "Post-installation cleanup: Removing unwanted kernel variants" "info"

	# ----------------------------------------------------------------------------
	# STEP 1: Remove unwanted kernel module directories (WHITELIST approach)
	# ----------------------------------------------------------------------------
	# DECISION: For CM5, use a whitelist - keep ONLY the single kernel variant
	# that CM5 hardware actually uses and remove everything else.
	# WHY: CM5 uses BCM2712 (same SoC as Pi 5). The 32-bit kernel does not
	# work on BCM2712. The proven working configuration is the standard v8+
	# kernel (64-bit, 4KB pages). We are not using the 16KB page kernel
	# (v8-16k+) at this time.
	#
	# KEEP:
	#   *-v8+   --> CM5 64-bit (standard 4KB pages, proven working)
	#
	# REMOVE (everything else):
	#   *+      --> ARMv6 base kernel (Pi 1/Zero/CM1 - not CM5 hardware)
	#   *-v7+   --> ARMv7 kernel (Pi 2/3/Zero2W - not CM5 hardware)
	#   *-v7l+  --> 32-bit kernel (does not work on BCM2712)
	#   *-v8-16k+ --> 16KB page kernel (not using large pages yet)
	#   *-rt+   --> Realtime kernels (not needed for Volumio)
	#   *+rpt-rpi-* --> Raspberry Pi OS package-managed kernels
	# ----------------------------------------------------------------------------
	for kdir in /lib/modules/*; do
		[[ ! -d "$kdir" ]] && continue
		kbase=$(basename "$kdir")

		# Whitelist: keep only CM5 64-bit kernel
		# Pattern anchored to end of string for precise matching
		# -v8+ does NOT match -v8-16k+ or -v8-rt+ (no extra suffix after v8)
		if [[ "$kbase" == *-v8+ ]]; then
			log "Keeping CM5 kernel modules: $kbase" "info"
			continue
		fi

		log "Removing non-CM5 kernel modules: $kbase" "info"
		rm -rf "$kdir"
	done

	# ----------------------------------------------------------------------------
	# STEP 2: Remove empty or incomplete module directories
	# ----------------------------------------------------------------------------
	# DECISION: A valid kernel module directory must contain modules.builtin file
	# WHY: Prevents boot failures from incomplete kernel installations
	# ----------------------------------------------------------------------------
	for kdir in /lib/modules/${KERNEL_VERSION}*; do
		if [[ -d "$kdir" && ! -f "$kdir/modules.builtin" ]]; then
			kbase=$(basename "$kdir")
			log "Removing incomplete kernel module directory: $kbase" "info"
			rm -rf "$kdir"
		fi
	done

	# ----------------------------------------------------------------------------
	# STEP 3: Remove unwanted kernel images from /boot (WHITELIST approach)
	# ----------------------------------------------------------------------------
	# DECISION: Keep only kernel8.img, remove all others.
	# CM5 (BCM2712) uses the standard 64-bit kernel (v8+, 4KB pages).
	# 32-bit kernels do not work on BCM2712. The 16KB page kernel
	# (kernel_2712.img) is not being used at this time.
	# ----------------------------------------------------------------------------

	log "Removing non-CM5 kernel images" "info"
	# Remove ARMv6 base kernel image
	# WHY: kernel.img is for Pi 1/Zero/CM1 (ARMv6) - does not work on BCM2712
	rm -f /boot/kernel.img          # ARMv6 Pi 1/Zero kernel

	# Remove Pi 2/3 kernel image
	# WHY: kernel7.img is for Pi 2/3 (ARMv7 v7+) - does not work on BCM2712
	rm -f /boot/kernel7.img         # ARMv7 Pi 2/3 kernel

	# Remove 32-bit kernel image
	# WHY: kernel7l.img is 32-bit (v7l+) - does not work on BCM2712
	rm -f /boot/kernel7l.img        # 32-bit kernel (not functional on CM5)

	# Remove Pi 5 16KB page kernel image
	# WHY: kernel_2712.img uses 16KB pages - not using large pages yet
	# NOTE: When large page support is needed, re-enable WANT_16K=1 and
	# update this whitelist to keep kernel_2712.img and -v8-16k+ modules
	rm -f /boot/kernel_2712.img     # Pi 5 16KB kernel (not using yet)
	rm -f /boot/kernel2712.img      # Alternate naming

	# Remove realtime kernel images if they exist
	# WHY: Corresponding to -v8-rt+ modules we don't want
	rm -f /boot/kernel8_rt.img      # 64-bit RT kernel
	rm -f /boot/kernel_rt.img       # Generic RT kernel naming
	rm -f /boot/kernel*-rt*.img     # Catch any RT variants

	log "Kernel cleanup completed" "okay"

	# ============================================================================
	# VERIFICATION CHECKPOINT - CM5 ONLY
	# ============================================================================
	# At this point, /lib/modules should contain ONLY:
	#   - {version}-v8+ (CM5 64-bit, standard 4KB pages)
	#
	# And /boot should contain ONLY this kernel image:
	#   - kernel8.img  (CM5 64-bit)
	#
	# NOT present (removed by whitelist cleanup):
	#   - Any + suffix directories or kernel.img (ARMv6)
	#   - Any -v7+ suffix directories or kernel7.img (Pi 2/3)
	#   - Any -v7l+ suffix directories or kernel7l.img (32-bit, not functional on BCM2712)
	#   - Any -v8-16k+ directories or kernel_2712.img (16KB pages, not using yet)
	#   - Any -v8-rt+ directories or kernel*_rt.img (realtime)
	#   - Any +rpt-rpi- directories (package-managed kernels)
	# ============================================================================
	log "Finished Kernel installation" "okay"

	### Other Rpi specific stuff
	## Lets update some packages from raspbian repos now
	log "Blocking nodejs upgrades for ${NODE_VERSION}" "info"
	cat <<-EOF >"${ROOTFSMNT}/etc/apt/preferences.d/nodejs"
		Package: nodejs
		Pin: release *
		Pin-Priority: -1
	EOF
	apt-get update && apt-get -y upgrade

	# https://github.com/volumio/volumio3-os/issues/174
	## Quick fix for dhcpcd in Raspbian vs Debian
	log "Raspbian vs Debian dhcpcd debug "
	apt-get remove dhcpcd -yy && apt-get autoremove

	wget -nv https://github.com/volumio/volumio3-os-static-assets/raw/master/custom-packages/dhcpcd/dhcpcd_9.4.1-24~deb12u4_all.deb
	wget -nv https://github.com/volumio/volumio3-os-static-assets/raw/master/custom-packages/dhcpcd/dhcpcd-base_9.4.1-24~deb12u4_armhf.deb
	dpkg -i dhcpcd*.deb && rm -rf dhcpcd*.deb

	log "Blocking dhcpcd upgrades for 9.4.1" "info"
	cat <<-EOF >"${ROOTFSMNT}/etc/apt/preferences.d/dhcpcd"
		Package: dhcpcd
		Pin: release *
		Pin-Priority: -1

		Package: dhcpcd-base
		Pin: release *
		Pin-Priority: -1
	EOF

	log "Installing WiringPi 3.10 package" "info"
	wget -nv https://github.com/WiringPi/WiringPi/releases/download/3.10/wiringpi_3.10_armhf.deb
	dpkg -i wiringpi_3.10_armhf.deb && rm wiringpi_3.10_armhf.deb

	log "Adding gpio & spi group and permissions" "info"
	groupadd -f --system gpio
	groupadd -f --system spi

	log "Disabling sshswitch" "info"
	rm /etc/sudoers.d/010_pi-nopasswd
	unlink /etc/systemd/system/multi-user.target.wants/sshswitch.service
	rm /lib/systemd/system/sshswitch.service

	log "Changing external ethX priority" "info"
	# As built-in eth _is_ on USB (smsc95xx or lan78xx drivers)
	sed -i 's/KERNEL==\"eth/DRIVERS!=\"smsc95xx\", DRIVERS!=\"lan78xx\", &/' /etc/udev/rules.d/99-Volumio-net.rules

	log "Adding volumio to gpio,i2c,spi group" "info"
	usermod -a -G gpio,i2c,spi,input volumio

	log "Handling Video Core quirks" "info"

	log "Adding /opt/vc/lib to linker" "info"
	cat <<-EOF >/etc/ld.so.conf.d/00-vmcs.conf
		/opt/vc/lib
	EOF

	log "Adding xorg configuration for kiosk mode with vc4-kms-v3d overlay" "info"
	mkdir -p /etc/X11/xorg.conf.d
	cat <<-EOF >/etc/X11/xorg.conf.d/99-vc4.conf
		Section "OutputClass"
			Identifier "vc4"
			MatchDriver "vc4"
			Driver "modesetting"
			Option "PrimaryGPU" "true"
		EndSection
	EOF

	log "Updating LD_LIBRARY_PATH" "info"
	ldconfig

	# libraspberrypi0 normally links this, so counter check and link if required
	if [[ ! -f /lib/ld-linux.so.3 ]] && [[ "$(dpkg --print-architecture)" = armhf ]]; then
		log "Linking /lib/ld-linux.so.3"
		ln -s /lib/ld-linux-armhf.so.3 /lib/ld-linux.so.3 2>/dev/null || true
		ln -s /lib/arm-linux-gnueabihf/ld-linux-armhf.so.3 /lib/arm-linux-gnueabihf/ld-linux.so.3 2>/dev/null || true
	fi

	log "Symlinking vc bins" "info"
	# Clean this up! > Quoting popcornmix "Code from here is no longer installed on latest RPiOS Bookworm images.If you are using code from here you should rethink your solution.Consider this repo closed."
	# https://github.com/RPi-Distro/firmware/blob/debian/debian/libraspberrypi-bin.links
	VC_BINS=("edidparser" "raspistill" "raspivid" "raspividyuv" "raspiyuv"
		"tvservice" "vcdbg" "vchiq_test"
		"dtoverlay-pre" "dtoverlay-post")

	for bin in "${VC_BINS[@]}"; do
		if [[ ! -f /usr/bin/${bin} && -f /opt/vc/bin/${bin} ]]; then
			ln -s "/opt/vc/bin/${bin}" "/usr/bin/${bin}"
			log "Linked ${bin}"
		else
			log "${bin} wasn't linked!" "wrn"
		fi
	done

	log "Fixing vcgencmd permissions" "info"
	cat <<-EOF >/etc/udev/rules.d/10-vchiq.rules
		SUBSYSTEM=="vchiq",GROUP="video",MODE="0660"
	EOF

	# All additional drivers
	log "Adding Custom firmware from github" "info"
	# TODO: There is gcc mismatch between Bookworm and rpi-firmware and as such in chroot environment ld-linux.so.3 is complaining when using drop-ship to /usr directly
		for key in "${!CustomFirmware[@]}"; do
		mkdir -p "/tmp/$key" && cd "/tmp/$key"
		wget -nv "${CustomFirmware[$key]}" -O "$key.tar.gz" || {
			log "Failed to get firmware:" "err" "${key}"
			rm "$key.tar.gz" && cd - && rm -rf "/tmp/$key"
			continue
		}
		tar --strip-components 1 --exclude "*.hash" --exclude "*.md" -xf "$key.tar.gz"
		rm "$key.tar.gz"
		if [[ -d boot ]]; then
			log "Updating /boot content" "info"
			cp -rp boot "${ROOTFS}"/ && rm -rf boot
		fi
		log "Adding $key update" "info"
		cp -rp * "${ROOTFS}"/usr && cd - && rm -rf "/tmp/$key"
	done

	# ============================================================================
	# FIRMWARE CLEANUP - CM5 SPECIFIC
	# ============================================================================
	# CONTEXT: /lib/firmware is populated by three sources:
	#   1. VolumioBase.conf [Firmware] - firmware-atheros, firmware-brcm80211,
	#      firmware-ralink, firmware-realtek, firmware-linux-free,
	#      firmware-misc-nonfree (all builds)
	#   2. arm.conf [RaspberryPi] - firmware-libertas, firmware-mediatek,
	#      firmware-marvell-prestera- (Pi/CM builds only)
	#   3. rpi-update - bootloader images in /lib/firmware/raspberrypi,
	#      plus brcm firmware additions
	#
	# PROBLEM: The combined result is ~181M of firmware, of which CM5 uses
	# only /lib/firmware/brcm (onboard WiFi/BT) at runtime. The rest is
	# pre-compiled binary data that compresses poorly under gzip, directly
	# inflating the squashfs image. See: https://github.com/volumio/volumio-os/issues/368
	#
	# APPROACH: Remove firmware for chipsets that are PCIe/platform-only and
	# physically cannot appear as USB peripherals on CM5 hardware.
	# Firmware for chipsets with USB variants is retained to support
	# user-attached USB WiFi/BT dongles.
	#
	# ALSO: Remove Pi 4/CM4 EEPROM bootloader images (BCM2711) - CM5 is BCM2712.
	# NOTE: /lib/firmware/cypress/ is kept - brcm/ has symlinks into it.
	# ============================================================================

	log "Firmware cleanup: removing unused firmware from /lib/firmware" "info"
	local fw_pre_size
	fw_pre_size=$(du -sm /lib/firmware 2>/dev/null | cut -f1)

	# Tier 1: PCIe/platform-only chipsets - no USB variants exist
	# These chipsets physically cannot be connected to CM5 via USB
	local -a FW_REMOVE_PCIE=(
		"ath11k"    # Qualcomm WiFi 6/6E - PCIe only (~43M)
		"ath10k"    # Qualcomm WiFi 5 - PCIe/SDIO only (~19M)
		"ath12k"    # Qualcomm WiFi 7 - PCIe only (~6M)
		"rtw89"     # Realtek WiFi 6 - PCIe only (~8M)
		"cxgb4"     # Chelsio 10/25GbE server NICs - PCIe only (~2M)
		"cnm"       # Chips&Media video codec IP - SoC only (~1M)
	)

	for fwdir in "${FW_REMOVE_PCIE[@]}"; do
		if [[ -d "/lib/firmware/${fwdir}" ]]; then
			log "Removing PCIe-only firmware: ${fwdir}" "info"
			rm -rf "/lib/firmware/${fwdir}"
		fi
	done

	# CM5-specific: remove Pi 4/CM4 EEPROM bootloader images (BCM2711)
	# CM5 is BCM2712 and uses bootloader-2712
	if [[ -d "/lib/firmware/raspberrypi/bootloader-2711" ]]; then
		log "Removing Pi 4/CM4 EEPROM bootloader images (BCM2711)" "info"
		rm -rf "/lib/firmware/raspberrypi/bootloader-2711"
	fi

	# NOTE: /lib/firmware/cypress/ is NOT removed here despite appearing unused.
	# Debian's firmware-brcm80211 creates symlinks from /lib/firmware/brcm/ into
	# cypress/ (e.g. brcmfmac43455-sdio.bin -> ../cypress/cyfmac43455-sdio.bin).
	# Removing cypress/ breaks WiFi. The directory is ~7M - not worth the
	# complexity of selective symlink resolution for that saving.

	local fw_post_size
	fw_post_size=$(du -sm /lib/firmware 2>/dev/null | cut -f1)
	log "Firmware cleanup completed" "okay" "${fw_pre_size}M -> ${fw_post_size}M"

	# Rename gpiomem in udev rules if kernel is equal or greater than 6.1.54
	if [[ "${KERNEL_SEMVER[0]}" -gt 6 ]] ||
		[[ "${KERNEL_SEMVER[0]}" -eq 6 && "${KERNEL_SEMVER[1]}" -gt 1 ]] ||
		[[ "${KERNEL_SEMVER[0]}" -eq 6 && "${KERNEL_SEMVER[1]}" -eq 1 && "${KERNEL_SEMVER[2]}" -ge 54 ]]; then
		log "Rename gpiomem in udev rules" "info"
		sed -i 's/bcm2835-gpiomem/gpiomem/g' /etc/udev/rules.d/99-com.rules
	fi

	log "Setting bootparms and modules" "info"
	log "Enabling i2c-dev module" "info"
	echo "i2c-dev" >>/etc/modules

	log "Writing config.txt file" "info"
	cat <<-EOF >/boot/config.txt
		### DO NOT EDIT THIS FILE ###
		### APPLY CUSTOM PARAMETERS TO userconfig.txt ###
		initramfs volumio.initrd
		dtparam=ant2
		dtparam=i2c=on
		dtparam=i2c_arm=on
		dtparam=uart0=on
		dtparam=uart1=off
		dtparam=audio=off
		dtparam=nvme
		dtparam=pciex1_gen=2
		arm_64bit=1
		gpu_mem=256
		enable_uart=1
		max_framebuffers=2
		hdmi_force_hotplug=1
		display_auto_detect=1
		disable_splash=1
		disable_overscan=1
		max_usb_current=1
		usb_max_current_enable=1
		force_eeprom_read=0
		start_x=1
		include volumioconfig.txt
		include userconfig.txt
	EOF

	log "Writing volumioconfig.txt file" "info"
	cat <<-EOF >/boot/volumioconfig.txt
		### DO NOT EDIT THIS FILE ###
		### APPLY CUSTOM PARAMETERS TO userconfig.txt ###
		dtoverlay=dwc2,dr_mode=host
		dtoverlay=vc4-kms-v3d-pi5,cma-384
	EOF

	log "Writing cmdline.txt file" "info"

	# Build up the base parameters
	# Prepare kernel_params placeholder
	kernel_params=(
	)
	# Prepare Volumio splash, quiet, debug and loglevel.
	# In init, "splash" controls Volumio logo, but in debug mode it will still be present
	# In init, "quiet" had no influence (unused), but in init{v2,v3} it will prevent initrd console output
	# So, when debugging, remove it and update loglevel to value: 8
	if [[ $DEBUG_IMAGE == yes ]]; then
		log "Debug image: remove splash from cmdline.txt" "cfg"
		SHOW_SPLASH="nosplash" # Debug removed
		log "Debug image: remove quiet from cmdline.txt" "cfg"
		KERNEL_QUIET="" # Debug removed
		log "Debug image: change loglevel to value: 8, debug, break and kmsg in cmdline.txt" "cfg"
		KERNEL_LOGLEVEL="loglevel=8 debug break= use_kmsg=yes" # Default Debug
	else
		log "Default image: add splash to cmdline.txt" "cfg"
		SHOW_SPLASH="splash" # Default splash enabled
		log "Default image: add quiet to cmdline.txt" "cfg"
		KERNEL_QUIET="quiet" # Default quiet enabled
		log "Default image: change loglevel to value: 0, nodebug, no break  and no kmsg in cmdline.txt" "cfg"
		KERNEL_LOGLEVEL="loglevel=0 nodebug use_kmsg=no" # Default to KERN_EMERG
	fi
	# Show splash
	kernel_params+=("${SHOW_SPLASH}")
	# Boot screen stuff
	kernel_params+=("plymouth.ignore-serial-consoles")
	# Raspi USB controller params
	# TODO: Check if still required!
	# Prevent Preempt-RT lock up
	kernel_params+=("dwc_otg.fiq_enable=1" "dwc_otg.fiq_fsm_enable=1" "dwc_otg.fiq_fsm_mask=0xF" "dwc_otg.nak_holdoff=1")
	# Hide kernel's stdio
	kernel_params+=("${KERNEL_QUIET}")
	# Output console device and options.
	kernel_params+=("console=serial0,115200" "console=tty1")
	# Image params
	kernel_params+=("imgpart=UUID=${UUID_IMG} imgfile=/volumio_current.sqsh bootpart=UUID=${UUID_BOOT} datapart=UUID=${UUID_DATA} uuidconfig=cmdline.txt")
	# Wait for root device
	kernel_params+=("rootwait" "bootdelay=7")
	# Disable linux logo during boot
	kernel_params+=("logo.nologo")
	# Disable cursor
	kernel_params+=("vt.global_cursor_default=0")

	# System OS tweaks
	DISABLE_PN="net.ifnames=0"
	kernel_params+=("${DISABLE_PN}")
	# ALSA tweaks
	kernel_params+=("snd-bcm2835.enable_compat_alsa=1")

	# Further debug changes
	if [[ $DEBUG_IMAGE == yes ]]; then
		log "Creating debug image" "dbg"
		log "Adding Serial Debug parameters" "dbg"
		echo "include debug.txt" >>/boot/config.txt
		cat <<-EOF >/boot/debug.txt
			# Enable serial console for boot debugging
			enable_uart=1
		EOF
		log "Enabling SSH" "dbg"
		touch /boot/ssh
		if [[ -f /boot/bootcode.bin ]]; then
			log "Enable serial boot debug" "dbg"
			sed -i -e "s/BOOT_UART=0/BOOT_UART=1/" /boot/bootcode.bin
		fi
	fi

	kernel_params+=("${KERNEL_LOGLEVEL}")
	log "Setting ${#kernel_params[@]} Kernel params:" "${kernel_params[*]}" "info"
	cat <<-EOF >/boot/cmdline.txt
		${kernel_params[@]}
	EOF

	log "Final cleanup: enforce CM5 kernel whitelist" "info"
	# WHY: CustomFirmware tarballs or apt-get upgrade may have introduced
	# additional kernel module directories after STEP 1 cleanup.
	# Re-apply the same whitelist to catch any late arrivals.
	# CM5 uses ONLY v8+ (64-bit, 4KB pages).
	for kdir in /lib/modules/*; do
		[[ ! -d "$kdir" ]] && continue
		kbase=$(basename "$kdir")
		if [[ "$kbase" == *-v8+ ]]; then
			continue
		fi
		log "Removing final-stage non-CM5 kernel modules: $kbase" "info"
		rm -rf "$kdir"
	done
	log "Raspi Kernel and Modules cleanup completed" "okay"

	log "Finalise all kernels with depmod and other tricks" "info"
	# https://www.raspberrypi.com/documentation/computers/linux_kernel.html
	# +         --> Pi 1,Zero,ZeroW, and CM 1 -- EXCLUDED (not BCM2712)
	# -v7+      --> Pi 2,3,3+,Zero 2W, CM3, and CM3+ -- EXCLUDED (not BCM2712)
	# -v7l+     --> Pi 4,400, CM 4 (32bit) -- EXCLUDED (32-bit does not work on BCM2712)
	# -v8+      --> Pi 3,3+,4,400,5, Zero 2W, CM 3,3+,4,5 (64bit) -- KEPT for CM5
	# -v8-16k+  --> Pi 5, CM 5 (64bit, 16KB pages) -- EXCLUDED (not using large pages yet)

	## Reconfirm our final kernel lists - we may have deleted a few!
	#shellcheck disable=SC2012 #We know it's going to be alphanumeric only!
	mapfile -t kver < <(ls -t /lib/modules | sort)
	for ver in "${kver[@]}"; do
		log "Running depmod on" "${ver}"
		depmod "${ver}"
		# Trick our non std kernel install with the right bits for intramfs creation
		cat <<-EOF >"/boot/config-${ver}"
			CONFIG_RD_ZSTD=y
			CONFIG_RD_GZIP=y
		EOF
	done
	log "Raspi Kernel and Modules installed" "okay"

}

# Will be run in chroot - Post initramfs
device_chroot_tweaks_post() {
	# log "Running device_chroot_tweaks_post" "ext"
	:
}

# Will be called by the image builder post the chroot, before finalisation
device_image_tweaks_post() {
	log "Running device_image_tweaks_post" "ext"
	# Plymouth systemd services OVERWRITE
	if [[ "${UPDATE_PLYMOUTH_SERVICES_FOR_KMS_DRM}" == yes ]]; then
		log "Updating plymouth systemd services" "info"
		cp -dR "${SRC}"/volumio/framebuffer/systemd/* "${ROOTFSMNT}"/lib/systemd
	fi

	log "Blocking raspi-config package (Volumio OS does not support raspi-config)" "info"
	cat <<-EOF >"${ROOTFSMNT}/etc/apt/preferences.d/raspi-config"
		Package: raspi-config
		Pin: release *
		Pin-Priority: -1
	EOF
}

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
DEVICENAME="CM4"
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
BOOT_END=257
IMAGE_END=3257
BOOT_TYPE=msdos   # msdos or gpt
BOOT_USE_UUID=yes # Add UUID to fstab
INIT_TYPE="initv3"
INIT_UUID_TYPE="pi" # Use block device GPEN if dynamic UUIDs are not handled.

## Plymouth theme management
PLYMOUTH_THEME="volumio-player"	# Choices are: {volumio,volumio-logo,volumio-player}

log "VARIANT is ${VARIANT}." "info"
## INIT_PLYMOUTH_DISABLE removes plymouth initialization in init if "yes" is selected
if [[ "${VARIANT}" == motivo ]]; then
	log "Building ${VARIANT}: Removing plymouth from init." "info"
	INIT_PLYMOUTH_DISABLE="yes"
else
	log "Using default plymouth initialization in init." "info"
	INIT_PLYMOUTH_DISABLE="no"
fi

## For any KMS DRM panel mudule, which does not create frambuffer bridge, set this variable to yes, otherwise no
## UPDATE_PLYMOUTH_SERVICES_FOR_KMS_DRM replaces default plymouth systemd services if "yes" is selected
if [[ "${VARIANT}" == motivo ]]; then
	log "Building ${VARIANT}: Replacing default plymouth systemd services" "info"
	UPDATE_PLYMOUTH_SERVICES_FOR_KMS_DRM="yes"
else
	log "Using packager default plymouth systemd services" "info"
	UPDATE_PLYMOUTH_SERVICES_FOR_KMS_DRM="no"
fi

# Modules that will be added to initramfs
MODULES=("drm" "fuse" "nls_cp437" "nls_iso8859_1" "nvme" "nvme_core" "overlay" "panel-dsi-mt" "panel-waveshare-dsi" "squashfs" "uas")
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
	[6.1.57]="12833d1bee03c4ac58dc4addf411944a189f1dfd|master|1688" # Support for Pi5
	[6.1.58]="7b859959a6642aff44acdfd957d6d66f6756021e|master|1690"
	[6.1.61]="d1ba55dafdbd33cfb938bca7ec325aafc1190596|master|1696"
	[6.1.64]="01145f0eb166cbc68dd2fe63740fac04d682133e|master|1702"
	[6.1.69]="ec8e8136d773de83e313aaf983e664079cce2815|master|1710"
	[6.1.70]="fc9319fda550a86dc6c23c12adda54a0f8163f22|master|1712"
	[6.1.77]="5fc4f643d2e9c5aa972828705a902d184527ae3f|master|1730"
	[6.6.30]="3b768c3f4d2b9a275fafdb53978f126d7ad72a1a|master|1763"
	[6.6.47]="a0d314ac077cda7cbacee1850e84a57af9919f94|master|1792"
	[6.6.51]="d5a7dbe77b71974b9abb133a4b5210a8070c9284|master|1796"
	[6.6.56]="a5efb544aeb14338b481c3bdc27f709e8ee3cf8c|master|1803"
	[6.6.62]="9a9bda382acec723c901e5ae7c7f415d9afbf635|master|1816"
	[6.12.27]="f54e67fef6e726725d3a8f56d232194497bd247c|master|1876"
	[6.12.34]="4f435f9e89a133baab3e2c9624b460af335bbe91|master|1889"
)
# Version we want
KERNEL_VERSION="6.12.34"

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
	RpiUpdate_args=("UPDATE_SELF=0" "ROOT_PATH=${ROOTFSMNT}" "BOOT_PATH=${ROOTFSMNT}/boot"
		"SKIP_WARNING=1" "SKIP_BACKUP=1" "SKIP_CHECK_PARTITION=1"
		"WANT_32BIT=1" "WANT_64BIT=1" "WANT_PI2=1" "WANT_PI4=1"
		"WANT_PI5=1" "WANT_16K=0" "WANT_64BIT_RT=0"
		# "BRANCH=${KERNEL_BRANCH}"
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
		[PiCustom]="https://raw.githubusercontent.com/Darmur/volumio-rpi-custom/main/output/modules-rpi-${KERNEL_VERSION}-custom.tar.gz"
		[MotivoCustom]="https://github.com/volumio/motivo-drivers/raw/main/output/modules-rpi-${KERNEL_VERSION}-motivo.tar.gz"
		[RPiUserlandTools]="https://github.com/volumio/volumio3-os-static-assets/raw/master/tools/rpi-softfp-vc.tar.gz"
	)

	# Define the kernel version (already parsed earlier)

	# Remove Pi5 16K kernel
	if [[ -d "/lib/modules/${KERNEL_VERSION}-v8-16k+" ]]; then
		log "Removing v8-16k+ (Pi5 16k) Kernel and modules" "info"
		rm -f /boot/kernel_2712.img
		rm -rf "/lib/modules/${KERNEL_VERSION}-v8-16k+"
	fi

	# Remove 64-bit realtime kernel
	if [[ -d "/lib/modules/${KERNEL_VERSION}-v8-rt+" ]]; then
		log "Removing v8-rt+ (64bit RT) Kernel and modules" "info"
		rm -f /boot/kernel_2712_rt.img
		rm -rf "/lib/modules/${KERNEL_VERSION}-v8-rt+"
	fi

	# Remove all unintended +rpt-rpi-* variants
	for kdir in /lib/modules/*; do
		kbase=$(basename "$kdir")
		if [[ "$kbase" == *+rpt-rpi-* ]]; then
			log "Removing stray kernel module folder: $kbase" "info"
			rm -rf "/lib/modules/$kbase"
		fi
	done

	# Optional: remove any empty module folders
	for kdir in /lib/modules/${KERNEL_VERSION}*; do
		if [[ -d "$kdir" && ! -f "$kdir/modules.builtin" ]]; then
			kbase=$(basename "$kdir")
			log "Removing empty kernel module folder: $kbase" "info"
			rm -rf "$kdir"
		fi
	done

	log "Finished Kernel installation" "okay"

	### Other Rpi specific stuff
	## Lets update some packages from raspbian repos now
	apt-get update && apt-get -y upgrade

	# https://github.com/volumio/volumio3-os/issues/174
	## Quick fix for dhcpcd in Raspbian vs Debian
	log "Raspbian vs Debian dhcpcd debug "
	apt-get remove dhcpcd -yy && apt-get autoremove
	# wget -nv http://ftp.debian.org/debian/pool/main/d/dhcpcd5/dhcpcd-base_9.4.1-24~deb12u4_armhf.deb
	# wget -nv http://ftp.debian.org/debian/pool/main/d/dhcpcd5/dhcpcd_9.4.1-24~deb12u4_all.deb
	wget -nv https://github.com/volumio/volumio3-os-static-assets/raw/master/custom-packages/dhcpcd/dhcpcd_9.4.1-24~deb12u4_all.deb
	wget -nv https://github.com/volumio/volumio3-os-static-assets/raw/master/custom-packages/dhcpcd/dhcpcd-base_9.4.1-24~deb12u4_armhf.deb
	dpkg -i dhcpcd*.deb && rm -rf dhcpcd*.deb

	log "Blocking dhcpcd upgrades for ${NODE_VERSION}" "info"
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

	NODE_VERSION=$(node --version)
	log "Node version installed:" "dbg" "${NODE_VERSION}"
	# drop the leading v
	NODE_VERSION=${NODE_VERSION:1}
	if [[ ${USE_NODE_ARMV6:-yes} == yes && ${NODE_VERSION%%.*} -ge 8 ]]; then
		log "Using a compatible nodejs version for all pi images" "info"
		# We don't know in advance what version is in the repo, so we have to hard code it.
		# This is temporary fix - make this smarter!
		declare -A NodeVersion=(
			[14]="https://repo.volumio.org/Volumio2/nodejs_14.15.4-1unofficial_armv6l.deb"
			[8]="https://repo.volumio.org/Volumio2/nodejs_8.17.0-1unofficial_armv6l.deb"
		)
		# TODO: Warn and proceed or exit the build?
		local arch=armv6l
		wget -nv "${NodeVersion[${NODE_VERSION%%.*}]}" -P /volumio/customNode || log "Failed fetching Nodejs for armv6!!" "wrn"
		# Proceed only if there is a deb to install
		if compgen -G "/volumio/customNode/nodejs_*-1unofficial_${arch}.deb" >/dev/null; then
			# Get rid of armv7 nodejs and pick up the armv6l version
			if dpkg -s nodejs &>/dev/null; then
				log "Removing previous nodejs installation from $(command -v node)" "info"
				log "Removing Node $(node --version) arm_version: $(node <<<'console.log(process.config.variables.arm_version)')" "info"
				apt-get -y purge nodejs
			fi
			log "Installing Node for ${arch}" "info"
			dpkg -i /volumio/customNode/nodejs_*-1unofficial_${arch}.deb
			log "Installed Node $(node --version) arm_version: $(node <<<'console.log(process.config.variables.arm_version)')" "info"
			rm -rf /volumio/customNode
		fi
		# Block upgrade of nodejs from raspi repos
		log "Blocking nodejs upgrades for ${NODE_VERSION}" "info"
		cat <<-EOF >"${ROOTFSMNT}/etc/apt/preferences.d/nodejs"
			Package: nodejs
			Pin: release *
			Pin-Priority: -1
		EOF
	fi

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
		gpu_mem=128
		dtparam=ant2
		max_framebuffers=1
		disable_splash=1
		force_eeprom_read=0
		dtparam=audio=off
		start_x=1
		include volumioconfig.txt
		include userconfig.txt
	EOF

	log "Writing volumioconfig.txt file" "info"
	cat <<-EOF >/boot/volumioconfig.txt
		### DO NOT EDIT THIS FILE ###
		### APPLY CUSTOM PARAMETERS TO userconfig.txt ###
		display_auto_detect=1
		enable_uart=1
		arm_64bit=1
		dtparam=uart0=on
		dtparam=uart1=off
		dtoverlay=dwc2,dr_mode=host
		otg_mode=1
		dtoverlay=vc4-kms-v3d,cma-384,audio=off,noaudio=on
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
	# A quirk of Linux on ARM that may result in suboptimal performance
	kernel_params+=("pcie_aspm=off" "pci=pcie_bus_safe")
	# Wait for root device
	kernel_params+=("rootwait" "bootdelay=7")
	# Disable linux logo during boot
	kernel_params+=("logo.nologo")
	# Disable cursor
	kernel_params+=("vt.global_cursor_default=0")

	# Buster tweaks
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

	log "Final cleanup: remove unintended +rpt-rpi-* kernel module folders" "info"
	for kdir in /lib/modules/*+rpt-rpi-*; do
		if [[ -d "$kdir" ]]; then
			kbase=$(basename "$kdir")
			log "Removing final-stage rpt-rpi kernel module folder:" "$kbase" "info"
			rm -rf "$kdir"
		fi
	done
	log "Raspi Kernel and Modules cleanup completed" "okay"

	log "Finalise all kernels with depmod and other tricks" "info"
	# https://www.raspberrypi.com/documentation/computers/linux_kernel.html
	# + 	--> Pi 1,Zero,ZeroW, and CM 1
	# -v7+  --> Pi 2,3,3+,Zero 2W, CM3, and CM3+
	# -v7l+ --> Pi 4,400, CM 4 (32bit)
	# -v8+  --> Pi 3,3+,4,400, Zero 2W, CM 3,3+,4 (64bit)

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
}

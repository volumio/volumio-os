#!/usr/bin/env bash
# shellcheck disable=SC2034
## Setup for x86 devices

# Base system
BASE="Debian"
ARCH="i386"
BUILD="x86"

### Build image with initramfs debug info?
DEBUG_IMAGE="no"
### Device information
DEVICENAME="x86_amd64"
# This is useful for multiple devices sharing the same/similar kernel
DEVICEFAMILY="x64"
# tarball from DEVICEFAMILY repo to use
#DEVICEBASE=${DEVICE} # Defaults to ${DEVICE} if unset
DEVICEREPO="http://github.com/volumio/platform-${DEVICEFAMILY}"
DEVICEREPO_BRANCH="6.12.49" # Branch to use for the device repo or empty for main

### What features do we want to target
# TODO: Not fully implemented
VOLVARIANT=no # Custom Volumio (Motivo/Primo etc)
MYVOLUMIO=no
VOLINITUPDATER=yes
KIOSKMODE=yes

## Partition info
BOOT_START=1
BOOT_END=385           # 384 MiB boot partition, aligned
IMAGE_END=6105         # BOOT_END + 4288 MiB (/img squashfs)
BOOT_TYPE=gpt          # Keep gpt for SSD, NVMe switch to msdos if needed
BOOT_USE_UUID=yes      # Use UUIDs in fstab for /boot mount
INIT_TYPE="initv3"     # Volumio init type

## Plymouth theme management
PLYMOUTH_THEME="volumio-player" # Choices are: {volumio,volumio-logo,volumio-player}
INIT_PLYMOUTH_DISABLE="no"      # yes/no or empty. Removes plymouth initialization in init if "yes" is selected

# Modules that will be added to intramfs
MODULES=("overlay" "squashfs"
  # USB/FS modules
  "usbcore" "usb_common" "mmc_core" "mmc_block" "nvme_core" "nvme-core" "nvme" "sdhci" "sdhci_pci" "sdhci_acpi"
  "ehci_pci" "ohci_pci" "uhci_hcd" "ehci_hcd" "xhci_hcd" "ohci_hcd" "usbhid" "hid_cherry" "hid_generic"
  "hid" "nls_cp437" "nls_utf8" "vfat" "fuse" "uas"
  # nls_ascii might be needed on some kernels (debian upstream for example)
  # Plymouth modules
  "intel_agp" "drm" "i915 modeset=1" "nouveau modeset=1" "radeon modeset=1"
  # Ata modules
  "acard-ahci" "ahci" "ata_generic" "ata_piix" "libahci" "libata"
  "pata_ali" "pata_amd" "pata_artop" "pata_atiixp" "pata_atp867x" "pata_cmd64x" "pata_cs5520" "pata_cs5530"
  "pata_cs5535" "pata_cs5536" "pata_efar" "pata_hpt366" "pata_hpt37x" "pata_isapnp" "pata_it8213"
  "pata_it821x" "pata_jmicron" "pata_legacy" "pata_marvell" "pata_mpiix" "pata_netcell" "pata_ninja32"
  "pata_ns87410" "pata_ns87415" "pata_oldpiix" "pata_opti" "pata_pcmcia" "pata_pdc2027x"
  "pata_pdc202xx_old" "pata_piccolo" "pata_rdc" "pata_rz1000" "pata_sc1200" "pata_sch" "pata_serverworks"
  "pata_sil680" "pata_sis" "pata_triflex" "pata_via" "pdc_adma" "sata_mv" "sata_nv" "sata_promise"
  "sata_qstor" "sata_sil24" "sata_sil" "sata_sis" "sata_svw" "sata_sx4" "ata_uli" "sata_via" "sata_vsc"
)
# Packages that will be installed
PACKAGES=()

# Kernel selection
# Kernel selection has been deprecated, the kernel version is now set during the 'build-x86-platform' process.

# Firmware selection
# FIRMWARE_VERSION="20230804"
# FIRMWARE_VERSION="20241110"
FIRMWARE_VERSION="20250509"

### Device customisation
# Copy the device specific files (Image/DTS/etc..)
write_device_files() {
  log "Running write_device_files" "ext"
  log "Copying x86 platform (kernel, headers, libc-dev) files" "info"

  cp -dR "${PLTDIR}/${DEVICE}/boot" "${ROOTFSMNT}"
  # for bookworm, copy "lib" to "/usr/lib"!!
  cp -pdR "${PLTDIR}/${DEVICE}/lib" "${ROOTFSMNT}/usr"
  cp -pdR "${PLTDIR}/${DEVICE}/usr" "${ROOTFSMNT}"

  log "Copying the latest firmware into /lib/firmware" "info"
  log "Unpacking the tar file firmware-${FIRMWARE_VERSION}" "info"
  # for bookworm, de-compress firmware to "/usr/lib"!!
  FIRMWARE_ARCHIVE="${PLTDIR}/firmware-${FIRMWARE_VERSION}.tar.xz"
  FIRMWARE_CHUNKS="${FIRMWARE_ARCHIVE}.part_"
  TEMP_REASSEMBLED="${FIRMWARE_ARCHIVE}.reassembled"

  if ls "${FIRMWARE_CHUNKS}"* 1>/dev/null 2>&1; then
    log "Detected chunked firmware archive, reassembling..." "info"
    cat "${FIRMWARE_CHUNKS}"* > "${TEMP_REASSEMBLED}"
    tar xfJ "${TEMP_REASSEMBLED}" -C "${ROOTFSMNT}/usr"
    rm -f "${TEMP_REASSEMBLED}"
  elif [[ -f "${FIRMWARE_ARCHIVE}" ]]; then
    tar xfJ "${FIRMWARE_ARCHIVE}" -C "${ROOTFSMNT}/usr"
  else
    log "No firmware archive found for ${FIRMWARE_VERSION}, skipping firmware install" "wrn"
  fi

  mkdir -p "${ROOTFSMNT}"/usr/local/bin/
  declare -A CustomScripts=(
    [bytcr_init.sh]="bytcr-init/bytcr_init.sh"
    [handle_jack-headphone_event.sh]="acpi/handlers/handle_jack-headphone_event.sh"
    [handle_mute-button_event.sh]="acpi/handlers/handle_mute-button_event.sh"
    [handle_brightness-button_event.sh]="acpi/handlers/handle_brightness-button_event.sh"
    [move_screenshot.sh]="prtsc-button/move_screenshot.sh"
    [volumio_hda_intel_tweak.sh]="hda-intel-tweaks/volumio_hda_intel_tweak.sh"
    [x86Installer.sh]="x86Installer/x86Installer.sh"
  )
  #TODO: not checked with other Intel SST bytrt/cht audio boards yet, needs more input
  #      to be added to the snd_hda_audio tweaks (see below)
  log "Adding ${#CustomScripts[@]} custom scripts to /usr/local/bin: " "ext"
  for script in "${!CustomScripts[@]}"; do
    log "..${script}"
    cp "${PLTDIR}/${DEVICE}/utilities/${CustomScripts[$script]}" "${ROOTFSMNT}"/usr/local/bin/"${script}"
    chmod +x "${ROOTFSMNT}"/usr/local/bin/"${script}"
  done

  log "Creating efi folders" "info"
  mkdir -p "${ROOTFSMNT}"/boot/efi
  mkdir -p "${ROOTFSMNT}"/boot/efi/EFI/debian
  mkdir -p "${ROOTFSMNT}"/boot/efi/BOOT/
  
  log "Copying bootloaders and grub configuration template" "ext"
  mkdir -p "${ROOTFSMNT}"/boot/grub
  cp "${PLTDIR}/${DEVICE}"/utilities/efi/BOOT/grub.cfg "${ROOTFSMNT}"/boot/efi/BOOT/grub.tmpl
  cp "${PLTDIR}/${DEVICE}"/utilities/efi/BOOT/BOOTIA32.EFI "${ROOTFSMNT}"/boot/efi/BOOT/BOOTIA32.EFI
  cp "${PLTDIR}/${DEVICE}"/utilities/efi/BOOT/BOOTX64.EFI "${ROOTFSMNT}"/boot/efi/BOOT/BOOTX64.EFI

  log "Copying current partition data for use in runtime fast 'installToDisk'" "ext"
  cat <<-EOF >"${ROOTFSMNT}/boot/partconfig.json"
{
  "params":[
  {"name":"boot_start","value":"$BOOT_START"},
  {"name":"boot_end","value":"$BOOT_END"},
  {"name":"volumio_end","value":"$IMAGE_END"},
  {"name":"boot_type","value":"$BOOT_TYPE"}
  ]
}
EOF

  # Headphone detect currently only for atom z8350 with rt5640 codec
  # Evaluate additional requirements when they arrive
  log "Copying acpi events for headphone jack detect (z8350 with rt5640 only)" "info"
  cp "${PLTDIR}/${DEVICE}"/utilities/acpi/events/jack-headphone_event "${ROOTFSMNT}"/etc/acpi/events
  
  # Generic acpi events
  log "Copying acpi events for mute and brightness buttons" "info"
  cp "${PLTDIR}/${DEVICE}"/utilities/acpi/events/brightness-button_event "${ROOTFSMNT}"/etc/acpi/events
  cp "${PLTDIR}/${DEVICE}"/utilities/acpi/events/mute-button_event "${ROOTFSMNT}"/etc/acpi/events
  
}

write_device_bootloader() {
  log "Running write_device_bootloader" "ext"
  log "Copying the Syslinux boot sector"
  dd conv=notrunc bs=440 count=1 if="${ROOTFSMNT}"/usr/lib/syslinux/mbr/gptmbr.bin of="${LOOP_DEV}"
}

# Will be called by the image builder for any customisation
device_image_tweaks() {
  log "Running device_image_tweaks" "ext"

  # Some wireless network drivers (e.g. for Marvell chipsets) create device 'mlan0'"
  log "Rename these 'mlan0' to 'wlan0' using a systemd link" 
  cat <<-EOF > "${ROOTFSMNT}/etc/systemd/network/10-rename-mlan0.link"
[Match]
Type=wlan
Driver=mwifiex_sdio
OriginalName=mlan0

[Link]
Name=wlan0
EOF

  # Add Intel sound service (setings at runtime)
  log "Add service to set sane defaults for baytrail/cherrytrail and HDA soundcards" "info"
  cat <<-EOF >"${ROOTFSMNT}/usr/local/bin/soundcard-init.sh"
#!/bin/sh -e
/usr/local/bin/bytcr_init.sh
/usr/local/bin/volumio_hda_intel_tweak.sh
exit 0
EOF
  chmod +x "${ROOTFSMNT}/usr/local/bin/soundcard-init.sh"
  [[ -d ${ROOTFSMNT}/lib/systemd/system/ ]] || mkdir -p "${ROOTFSMNT}/lib/systemd/system/"
  cat <<-EOF >"${ROOTFSMNT}/lib/systemd/system/soundcard-init.service"
[Unit]
Description = Intel SST and HDA soundcard init service
After=volumio.service

[Service]
Type=simple
ExecStart=/usr/local/bin/soundcard-init.sh

[Install]
WantedBy=multi-user.target
EOF
  ln -s "${ROOTFSMNT}/lib/systemd/system/soundcard-init.service" "${ROOTFSMNT}/etc/systemd/system/multi-user.target.wants/soundcard-init.service"

 cat <<-EOF >"${ROOTFSMNT}/lib/systemd/system/screenshot.service"
[Unit]
Description = Process screenshots triggered by PrtSc-button
After=volumio.service

[Service]
Type=simple
ExecStart=/usr/local/bin/move_screenshot.sh

[Install]
WantedBy=multi-user.target
EOF
  ln -s "${ROOTFSMNT}/lib/systemd/system/screenshot.service" "${ROOTFSMNT}/etc/systemd/system/multi-user.target.wants/screenshot.service"

  #log "Adding ACPID Service to Startup"
  #ln -s "${ROOTFSMNT}/lib/systemd/system/acpid.service" "${ROOTFSMNT}/etc/systemd/system/multi-user.target.wants/acpid.service"

  log "Blacklisting PC speaker" "wrn"
  cat <<-EOF >>"${ROOTFSMNT}/etc/modprobe.d/blacklist.conf"
blacklist snd_pcsp
blacklist pcspkr
EOF

}

# Will be run in chroot (before other things)
device_chroot_tweaks() {
  #log "Running device_image_tweaks" "ext"
  :
}

# Will be run in chroot - Pre initramfs
# TODO Try and streamline this!
device_chroot_tweaks_pre() {
  log "Performing device_chroot_tweaks_pre" "ext"

  log "Change linux kernel image name to 'vmlinuz'" "info"
  # Rename linux kernel to a fixed name, like we do for any other platform.
  # We only have one and we should not start multiple versions.
  # - our OTA update can't currently handle that and it blows up size of /boot and /lib.
  # This rename is safe, because we have only one vmlinuz* in /boot
  mv /boot/vmlinuz* /boot/vmlinuz

  log "Preparing BIOS" "info"
  log "Installing Syslinux Legacy BIOS at ${BOOT_PART-?BOOT_PART is not known}" "info"
  syslinux -v
  syslinux "${BOOT_PART}"
  dd if="${BOOT_PART}" of=bootrec.dat bs=512 count=1
  dd if=bootrec.dat of="${BOOT_PART}" bs=512 seek=6
  rm bootrec.dat 
  
  log "Preparing boot configurations" "cfg"
  if [[ $DEBUG_IMAGE == yes ]]; then
		log "Debug image: remove splash from cmdline" "cfg"
		SHOW_SPLASH="nosplash" # Debug removed
		log "Debug image: remove quiet from cmdline" "cfg"
		KERNEL_QUIET="loglevel=8" # Default Debug
  else
		log "Default image: add splash to cmdline" "cfg"
		SHOW_SPLASH="initramfs.clear splash plymouth.ignore-serial-consoles" # Default splash enabled
		log "Default image: add quiet to cmdline" "cfg"
		KERNEL_QUIET="quiet loglevel=0" # Default quiet enabled, loglevel default to KERN_EMERG
  fi

  # Boot screen stuff
	kernel_params+=("${SHOW_SPLASH}")
  # Boot logging stuff
	kernel_params+=("${KERNEL_QUIET}")

  # Build up the base parameters
  kernel_params+=(
    # Boot delay
	"bootdelay=5"
    # Bios stuff
    "biosdevname=0"
    # Boot params
    "imgpart=UUID=%%IMGPART%%" "bootpart=UUID=%%BOOTPART%%" "datapart=UUID=%%DATAPART%%"
    "hwdevice=x86"
    "uuidconfig=syslinux.cfg,efi/BOOT/grub.cfg"
    # Image params
    "imgfile=/volumio_current.sqsh"
    # Disable linux logo during boot
    "logo.nologo"
    # Disable cursor
    "vt.global_cursor_default=0"
    # backlight control (notebooks)
    "acpi_backlight=vendor"
    # for legacy ifnames in bookworm
    "net.ifnames=0"   
  )
  
  if [ "${DEBUG_IMAGE}" == "yes" ]; then
    log "Creating debug image" "wrn"
    # Set breakpoints, loglevel, debug, kernel buffer output etc.
    #kernel_params+=("break=" "use_kmsg=yes") 
    kernel_params+=("break=" "use_kmsg=yes") 
    log "Enabling ssh on boot" "dbg"
    touch /boot/ssh
  else
    # No output
    kernel_params+=("use_kmsg=no") 
  fi
 
  log "Setting ${#kernel_params[@]} Kernel params:" "" "${kernel_params[*]}" "cfg"

  log "Setting up syslinux and grub configs" "cfg"
  log "Creating run-time template for syslinux config" "cfg"
  # Create a template for init to use later in `update_config_UUIDs`
  cat <<-EOF >/boot/syslinux.tmpl
DEFAULT volumio
LABEL volumio
	SAY Booting Volumio Audiophile Music Player...
  LINUX vmlinuz
  APPEND ${kernel_params[@]}
  INITRD volumio.initrd
EOF

  log "Creating syslinux.cfg from syslinux template" "cfg"
  sed "s/%%IMGPART%%/${UUID_IMG}/g; s/%%BOOTPART%%/${UUID_BOOT}/g; s/%%DATAPART%%/${UUID_DATA}/g" /boot/syslinux.tmpl >/boot/syslinux.cfg

  log "Setting up Grub configuration" "cfg"
  grub_tmpl=/boot/efi/BOOT/grub.tmpl
  grub_cfg=/boot/efi/BOOT/grub.cfg
  log "Inserting our kernel parameters to grub.tmpl" "cfg"
  # Use a different delimiter as we might have some `/` paths
  sed -i "s|%%CMDLINE_LINUX%%|""${kernel_params[*]}""|g" ${grub_tmpl}

  log "Creating grub.cfg from grub template"
  cp ${grub_tmpl} ${grub_cfg}

  log "Inserting root and boot partition UUIDs (building the boot cmdline used in initramfs)" "cfg"
  # Opting for finding partitions by-UUID
  sed -i "s/%%IMGPART%%/${UUID_IMG}/g" ${grub_cfg}
  sed -i "s/%%BOOTPART%%/${UUID_BOOT}/g" ${grub_cfg}
  sed -i "s/%%DATAPART%%/${UUID_DATA}/g" ${grub_cfg}

  log "Finished setting up boot config" "okay"

  log "Creating fstab template to be used in initrd" "cfg"
  sed "s/^UUID=${UUID_BOOT}/%%BOOTPART%%/g" /etc/fstab >/etc/fstab.tmpl

  log "Notebook-specific: ignore 'cover closed' event" "info"
  sed -i "s/#HandleLidSwitch=suspend/HandleLidSwitch=ignore/g" /etc/systemd/logind.conf
  sed -i "s/#HandleLidSwitchExternalPower=suspend/HandleLidSwitchExternalPower=ignore/g" /etc/systemd/logind.conf

}

# Will be run in chroot - Post initramfs
device_chroot_tweaks_post() {
  log "Running device_chroot_tweaks_post" "ext"

  log "Cleaning up /boot" "info"
  log "Removing System.map" "$(ls -lh --block-size=M /boot/System.map-*)" "info"
  rm /boot/System.map-*
}

# Will be called by the image builder post the chroot, before finalisation
device_image_tweaks_post() {
  # log "Running device_image_tweaks_post" "ext"
  :
}

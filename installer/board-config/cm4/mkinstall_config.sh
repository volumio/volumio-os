#!/bin/bash

# Device Info Raspberry Pi CM4
DEVICEBASE="cm4"
BOARDFAMILY="cm4"
BUILD="arm"
NONSTANDARD_REPO=yes	# yes requires "non_standard_repo() function in make.sh
LBLBOOT="BOOT"
LBLIMAGE="volumio"
LBLDATA="volumio_data"

# Partition Info
BOOT_TYPE=msdos			# msdos or gpt
BOOT_START=1
BOOT_END=385
IMAGE_END=4673
BOOT=/mnt/boot
BOOTDELAY=
BOOTDEV="sda"
BOOTPART=/dev/sda1
BOOTCONFIG=cmdline.txt

TARGETBOOT="/dev/mmcblk0p1"
TARGETDEV="/dev/mmcblk0"
TARGETDATA="/dev/mmcblk0p3"
TARGETIMAGE="/dev/mmcblk0p2"
HWDEVICE="cm4"
USEKMSG="yes"
UUIDFMT="yes"			# yes|no (actually, anything non-blank)
FACTORYCOPY="yes"

INSTALLER_SIZE=5000

# Modules to load (as a blank separated string array)
MODULES="fuse nls_cp437 nls_iso8859_1 usb_storage uas"

# Additional packages to install (as a blank separated string)
#PACKAGES=""

# initramfs type
RAMDISK_TYPE=gzip		# image or gzip (ramdisk image = uInitrd, gzip compressed = volumio.initrd)

mkdir -p "${SRC}/platform-${DEVICEBASE}"

non_standard_repo()
{
   local src=/mnt/cm4src
   local loop
   rm -rf "${PLTDIR:?}/${BOARDFAMILY}"
   mkdir -p "${PLTDIR}/${BOARDFAMILY}/boot" "${PLTDIR}/${BOARDFAMILY}/lib" ${src}/boot ${src}/image ${src}/sqsh
   loop=$(losetup -f --show -P "${VOLUMIOIMAGE}")
   mount -o ro "${loop}p1" ${src}/boot
   mount -o ro "${loop}p2" ${src}/image
   mount -o ro,loop ${src}/image/volumio_current.sqsh ${src}/sqsh
   cp -R ${src}/boot/. "${PLTDIR}/${BOARDFAMILY}/boot"
   cp -pdR ${src}/sqsh/lib/modules "${PLTDIR}/${BOARDFAMILY}/lib"
   umount ${src}/sqsh ${src}/image ${src}/boot
   losetup -d "${loop}"
   rm -r ${src}
}

fetch_bootpart_uuid()
{
echo "[info] replace BOOTPART device by ${FLASH_PART} UUID value"
UUIDBOOT=$(blkid -s UUID -o value "${FLASH_PART}")
BOOTPART="UUID=${UUIDBOOT}"
}

is_dataquality_ok()
{
   return 0
}

write_device_files()
{
   cp -R "${PLTDIR}/${BOARDFAMILY}/boot/." "$ROOTFSMNT"/boot
   rm -f "$ROOTFSMNT"/boot/volumio.initrd
}

write_device_bootloader()
{
   :
}

copy_device_bootloader_files()
{
   :
}

write_boot_parameters()
{
   echo "console=serial0,115200 console=tty1 loglevel=4 use_kmsg=yes hwdevice=${HWDEVICE}" > "$ROOTFSMNT"/boot/cmdline.txt
}

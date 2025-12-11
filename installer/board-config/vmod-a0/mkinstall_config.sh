#!/bin/bash

# Device Info VMOD-A0
DEVICEBASE="rockpi"
BOARDFAMILY="vmod-a0"
PLATFORMREPO="https://github.com/volumio/platform-${DEVICEBASE}.git"
BUILD="armv7"
#NONSTANDARD_REPO=yes	# yes requires "non_standard_repo() function in make.sh 
LBLBOOT="BOOT"
LBLIMAGE="volumio"
LBLDATA="volumio_data"

# Partition Info
BOOT_TYPE=msdos			# msdos or gpt   
BOOT_START=20
BOOT_END=148
IMAGE_END=3800
BOOT=/mnt/boot
BOOTDELAY=1
BOOTDEV="mmcblk0"
BOOTPART=/dev/${BOOTDEV}p1
BOOTCONFIG=armbianEnv.txt

TARGETBOOT="/dev/mmcblk1p1"
TARGETDEV="/dev/mmcblk1"
TARGETDATA="/dev/mmcblk1p3"
TARGETIMAGE="/dev/mmcblk1p2"
HWDEVICE="vmod-a0"
USEKMSG="yes"
UUIDFMT="yes"			# yes|no (actually, anything non-blank)
FACTORYCOPY="yes"


# Modules to load (as a blank separated string array)
MODULES="nls_cp437 fuse"

# Additional packages to install (as a blank separated string)
#PACKAGES=""

# initramfs type
RAMDISK_TYPE=image		# image or gzip (ramdisk image = uInitrd, gzip compressed = volumio.initrd) 

non_standard_repo()
{
   :
}

fetch_bootpart_uuid()
{
   :
}

is_dataquality_ok()
{
   return 0
}

write_device_files()
{
  cp ${PLTDIR}/${BOARDFAMILY}/boot/Image ${ROOTFSMNT}/boot
  cp ${PLTDIR}/${BOARDFAMILY}/boot/armbianEnv.txt ${ROOTFSMNT}/boot
  cp ${PLTDIR}/${BOARDFAMILY}/boot/config-6.1.95-rockchip64 ${ROOTFSMNT}/boot
  cp ${PLTDIR}/${BOARDFAMILY}/boot/boot.scr ${ROOTFSMNT}/boot
  cp -dR ${PLTDIR}/${BOARDFAMILY}/boot/dtb ${ROOTFSMNT}/boot
} 

write_device_bootloader()
{
  dd if=${PLTDIR}/${BOARDFAMILY}/u-boot/idbloader.bin of=${LOOP_DEV} seek=64 conv=notrunc status=none
  dd if=${PLTDIR}/${BOARDFAMILY}/u-boot/uboot.img of=${LOOP_DEV} seek=16384 conv=notrunc status=none
  dd if=${PLTDIR}/${BOARDFAMILY}/u-boot/trust.bin of=${LOOP_DEV} seek=24576 conv=notrunc status=none
}

copy_device_bootloader_files()
{
   mkdir ${ROOTFSMNT}/boot/u-boot
   cp ${PLTDIR}/${BOARDFAMILY}/u-boot/idbloader.bin $ROOTFSMNT/boot/u-boot
   cp ${PLTDIR}/${BOARDFAMILY}/u-boot/uboot.img $ROOTFSMNT/boot/u-boot
   cp ${PLTDIR}/${BOARDFAMILY}/u-boot/trust.bin $ROOTFSMNT/boot/u-boot
}

write_boot_parameters()
{
   sed -i "s/verbosity=0/verbosity/g" $ROOTFSMNT/boot/armbianEnv.txt
   # edit console settings, should be "both" for simplicity
   sed -i "s/console=serial/console=both/g" $ROOTFSMNT/boot/armbianEnv.txt
   sed -i "s/imgpart=UUID= bootpart=UUID= datapart=UUID= uuidconfig=armbianEnv.txt bootconfig=armbianEnv.txt imgfile=\/volumio_current.sqsh net.ifnames=0//g" $ROOTFSMNT/boot/armbianEnv.txt
   sed -i "s/user_overlays=audio-i2s audio-spdif usb-otg-host//g" $ROOTFSMNT/boot/armbianEnv.txt
}





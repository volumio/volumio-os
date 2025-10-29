# 
|Date|Author|Change|
|---|---|---|
|20230501|gkkpch|Initial V1.0
|20230621||Starting the documention
|20230622||Adding the old (20210209) build environment as a reference
|20231224||Added first "Malaga" amendments
|20231230||Continued. initramfs for x86 tested ok, plymouth splash to follow
|20240110||Halted plymouth for the time being
|||Continued with verifying and updating armv7
|20240112||Started Odroid N2/N2+ tests
|20240117||Documentation in progress
|20240314|foonerd|Starting on initv3
|20240329|gkkpch,foonerd|Starting device testing on initv3
|20240403|gkkpch|x86, mp1, odroidc4, odroidn2, nanopineo2, nanopineo3 and nanopim4 are ready for beta
|20240411|foonerd|Devices move to beta
|20240422|foonerd|OEM device handling move to beta
|20240508|foonerd|Beta testing start across all builds
|20240528|foonerd|Release across all builds
|20251029|foonerd|Reworked plymouth theme detection

## ```##TODO```

|Task|Status|
|---|---|
|Check all init scripts for changes after december 2020|done|
|Test whether the overriding of functions works properly|done
|Board-specifics for odroidn2|done
|Board-specifics for mp1|done
|Verify RPi USB boot|done
|Pick up the plymouth issue, as a default (debian futureprototype) seems to startup and hold until booted|done
|Plymouth can't do early display (only after systemd start, shutdown mode was/is ok), kernel module missing in initrd?|done
|Initrd modules to be investigated|ongoing
|Backport Plymouth in case successful|done
|init.nextarm test/ adaptions|done
|PI additions, incl. block device info to UUID|done
|OTA tests|done
|initv3 test/ adaptions|done

# **Volumio initramfs implementation**

This readme gives a quick overview of the files involved and how to integrate them into **volumio-os**.  
This documentation is still WIP.

One of the main reasons for refactoring this was the lack of debugging capabilities in the current init script versions.  
Where most of the arm boards have the ability to add a console log to monitor/debug the boot process, x86 does not have that opportunity.
Also, using the chosen approach brings Volumio's init script into a structure closer to the original initramfs scripts as used with  Debian and Ubuntu.

During the development process, the currently maintained init scripts (init, init.nextarm, init86 etc.) will be replaced by a single initramfs script set, covering the Raspberry PI, various other armv7 boards and x86.  
Replacing the Volumio init script with the original initramfs approach from Ubuntu and Debian also means that, instead of moving just one "init" script into initramfs, the new design now inserts a basic collection of initramfs scripts. 

The design followed the main debian and ubuntu initramfs process, there is no link to dracut.

Though the use of init "hooks" does not really apply to Volumio, the available initramfs general functions have been used as much as possible. Volumio-specific functions are added to a separate script module.
Volumio does not need all initramfs functions and therefore only uses a part of them. As mentioned, Volumio does not use hooks like the standard initramfs does, but implements something similar (without calling it a hook).

Volumio-specific scripts are not allowed to be modified to implement function extensions. This ought to be done in a separate function module (script) ```custom-functions``` by adding the modified function from ```volumio-functions``` (it willl override the standard one) or by adding a function (extension).  
 
An extension can be therefore be used to implement a device-specific requirement. 
Extensions are therefore board-specific and the board implementer's responsibility. Extensions are always a combination of an overridden volumio function and an addition.

Extension example: see ```recipe/families/x86_amd64``` and ```scripts/initramfs/scripts/custom/x86``` 

# **Contents**
|File/ folder|Contents
|---|---|
|conf|Environment configuration	
|scripts|initramfs scripts (custom and standard functions)
|init|init script
|mkinitramfs-custom.sh|adapted script (replace standard initramfs script folder)


## Folder **scripts/functions**
This is basically an unmodified copy from ```/usr/share/initramfs-tools/scripts/functions```.  
Only a few of them are used.  
(Based on Debian 10 from spring 2020, after the release of Volumio 3, still valid). 
 
## **scripts/volumio-functions**
Standard Volumio functions, used with all boards.

## **scripts/custom-functions**
Board-specific functions and/ or overrides are placed in script file ```custom-functions```. 

## **mkinitramfs-custom.sh**

The customized ```mkinitramfs``` build script for Volumio has been modified to replace the standard initramfs hook scripts by the above used scripts for volumio, see function ```build_initrd()```.

# Debugging

## **1. Using ```debug``` and ```use_kmsg``` cmdline parameters**
The use of ```debug``` will allow you to debug the init and functions scripts.  
Combined with the ```use_kmsg``` parameter, the debug messages will either be printed on the console (use_kmsg=yes) or to the debug file in ```/run/initramfs/initramfs.debug```.  
The debug file can be accessed during initramfs processing ***and*** after the boot process has completed.

## 2. **Using Breakpoints**
Breakpoints are a big step forward for debugging, designed to let initramfs stop at optional locations in initramfs, the locations themselves are pre-defined, but can be configured with the ```break``` cmdline parameter.
When a breakpoint is reached, initramfs jumps to a temporary busybox shell.  
Here you can check parameters, look at the kernel log (dmesg) or check the initramfs.debug file (when ```debug``` has been configure, combined with ```use_ksmsg=yes```, see above). 

You could add your own breakpoints, but that would mean a modification of the init script.
Use ```maybe_volumio_break <break name> "init: $LINENO"``` for that and remove them when you are finished.


### Valid breakpoints are:
```
top, modules, premount, mount, udev-slumber, cust-init-part, init-part-pars, progress, dev_partiton, krnl-archive, search-for-firmw, search-fact-reset, search-fact-reset, krnl-rollbck,krnl-upd, resize-data, mnt-overlayfs, cust-upd-uuid, updfstab, bottom, init
```

### Configuring a breakpoint
A kernel cmdline parameter `break=` with a comma-separated list, e.g.

```
break=modules,kernel-upd
```

Dropping to a shell will not cause a kernel panic, when leaving the shell with ```exit```.   
The initramfs flow will continue after the breakpoints, you can use as many breakpoints from the list as you need.  
This is different from the way debugging is done with the current version, which stops initramfs alltogether and then causes a kernel panic.  

## 3. Only for Plymouth issues
Add "plymouth.debug" to the cmdline parameters. 
Boot and just let it run. After boot, login (```ctrl-F1```) and check file ```/var/log/plymouth-debug.log```

# Plymouth Display Detection

Starting with initv3, Plymouth has built-in display detection and rotation support to handle SPI, DSI, and other non-standard display configurations.

## Display Detection

Plymouth will automatically wait for display devices to become available during init. The detection checks:

1. DRM/KMS devices (/sys/class/drm/card*/status = connected)
2. Framebuffer devices (/dev/fb0, /dev/fb1)
3. DRI devices (/dev/dri/card*)

If no display is found within the timeout period, Plymouth will be skipped automatically.

## Configuration Options

The following environment variables control Plymouth display behavior:

**PLYMOUTH_WAIT_TIMEOUT** (default: 5)
- Seconds to wait for display device during init
- Set in buildoptions.sh or device recipe

**PLYMOUTH_TEXT_THEME** (default: volumio-text)
- Text-mode theme to use for problematic displays
- Automatically selected for very small screens or when graphical mode fails

**PLYMOUTH_REQUIRE_DISPLAY** (default: no)
- If "yes", Plymouth will always try to start even without detected display
- If "no", Plymouth skips when no display found

## Rotation Detection

Display rotation is detected from kernel command line parameters:

Supported formats:
- video=HDMI-A-1:1920x1080,rotate=90
- video=DSI-1:800x480,rotate=270
- fbcon=rotate:1 (where 0=0deg, 1=90deg, 2=180deg, 3=270deg)
- rotation=90

Rotation is applied before Plymouth starts.

## Device-Specific Overrides

Device recipes can override rotation detection by providing a custom function in their custom-functions file:
```sh
custom_detect_rotation() {
  # Read rotation from config.txt, device tree, or other source
  # Echo rotation value (0, 1, 2, 3) and return 0
  # Or return 1 if no rotation detected
  
  # Example: read from config.txt
  if [ -f /mnt/boot/config.txt ]; then
    rotation=$(grep "^display_rotate=" /mnt/boot/config.txt | cut -d= -f2)
    [ -n "$rotation" ] && echo "$rotation" && return 0
  fi
  
  return 1
}
```

## Volumio Text Theme

The volumio-text theme provides a fallback for displays that cannot support graphical Plymouth:

- Black background with white text
- "Volumio Player" title centered
- Progress bar below title
- Message scrolling support
- Responsive to screen size
- Automatically selected for:
  - Displays smaller than 320x240
  - SPI displays without framebuffer bridge
  - DSI displays with detection issues

## Troubleshooting

**Plymouth not showing:**
- Check display is detected: `ls /sys/class/drm/card*/status`
- Check framebuffer: `ls /dev/fb*`
- Add `debug` to cmdline.txt and check /run/initramfs/initramfs.debug
- Increase PLYMOUTH_WAIT_TIMEOUT if display takes long to initialize

**Rotation not applied:**
- Verify rotation parameter in /proc/cmdline
- Check if custom_detect_rotation() is implemented for your device
- Some displays require rotation at driver level, not Plymouth

**Text mode instead of graphical:**
- Check display resolution in /sys/class/graphics/fb0/virtual_size
- Graphical theme requires minimum 320x240 resolution
- Override by setting INIT_PLYMOUTH_DISABLE="yes" in device recipe

# **Modifying kernel command parameters in an already built image**

The parameters are integrated in the ```grub.cfg``` file, which can be found in folder ```/boot/efi/BOOT/grub.cfg```.  
Scroll down to ```menuentry 'Volumio Audiophile Music player GNU/Linux'```.  
 and locate the line ```linux   /vmlinuz ```.

# Integrating the new INITRAMFS (initv3)
## WIP

This documentation is still work in progress and will be completed soon with a comprehensive description of the components involved.  
The initramfs script collection has been thoroughly tested with x86 and arvm7 (Odroid N2).  
It has thoroughly tested and verified with an RPi or Primo, for all other boards this *should* be just verification, as there *should* be no more functional differences.  
(Most of the original differences are now obsolete as support has stopped for old armv7 boards).  

MP1 was added to Volumio later and has also been verified.
This is relevant, because some work needs to be done for mp1, it is the only device which received very specific ```init``` updates because of necessary modifications with preparing kernel 6.1y: it needs u-boot to be updated as well..  

## Build recipe implementation details

### cmdline parameters
|Item|Usage|(Re)quired/ (O)ptional|
|---|---|---|
|bootdelay=|Default is 5, in case you want to reduce the value, add bootdelay to the kernel cmdline. But make sure it also works with factory reset on usb stick|O|
hwdevice=|Add the name of the device e.g. PI, x86, odroidn2, mp1 etc.|R
quiet loglevel=0 use_kmsg=no|Normal case, no console output, three parameter combi, use in that order!|R
loglevel={1¦2¦3¦4¦5¦6¦7¦8}} use_kmsg={yes¦no} {break=}|Alternative for above, for debugging, two or three parameter combi, without 'quiet'. See "Debugging"|O

### init scripts

|Item|Usage|(R)equired/ (O)ptional|
|---|---|---|
|initv3| The recipe should use this for the new init script type|R
||```init``` and ```init.nextarm``` are the legacy ones, but can still be used. When used, initramfs will revert to the existing version|
||
|custom-functions|In case the sbc requires specific initramfs processing, try adding a custom function, overriding the existing one as described in the chapter above. Put the function in ```initramfs/custom/<your-sbc-name>/custom-functions```. The recipe should copy this to folder ```${ROOTFSMNT}/root/scripts/custom/```. See x86 as a simple and mp1 or pi for a more complex example including init placeholders|O


# **Quick Edit Initramfs**

Rebuilding an image just for testing initramfs is not very efficient, it is easier just to decompress, edit the script(s) or anything else and then compress again.  
Below is a sample script


## Example script


```bash
#!/bin/bash
TMPBOOT=$HOME/tmpboot
TMPWORK=$HOME/tmpwork
HELP() {
  echo "

Help documentation for initrd editor

Basic usage: edit-initramfs.sh -d /dev/sdx -f volumio.initrd

  -d <dir>	Device with the flashed volumio image
  -f <name>	Name of the volumio initrd file
  -a <arm|arm64> Either 32 or 64bit arm, default arm64

Example: ./edit.initramfs.sh -d /dev/sdb -f volumio.initrd -a arm

Notes:
The script will try to determine how the initrd was compressed and unpack/ repack accordingly
It currently uses 'pluma' as the editor, see variable 'EDITOR'

"
  exit 1
}

EDITOR=pluma
EXISTS=`which $EDITOR`
if [ "x" = "x$EXISTS" ]; then
	echo "This script requires text editor '${EDITOR}'"
    echo "Please install '$EDITOR' or change the current value of variable EDITOR"
	exit 1
fi

ARCH="arm64"
NUMARGS=$#
if [ "$NUMARGS" -eq 0 ]; then
  HELP
fi

while getopts d:f:a: FLAG; do
  case $FLAG in
    d)
      DEVICE=$OPTARG
      ;;
    f)
      INITRDNAME=$OPTARG
      ;;
    a)
      ARCH=$OPTARG
      ;;

    h)  #show help
      HELP
      ;;
    /?) #unrecognized option - show help
      echo -e \\n"Option -${BOLD}$OPTARG${NORM} not allowed."
      HELP
      ;;
  esac
done

if [ -z $DEVICE ] || [ -z $INITRDNAME ]; then
	echo ""
	echo "$0: missing argument(s)"
	HELP
	exit 1
fi


[ -d $TMPBOOT ] || mkdir $TMPBOOT
if [ -d $TMPWORK ]; then
	echo "Workarea exists, cleaning it..."
	rm -r $TMPWORK/*
else
	mkdir $TMPWORK
fi

echo "Mounting volumio boot partition..."
mounted=`mount | grep -o ${DEVICE}1`
if [ ! "x$mounted" = "x" ]; then
	echo "Please unmount this device first"
	exit 1
fi
mount ${DEVICE}1 $TMPBOOT
if [ ! $? = 0 ]; then
	exit 1
fi

pushd $TMPWORK > /dev/null 2>&1
if [ ! $? = 0 ]; then
	exit 1
fi

echo "Making $INITRDNAME backup copy..."
cp $TMPBOOT/$INITRDNAME $TMPBOOT/$INITRDNAME".bak"

FORMAT=`file $TMPBOOT/$INITRDNAME | grep -o "RAMDisk Image"`
if [ "x$FORMAT" = "xRAMDisk Image" ]; then
	echo "Unpacking RAMDisk image $INITRDNAME..."
	dd if=$TMPBOOT/$INITRDNAME bs=64 skip=1 | gzip -dc | cpio -div
	pluma init
	echo "Creating a new $INITRDNAME, please wait..."
	find . -print0 | cpio --quiet -o -0 --format=newc | gzip -9 > $TMPBOOT/$INITRDNAME.new
	mkimage -A ${ARCH} -O linux -T ramdisk -C none -a 0 -e 0 -n uInitrd -d $TMPBOOT/$INITRDNAME.new $TMPBOOT/$INITRDNAME
	rm $TMPBOOT/$INITRDNAME.new
else
	echo "Unpacking gzip compressed $INITRDNAME..."
	zcat $TMPBOOT/$INITRDNAME | cpio -idmv > /dev/null 2>&1
	echo "Starting $EDITOR editor..."
	pluma init
	echo "Creating a new $INITRDNAME, please wait..."
	find . -print0 | cpio --quiet -o -0 --format=newc | gzip -9 > $TMPBOOT/$INITRDNAME
fi

echo "Done."
sync
popd > /dev/null 2>&1
umount ${DEVICE}1
if [ ! $? ]; then
	exit 1
fi

rmdir $TMPBOOT
rm -r $TMPWORK
```

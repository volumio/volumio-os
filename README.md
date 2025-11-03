### Buildscripts for Volumio System

Copyright Volumio SRL

#### Requirements

On a Debian (bookworm) host, the following packages are required:
```
build-essential
ca-certificates
curl
debootstrap
dosfstools
git
jq
kpartx
libssl-dev
lz4
lzop
md5deep
multistrap
parted
patch
pv
qemu-user-static
qemu-utils
qemu-system
squashfs-tools
sudo
u-boot-tools
wget
xz-utils
zip
```

#### How to

- Ensure you have installed all dependencies listed above.
- Clone the build repo, and launch the build script (requires root permissions).
```
git clone https://github.com/volumio/volumio-os.git build
cd ./build
./build.sh -b <architecture> -d <device> -v <version>
```

where flags are:

 * -b `<arch>` Build a base rootfs with Multistrap.

   Options for the target architecture are:<br>
       **arm** (Raspbian armhf ARMv6 32bit - Legacy: Pi 1, Zero, Zero W, CM1)<br>
       **armv7** (Debian armhf ARMv7 32bit - Pi 2+, ODROID, Tinkerboard, etc.)<br>
       **armv8** (Debian arm64 64bit - 64-bit ARM devices)<br>
       **x64** (Debian amd64 64bit - x86-64 PCs)

 * -d `<dev>`  Create Image for Specific Devices.

   Currently supported devices:<br>
       **Raspberry Pi:** pi, cm4<br>
       **ODROID:** odroidc4, odroidn2, odroidm1s<br>
       **Radxa:** radxa-zero, radxa-zero2, rock-3a<br>
       **NanoPi:** nanopineo2, nanopineo3, nanopim4<br>
       **Other SBCs:** tinkerboard, orangepilite, rockpis, rockpi-4b<br>
       **x86-64:** x86_amd64<br>
       **Volumio Hardware:** mp0, mp1, mp2, motivo, vmod-a0

   Run ```./build.sh -h``` for complete list; new devices added regularly.

 * -v `<vers>` Version

   Version must be a dot-separated number. Example: `4.001`

#### Examples

**Build Raspberry Pi image (ARMv7 - Pi 2+) from scratch, version 4.0:**
```
./build.sh -b armv7 -d pi -v 4.0
```

**Build x86-64 image from scratch:**
```
./build.sh -b x64 -d x86_amd64 -v 4.0
```

**Build ODROID C4 image:**
```
./build.sh -b armv7 -d odroidc4 -v 4.0
```

You do not have to build the base and the image at the same time.

**Build the base for x86-64 first and the image in a second step:**
```
./build.sh -b x64
./build.sh -d x86_amd64 -v 4.001
```

**Build the base for ARMv7 first, then multiple device images:**
```
./build.sh -b armv7
./build.sh -d pi -v 4.001
./build.sh -d odroidc4 -v 4.001
./build.sh -d tinkerboard -v 4.001
```

#### Architecture Notes

**ARMv6 vs ARMv7 for Raspberry Pi:**

- **ARMv7 builds (recommended for Pi 2+):**
  - Use Debian packages optimized for ARMv7 (Thumb-2, VFPv3)
  - 10-25% performance improvement over ARMv6 builds
  - Support: Pi 2, 3, 3+, 4, 400, 5, Zero 2 W, CM3, CM3+, CM4

- **ARMv6 builds (legacy support):**
  - Use Raspbian packages for ARMv6 compatibility
  - Required for: Pi 1 (all models), Pi Zero, Pi Zero W, CM1
  - Will work on newer Pi models but with reduced performance

**Device Recipe BUILD Variable:**

Each device recipe defines a `BUILD` variable that specifies which base architecture it requires:
- The `-b` flag creates a base rootfs tarball: `build/bookworm/<arch>_rootfs.lz4`
- The `-d` flag uses the device recipe's `BUILD` variable to find the matching base tarball
- **The `-b` architecture must match the device's `BUILD` variable**

Example: `pi.sh` contains `BUILD="armv7"`, so you must use `-b armv7` when building the Pi base.

#### Sources

**Kernel Sources:**

* [Raspberry Pi](https://github.com/raspberrypi/linux) - Official Pi kernel
* [Armbian](https://github.com/armbian/build) - Multi-platform ARM kernel support

**Main Package Sources:**

* [MPD](https://github.com/volumio/MPD) - Music Player Daemon by Max Kellerman
* [Shairport-Sync](https://github.com/volumio/shairport-sync) - AirPlay audio player by Mike Brady
* [Node.JS](https://nodejs.org) - JavaScript runtime
* [SnapCast](https://github.com/badaix/snapcast) - Multi-room audio by Badaix
* [Upmpdcli](https://www.lesbonscomptes.com/upmpdcli/) - UPnP/DLNA renderer by Jean-Francois Dockes

**Debian Package Sources:**

All Debian-retrieved package sources can be found at the [debian-sources Repository](https://github.com/volumio/debian-sources)

**Raspbian Package Sources (ARMv6 builds only):**

All Raspbian-retrieved package sources can be found at the [raspbian-sources Repository](https://github.com/volumio/raspbian-sources)

If any information, source package or license is missing, please report it to info at volumio dot org

#### Caching Packages

If you are doing multiple Volumio builds, you can save bandwidth by caching packages with `apt-cacher-ng`.

**Installation:**

Install apt-cacher-ng:
```
sudo apt-get install apt-cacher-ng
```

Configure pass-through:
```
sudo tee -a /etc/apt-cacher-ng/acng.conf > /dev/null <<'EOF'

PassThroughPattern: .*
EOF
```

Start service:
```
sudo systemctl enable apt-cacher-ng
sudo systemctl restart apt-cacher-ng
```

**Usage:**

Set environment variable:
```
export APT_CACHE='http://localhost:3142'
```

Run build with -E flag to preserve environment:
```
sudo -E ./build.sh -b armv7 -d pi -v 4.0
```

**Verification:**

Monitor cache activity:
```
sudo tail -f /var/log/apt-cacher-ng/apt-cacher-ng.log
```

Check cache statistics:
```
curl http://localhost:3142/acng-report.html
```

**Limitations:**

HTTPS repositories cannot be cached due to SSL certificate validation. Only HTTP repositories benefit from caching. Packages downloaded via wget or curl bypass the cache system.

#### Device Recipe Structure

Device configurations are located in `recipes/devices/`. Each device recipe defines:
- `BUILD` variable: Which base architecture to use (arm, armv7, armv8, x64)
- `ARCH` variable: Debian architecture name (armhf, arm64, amd64)
- Hardware-specific kernel configuration and version
- Boot partition layout and bootloader setup
- Device tree overlays and hardware initialization
- Initramfs customization
- Platform-specific tweaks and optimizations

For details on creating new device recipes, see `recipes/devices/README.MD`.

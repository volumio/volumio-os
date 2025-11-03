# Volumio OS Image Builder

Build system for creating Volumio operating system images for various devices.

Copyright Volumio SRL

## Requirements

Debian bookworm host system with the following packages installed:

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

## Build Commands

Clone the repository and run the build script with root permissions.

```
git clone https://github.com/volumio/volumio-os.git build
cd ./build
./build.sh -b <architecture> -d <device> -v <version>
```

## Build Flags

### Architecture Selection (-b)

Build a base root filesystem using multistrap.

Available architectures:

- arm - Raspbian armhf ARMv6 32-bit (Pi 1, Zero, Zero W, CM1)
- armv7 - Debian armhf ARMv7 32-bit (Pi 2+, ODROID, Tinkerboard)
- armv8 - Debian arm64 64-bit (64-bit ARM devices)
- x64 - Debian amd64 64-bit (x86-64 PCs)

### Device Selection (-d)

Create bootable image for specific hardware.

Supported device families:

- Raspberry Pi: pi, cm4
- ODROID: odroidc4, odroidn2, odroidm1s
- Radxa: radxa-zero, radxa-zero2, rock-3a
- NanoPi: nanopineo2, nanopineo3, nanopim4
- Other SBCs: tinkerboard, orangepilite, rockpis, rockpi-4b
- x86-64: x86_amd64
- Volumio Hardware: mp0, mp1, mp2, motivo, vmod-a0

Run ./build.sh -h for complete device list.

### Version Number (-v)

Specify version as dot-separated number. Example: 4.001

## Build Examples

Build Raspberry Pi image from scratch:

```
./build.sh -b armv7 -d pi -v 4.0
```

Build x86-64 image from scratch:

```
./build.sh -b x64 -d x86_amd64 -v 4.0
```

Build ODROID C4 image:

```
./build.sh -b armv7 -d odroidc4 -v 4.0
```

Two-step build process. First create base system, then device image:

```
./build.sh -b x64
./build.sh -d x86_amd64 -v 4.001
```

Build one base for multiple devices:

```
./build.sh -b armv7
./build.sh -d pi -v 4.001
./build.sh -d odroidc4 -v 4.001
./build.sh -d tinkerboard -v 4.001
```

## Architecture Details

### Raspberry Pi Builds

ARMv7 builds recommended for Pi 2 and newer models.

ARMv7 advantages:

- Debian packages optimized for ARMv7 instruction set
- Thumb-2 and VFPv3 support
- 10-25% performance improvement over ARMv6
- Supported: Pi 2, 3, 3+, 4, 400, 5, Zero 2 W, CM3, CM3+, CM4

ARMv6 builds for legacy hardware:

- Raspbian packages for ARMv6 compatibility
- Required: Pi 1 (all models), Pi Zero, Pi Zero W, CM1
- Works on newer Pi models with reduced performance

### Build System Architecture

Each device recipe defines BUILD variable specifying required base architecture.

The -b flag creates base rootfs tarball at build/bookworm/arch_rootfs.lz4

The -d flag reads device recipe BUILD variable to locate matching base tarball.

Architecture specified with -b must match device recipe BUILD variable.

Example: pi.sh contains BUILD="armv7" therefore use -b armv7 for Pi base.

## Package Sources

### Kernel Sources

* [Raspberry Pi](https://github.com/raspberrypi/linux) - Official Pi kernel
* [Armbian](https://github.com/armbian/build) - Multi-platform ARM kernel support


### Main Packages

* [MPD](https://github.com/volumio/MPD) - Music Player Daemon by Max Kellerman
* [Shairport-Sync](https://github.com/volumio/shairport-sync) - AirPlay audio player by Mike Brady
* [Node.JS](https://nodejs.org) - JavaScript runtime
* [SnapCast](https://github.com/badaix/snapcast) - Multi-room audio by Badaix
* [Upmpdcli](https://www.lesbonscomptes.com/upmpdcli/) - UPnP/DLNA renderer by Jean-Francois Dockes

### Package Source Repositories

- Debian packages: https://github.com/volumio/debian-sources
- Raspbian packages: https://github.com/volumio/raspbian-sources

Report missing information or licenses to info at volumio dot org

## Package Caching

Reduce bandwidth usage for multiple builds using apt-cacher-ng.

Install apt-cacher-ng:

```
sudo apt-get install apt-cacher-ng
```

Configure pass-through for all repositories:

```
sudo tee -a /etc/apt-cacher-ng/acng.conf > /dev/null <<'EOF'

PassThroughPattern: .*
EOF
```

Start caching service:

```
sudo systemctl enable apt-cacher-ng
sudo systemctl restart apt-cacher-ng
```

Set cache environment variable:

```
export APT_CACHE='http://localhost:3142'
```

Run build with preserved environment:

```
sudo -E ./build.sh -b armv7 -d pi -v 4.0
```

Monitor cache activity:

```
sudo tail -f /var/log/apt-cacher-ng/apt-cacher-ng.log
```

View cache statistics:

```
curl http://localhost:3142/acng-report.html
```

Caching limitations:

HTTPS repositories cannot be cached due to SSL certificate validation. Only HTTP repositories use the cache. Packages downloaded via wget or curl bypass the cache.

## Device Recipes

Device configurations located in recipes/devices/ directory.

Each device recipe defines:

- BUILD variable for base architecture (arm, armv7, armv8, x64)
- ARCH variable for Debian architecture (armhf, arm64, amd64)
- Kernel configuration and version
- Boot partition layout
- Bootloader setup
- Device tree overlays
- Hardware initialization
- Initramfs customization
- Platform-specific optimizations

See [recipes/devices/README.MD](recipes/devices/README.MD) for device recipe creation details.

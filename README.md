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

Ensure you have installed all dependencies listed above. Clone the build repo and launch the build script with root permissions.

```
git clone https://github.com/volumio/volumio-os.git build
cd ./build
./build.sh -b <architecture> -d <device> -v <version>
```

Build flags:

 * -b `<arch>` Build a base rootfs with Multistrap.

   Options for the target architecture are:
   
   **arm** (Raspbian armhf ARMv6 32bit - Legacy: Pi 1, Zero, Zero W, CM1)
   
   **armv7** (Debian armhf ARMv7 32bit - Pi 2+, ODROID, Tinkerboard, etc.)
   
   **armv8** (Debian arm64 64bit - 64-bit ARM devices)
   
   **x64** (Debian amd64 64bit - x86-64 PCs)

 * -d `<dev>`  Create Image for Specific Devices.

   Currently supported devices:
   
   **Raspberry Pi:** pi, cm4
   
   **ODROID:** odroidc4, odroidn2, odroidm1s
   
   **Radxa:** radxa-zero, radxa-zero2, rock-3a
   
   **NanoPi:** nanopineo2, nanopineo3, nanopim4
   
   **Other SBCs:** tinkerboard, orangepilite, rockpis, rockpi-4b
   
   **x86-64:** x86_amd64
   
   **Volumio Hardware:** mp0, mp1, mp2, motivo, vmod-a0

   Run ```./build.sh -h``` for complete list. New devices added regularly.

 * -v `<vers>` Version

   Version must be a dot-separated number. Example: `4.001`

#### Examples

Build Raspberry Pi image (ARMv7 - Pi 2+) from scratch, version 4.0:

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

You do not have to build the base and the image at the same time. Build the base for x86-64 first and the image in a second step:

```
./build.sh -b x64
./build.sh -d x86_amd64 -v 4.001
```

Build the base for ARMv7 first, then multiple device images:

```
./build.sh -b armv7
./build.sh -d pi -v 4.001
./build.sh -d odroidc4 -v 4.001
./build.sh -d tinkerboard -v 4.001
```

#### Architecture Notes

ARMv6 vs ARMv7 for Raspberry Pi:

ARMv7 builds are recommended for Pi 2 and newer. They use Debian packages optimized for ARMv7 with Thumb-2 and VFPv3 support. Performance improvement is 10-25% over ARMv6 builds. Supported devices: Pi 2, 3, 3+, 4, 400, 5, 500, 500+, Zero 2 W, CM3, CM3+, CM4, CM5.

ARMv6 builds provide legacy support using Raspbian packages for ARMv6 compatibility. Required for: Pi 1 (all models), Pi Zero, Pi Zero W, CM1. These builds will work on newer Pi models but with reduced performance.

Device Recipe BUILD Variable:

Each device recipe defines a BUILD variable that specifies which base architecture it requires. The -b flag creates a base rootfs tarball at build/bookworm/arch_rootfs.lz4. The -d flag uses the device recipe's BUILD variable to find the matching base tarball. The -b architecture must match the device's BUILD variable.

Example: pi.sh contains BUILD="armv7", so you must use -b armv7 when building the Pi base.

#### Sources

Kernel Sources:

* [Raspberry Pi](https://github.com/raspberrypi/linux) - Official Pi kernel
* [Armbian](https://github.com/armbian/build) - Multi-platform ARM kernel support

Main Package Sources:

* [MPD](https://github.com/volumio/MPD) - Music Player Daemon by Max Kellerman
* [Shairport-Sync](https://github.com/volumio/shairport-sync) - AirPlay audio player by Mike Brady
* [Node.JS](https://nodejs.org) - JavaScript runtime
* [SnapCast](https://github.com/badaix/snapcast) - Multi-room audio by Badaix
* [Upmpdcli](https://www.lesbonscomptes.com/upmpdcli/) - UPnP/DLNA renderer by Jean-Francois Dockes

Debian Package Sources:

All Debian-retrieved package sources can be found at the [debian-sources Repository](https://github.com/volumio/debian-sources)

Raspbian Package Sources (ARMv6 builds only):

All Raspbian-retrieved package sources can be found at the [raspbian-sources Repository](https://github.com/volumio/raspbian-sources)

If any information, source package or license is missing, please report it to info at volumio dot org

#### Caching Packages

If you are doing multiple Volumio builds, you can save bandwidth by caching packages with apt-cacher-ng.

Installation Steps:

1. Install apt-cacher-ng package
2. Configure pass-through pattern
3. Enable and start service
4. Fix build.sh bug on line 181
5. Set environment variable
6. Run build with -E flag

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

Verify service:

```
sudo systemctl status apt-cacher-ng
```

Fix build.sh bug at line 181. Remove the exclamation mark.

Current code at line 181:

```
if [[ -n "${APT_CACHE}" ]] && ! curl -sSf "${APT_CACHE}" >/dev/null; then
```

Replace with:

```
if [[ -n "${APT_CACHE}" ]] && curl -sSf "${APT_CACHE}" >/dev/null; then
```

Set environment variable:

```
export APT_CACHE='http://localhost:3142'
```

Run build with environment preserved. The -E flag preserves environment variables when using sudo.

```
sudo -E ./build.sh -b armv7 -d pi -v 4.0
```

Monitor cache activity (optional):

```
sudo tail -f /var/log/apt-cacher-ng/apt-cacher-ng.log
```

Verify configuration:

```
cat build/bookworm/armv7/root/etc/apt/apt.conf.d/02cache
```

Expected output:

```
Acquire::http { Proxy "http://localhost:3142"; };
```

Limitations:

HTTPS repositories cannot be cached due to SSL certificate validation. Only HTTP repositories benefit from caching. Packages downloaded via wget or curl bypass the cache system.

Troubleshooting:

Check if environment variable is set:

```
echo $APT_CACHE
```

Verify service is running:

```
sudo systemctl status apt-cacher-ng
```

Check if port 3142 is listening:

```
sudo netstat -tlnp | grep 3142
```

Confirm build.sh line 181 was modified correctly by checking for the removed exclamation mark.

#### Device Recipe Structure

Device configurations are located in recipes/devices/. Each device recipe defines:

- BUILD variable: Which base architecture to use (arm, armv7, armv8, x64)
- ARCH variable: Debian architecture name (armhf, arm64, amd64)
- Hardware-specific kernel configuration and version
- Boot partition layout and bootloader setup
- Device tree overlays and hardware initialization
- Initramfs customization
- Platform-specific tweaks and optimizations

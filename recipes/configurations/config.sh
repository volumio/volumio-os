#!/usr/bin/env bash
# Location for configuration(s) for rootfs and image creation

declare -A SecureApt=(
  [debian_12.gpg]="https://ftp-master.debian.org/keys/archive-key-12.asc"
  [nodesource.gpg]="https://deb.nodesource.com/gpgkey/nodesource.gpg.key"
  [lesbonscomptes.gpg]="https://www.lesbonscomptes.com/pages/lesbonscomptes.gpg"
  #TODO Not needed for arm64 and x86
  [raspbian.gpg]="https://archive.raspbian.org/raspbian.public.key"
  [raspberrypi.gpg]="http://archive.raspberrypi.com/debian/raspberrypi.gpg.key"
)

# Repo locations that are utilised to create source.list in the rootfs
declare -A APTSOURCE=(
  [Debian]="http://deb.debian.org/debian"
  [Raspbian]="http://raspbian.raspberrypi.com/raspbian/"
)

## Path to the volumio repo
VOLBINSREPO="https://github.com/volumio/volumio3-os-static-assets/raw/master/custom-packages/binaries/"

## Array of volumio binaries
#TODO: Fix naming scheme and repo location
declare -A VOLBINS=(
  [init_updater]="volumio-init-updater-v2"
)

## Array of custom packages
# The expected naming scheme is
# name_version_${BUILD}.deb
# Note the use of $BUILD (arm/armv7/armv8/x86/x64) and not $ARCH(armel/armhf/arm64/i386/amd64) thanks to raspberrypi compatibility naming quirks
declare -A CUSTOM_PKGS=(
  [volumio_remote_updater]="https://github.com/volumio/volumio3-os-static-assets/raw/master/custom-packages/volumio-remote-updater/volumio-remote-updater_1.8.12-1"
    [mpd]="https://github.com/volumio/volumio3-os-static-assets/raw/master/custom-packages/mpd/mpd_0.24.5-2volumio1"
  # [mpc]="https://github.com/volumio/volumio3-os-static-assets/raw/master/custom-packages/mpc/mpc_0.34-2"
    [alsacap]="https://github.com/volumio/volumio3-os-static-assets/raw/master/custom-packages/alsacap/alsacap_1.4-2"
    [bluetooth]="https://github.com/volumio/volumio3-os-static-assets/raw/refs/heads/master/custom-packages/bluetooth/bluez/bluetooth_5.72-1volumio1"
    [bluez]="https://github.com/volumio/volumio3-os-static-assets/raw/refs/heads/master/custom-packages/bluetooth/bluez/bluez_5.72-1volumio1"
    [libbluetooth3]="https://github.com/volumio/volumio3-os-static-assets/raw/refs/heads/master/custom-packages/bluetooth/bluez/libbluetooth3_5.72-1volumio1"
    [bluez-alsa-utils]="https://github.com/volumio/volumio3-os-static-assets/raw/refs/heads/master/custom-packages/bluetooth/alsa-utils/bluez-alsa-utils_4.3.1volumio1"
    [libasound2-plugin]="https://github.com/volumio/volumio3-os-static-assets/raw/refs/heads/master/custom-packages/bluetooth/alsa-utils/libasound2-plugin-bluez_4.3.1volumio1"
)

## Backend and Frontend Repository details
VOL_BE_REPO="https://github.com/volumio/volumio3-backend.git"
VOL_BE_REPO_BRANCH="master"

## NodeJS Controls
# Semver is only used w.t.r modules fetched from repo,
# actual node version installs only respects the current major versions (Major.x)
NODE_VERSION=20.5.1
# Used to pull the right version of modules
# expected format node_modules_{arm/x86}-v${NODE_VERSION}.tar.gz
NODE_MODULES_REPO="https://github.com/volumio/volumio3-os-static-assets/raw/master/node_modules"

## 
# Array of custom ALSA plugins
# The expected naming scheme is
# ${BUILD}-libasound_module_pcm_<name>.so
# Note the use of $BUILD (arm/x86/x64) and not $ARCH(armel/armhf/arm64/i386/amd64) thanks to raspberrypi compatibility naming quirks
declare -A ALSA_PLUGINS=(
  [volumiohook]="https://github.com/volumio/volumio-alsa-hook/releases/download/volumiohook-1.0.1/"
  [volumiofifo]="https://github.com/volumio/volumio-alsa-fifo/releases/download/volumiofifo-1.0.1/"
)

export SecureApt APTSOURCE VOLBINSREPO VOLBINS VOL_BE_REPO VOL_BE_REPO_BRANCH VOL_BE_REPO_SHA NODE_VERSION NODE_MODULES_REPO CUSTOM_PKGS ALSA_PLUGINS

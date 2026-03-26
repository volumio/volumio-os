#!/usr/bin/env bash
# shellcheck disable=SC2034

### Setup for <OEM_PI> device
DEVICE_SUPPORT_TYPE="S" # First letter (Community Porting|Supported Officially|OEM)
DEVICE_STATUS="M"       # First letter (Planned|Test|Maintenance)

# Import the base family configuration
# shellcheck source=./recipes/devices/pi.sh
source "${SRC}"/recipes/devices/pi.sh

# Enable kiosk
KIOSKMODE=yes
KIOSKBROWSER=chromium

## Partition info (same as pi.sh)
BOOT_START=1
BOOT_END=385           # 384 MiB boot partition, aligned
IMAGE_END=4673         # BOOT_END + 4288 MiB (/img squashfs)

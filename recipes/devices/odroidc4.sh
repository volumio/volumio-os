#!/usr/bin/env bash
# shellcheck disable=SC2034

## Setup for Odroid C4 device  (Community Portings)
DEVICE_SUPPORT_TYPE="C" # First letter (Community Porting|Supported Officially|OEM)
DEVICE_STATUS="P"       # First letter (Planned|Test|Maintenance)

# shellcheck source=./recipes/devices/families/odroids.sh
source "${SRC}"/recipes/devices/families/odroids.sh

### Device information
DEVICENAME="Odroid-C4"
DEVICE="odroidc4"

PLYMOUTH_THEME="volumio-adaptive"
DEBUG_IMAGE="yes"

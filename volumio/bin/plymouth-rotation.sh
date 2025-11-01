#!/bin/bash
# Plymouth rotation detection script
# Patches installed Plymouth scripts based on kernel command line parameters
# Both themes use the same plymouth= parameter

CMDLINE=$(cat /proc/cmdline)
ROTATION=0

# Detect plymouth= parameter (for both themes)
if echo "$CMDLINE" | grep -q "plymouth=90"; then ROTATION=90; fi
if echo "$CMDLINE" | grep -q "plymouth=180"; then ROTATION=180; fi
if echo "$CMDLINE" | grep -q "plymouth=270"; then ROTATION=270; fi

# Patch image theme (volumio-adaptive) - uses plymouth_rotation variable
ADAPTIVE_SCRIPT="/usr/share/plymouth/themes/volumio-adaptive/volumio-adaptive.script"
if [ -f "$ADAPTIVE_SCRIPT" ]; then
  sed -i "s/^plymouth_rotation = [0-9]*;/plymouth_rotation = ${ROTATION};/" "$ADAPTIVE_SCRIPT"
fi

# Patch text theme (volumio-text) - uses global.rotation variable
TEXT_SCRIPT="/usr/share/plymouth/themes/volumio-text/volumio-text.script"
if [ -f "$TEXT_SCRIPT" ]; then
  sed -i "s/^global\.rotation = [0-9]*;/global.rotation = ${ROTATION};/" "$TEXT_SCRIPT"
fi

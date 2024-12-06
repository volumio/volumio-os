#!/usr/bin/env bash
# This script check if Volumio kernel nl80211 modules are in the blocked state
# prior use with hostapd. As such, WiFi or Bluetooth interfaces are changed
# from the default "Blocked" state.
set -eo pipefail

#shellcheck source=/dev/null
source /etc/os-release

echo "Volumio WiFi Soft Blocked check script"
echo "Check if rfkill is available"

if [ ! -x /usr/sbin/rfkill ] || [ ! -r /dev/rfkill ]; then
  echo "The rfkill is not present on this system"
  exit 0
fi

echo "Check if rfkill listed devices are already unblocked"

if ! /usr/sbin/rfkill list wifi | grep -q "Soft blocked: yes" ; then
  echo "Wi-Fi is already unblocked."
  exit 0
fi

echo "nl80211 modules are in the blocked state - unblocking"
/usr/sbin/rfkill unblock all
/usr/sbin/rfkill list
exit 0

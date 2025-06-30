#!/usr/bin/env bash
set -eo pipefail

#shellcheck source=/dev/null
source /etc/os-release

echo "Volumio first start configuration script"

echo "Configuring unconfigured packages"
dpkg --configure --pending

echo "Creating /var/log/samba/cores folder"
mkdir -p /var/log/samba/cores && chmod -R 0700 "$_"

if [[ ${VOLUMIO_HARDWARE} == "pi" ]]; then
  echo "Creating /boot/userconfig.txt"
  echo "# Add your custom config.txt options to this file, which will be preserved during updates" > /boot/userconfig.txt
fi

echo "Disabling systemd alsa services"
systemctl disable alsa-restore.service
systemctl disable alsa-state.service

echo "Blocking systemd alsa services"
systemctl mask alsa-restore.service
systemctl mask alsa-state.service

echo "Removing default SSH host keys"
# These should be created on first boot to ensure they are unique on each system
rm -v /etc/ssh/ssh_host_*

echo "Generating SSH host keys"
dpkg-reconfigure openssh-server

echo "Enabling SSH for first boot"
systemctl start ssh.service

echo "Disabling firststart service"
systemctl disable firststart.service

echo "Finalizing"
sync

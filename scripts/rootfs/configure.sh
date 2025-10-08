#!/usr/bin/env bash
# Copy configuration files into rootfs post chroot configuration

set -eo pipefail
function exit_error() {
  log "Volumio config failed" "err" "echo ""${1}" "$(basename "$0")"""
}

trap 'exit_error ${LINENO}' INT ERR

log "Copying Custom Volumio System Files" "info"

log "Copying ${BUILD} related Configuration files"
if [[ ${BUILD:0:3} == arm ]]; then
  log 'Setting time for ARM devices with fakehwclock to build time'
  date -u '+%Y-%m-%d %H:%M:%S' >"${ROOTFS}/etc/fake-hwclock.data"
fi

log "Copying misc config/tweaks to rootfs" "info"
# TODO: Streamline this!!
# map files from ${SRC}/volumio => ${ROOTFS}?
#

#Edimax Power Saving Fix + Alsa modprobe
cp -r "${SRC}/volumio/etc/modprobe.d" "${ROOTFS}/etc/"

#Samba conf file
cp "${SRC}/volumio/etc/samba/smb.conf" "${ROOTFS}/etc/samba/smb.conf"

#Udev confs file (NET)
cp -r "${SRC}/volumio/etc/udev" "${ROOTFS}/etc/"

# errors cp: cannot create regular file './build/bookworm/armv8/root/etc/polkit-1/localauthority/50-local.d/50-mount-as-pi.pkla': No such file or directory
# cp -r "${SRC}/volumio/etc/polkit-1/localauthority/50-local.d/50-mount-as-pi.pkla" \
#   "${ROOTFS}/etc/polkit-1/localauthority/50-local.d/50-mount-as-pi.pkla"

#SSH
cp "${SRC}/volumio/etc/ssh/sshd_config" "${ROOTFS}/etc/ssh/sshd_config"

#Mpd
cp "${SRC}/volumio/etc/mpd.conf" "${ROOTFS}/etc/mpd.conf"
chmod 777 "${ROOTFS}/etc/mpd.conf"

#Log via JournalD in RAM
cp "${SRC}/volumio/etc/systemd/journald.conf" "${ROOTFS}/etc/systemd/journald.conf"

#Volumio SystemD Services
# The amount of time I've spend debugging strange things only to realise we overwrite everything with these files.
# cp -r "${SRC}"/volumio/lib "${ROOTFS}"/
for service in "${SRC}"/volumio/lib/systemd/system/*.service; do
  log "Copying ${service}" 
  cp  "${service}" "${ROOTFS}"/lib/systemd/system/
done

for target in "${SRC}"/volumio/lib/systemd/system/*.target; do
  log "Copying ${target}" 
  cp  "${target}" "${ROOTFS}"/lib/systemd/system/
done

# Network
cp -r "${SRC}"/volumio/etc/network/* "${ROOTFS}"/etc/network

# nl80211 modules blocking state
cp "${SRC}/volumio/bin/volumio_rfkill_unblock.sh" "${ROOTFS}/bin/volumio_rfkill_unblock.sh"
chmod a+x "${ROOTFS}/bin/volumio_rfkill_unblock.sh"

# Wpa Supplicant
echo " " >"${ROOTFS}"/etc/wpa_supplicant/wpa_supplicant.conf
chmod 777 "${ROOTFS}"/etc/wpa_supplicant/wpa_supplicant.conf

#nsswitch
cp "${SRC}/volumio/etc/nsswitch.conf" "${ROOTFS}/etc/nsswitch.conf"

#firststart
cp "${SRC}/volumio/bin/firststart.sh" "${ROOTFS}/bin/firststart.sh"

#dynswap
cp "${SRC}/volumio/bin/dynswap.sh" "${ROOTFS}/bin/dynswap.sh"

#udev scripts
cp "${SRC}/volumio/bin/rename_netiface0.sh" "${ROOTFS}/bin/rename_netiface0.sh"
chmod a+x "${ROOTFS}/bin/rename_netiface0.sh"

cp "${SRC}/volumio/bin/th-udev-rebind.sh" "${ROOTFS}/bin/th-udev-rebind.sh"
chmod a+x "${ROOTFS}/bin/th-udev-rebind.sh"

#Plymouth & upmpdcli files
cp -rp "${SRC}"/volumio/usr/* "${ROOTFS}/usr/"

#CPU TWEAK
cp "${SRC}/volumio/bin/volumio_cpu_tweak" "${ROOTFS}/bin/volumio_cpu_tweak"
chmod a+x "${ROOTFS}/bin/volumio_cpu_tweak"

#MPD Monitor
cp "${SRC}/volumio/bin/mpd_monitor.sh" "${ROOTFS}/bin/mpd_monitor.sh"
chmod a+x "${ROOTFS}/bin/mpd_monitor.sh"

#Welcome
cp "${SRC}/volumio/bin/welcome" "${ROOTFS}/bin/welcome"
chmod a+x "${ROOTFS}/bin/welcome"

#LAN HOTPLUG
cp "${SRC}/volumio/etc/default/ifplugd" "${ROOTFS}/etc/default/ifplugd"

#LAN HOTPLUG IFUPD SCRIPT
cp "${SRC}/volumio/etc/ifplugd/action.d/eth0-status" "${ROOTFS}/etc/ifplugd/action.d/eth0-status"
chmod a+x "${ROOTFS}/etc/ifplugd/action.d/eth0-status"

#TRIGGERHAPPY
cp "${SRC}/volumio/etc/triggerhappy/triggers.d/audio.conf" "${ROOTFS}/etc/triggerhappy/triggers.d/audio.conf"

#VOLUMIO LOG ROTATE
cp -rp "${SRC}/volumio/bin/volumiologrotate" "${ROOTFS}/bin/volumiologrotate"

#VOLUMIO TIME HELPER
cp -rp "${SRC}/volumio/bin/setdatetime-helper.sh" "${ROOTFS}/bin/setdatetime-helper.sh"
chmod a+x "${ROOTFS}/bin/setdatetime-helper.sh"

for timer in "${SRC}"/volumio/lib/systemd/system/*.timer ; do
  log "Copying ${timer}" 
  cp  "${timer}" "${ROOTFS}"/lib/systemd/system/
done

for path in "${SRC}"/volumio/lib/systemd/system/*.path; do
  log "Copying ${path}" 
  cp  "${path}" "${ROOTFS}"/lib/systemd/system/
done

log 'Done Copying Custom Volumio System Files' "okay"

#VOLUMIO SERVICES OVERRIDE
log "Volumio Service Overrides" "info"
for override in "${SRC}"/volumio/etc/systemd/system/*/*.conf; do
  log "Copying ${override}"
  relpath="${override#${SRC}/volumio/}"  # strip leading prefix
  mkdir -p "${ROOTFS}/$(dirname "${relpath}")"
  cp "${override}" "${ROOTFS}/${relpath}"
done

# ALSA RESTORE OVERRIDE HELPER SCRIPT
cp -rp "${SRC}/volumio/bin/wait-for-cards.sh" "${ROOTFS}/usr/bin/wait-for-cards.sh"
chmod a+x "${ROOTFS}/usr/bin/wait-for-cards.sh"

log 'Done Volumio Service Overrides' "okay"

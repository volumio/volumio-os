#!/usr/bin/env bash
set -eo pipefail

CMP_NAME=$(basename "$(dirname "${BASH_SOURCE[0]}")")
CMP_NAME=volumio-kiosk-vivaldi-wayland
log "Installing $CMP_NAME" "ext"

#shellcheck source=/dev/null
source /etc/os-release
export DEBIAN_FRONTEND=noninteractive

# ----------------------------------------------------------------------------
# Package list
# ----------------------------------------------------------------------------
# Wayland kiosk stack: labwc compositor + Vivaldi via Ozone/Wayland.
# Notably absent vs X.Org variant: xserver-xorg-core, xinit, openbox,
# x11-xserver-utils, xserver-xorg-input-libinput, xinput, unclutter.
# Touch + libinput integration is built into wlroots; cursor hiding is
# handled by labwc rc.xml on F24 keybind.
CMP_PACKAGES=(
  # Keyboard config
  "keyboard-configuration"
  # Wayland compositor
  "labwc"                 # Compositor (wlroots based)
  "wlr-randr"             # Output transform / rotation tool
  "wtype"                 # Send synthetic key events (used to fire HideCursor)
  "dbus-user-session"     # Per-session dbus required by labwc/vivaldi
  # Browser GTK / a11y / nss runtime deps
  "fonts-liberation" "libatk-bridge2.0-0" "libatk1.0-0" "libatspi2.0-0"
  "libgtk-3-0" "libnspr4" "libnss3" "xdg-utils" "libexif12"
  "libu2f-udev" "libvulkan1"
  # CJK and international font support for kiosk UI
  # NOTE: These add ~30M installed. If international UI support is not needed
  # for a specific OEM build, these can be omitted to save space.
  "fonts-arphic-ukai" "fonts-arphic-gbsn00lp" "fonts-unfonts-core"
  "fonts-ipafont" "fonts-vlgothic" "fonts-thai-tlwg-ttf"
)

log "Installing ${#CMP_PACKAGES[@]} ${CMP_NAME} packages:" "" "${CMP_PACKAGES[*]}"
apt-get install -y "${CMP_PACKAGES[@]}" --no-install-recommends

log "${CMP_NAME} Dependencies installed!"

# ----------------------------------------------------------------------------
# Vivaldi install (same prebuilt deb as X.Org variant)
# ----------------------------------------------------------------------------
log "Download Vivaldi"
cd /home/volumio/
wget https://github.com/volumio/volumio3-os-static-assets/raw/master/browsers/vivaldi/vivaldi-stable_7.5.3735.74-1_armhf.deb

log "Install Vivaldi"
sudo dpkg -i /home/volumio/vivaldi-*.deb
sudo apt-get install -y -f --no-install-recommends
sudo dpkg -i /home/volumio/vivaldi-*.deb
rm /home/volumio/vivaldi-*.deb

log "Cleaning Vivaldi Apt Sources"
rm /etc/apt/sources.list.d/vivaldi.list

# ----------------------------------------------------------------------------
# Vivaldi user-data dir + initial Preferences
# ----------------------------------------------------------------------------
log "Creating ${CMP_NAME} dirs and initial Preferences"
mkdir -p /data/volumiokiosk/Default
echo '{"credentials_enable_service": false, "profile": {"password_manager_enabled": false}}' \
  > /data/volumiokiosk/Default/Preferences

# ----------------------------------------------------------------------------
# /opt/volumiokiosk-launch.sh
# Top-level launcher started by systemd. Waits for backend curl 200, then
# touches the marker that releases plymouth-quit, then execs the compositor
# with the session script.
# ----------------------------------------------------------------------------
log "Creating ${CMP_NAME} launcher script"
cat > /opt/volumiokiosk-launch.sh <<'LAUNCHER'
#!/bin/sh
set -e

# XDG_RUNTIME_DIR for root session (kiosk runs as root)
mkdir -p /run/user/0
chmod 700 /run/user/0
export XDG_RUNTIME_DIR=/run/user/0
export HOME=/root

mkdir -p /data/volumiokiosk

# Vivaldi singleton + crash-flag housekeeping. Required to allow restart
# without reboot when the previous instance was killed (matches X.Org variant).
if [ -L /data/volumiokiosk/SingletonCookie ]; then
  rm -rf /data/volumiokiosk/Singleton*
fi
if [ -e /data/volumiokiosk/Default/Preferences ]; then
  sed -i 's/"exited_cleanly":false/"exited_cleanly":true/' /data/volumiokiosk/Default/Preferences
  sed -i 's/"exit_type":"Crashed"/"exit_type":"None"/' /data/volumiokiosk/Default/Preferences
  sed -i 's/"credentials_enable_service":true/"credentials_enable_service":false/' /data/volumiokiosk/Default/Preferences
fi

# First-run delay (mirrors X.Org variant) - on a brand new install give the
# backend extra room to settle before kiosk starts polling.
if [ ! -f /data/volumiokiosk/firststartdone ]; then
  echo "[kiosk-launch] first start, allowing backend extra startup time"
  sleep 15
  touch /data/volumiokiosk/firststartdone
fi

# Synchronous wait for backend HTTP. Plymouth stays visible until this returns
# because plymouth-quit.service has a drop-in that gates on the marker file.
echo "[kiosk-launch] waiting for backend"
while [ "$(curl -Is http://127.0.0.1:3000 | head -n 1 | cut -d ' ' -f 2)" != "200" ]; do
  sleep 1
done
echo "[kiosk-launch] backend up"

# Release plymouth-quit
touch /run/volumio-kiosk-ready

# Hand off to compositor
exec dbus-run-session -- labwc -C /etc/xdg/labwc -s /opt/volumiokiosk-session.sh
LAUNCHER
chmod +x /opt/volumiokiosk-launch.sh

# ----------------------------------------------------------------------------
# /opt/volumiokiosk-session.sh
# Inside-labwc startup. Reads plymouth rotation from kernel cmdline so the
# same script works on landscape HDMI and portrait DSI devices.
# ----------------------------------------------------------------------------
log "Creating ${CMP_NAME} session script"
cat > /opt/volumiokiosk-session.sh <<'SESSION'
#!/bin/sh
# Apply output rotation matching plymouth's. plymouth=N kernel param drives both.
PLY_ROT=$(grep -oP 'plymouth=\K\d+' /proc/cmdline 2>/dev/null || echo 0)
case "$PLY_ROT" in
  90|180|270)
    OUTPUT=$(wlr-randr 2>/dev/null | awk '/^[A-Za-z]/{print $1; exit}')
    if [ -n "$OUTPUT" ]; then
      wlr-randr --output "$OUTPUT" --transform "$PLY_ROT" || true
    fi
    ;;
esac

# Hide the cursor by firing the F24 keybind that labwc rc.xml maps to HideCursor
wtype -k F24 &

SCALE_FACTOR=1.2
[ -f /data/browserargs ] && . /data/browserargs

exec /usr/bin/vivaldi \
  --ozone-platform=wayland \
  --enable-features=UseOzonePlatform \
  --kiosk \
  --no-sandbox \
  --disable-background-networking \
  --disable-remote-extensions \
  --disable-pinch \
  --disable-features=GoogleCloudMessaging,Translate \
  --ignore-gpu-blocklist \
  --use-gl=angle --use-angle=gles \
  --enable-gpu-rasterization \
  --enable-zero-copy \
  --enable-scroll-prediction \
  --user-agent="volumiokiosk-touch" \
  --touch-events \
  --user-data-dir=/data/volumiokiosk \
  --force-device-scale-factor="$SCALE_FACTOR" \
  --load-extension=/data/volumiokioskextensions/VirtualKeyboard/ \
  --no-first-run \
  --default-background-color=000000 \
  --app=file:///opt/volumio-splash.html
SESSION
chmod +x /opt/volumiokiosk-session.sh

# ----------------------------------------------------------------------------
# /opt/volumio-splash.html
# Black holding page. Loads localhost:3000 in a hidden iframe; only fades the
# iframe in once the page has loaded (+ 1.2s settle for Angular mount). Hides
# the white-during-page-load that would otherwise appear during navigation.
# ----------------------------------------------------------------------------
log "Creating ${CMP_NAME} splash page"
cat > /opt/volumio-splash.html <<'SPLASH'
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<style>
html, body {
  margin: 0;
  padding: 0;
  height: 100vh;
  width: 100vw;
  overflow: hidden;
  background: #000;
}
iframe {
  display: block;
  width: 100%;
  height: 100%;
  border: 0;
  background: #000;
  visibility: hidden;
  opacity: 0;
  transition: opacity 600ms ease;
  position: absolute;
  inset: 0;
}
iframe.ready { visibility: visible; opacity: 1; }
</style>
</head>
<body>
<iframe id="k" src="http://127.0.0.1:3000"></iframe>
<script>
const f = document.getElementById("k");
f.addEventListener("load", () => setTimeout(() => f.classList.add("ready"), 1200));
</script>
</body>
</html>
SPLASH

# ----------------------------------------------------------------------------
# /etc/xdg/labwc/rc.xml
# Minimal labwc config: client-side decoration, F24 keybind for HideCursor.
# No autostart - that's handled by the explicit -s argument from the launcher.
# Output transform is NOT set here; rc.xml output element is ignored upstream
# and wlr-randr is the supported path.
# ----------------------------------------------------------------------------
log "Creating labwc rc.xml"
mkdir -p /etc/xdg/labwc
cat > /etc/xdg/labwc/rc.xml <<'LABWC'
<?xml version="1.0"?>
<labwc_config>
  <core>
    <decoration>client</decoration>
  </core>
  <keyboard>
    <default/>
    <keybind key="F24">
      <action name="HideCursor"/>
    </keybind>
  </keyboard>
</labwc_config>
LABWC

# ----------------------------------------------------------------------------
# /lib/systemd/system/volumio-kiosk.service
# ----------------------------------------------------------------------------
# Notes on the TTY directives:
#   TTYPath/TTYReset/TTYVHangup yes - hand /dev/tty1 cleanly to the compositor
#     and reset it on stop so a subsequent restart starts fresh.
#   TTYVTDisallocate=no - DO NOT release the VT on stop. Setting this to yes
#     fights plymouth-reboot.service for the framebuffer during shutdown and
#     prevents the shutdown plymouth splash from appearing.
# Notes on KillMode/ExecStopPost:
#   Vivaldi/Chromium daemonises children via setsid; they escape the unit's
#   cgroup. Without explicit cleanup a service restart leaves multiple
#   compositor + browser trees running. ExecStopPost reaps them.
# ----------------------------------------------------------------------------
log "Creating ${CMP_NAME} systemd unit"
cat > /lib/systemd/system/volumio-kiosk.service <<'UNIT'
[Unit]
Description=Volumio Kiosk (labwc + vivaldi-wayland)
Wants=volumio.service volumio-kiosk-preload.service
After=volumio-kiosk-preload.service volumio.service systemd-user-sessions.service

[Service]
Type=simple
User=root
Group=root
PAMName=login
TTYPath=/dev/tty1
TTYReset=yes
TTYVHangup=yes
TTYVTDisallocate=no
StandardInput=tty
StandardOutput=journal
StandardError=journal
UtmpIdentifier=tty1
UtmpMode=user
Environment=XDG_SESSION_TYPE=wayland
Environment=XDG_SESSION_CLASS=user
Environment=HOME=/root
Nice=-10
ExecStart=/opt/volumiokiosk-launch.sh
ExecStopPost=/bin/sh -c 'pkill -9 -f vivaldi-bin ; pkill -9 -f labwc ; pkill -9 -f dbus-run-session ; rm -f /run/volumio-kiosk-ready ; rm -f /run/user/0/wayland-0 /run/user/0/wayland-0.lock'
KillMode=mixed
KillSignal=SIGTERM
SendSIGKILL=yes
TimeoutStopSec=5
TimeoutSec=300
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT

# ----------------------------------------------------------------------------
# /lib/systemd/system/volumio-kiosk-preload.service
# Reads the vivaldi binary + key shared libs into page cache early in boot,
# in parallel with backend init. By the time the kiosk launcher finishes
# waiting for the backend and exec's labwc/vivaldi, the binary is in RAM.
# Reduces vivaldi cold-start by ~2s on SD-backed devices.
# ----------------------------------------------------------------------------
log "Creating ${CMP_NAME} preload unit"
cat > /lib/systemd/system/volumio-kiosk-preload.service <<'PRELOAD'
[Unit]
Description=Preload Vivaldi binary into page cache
DefaultDependencies=no
After=local-fs.target
Before=volumio-kiosk.service

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'cat /opt/vivaldi/vivaldi-bin /opt/vivaldi/chrome_crashpad_handler /opt/vivaldi/libGLESv2.so /opt/vivaldi/libEGL.so /opt/vivaldi/libvulkan.so.1 > /dev/null 2>&1 || true'
IOSchedulingClass=idle
Nice=19
TimeoutSec=60
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
PRELOAD

# ----------------------------------------------------------------------------
# Drop-ins for plymouth-quit / plymouth-quit-wait
# Hold the splash visible until the kiosk has touched the marker file.
# Drop-ins are used instead of overwriting the upstream
# volumio/framebuffer/systemd/system/plymouth-quit.service so the existing
# KMS DRM service stays the source of truth and only behavior specific to
# this kiosk variant lives here.
# ----------------------------------------------------------------------------
log "Creating plymouth-quit drop-ins"
mkdir -p /etc/systemd/system/plymouth-quit.service.d
cat > /etc/systemd/system/plymouth-quit.service.d/wait-for-kiosk.conf <<'DROPIN_QUIT'
[Service]
ExecStartPre=/bin/bash -c 'until [ -e /run/volumio-kiosk-ready ]; do sleep 0.5; done'
TimeoutStartSec=300
DROPIN_QUIT

mkdir -p /etc/systemd/system/plymouth-quit-wait.service.d
cat > /etc/systemd/system/plymouth-quit-wait.service.d/wait-for-kiosk.conf <<'DROPIN_WAIT'
[Service]
ExecStartPre=/bin/bash -c 'until [ -e /run/volumio-kiosk-ready ]; do sleep 0.5; done'
TimeoutStartSec=300
DROPIN_WAIT

# ----------------------------------------------------------------------------
# Enable units
# ----------------------------------------------------------------------------
log "Enabling ${CMP_NAME} units"
ln -sf /lib/systemd/system/volumio-kiosk.service \
  /etc/systemd/system/multi-user.target.wants/volumio-kiosk.service
ln -sf /lib/systemd/system/volumio-kiosk-preload.service \
  /etc/systemd/system/multi-user.target.wants/volumio-kiosk-preload.service

# ----------------------------------------------------------------------------
# Virtual keyboard extension
# ----------------------------------------------------------------------------
log "Installing Virtual Keyboard"
mkdir -p /data/volumiokioskextensions
git clone https://github.com/volumio/chrome-virtual-keyboard-v3.git \
  /data/volumiokioskextensions/VirtualKeyboard

# ----------------------------------------------------------------------------
# Volumio backend plugin config tweaks (matches X.Org variant)
# ----------------------------------------------------------------------------
log "Setting HDMI UI enabled by default"
config_path="/volumio/app/plugins/system_controller/system/config.json"
#shellcheck disable=SC2094
cat <<<"$(jq '.hdmi_enabled={value:true, type:"boolean"}' ${config_path})" >${config_path}

log "Show HDMI output selection"
echo '[{"value": false,"id":"section_hdmi_settings","attribute_name": "hidden"},{"value": false,"id":"hdmi_enabled","attribute_name": "hidden"}]' \
  >/volumio/app/plugins/system_controller/system/override.json

log "Disable login prompt before browser starts"
systemctl disable getty@tty1.service

# ----------------------------------------------------------------------------
# Per-device touchscreen tweaks. Cursor is hidden by labwc HideCursor on F24
# regardless of device, so unlike the X.Org variant there is no /data/kioskargs
# `-nocursor` flag to write. We just hide the HDMI output selector on
# integrated-touchscreen devices.
# ----------------------------------------------------------------------------
if [[ ${VOLUMIO_HARDWARE} = cm4 || ${VOLUMIO_HARDWARE} = pi-kiosk ]]; then
  log "Hide HDMI output selection"
  echo '[{"value": false,"id":"section_hdmi_settings","attribute_name": "hidden"},{"value": true,"id":"hdmi_enabled","attribute_name": "hidden"},{"value": false,"id":"show_mouse_pointer","attribute_name": "hidden"}]' \
    >/volumio/app/plugins/system_controller/system/override.json
fi

log "${CMP_NAME} install complete" "okay"

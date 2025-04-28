#!/usr/bin/env bash
set -eo pipefail

CMP_NAME=$(basename "$(dirname "${BASH_SOURCE[0]}")")
CMP_NAME=volumio-kiosk
log "Installing $CMP_NAME" "ext"

#shellcheck source=/dev/null
source /etc/os-release
export DEBIAN_FRONTEND=noninteractive

# Some (more) raspbian specific schenanigans
BrowerPckg="chromium"
[[ ${ID} == raspbian ]] && BrowerPckg+="-browser"

CMP_PACKAGES=(
  # Keyboard config
  "keyboard-configuration"
  # Display stuff
  "openbox" "unclutter" "xorg" "xinit"
  # Browser
  # TODO: Why not firefox? it seems to work OTB on most devices with less hassle?
  "${BrowerPckg}" "chromium-l10n"
  # Fonts
  "fonts-arphic-ukai" "fonts-arphic-gbsn00lp" "fonts-unfonts-core"
  # Fonts for Japanese and Thai languages
  "fonts-ipafont" "fonts-vlgothic" "fonts-thai-tlwg-ttf"
  # On-Screen Keyboard
  "onboard"
)

log "Installing ${#CMP_PACKAGES[@]} ${CMP_NAME} packages:" "" "${CMP_PACKAGES[*]}"
apt-get install -y "${CMP_PACKAGES[@]}" --no-install-recommends

log "${CMP_NAME} Dependencies installed!"

log "Creating ${CMP_NAME} dirs and scripts"
mkdir -p /data/volumiokiosk/onboard

log "Creating Onboard configuration files"

# Create large screen Onboard config
cat <<-EOF >/data/volumiokiosk/onboard/onboard-large.conf
[Window]
x=100
y=800
width=800
height=250
fullscreen=false
keep-aspect=false
keep-visible=true
window-state=normal
keep-above=true
transparent-background=true
background-transparency=0.10
dockx=0
docky=0
dock-width=0
dock-height=0
dock-fixed=false
sticky=true

[Layout]
layout-id=Default
system-default-layout=false
show-toolbars=false
show-floating-icon=false

[Keyboard]
show-click=true
show-secondary=false
use-right-shift=false
key-label-font="Sans Bold 16"
key-border-width=1
key-border-radius=2
use-theme-colors=true

[AutoShow]
enabled=true
only-in-focus=true
focus-show-mode=always
hide-on-keyboard-focus-loss=true

[TypingAssist]
auto-capitalize=false
auto-correct=false
auto-space=false
auto-punctuate=false
completion-enabled=false
completion-inline=false
predict-enabled=false

[Theme]
theme-id=DarkRoom
use-system-theme=false

[Advanced]
show-status-icon=false
disable-internal-settings=true
EOF

# Create small screen Onboard config
cat <<-EOF >/data/volumiokiosk/onboard/onboard-small.conf
[Window]
x=0
y=600
width=600
height=200
fullscreen=false
keep-aspect=false
keep-visible=true
window-state=normal
keep-above=true
transparent-background=true
background-transparency=0.10
dockx=0
docky=0
dock-width=0
dock-height=0
dock-fixed=false
sticky=true

[Layout]
layout-id=Small
system-default-layout=false
show-toolbars=false
show-floating-icon=false

[Keyboard]
show-click=true
show-secondary=false
use-right-shift=false
key-label-font="Sans Bold 14"
key-border-width=1
key-border-radius=2
use-theme-colors=true

[AutoShow]
enabled=true
only-in-focus=true
focus-show-mode=always
hide-on-keyboard-focus-loss=true

[TypingAssist]
auto-capitalize=false
auto-correct=false
auto-space=false
auto-punctuate=false
completion-enabled=false
completion-inline=false
predict-enabled=false

[Theme]
theme-id=DarkRoom
use-system-theme=false

[Advanced]
show-status-icon=false
disable-internal-settings=true
EOF

# A lot of these flags are wrong/deprecated/not required
# eg. https://chromium.googlesource.com/chromium/src/+/4baa4206fac22a91b3c76a429143fc061017f318
# Translate: remove --disable-translate flag

CHROMIUM_FLAGS=(
  "--kiosk"
  "--touch-events"
  "--enable-touchview"
  "--enable-pinch"
  "--window-position=0,0"
  "--disable-session-crashed-bubble"
  "--disable-infobars"
  "--disable-sync"
  "--no-first-run"
  "--no-sandbox"
  "--user-data-dir='/data/volumiokiosk'"
  "--disable-background-networking"
  "--enable-remote-extensions"
  "--enable-native-gpu-memory-buffers"
  "--disable-quic"
  "--enable-fast-unload"
  "--enable-tcp-fast-open"
  "--autoplay-policy=no-user-gesture-required"
)

if [[ ${BUILD:0:3} != 'arm' ]]; then
  log "Adding additional chromium flags for x86"
  # Again, these flags probably need to be revisited and checked!
  CHROMIUM_FLAGS+=(
    #GPU
    "--ignore-gpu-blacklist"
    "--use-gl=desktop"
    "--force-gpu-rasterization"
    "--enable-zero-copy"
  )
fi

log "Adding ${#CHROMIUM_FLAGS[@]} Chromium flags"

#TODO: Instead of all this careful escaping, make a simple template and add in CHROMIUM_FLAGS?
cat <<-EOF >/opt/volumiokiosk.sh
#!/usr/bin/env bash
#set -eo pipefail
exec >/var/log/volumiokiosk.log 2>&1

echo "Starting Kiosk"
start=\$(date +%s)

export DISPLAY=:0
# in case we want to cap hires monitors (e.g. 4K) to HD (1920x1080)
#CAPPEDRES="1920x1080"
#SUPPORTEDRES="$(xrandr | grep $CAPPEDRES)"
#if [ -z "$SUPPORTEDRES" ]; then
#  echo "Resolution $CAPPEDRES not found, skipping"
#else
#  echo "Capping resolution to $CAPPEDRES"
#  xrandr -s "$CAPPEDRES"
#fi

#TODO xpdyinfo does not work on a fresh install (freezes), skipping it just now
#Perhaps xrandr can be parsed instead? (Needs DISPLAY:=0 to be exported first)
#res=\$(xdpyinfo | awk '/dimensions:/ { print \$2; exit }')
#res=\${res/x/,}
#echo "Current probed resolution: \${res}"

xset -dpms
xset s off

[[ -e /data/volumiokiosk/Default/Preferences ]] && {
  sed -i 's/"exited_cleanly":false/"exited_cleanly":true/' /data/volumiokiosk/Default/Preferences
  sed -i 's/"exit_type":"Crashed"/"exit_type":"None"/' /data/volumiokiosk/Default/Preferences
}

if [ -L /data/volumiokiosk/SingletonCookie ]; then
  rm -rf /data/volumiokiosk/Singleton*
fi

if [ ! -f /data/volumiokiosk/firststartdone ]; then
  echo "Volumio Kiosk Starting for the first time, giving time for Volumio To start"
  sleep 15
  touch /data/volumiokiosk/firststartdone
fi


# Wait for Volumio webUI to be available
while true; do timeout 5 bash -c "</dev/tcp/127.0.0.1/3000" >/dev/null 2>&1 && break; done
echo "Waited \$((\$(date +%s) - start)) sec for Volumio UI"

# Start Openbox
openbox-session &

# Detect screen width dynamically
screen_width=\$(xrandr | grep '*' | awk '{print \$1}' | cut -d 'x' -f1 | head -n1)

# Launch Onboard depending on detected screen width
if [[ -n "\$screen_width" && "\$screen_width" -le 1024 ]]; then
  echo "Detected small screen (\$screen_width px), using minimal Onboard config."
  onboard --config-file=/data/volumiokiosk/onboard/onboard-small.conf &
else
  echo "Detected large screen (\$screen_width px), using standard Onboard config."
  onboard --config-file=/data/volumiokiosk/onboard/onboard-large.conf &
fi

# Start Chromium browser
/usr/bin/chromium \\
$(printf '    %s \\\n' "${CHROMIUM_FLAGS[@]}") \\
    http://localhost:3000
EOF

chmod +x /opt/volumiokiosk.sh

log "Creating Systemd Unit for ${CMP_NAME}"
cat <<-EOF >/lib/systemd/system/volumio-kiosk.service
[Unit]
Description=Start Volumio Kiosk
Wants=volumio.service
After=volumio.service
[Service]
Type=simple
User=root
Group=root
ExecStart=/usr/bin/startx /etc/X11/Xsession /opt/volumiokiosk.sh -- -keeptty
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
EOF

log "Enabling ${CMP_NAME} service"
ln -sf /lib/systemd/system/volumio-kiosk.service /etc/systemd/system/multi-user.target.wants/volumio-kiosk.service

log "Setting localhost"
echo '{"localhost": "http://127.0.0.1:3000"}' >/volumio/http/www/app/local-config.json
if [ -d "/volumio/http/www3" ]; then
  echo '{"localhost": "http://127.0.0.1:3000"}' >/volumio/http/www3/app/local-config.json
fi

if [[ ${VOLUMIO_HARDWARE} != motivo ]]; then

  log "Enabling UI for HDMI output selection"
  echo '[{"value": false,"id":"section_hdmi_settings","attribute_name": "hidden"}]' >/volumio/app/plugins/system_controller/system/override.json

  log "Setting HDMI UI enabled by default"
  config_path="/volumio/app/plugins/system_controller/system/config.json"
  # Should be okay right?
  #shellcheck disable=SC2094
  cat <<<"$(jq '.hdmi_enabled={value:true, type:"boolean"}' ${config_path})" >${config_path}
fi

#!/usr/bin/env bash
set -eo pipefail

# =============================================================================
# install-kiosk-wpe.sh
# =============================================================================
# Kiosk browser install script using WPE WebKit (cog) with cage compositor.
#
# Stack: cage (Wayland kiosk compositor) + cog (WPE WebKit launcher)
# Virtual keyboard: simple-keyboard (JS, browser-agnostic, injected at build)
#
# Eliminates: X11, openbox, Chromium/Vivaldi, Chrome extension keyboard
# Requires: DRM/KMS (vc4-kms-v3d), Pi/ARM Bookworm
#
# Architecture note - Pi 5 (BCM2712):
#   Pi 5 splits GPU rendering (v3d) and display output (rp1-dsi/vc4) across
#   separate DRM devices. cog's DRM platform plugin cannot bridge them.
#   cage (wlroots-based kiosk compositor) handles this transparently.
#   On Pi 4/CM4 (single DRM device) cage also works correctly.
#
# Build system integration:
#   Device recipe sets KIOSKBROWSER=wpe
#   makeimage.sh copies this script into chroot as /install-kiosk.sh
#   chrootconfig.sh executes it
# =============================================================================

CMP_NAME=$(basename "$(dirname "${BASH_SOURCE[0]}")")
CMP_NAME=volumio-kiosk-wpe
log "Installing $CMP_NAME" "ext"

#shellcheck source=/dev/null
source /etc/os-release
export DEBIAN_FRONTEND=noninteractive

# =============================================================================
# PACKAGES
# =============================================================================
# No X11, no window manager, no multi-process browser.
# cage: ~200KB kiosk Wayland compositor (wlroots-based, DRM/KMS direct)
# wlr-randr: ~20KB output configuration tool for wlroots compositors
# cog: ~78KB WPE WebKit launcher (pulls in libwpewebkit ~16.5MB)
# =============================================================================

CMP_PACKAGES=(
  # Wayland kiosk compositor and tools
  "cage"                        # Kiosk Wayland compositor - single app fullscreen
  "wlr-randr"                   # Output rotation for wlroots compositors
  # WPE WebKit browser
  "cog"                         # WPE WebKit launcher (depends: libwpewebkit, libwpebackend-fdo)
  # Keyboard config
  "keyboard-configuration"
  # CJK and international font support for kiosk UI
  # NOTE: These add ~30M installed. If international UI support is not needed
  # for a specific OEM build, these can be omitted to save space.
  "fonts-arphic-ukai" "fonts-arphic-gbsn00lp" "fonts-unfonts-core"
  "fonts-ipafont" "fonts-vlgothic" "fonts-thai-tlwg-ttf"
)

log "Installing ${#CMP_PACKAGES[@]} ${CMP_NAME} packages:" "" "${CMP_PACKAGES[*]}"
apt-get install -y "${CMP_PACKAGES[@]}" --no-install-recommends

log "${CMP_NAME} Dependencies installed!"

# =============================================================================
# KIOSK DATA DIRECTORY
# =============================================================================

log "Creating ${CMP_NAME} dirs"
mkdir -p /data/volumiokiosk

# =============================================================================
# VIRTUAL KEYBOARD - SIMPLE-KEYBOARD (JS, BROWSER-AGNOSTIC)
# =============================================================================
# Instead of a Chrome extension, the virtual keyboard is a JS library injected
# into the Volumio UI HTML at build time. Works with any browser engine.
#
# Assets:
#   index.min.js          - simple-keyboard core (~107KB, MIT)
#   index.css             - simple-keyboard base CSS (~3KB)
#   layouts.min.js        - simple-keyboard-layouts, all languages (~280KB, MIT)
#   vkb-init.js           - bootstrapper with i18n, Volumio integration
#   vkb-layouts-custom.js - layouts for da, hr, sk, vi (not in package)
#   vkb-theme.css         - Volumio dark theme overrides
# =============================================================================

# Pinned versions for build reproducibility
# TODO: Host these on volumio3-os-static-assets for offline builds
VKB_VERSION="3.8.125"
VKB_LAYOUTS_VERSION="3.4.188"

log "Installing ${CMP_NAME} Virtual Keyboard (simple-keyboard ${VKB_VERSION})"

# Common asset directory - symlinked into each UI variant
VKB_DIR="/volumio/http/virtualkeyboard"
mkdir -p "${VKB_DIR}"

log "Downloading simple-keyboard core"
wget -nv -O "${VKB_DIR}/index.min.js" \
  "https://cdn.jsdelivr.net/npm/simple-keyboard@${VKB_VERSION}/build/index.min.js"

wget -nv -O "${VKB_DIR}/index.css" \
  "https://cdn.jsdelivr.net/npm/simple-keyboard@${VKB_VERSION}/build/css/index.css"

log "Downloading simple-keyboard-layouts"
wget -nv -O "${VKB_DIR}/layouts.min.js" \
  "https://cdn.jsdelivr.net/npm/simple-keyboard-layouts@${VKB_LAYOUTS_VERSION}/build/index.min.js"

# ---- vkb-layouts-custom.js ----
# Custom keyboard layouts for Volumio languages not covered by the
# simple-keyboard-layouts package: Danish, Croatian, Slovak, Vietnamese.
# Standard physical keyboard layouts from ISO 9995 specifications.
log "Creating custom keyboard layouts"
cat << 'VKB_CUSTOM_LAYOUTS_EOF' > "${VKB_DIR}/vkb-layouts-custom.js"
(function() {
  "use strict";
  window.VkbCustomLayouts = {
    danish: {
      layout: {
        "default": [
          "\u00a7 1 2 3 4 5 6 7 8 9 0 + \u00b4 {bksp}",
          "q w e r t y u i o p \u00e5 \u00a8",
          "{lock} a s d f g h j k l \u00e6 \u00f8 ' {enter}",
          "{shift} < z x c v b n m , . - {shift}",
          "{lang} {space}"
        ],
        "shift": [
          "\u00bd ! \" # \u00a4 % & / ( ) = ? ` {bksp}",
          "Q W E R T Y U I O P \u00c5 ^",
          "{lock} A S D F G H J K L \u00c6 \u00d8 * {enter}",
          "{shift} > Z X C V B N M ; : _ {shift}",
          "{lang} {space}"
        ]
      }
    },
    croatian: {
      layout: {
        "default": [
          "\u00b8 1 2 3 4 5 6 7 8 9 0 ' + {bksp}",
          "q w e r t z u i o p \u0161 \u0111",
          "{lock} a s d f g h j k l \u010d \u0107 \u017e {enter}",
          "{shift} < y x c v b n m , . - {shift}",
          "{lang} {space}"
        ],
        "shift": [
          "\u00a8 ! \" # $ % & / ( ) = ? * {bksp}",
          "Q W E R T Z U I O P \u0160 \u0110",
          "{lock} A S D F G H J K L \u010c \u0106 \u017d {enter}",
          "{shift} > Y X C V B N M ; : _ {shift}",
          "{lang} {space}"
        ]
      }
    },
    slovak: {
      layout: {
        "default": [
          "; + \u013e \u0161 \u010d \u0165 \u017e \u00fd \u00e1 \u00ed \u00e9 = \u00b4 {bksp}",
          "q w e r t z u i o p \u00fa \u00e4",
          "{lock} a s d f g h j k l \u00f4 \u00a7 \u0148 {enter}",
          "{shift} & y x c v b n m , . - {shift}",
          "{lang} {space}"
        ],
        "shift": [
          "\u00b0 1 2 3 4 5 6 7 8 9 0 % \u02c7 {bksp}",
          "Q W E R T Z U I O P / (",
          "{lock} A S D F G H J K L \" ! ) {enter}",
          "{shift} * Y X C V B N M ? : _ {shift}",
          "{lang} {space}"
        ]
      }
    },
    vietnamese: {
      layout: {
        "default": [
          "` 1 2 3 4 5 6 7 8 9 0 - = {bksp}",
          "q w e r t y u i o p \u01b0 \u01a1",
          "{lock} a s d f g h j k l \u0103 \u00e2 \u00ea {enter}",
          "{shift} z x c v b n m , . \u0111 \u00f4 {shift}",
          "{lang} {space}"
        ],
        "shift": [
          "~ ! @ # $ % ^ & * ( ) _ + {bksp}",
          "Q W E R T Y U I O P \u01af \u01a0",
          "{lock} A S D F G H J K L \u0102 \u00c2 \u00ca {enter}",
          "{shift} Z X C V B N M < > \u0110 \u00d4 {shift}",
          "{lang} {space}"
        ]
      }
    }
  };
})();
VKB_CUSTOM_LAYOUTS_EOF

# ---- vkb-theme.css ----
# Volumio dark theme overrides for simple-keyboard.
# Matches Volumio Classic UI color scheme.
log "Creating virtual keyboard theme CSS"
cat << 'VKB_THEME_CSS_EOF' > "${VKB_DIR}/vkb-theme.css"
#vkb-container {
  position: fixed;
  bottom: 0;
  left: 0;
  width: 100%;
  z-index: 999999;
  display: none;
  touch-action: manipulation;
}
#vkb-container.vkb-visible {
  display: block;
}
body.vkb-active {
  padding-bottom: 220px !important;
}
#vkb-container .simple-keyboard {
  background: #282828 !important;
  padding: 6px !important;
  font-family: "Lato", sans-serif !important;
}
#vkb-container .hg-button {
  background: #383838 !important;
  color: rgba(255,255,255,0.85) !important;
  border-bottom: 1px solid #222 !important;
  height: 38px !important;
  min-width: 20px !important;
  font-size: 14px !important;
  border-radius: 4px !important;
  touch-action: manipulation;
}
#vkb-container .hg-button:active,
#vkb-container .hg-button.hg-activeButton {
  background: #68c28d !important;
  color: #fff !important;
}
#vkb-container .hg-button.hg-functionBtn {
  background: #2d2d2d !important;
}
#vkb-container .hg-button.hg-functionBtn:active {
  background: #68c28d !important;
}
#vkb-container .hg-button[data-skbtn="{space}"] {
  min-width: 40% !important;
}
#vkb-container .hg-button[data-skbtn="{lang}"] {
  max-width: 60px !important;
  font-size: 12px !important;
  color: #68c28d !important;
  background: #2d2d2d !important;
  border: 1px solid #68c28d !important;
}
#vkb-container .hg-button[data-skbtn="{lang}"]:active {
  background: #68c28d !important;
  color: #fff !important;
}
VKB_THEME_CSS_EOF

# ---- vkb-init.js ----
# Main bootstrapper: loads libraries, detects language via socket.io,
# maps to keyboard layout, handles show/hide and language toggle.
log "Creating virtual keyboard bootstrapper"
cat << 'VKB_INIT_JS_EOF' > "${VKB_DIR}/vkb-init.js"
(function() {
  "use strict";
  if (window.__vkbInitDone) return;
  window.__vkbInitDone = true;

  var BASE_PATH = "/virtualkeyboard/";
  var ASSETS = {
    coreCss:   BASE_PATH + "index.css",
    themeCss:  BASE_PATH + "vkb-theme.css",
    coreJs:    BASE_PATH + "index.min.js",
    layoutsJs: BASE_PATH + "layouts.min.js",
    customJs:  BASE_PATH + "vkb-layouts-custom.js"
  };

  var LANG_MAP = {
    "en":"english","cs":"czech","de":"german","es":"spanish","fr":"french",
    "gr":"greek","hu":"hungarian","it":"italian","ja":"japanese","ko":"korean",
    "no":"norwegian","pl":"polish","ru":"russian","sv":"swedish","th":"thai",
    "tr":"turkish","ua":"ukrainian","zh":"chinese","zh_TW":"chinese",
    "pt":"brazilian","fi":"swedish","ca":"spanish","nl":"english",
    "da":"danish","hr":"croatian","sk":"slovak","vi":"vietnamese"
  };

  var CUSTOM_LAYOUT_NAMES = ["danish","croatian","slovak","vietnamese"];

  var ENGLISH_LAYOUT = {
    "default": [
      "` 1 2 3 4 5 6 7 8 9 0 - = {bksp}",
      "q w e r t y u i o p [ ] \\",
      "{lock} a s d f g h j k l ; ' {enter}",
      "{shift} z x c v b n m , . / {shift}",
      "{lang} {space}"
    ],
    "shift": [
      "~ ! @ # $ % ^ & * ( ) _ + {bksp}",
      "Q W E R T Y U I O P { } |",
      '{lock} A S D F G H J K L : " {enter}',
      "{shift} Z X C V B N M < > ? {shift}",
      "{lang} {space}"
    ]
  };

  var keyboard = null, activeInput = null, isVisible = false;
  var systemLangCode = "en", systemLayout = null;
  var currentLangCode = "en", usingSystemLang = true;

  function loadCss(href) {
    var link = document.createElement("link");
    link.rel = "stylesheet";
    link.href = href;
    document.head.appendChild(link);
  }
  loadCss(ASSETS.coreCss);
  loadCss(ASSETS.themeCss);

  var container = document.createElement("div");
  container.id = "vkb-container";
  container.innerHTML = '<div class="simple-keyboard"></div>';
  document.body.appendChild(container);

  function loadScript(src) {
    return new Promise(function(resolve) {
      var s = document.createElement("script");
      s.src = src;
      s.onload = resolve;
      s.onerror = function() { console.error("[vkb] Failed: " + src); resolve(); };
      document.head.appendChild(s);
    });
  }

  loadScript(ASSETS.coreJs)
    .then(function() { return loadScript(ASSETS.layoutsJs); })
    .then(function() { return loadScript(ASSETS.customJs); })
    .then(function() { detectLanguage(); });

  function detectLanguage() {
    if (typeof io !== "undefined") {
      try {
        var socket = io.connect(window.location.origin);
        socket.emit("getUiSettings");
        socket.on("pushUiSettings", function(data) {
          if (data && data.language) systemLangCode = data.language;
          socket.disconnect();
          initWithLanguage(systemLangCode);
        });
        setTimeout(function() { if (!keyboard) initWithLanguage("en"); }, 3000);
      } catch(e) { initWithLanguage("en"); }
    } else {
      initWithLanguage("en");
    }
  }

  function getLayoutByName(layoutName) {
    if (CUSTOM_LAYOUT_NAMES.indexOf(layoutName) !== -1) {
      if (window.VkbCustomLayouts && window.VkbCustomLayouts[layoutName])
        return window.VkbCustomLayouts[layoutName].layout;
    }
    if (window.SimpleKeyboardLayouts) {
      try {
        var Layouts = window.SimpleKeyboardLayouts.default || window.SimpleKeyboardLayouts;
        var obj = new Layouts().get(layoutName);
        if (obj && obj.layout) return obj.layout;
      } catch(e) { console.error("[vkb] Layout not found: " + layoutName); }
    }
    return null;
  }

  function addLangKey(layout) {
    var result = {};
    var keys = Object.keys(layout);
    for (var i = 0; i < keys.length; i++) {
      var rows = layout[keys[i]].slice();
      var last = rows[rows.length - 1];
      if (last.indexOf("{lang}") === -1) rows[rows.length - 1] = "{lang} " + last;
      result[keys[i]] = rows;
    }
    return result;
  }

  function getShortCode(lc) { return lc.toUpperCase().substring(0, 2); }

  function initWithLanguage(langCode) {
    systemLangCode = langCode;
    currentLangCode = langCode;
    usingSystemLang = true;
    var layoutName = LANG_MAP[langCode] || "english";
    var resolved = getLayoutByName(layoutName);
    systemLayout = resolved ? addLangKey(resolved) : ENGLISH_LAYOUT;
    createKeyboard(systemLayout, langCode);
  }

  function createKeyboard(layout, langCode) {
    var sk = window.SimpleKeyboard;
    if (!sk) return;
    var Ctor = sk.SimpleKeyboard || sk.default || sk;
    if (typeof Ctor !== "function") return;

    keyboard = new Ctor(".simple-keyboard", {
      onChange: onKbChange,
      onKeyPress: onKbKeyPress,
      preventMouseDownDefault: true,
      useTouchEvents: true,
      useButtonTag: true,
      layout: layout,
      display: getDisplay(langCode),
      theme: "hg-theme-default hg-layout-default"
    });

    // Direct handler for {lang} button (custom keys may not fire onKeyPress
    // via useTouchEvents in some builds)
    try {
      var langBtn = keyboard.getButtonElement("{lang}");
      if (langBtn) {
        var btn = Array.isArray(langBtn) ? langBtn[0] : langBtn;
        btn.addEventListener("touchend", function(e) { e.stopPropagation(); toggleLanguage(); });
        btn.addEventListener("click", function(e) { e.stopPropagation(); toggleLanguage(); });
      }
    } catch(e) {}

    document.addEventListener("touchend", onDocTap, true);
    document.addEventListener("click", onDocTap, true);
    document.addEventListener("focusin", onFocusIn, true);
  }

  function getDisplay(lc) {
    return {
      "{bksp}":"bksp", "{enter}":"enter", "{shift}":"shift",
      "{lock}":"caps", "{space}":" ", "{tab}":"tab", "{lang}":getShortCode(lc)
    };
  }

  function onKbChange(input) {
    if (!activeInput) return;
    setNativeValue(activeInput, input);
  }

  function onKbKeyPress(button) {
    if (button === "{shift}" || button === "{lock}") {
      var cur = keyboard.options.layoutName;
      keyboard.setOptions({ layoutName: cur === "default" ? "shift" : "default" });
      return;
    }
    if (button === "{enter}" && activeInput) {
      activeInput.dispatchEvent(new KeyboardEvent("keydown", {
        key:"Enter", code:"Enter", keyCode:13, bubbles:true
      }));
      return;
    }
    if (button === "{lang}") { toggleLanguage(); return; }
  }

  function toggleLanguage() {
    var saved = activeInput ? keyboard.getInput() : "";
    if (usingSystemLang && systemLangCode !== "en") {
      currentLangCode = "en"; usingSystemLang = false;
      keyboard.setOptions({ layout: ENGLISH_LAYOUT, display: getDisplay("en") });
    } else {
      currentLangCode = systemLangCode; usingSystemLang = true;
      keyboard.setOptions({ layout: systemLayout, display: getDisplay(systemLangCode) });
    }
    if (activeInput) keyboard.setInput(saved);
    // Re-attach lang button handler after layout rebuild
    try {
      var langBtn = keyboard.getButtonElement("{lang}");
      if (langBtn) {
        var btn = Array.isArray(langBtn) ? langBtn[0] : langBtn;
        btn.addEventListener("touchend", function(e) { e.stopPropagation(); toggleLanguage(); });
        btn.addEventListener("click", function(e) { e.stopPropagation(); toggleLanguage(); });
      }
    } catch(e) {}
  }

  function setNativeValue(el, value) {
    var proto = el.tagName === "TEXTAREA" ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
    var desc = Object.getOwnPropertyDescriptor(proto, "value");
    if (desc && desc.set) desc.set.call(el, value); else el.value = value;
    el.dispatchEvent(new Event("input", { bubbles: true }));
    el.dispatchEvent(new Event("change", { bubbles: true }));
  }

  function showKeyboard() {
    if (!isVisible) {
      container.classList.add("vkb-visible");
      document.body.classList.add("vkb-active");
      isVisible = true;
    }
  }

  function hideKeyboard() {
    container.classList.remove("vkb-visible");
    document.body.classList.remove("vkb-active");
    isVisible = false;
    activeInput = null;
  }

  function isTextInput(el) {
    if (!el) return false;
    if (el.tagName === "TEXTAREA") return true;
    if (el.tagName === "INPUT") {
      var type = (el.type || "text").toLowerCase();
      return "text search email url tel password number".indexOf(type) !== -1;
    }
    return false;
  }

  function onFocusIn(e) {
    if (!isTextInput(e.target)) return;
    activeInput = e.target;
    if (keyboard) keyboard.setInput(e.target.value || "");
    showKeyboard();
  }

  function onDocTap(e) {
    if (!isVisible) return;
    if (container.contains(e.target)) return;
    if (isTextInput(e.target)) return;
    hideKeyboard();
  }
})();
VKB_INIT_JS_EOF

# =============================================================================
# INJECT VIRTUAL KEYBOARD INTO VOLUMIO UI VARIANTS
# =============================================================================
# Create symlinks from each UI variant to the common asset directory,
# then inject a <script> tag into each variant's index.html.
# =============================================================================

VKB_SCRIPT_TAG='<script src="/virtualkeyboard/vkb-init.js"></script>'

for ui_dir in /volumio/http/www /volumio/http/www3 /volumio/http/www4; do
  if [[ -d "${ui_dir}" ]]; then
    # Symlink to common assets (saves disk space vs copying)
    if [[ ! -e "${ui_dir}/virtualkeyboard" ]]; then
      ln -sf "${VKB_DIR}" "${ui_dir}/virtualkeyboard"
      log "Linked virtualkeyboard assets into ${ui_dir}"
    fi

    # Inject script tag if not already present
    if [[ -f "${ui_dir}/index.html" ]]; then
      if ! grep -q "vkb-init.js" "${ui_dir}/index.html"; then
        sed -i "s|</body>|${VKB_SCRIPT_TAG}</body>|" "${ui_dir}/index.html"
        log "Injected virtual keyboard into ${ui_dir}/index.html"
      else
        log "Virtual keyboard already injected in ${ui_dir}/index.html"
      fi
    fi
  fi
done

# =============================================================================
# KIOSK LAUNCHER SCRIPTS
# =============================================================================

# ---- Inner script: runs inside the cage Wayland session ----
# Applies output rotation via wlr-randr, then launches cog.
log "Creating ${CMP_NAME} cog launcher script"
cat << 'COG_LAUNCHER_EOF' > /opt/volumiokiosk-cog.sh
#!/usr/bin/env bash
exec >/var/log/volumiokiosk-cog.log 2>&1

echo "Starting cog inside cage session"

# Read kiosk configuration
# WLR_TRANSFORM: output rotation (0=none, 90, 180, 270)
# COG_SCALE: content scale factor (default 1.0)
WLR_TRANSFORM="0"
COG_SCALE="1.0"

# Source runtime overrides if present
# shellcheck source=/dev/null
[[ -f /data/wpeargs ]] && source /data/wpeargs

# Apply output rotation if set
# wlr-randr needs a brief delay for the compositor to be ready
if [[ "${WLR_TRANSFORM}" != "0" ]]; then
  sleep 1

  # Detect the connected output name
  WLR_OUTPUT=""
  while IFS= read -r line; do
    if [[ "${line}" != " "* ]] && [[ -n "${line}" ]]; then
      WLR_OUTPUT="${line%% (*}"
    fi
    if [[ "${line}" == *"Enabled: yes"* ]] && [[ -n "${WLR_OUTPUT}" ]]; then
      break
    fi
  done < <(wlr-randr 2>/dev/null)

  if [[ -n "${WLR_OUTPUT}" ]]; then
    echo "Rotating output ${WLR_OUTPUT} by ${WLR_TRANSFORM} degrees"
    wlr-randr --output "${WLR_OUTPUT}" --transform "${WLR_TRANSFORM}"
  else
    echo "Warning: No enabled output found for rotation"
  fi
else
  sleep 1
fi

# Build cog arguments
COG_ARGS=(
  "--platform=wl"
)

# Apply scale factor if not default
if [[ "${COG_SCALE}" != "1.0" ]]; then
  COG_ARGS+=("--scale=${COG_SCALE}")
fi

echo "Launching cog with args: ${COG_ARGS[*]}"
exec /usr/bin/cog "${COG_ARGS[@]}" http://localhost:3000
COG_LAUNCHER_EOF

chmod +x /opt/volumiokiosk-cog.sh

# ---- Outer script: sets environment, waits for Volumio, launches cage ----
log "Creating ${CMP_NAME} kiosk start script"
cat << 'KIOSK_LAUNCHER_EOF' > /opt/volumiokiosk.sh
#!/usr/bin/env bash
exec >/var/log/volumiokiosk.log 2>&1

echo "Starting Volumio WPE Kiosk"
start=$(date +%s)

# Required for cage (Wayland compositor)
export XDG_RUNTIME_DIR="/tmp/xdg-runtime-kiosk"
mkdir -p "${XDG_RUNTIME_DIR}"

# First boot delay
if [[ ! -f /data/volumiokiosk/firststartdone ]]; then
  echo "First boot - waiting for Volumio to start"
  sleep 15
  touch /data/volumiokiosk/firststartdone
fi

# Wait for Volumio webUI to be available
while true; do
  timeout 5 bash -c "</dev/tcp/127.0.0.1/3000" >/dev/null 2>&1 && break
  sleep 2
done
echo "Waited $(($(date +%s) - start)) sec for Volumio UI"

# Read cursor configuration
# Default: no cursor (touchscreen kiosk)
SHOW_CURSOR="no"
# shellcheck source=/dev/null
[[ -f /data/wpeargs ]] && source /data/wpeargs

# Launch cage with cog as the kiosk application
# cage runs one application fullscreen on DRM/KMS
exec /usr/bin/cage -- /opt/volumiokiosk-cog.sh
KIOSK_LAUNCHER_EOF

chmod +x /opt/volumiokiosk.sh

# =============================================================================
# SYSTEMD SERVICE
# =============================================================================

log "Creating Systemd Unit for ${CMP_NAME}"
cat << 'SYSTEMD_UNIT_EOF' > /lib/systemd/system/volumio-kiosk.service
[Unit]
Description=Start Volumio Kiosk (WPE)
Wants=volumio.service
After=volumio.service

[Service]
Type=simple
User=root
Group=root
ExecStart=/opt/volumiokiosk.sh
Restart=always
RestartSec=5
# Give a reasonable amount of time for the server to start up/shut down
TimeoutSec=300

[Install]
WantedBy=multi-user.target
SYSTEMD_UNIT_EOF

log "Enabling ${CMP_NAME} service"
ln -sf /lib/systemd/system/volumio-kiosk.service \
  /etc/systemd/system/multi-user.target.wants/volumio-kiosk.service

# =============================================================================
# RUNTIME CONFIGURATION DEFAULTS
# =============================================================================
# /data/wpeargs is sourced by the kiosk launcher at runtime.
# Device recipes or display configuration plugins can override these values.
# =============================================================================

log "Creating default WPE kiosk runtime configuration"
cat << 'WPEARGS_EOF' > /data/wpeargs
# Volumio WPE Kiosk runtime configuration
# This file is sourced by /opt/volumiokiosk.sh and /opt/volumiokiosk-cog.sh
#
# WLR_TRANSFORM: Output rotation in degrees (0, 90, 180, 270)
#   Set to match your display's physical orientation.
#   Pi Touch Display 2 (DSI, portrait native): typically 90 or 270
#   HDMI displays: typically 0
WLR_TRANSFORM="0"

# COG_SCALE: Content scale factor (default 1.0)
#   Increase for small/high-DPI displays, decrease to fit more content.
COG_SCALE="1.0"

# SHOW_CURSOR: Show mouse cursor (yes/no)
#   Set to "no" for touchscreen-only devices
SHOW_CURSOR="no"
WPEARGS_EOF

chmod 644 /data/wpeargs

# =============================================================================
# TOUCH INPUT CALIBRATION (UDEV RULE)
# =============================================================================
# When display rotation is applied via wlr-randr, touch input coordinates
# must be remapped to match. This udev rule sets the libinput calibration
# matrix for touchscreens.
#
# The matrix values depend on the rotation angle:
#   0 degrees:   "1 0 0 0 1 0"       (identity)
#   90 degrees:  "0 1 0 -1 0 1"
#   180 degrees: "-1 0 1 0 -1 1"
#   270 degrees: "0 -1 1 1 0 0"
#
# A helper script at /opt/volumio-touch-calibrate.sh updates the udev rule
# to match the current WLR_TRANSFORM setting.
# =============================================================================

log "Creating touch calibration helper"
cat << 'TOUCH_CAL_EOF' > /opt/volumio-touch-calibrate.sh
#!/usr/bin/env bash
# Generates a udev rule to remap touchscreen input for display rotation.
# Called by device recipes or display configuration plugins.
# Usage: /opt/volumio-touch-calibrate.sh [rotation_degrees]
#   rotation_degrees: 0, 90, 180, or 270 (default: read from /data/wpeargs)

set -eo pipefail

ROTATION="${1:-}"
if [[ -z "${ROTATION}" ]]; then
  # shellcheck source=/dev/null
  [[ -f /data/wpeargs ]] && source /data/wpeargs
  ROTATION="${WLR_TRANSFORM:-0}"
fi

case "${ROTATION}" in
  0)   MATRIX="1 0 0 0 1 0" ;;
  90)  MATRIX="0 1 0 -1 0 1" ;;
  180) MATRIX="-1 0 1 0 -1 1" ;;
  270) MATRIX="0 -1 1 1 0 0" ;;
  *)   echo "Invalid rotation: ${ROTATION}"; exit 1 ;;
esac

UDEV_RULE="/etc/udev/rules.d/99-volumio-touch-rotation.rules"
echo "# Volumio WPE kiosk touch calibration for ${ROTATION} degree rotation" > "${UDEV_RULE}"
echo "ENV{ID_INPUT_TOUCHSCREEN}==\"1\", ENV{LIBINPUT_CALIBRATION_MATRIX}=\"${MATRIX}\"" >> "${UDEV_RULE}"

udevadm control --reload-rules 2>/dev/null || true
udevadm trigger 2>/dev/null || true
echo "Touch calibration set for ${ROTATION} degrees: ${MATRIX}"
TOUCH_CAL_EOF

chmod +x /opt/volumio-touch-calibrate.sh

# Generate default (identity) touch calibration rule
/opt/volumio-touch-calibrate.sh 0

# =============================================================================
# SYSTEM CONFIGURATION
# =============================================================================

log "Setting HDMI UI enabled by default"
config_path="/volumio/app/plugins/system_controller/system/config.json"
#shellcheck disable=SC2094
cat <<<"$(jq '.hdmi_enabled={value:true, type:"boolean"}' "${config_path}")" >"${config_path}"

log "Show HDMI output selection"
echo '[{"value": false,"id":"section_hdmi_settings","attribute_name": "hidden"},{"value": false,"id":"hdmi_enabled","attribute_name": "hidden"}]' \
  >/volumio/app/plugins/system_controller/system/override.json

log "Disable login prompt before browser starts"
systemctl disable getty@tty1.service

# =============================================================================
# DEVICE-SPECIFIC TOUCHSCREEN CONFIGURATION
# =============================================================================
# Devices with integrated touchscreens need:
# - Display rotation (WLR_TRANSFORM in /data/wpeargs)
# - Touch calibration matrix (udev rule)
# - Cursor hidden by default
# =============================================================================

# TODO USE GLOBAL VARIABLE FOR DEVICES WITH INTEGRATED TOUCHSCREEN
if [[ ${VOLUMIO_HARDWARE} = cm4 || ${VOLUMIO_HARDWARE} = pi-kiosk || ${VOLUMIO_HARDWARE} = cm5 ]]; then

  log "Configuring touchscreen defaults for ${VOLUMIO_HARDWARE}"

  log "Hide HDMI output selection"
  echo '[{"value": false,"id":"section_hdmi_settings","attribute_name": "hidden"},{"value": true,"id":"hdmi_enabled","attribute_name": "hidden"},{"value": false,"id":"show_mouse_pointer","attribute_name": "hidden"}]' \
    >/volumio/app/plugins/system_controller/system/override.json

  # DSI displays are typically portrait-native and need rotation.
  # The exact rotation depends on the display model and mount orientation.
  # Default: 90 degrees for Pi Touch Display 2 (most common config).
  log "Setting default display rotation for DSI touchscreen"
  sed -i 's/^WLR_TRANSFORM=.*/WLR_TRANSFORM="90"/' /data/wpeargs

  log "Setting touch calibration for 90 degree rotation"
  /opt/volumio-touch-calibrate.sh 90
fi

log "${CMP_NAME} installation complete"

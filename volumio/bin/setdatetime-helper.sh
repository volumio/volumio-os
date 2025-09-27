#!/bin/bash
#
# Volumio setdatetime-helper with SD-friendly logging, drift guard, and CLI flags
#
# Sentinel file controls default verbosity:
#   /data/setdatetime.logger  ->  error | info | debug
#
# CLI flags override sentinel for this run:
#   -f | --force        Force sync: bypass ntpsec and drift guard
#   -v | --verbose      Verbose (info)
#   -d | --debug        Debug logging
#   -q | --quiet        Errors only
#   --no-sentinel       Do not read or create the sentinel for this run
#   -h | --help         Show usage and exit
#
set -eu

SENTINEL="/data/setdatetime.logger"
USE_SENTINEL=1
FORCE_SYNC=0

usage() {
  cat <<'USAGE'
Usage: setdatetime-helper.sh [options]

Options:
  -f, --force        Force sync now (ignore ntpsec status and drift guard)
  -v, --verbose      Set verbosity to info for this run
  -d, --debug        Set verbosity to debug for this run
  -q, --quiet        Set verbosity to error for this run
  --no-sentinel      Do not read or create /data/setdatetime.logger for this run
  -h, --help         Show this help and exit
USAGE
}

# Parse CLI flags
LOGLEVEL_OVRD=""
while [ $# -gt 0 ]; do
  case "$1" in
    -f|--force) FORCE_SYNC=1 ;;
    -v|--verbose) LOGLEVEL_OVRD=2 ;;
    -d|--debug) LOGLEVEL_OVRD=3 ;;
    -q|--quiet) LOGLEVEL_OVRD=1 ;;
    --no-sentinel) USE_SENTINEL=0 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 2 ;;
  esac
  shift
done

# Create or fix sentinel when enabled
ensure_sentinel() {
  mkdir -p /data || true
  if [ ! -f "$SENTINEL" ]; then
    if command -v install >/dev/null 2>&1; then
      install -o volumio -g volumio -m 0644 /dev/null "$SENTINEL" || true
    else
      : >"$SENTINEL" || true
      chown volumio:volumio "$SENTINEL" || true
      chmod 0644 "$SENTINEL" || true
    fi
    printf "%s\n" "error" >"$SENTINEL" 2>/dev/null || true
  else
    if command -v stat >/dev/null 2>&1; then
      owner="$(stat -c %U "$SENTINEL" 2>/dev/null || echo root)"
      group="$(stat -c %G "$SENTINEL" 2>/dev/null || echo root)"
      if [ "$owner" != "volumio" ] || [ "$group" != "volumio" ]; then
        chown volumio:volumio "$SENTINEL" || true
      fi
    else
      chown volumio:volumio "$SENTINEL" || true
    fi
    chmod 0644 "$SENTINEL" || true
  fi
}

# Determine LOGLEVEL: 1=error, 2=info, 3=debug
if [ -n "${LOGLEVEL_OVRD:-}" ]; then
  LOGLEVEL="$LOGLEVEL_OVRD"
else
  if [ "$USE_SENTINEL" -eq 1 ]; then
    ensure_sentinel
    LEVEL_RAW="$(tr -d ' \t\r\n' <"$SENTINEL" 2>/dev/null || printf "%s" "error")"
  else
    LEVEL_RAW="error"
  fi
  case "$LEVEL_RAW" in
    debug) LOGLEVEL=3 ;;
    info)  LOGLEVEL=2 ;;
    error|*) LOGLEVEL=1 ;;
  esac
fi

log_err()  { printf "%s\n" "setdatetime-helper: $*" >&2; }
log_info() { [ "$LOGLEVEL" -ge 2 ] && printf "%s\n" "setdatetime-helper: $*"; true; }
log_dbg()  { [ "$LOGLEVEL" -ge 3 ] && printf "%s\n" "setdatetime-helper: $*"; true; }

# Require root when run manually
if [ "$(id -u)" -ne 0 ]; then
  log_err "must run as root or via systemd unit"
  exit 1
fi

# Endpoints in preferred order
ENDPOINTS="
https://time.is
https://time.cloudflare.com
https://time.google.com
https://www.bing.com
https://www.baidu.com
"

# Drift guard thresholds
SMALL_DRIFT=1          # No adjust if |drift| <= 1s
BACKWARD_ALLOW=120     # Avoid backward steps unless >= 120s

get_date_hdr() {
  local url="$1"
  curl -sI --max-time 3 --retry 1 "$url" 2>/dev/null | grep -i '^Date:' | sed 's/^[Dd]ate:[[:space:]]*//'
}

abs() { local v="$1"; [ "${v#-}" = "$v" ] && echo "$v" || echo "${v#-}"; }

ntpsec_has_peers() {
  # Return 0 if ntpsec active with any reachable peers, else 1
  if systemctl is-active --quiet ntpsec.service 2>/dev/null; then
    if command -v ntpq >/dev/null 2>&1; then
      if ntpq -p 2>/dev/null | awk 'BEGIN{ok=0} /^[+*\- ]/ { if ($8 ~ /^[0-7]{3}$/ && $8 != "000") ok=1 } END{exit ok?0:1}'; then
        return 0
      fi
    fi
  fi
  return 1
}

sync_once() {
  local forced="${1:-0}"

  if [ "$forced" -ne 1 ]; then
    if ntpsec_has_peers; then
      log_info "ntpsec active with reachable peers; no action needed"
      return 0
    else
      log_dbg "ntpsec not ready; using HTTPS Date fallback"
    fi
  else
    log_info "force requested; bypassing ntpsec and drift guard"
  fi

  log_info "attempting HTTPS Date fallback sequence"

  for url in $ENDPOINTS; do
    hdr="$(get_date_hdr "$url" || true)"
    if [ -z "${hdr:-}" ]; then
      log_dbg "no Date header from $url"
      continue
    fi

    now_local="$(date -u +%s)"
    ref_epoch="$(date -ud "$hdr" +%s 2>/dev/null || echo "")"
    if [ -z "$ref_epoch" ]; then
      log_dbg "failed to parse Date from $url"
      continue
    fi

    drift="$(( now_local - ref_epoch ))"
    adrift="$(abs "$drift")"
    log_dbg "drift vs $url is ${drift}s"

    if [ "$forced" -ne 1 ]; then
      # Skip tiny drift
      if [ "$adrift" -le "$SMALL_DRIFT" ]; then
        log_info "drift ${drift}s within ${SMALL_DRIFT}s; no adjust"
        return 0
      fi
      # Avoid small backward steps
      if [ "$drift" -gt 0 ] && [ "$drift" -lt "$BACKWARD_ALLOW" ]; then
        log_info "backward drift ${drift}s < ${BACKWARD_ALLOW}s; defer to ntpsec"
        return 0
      fi
    fi

    log_info "using Date header from $url -> $hdr"
    if date -s "$hdr" >/dev/null 2>&1; then
      log_info "time set successfully from $url"
      return 0
    else
      log_err "date set failed for $url"
      # try next endpoint
    fi
  done

  log_err "all HTTPS Date fallbacks failed"
  return 1
}

if sync_once "$FORCE_SYNC"; then
  exit 0
else
  exit 1
fi

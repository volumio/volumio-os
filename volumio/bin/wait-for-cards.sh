#!/bin/bash
timeout=10
count=0
while true; do
  if [ -e /proc/asound/cards ] && grep -q '\[.*\]' /proc/asound/cards; then
    exit 0
  fi
  sleep 1
  count=$((count + 1))
  if [ "$count" -ge "$timeout" ]; then
    echo "ALSA card wait timeout"
    exit 0
  fi
done

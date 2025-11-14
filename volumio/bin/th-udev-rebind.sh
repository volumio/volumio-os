#!/bin/bash

# Wait up to 5 seconds for the socket to appear
timeout=10
while [ ! -S /run/thd.socket ] && [ $timeout -gt 0 ]; do
  sleep 0.5
  timeout=$((timeout - 1))
done

if [ ! -S /run/thd.socket ]; then
  echo "Error: thd.socket not found after timeout"
  exit 1
fi

# Enumerate and rebind all input event devices
for dev in /dev/input/event*; do
  if [ -r "$dev" ]; then
    echo "Rebinding $dev to thd using --add..."
    /usr/sbin/th-cmd --socket /run/thd.socket --passfd --add "$dev"
  fi
done

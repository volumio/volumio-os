#!/bin/bash

timeout=5
while [ ! -S /run/thd.socket ] && [ $timeout -gt 0 ]; do
  sleep 0.5
  timeout=$((timeout - 1))
done

for dev in /dev/input/event*; do
  /usr/sbin/th-cmd --socket /run/thd.socket --passfd --udev < "$dev"
done

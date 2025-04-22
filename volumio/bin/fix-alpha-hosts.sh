#!/bin/bash

HOSTS_FILE="/etc/hosts"
SENTINELS=("/data/test-alpha" "/data/testplugins")

# Ensure hosts entries
grep -q "136.144.163.173 updater.volumio.org" "$HOSTS_FILE" || echo "136.144.163.173 updater.volumio.org" >> "$HOSTS_FILE"
grep -q "136.144.163.173 updates.volumio.org" "$HOSTS_FILE" || echo "136.144.163.173 updates.volumio.org" >> "$HOSTS_FILE"

# Ensure sentinel files
for file in "${SENTINELS[@]}"; do
  [ -f "$file" ] || touch "$file"
done

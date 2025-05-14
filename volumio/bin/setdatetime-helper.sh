#!/bin/bash

# Check if time is synchronized
if ! timedatectl show --property=NTPSynchronized --value | grep -q 'yes'; then
  echo "Time is not synchronized. Attempting to sync..."
  # Use fallback NTP server or HTTP-based date retrieval for synchronization
  date_string=$(curl -s --head http://time.is | grep ^Date: | sed 's/Date: //g')
  if [ -n "$date_string" ]; then
    # Set the system time from the HTTP header
    sudo date -s "$date_string"
    echo "Time synchronized successfully."
    exit 0
  else
    echo "Sync attempt failed."
    exit 1
  fi
else
  echo "Time is already synchronized."
  exit 0
fi

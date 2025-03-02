#!/bin/bash

CONFIG_FILE="/etc/groups-config.conf"
LOG_FILE="/var/log/groups-config.log"

# Check if config file exists
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "$(date) - Config file $CONFIG_FILE not found!" | tee -a "$LOG_FILE"
    exit 1
fi

# Process each line in the config file
while IFS=: read -r user groups; do
    if [[ -z "$user" || -z "$groups" ]]; then
        continue  # Skip empty lines
    fi
    
    echo "$(date) - Checking user: $user" | tee -a "$LOG_FILE"

    # Get current groups for the user
    current_groups=$(groups "$user" | cut -d ":" -f2)

    for group in $(echo "$groups" | tr ',' ' '); do
        if [[ "$current_groups" == *"$group"* ]]; then
            echo "$(date) - User $user is already in group $group, skipping." | tee -a "$LOG_FILE"
        else
            echo "$(date) - Adding user $user to group $group" | tee -a "$LOG_FILE"
            sudo usermod -aG "$group" "$user"
        fi
    done
done < "$CONFIG_FILE"

echo "$(date) - Group management complete." | tee -a "$LOG_FILE"

#!/bin/bash

# Define the groups that root should be added to
GROUPS_TO_ADD=("volumio" "audio" "lp" "bluetooth")

# Log file for tracking changes
LOG_FILE="/var/log/root_group_update.log"

# Function to add root to groups
add_root_to_groups() {
    echo "Adding root to critical groups: ${GROUPS_TO_ADD[*]}"
    for group in "${GROUPS_TO_ADD[@]}"; do
        if getent group "$group" > /dev/null 2>&1; then
            sudo usermod -aG "$group" root
            echo "$(date) - Added root to group: $group" | sudo tee -a "$LOG_FILE"
        else
            echo "$(date) - Warning: Group $group does not exist!" | sudo tee -a "$LOG_FILE"
        fi
    done
    echo "Update complete. New root group membership:"
    groups root
}

# Function to revert changes (remove root from groups)
revert_root_from_groups() {
    echo "Reverting root from critical groups: ${GROUPS_TO_ADD[*]}"
    for group in "${GROUPS_TO_ADD[@]}"; do
        if getent group "$group" > /dev/null 2>&1; then
            sudo gpasswd -d root "$group"
            echo "$(date) - Removed root from group: $group" | sudo tee -a "$LOG_FILE"
        fi
    done
    echo "Reversion complete. New root group membership:"
    groups root
}

# Main execution
if [[ $1 == "--revert" ]]; then
    revert_root_from_groups
else
    add_root_to_groups
fi

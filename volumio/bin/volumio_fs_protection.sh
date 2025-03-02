#!/bin/bash

# Script to enable or disable fs.protected_regular and fs.protected_fifos
# This allows fine-tuned control over kernel security settings for managing access to
# world-writable directories, named pipes, and Unix domain sockets.

ACTION=$1

case "$ACTION" in
    enable)
        echo "Enabling fs.protected_regular and fs.protected_fifos..."
        sudo sysctl fs.protected_regular=2
        sudo sysctl fs.protected_fifos=1
        echo "fs.protected_regular=1" | sudo tee /etc/sysctl.d/99-protected-regular.conf
        echo "fs.protected_fifos=1" | sudo tee /etc/sysctl.d/99-protected-fifos.conf
        sudo sysctl --system
        ;;
    disable)
        echo "Disabling fs.protected_regular and fs.protected_fifos..."
        sudo sysctl fs.protected_regular=0
        sudo sysctl fs.protected_fifos=0
        echo "fs.protected_regular=0" | sudo tee /etc/sysctl.d/99-protected-regular.conf
        echo "fs.protected_fifos=0" | sudo tee /etc/sysctl.d/99-protected-fifos.conf
        sudo sysctl --system
        ;;
    status)
        echo "Current settings:"
        sudo sysctl fs.protected_regular
        sudo sysctl fs.protected_fifos
        ;;
    *)
        echo "Usage: $0 {enable|disable|status}"
        exit 1
        ;;
esac

# Archive keys

The multistrap base build trusts only these keys (`SecureApt` in `recipes/configurations/config.sh`),
so a key swapped on a server is never picked up silently.

When an archive changes key, the build stops at multistrap with `NO_PUBKEY <id>`. Then:

1. Download the new key from the URL in the comment next to its `SecureApt` entry.
2. Check its fingerprint against a second source: https://ftp-master.debian.org/keys.html for
   Debian, `stage0/files/raspberrypi.gpg` in RPi-Distro/pi-gen for Raspbian and Raspberry Pi.
3. Replace the `.asc` file here and open a PR.

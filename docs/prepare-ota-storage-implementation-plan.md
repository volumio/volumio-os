# Prepare OTA Storage – Detailed Implementation Plan

**Document version:** 1.0  
**Script name:** `prepare-ota-storage`  
**Target:** volumio-os initramfs (BusyBox ash)

---

## 1. Purpose

One-time resize of boot and image partitions to match the Pi recipe layout so future OTA updates (e.g. Bookworm/Trixie) can succeed on devices with smaller factory layout (e.g. Motivo, CM4) without reflashing. User data on the data partition is discarded; backup/restore applies only to boot and image partitions.

---

## 2. Target Layout (Pi Recipe)

| Partition | Start (MiB) | End (MiB) | Size    |
|-----------|-------------|-----------|---------|
| 1 (boot)  | 1           | 385       | 384 MiB |
| 2 (img)   | 385         | 4673      | 4288 MiB|
| 3 (data)  | 4673        | 100%      | rest    |

Constants in script: `TARGET_BOOT_END=385`, `TARGET_IMAGE_END=4673`.

---

## 3. Method

- **No in-place resize of data partition** (avoids hours on slow eMMC/SD).
- Backup boot + image partition contents to the **tail of the disk** (blocks from 4673 MiB to end).
- Recreate partition table: new p1, p2, p3 with Pi layout; mkfs p1 and p2 only.
- Restore backup from tail to new p1 and p2; then mkfs p3 (fresh data partition).

---

## 4. Script Location and Missing-File Handling

- **Script may be absent on purpose** (e.g. EOL builds). Init must never assume the file exists.
- **Script may be delivered by OTA** (e.g. pre-check) instead of being in the image.

**Two valid locations (checked in order):**

1. **Initramfs:** `/scripts/prepare-ota-storage`
2. **Boot partition:** `${BOOTMNT}/prepare-ota-storage` (after boot is mounted)

**Init behaviour:**

- If **neither** path exists: skip silently (no error, optional single debug log). Continue normal boot.
- If **either** exists: run that script (same contract: POSIX sh, same entry point). Script unmounts boot (and imgpart if mounted) before repartitioning.

**Run point in init:** After first mount of the **boot** partition (and image partition), so OTA-delivered script on boot can be used.

---

## 5. Init Integration (initv3)

After mounting boot and image partition, check for script at initramfs or boot path; if present, source and call `prepare_ota_storage`. No error if script is missing.

---

## 6. High-Level Flow (inside script)

1. **Resolve device:** Use `BOOT_PARTITION`, `IMAGE_PARTITION`, `DATA_PARTITION`; derive `DATADEV`.
2. **Check if resize needed:** Read current p1 end, p2 end via parted. If `p1_end >= 385` and `p2_end >= 4673` → return 0 (no VT, no work).
3. **If resize needed:** Show VT + large text, unmount boot/imgpart, backup to tail, repartition, mkfs p1/p2, restore from tail, mkfs p3, clear stage, remount boot/imgpart, switch back VT.
4. **Recovery path:** If init later detects boot failure, read stage from tail; if stage indicates resize in progress, run complete-from-backup.

---

## 7. Stage and Recovery

- **Stage area:** Last 64 KB of disk; magic "VOLRESIZE" + stage (1 = backup done, 2 = table recreated).
- **Recovery:** When normal boot would fail, read stage; if in progress, run complete-from-backup.
- **Idempotent:** If layout already Pi, do nothing; optionally clear stale stage.

---

## 8. User Message (VT, Only When Resize Runs)

- **When:** Only if resize (or recovery) will run; **no VT switch if resize not needed.**
- **How:** Switch to reserved VT (e.g. 2), clear screen, large text. No Plymouth.

---

## 9. Code and Environment

- **Shell:** `#!/bin/sh`; POSIX only; BusyBox ash. No bashisms.
- **Errors:** Check exit code of every critical command; on failure: log, cleanup/update stage, return.
- **Paths:** Full paths for critical tools where appropriate.
- **Quoting:** Quote all expansions. Arithmetic: integer only, `$(( ))`.

---

## 10. Deliverables

| Item | Location / note |
|------|------------------|
| Script | `scripts/initramfs/scripts/prepare-ota-storage` |
| Entry point | `prepare_ota_storage` |
| Init change | initv3: after mount boot/imgpart, check both paths; if present, source and call |
| Constants | `TARGET_BOOT_END=385`, `TARGET_IMAGE_END=4673` |
| Stage | Last 64 KB of disk; magic + stage |

---

## 11. EOL and OTA Delivery

- **EOL:** Omit script from image; init skips (missing file).
- **OTA pre-check:** Place script on boot partition at agreed path; next boot runs it from there.

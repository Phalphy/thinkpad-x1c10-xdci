#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  sudo ./scripts/set-x1c10-nvram-unprotect-marker.sh /dev/sdX APPLY

Patches an existing whole-disk FAT32 USB medium with the Lenovo service
markers at DECIMAL byte offsets 10 and 21. The medium must already contain a
working EFI/BOOT/BOOTX64.EFI. No files are copied and the drive is not
formatted. Unmount the drive before running this command.
EOF
}

if [[ $# -ne 2 || $2 != APPLY ]]; then
  usage >&2
  exit 2
fi

device=$1

if [[ $EUID -ne 0 ]]; then
  echo "Run as root with sudo." >&2
  exit 1
fi

if [[ ! -b $device ]]; then
  echo "Not a block device: $device" >&2
  exit 1
fi

device_type=$(lsblk -dnro TYPE "$device")
transport=$(lsblk -dnro TRAN "$device")
removable=$(lsblk -dnro RM "$device")

if [[ $device_type != disk || $transport != usb || $removable != 1 ]]; then
  echo "Refusing target: expected a whole removable USB disk." >&2
  exit 1
fi

root_source=$(findmnt -nro SOURCE /)
root_parent=$(lsblk -no PKNAME "$root_source" 2>/dev/null || true)
if [[ -n $root_parent && $device == "/dev/$root_parent" ]]; then
  echo "Refusing the disk that contains the running root filesystem." >&2
  exit 1
fi

if lsblk -nrpo MOUNTPOINTS "$device" | grep -q '[^[:space:]]'; then
  echo "Refusing a mounted target. Unmount it first:" >&2
  lsblk -o NAME,PATH,SIZE,FSTYPE,MOUNTPOINTS "$device" >&2
  exit 1
fi

if [[ $(dd if="$device" bs=1 skip=510 count=2 status=none | od -An -tx1 | tr -d '[:space:]') != 55aa ]]; then
  echo "Refusing target without a 0x55AA boot-sector signature." >&2
  exit 1
fi

read_byte() {
  od -An -tx1 -j "$1" -N 1 "$device" | tr -d '[:space:]'
}

marker_10="$(read_byte 10)"
marker_21="$(read_byte 21)"
echo "Before: byte[10]=0x$marker_10, byte[21]=0x$marker_21"

if [[ $marker_10 != 74 && $marker_10 != 7a ]]; then
  echo "Refusing unexpected byte[10]=0x$marker_10 (expected 0x74 or 0x7a)." >&2
  exit 1
fi

if [[ $marker_21 != f8 && $marker_21 != f0 ]]; then
  echo "Refusing unexpected byte[21]=0x$marker_21 (expected 0xf8 or 0xf0)." >&2
  exit 1
fi

# Both offsets are decimal, matching dd seek=10/21 in the Lenovo community method.
printf '\x7a' | dd of="$device" bs=1 seek=10 count=1 conv=notrunc,fsync status=none
printf '\xf0' | dd of="$device" bs=1 seek=21 count=1 conv=notrunc,fsync status=none
sync

after_10="$(read_byte 10)"
after_21="$(read_byte 21)"
echo "After: byte[10]=0x$after_10, byte[21]=0x$after_21"

if [[ "$after_10" != "7a" || "$after_21" != "f0" ]]; then
  echo "Fehler: Rohbyte-Verifikation fehlgeschlagen." >&2
  exit 1
fi

echo "Combined Lenovo marker 0x7a/0xf0 applied successfully."

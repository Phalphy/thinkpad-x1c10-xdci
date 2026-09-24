#!/usr/bin/env bash
set -euo pipefail

gadget=/sys/kernel/config/usb_gadget/x1c10_xdci_test

if [[ $EUID -ne 0 ]]; then
  echo "Run as root." >&2
  exit 1
fi

if [[ ! -d $gadget ]]; then
  echo "Test gadget is not active."
  exit 0
fi

printf '' > "$gadget/UDC"
rm -f "$gadget/configs/c.1/hid.usb0"
rmdir "$gadget/functions/hid.usb0"
rmdir "$gadget/configs/c.1/strings/0x409"
rmdir "$gadget/configs/c.1"
rmdir "$gadget/strings/0x409"
rmdir "$gadget"
echo "Test gadget removed."

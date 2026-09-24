#!/usr/bin/env bash
set -euo pipefail

gadget=/sys/kernel/config/usb_gadget/x1c10_xdci_test
udc=dwc3.1.auto

if [[ $EUID -ne 0 ]]; then
  echo "Run as root." >&2
  exit 1
fi

modprobe libcomposite

if [[ -d $gadget ]]; then
  current_udc=$(cat "$gadget/UDC" 2>/dev/null || true)
  if [[ -n $current_udc ]]; then
    printf '' > "$gadget/UDC"
  fi
  rm -f "$gadget/configs/c.1/hid.usb0"
  rmdir "$gadget/functions/hid.usb0" 2>/dev/null || true
  rmdir "$gadget/configs/c.1/strings/0x409" 2>/dev/null || true
  rmdir "$gadget/configs/c.1" 2>/dev/null || true
  rmdir "$gadget/strings/0x409" 2>/dev/null || true
  rmdir "$gadget" 2>/dev/null || true
fi

mkdir -p "$gadget"
printf '0x1d6b' > "$gadget/idVendor"
printf '0x0104' > "$gadget/idProduct"
printf '0x0200' > "$gadget/bcdUSB"
printf '0x0100' > "$gadget/bcdDevice"

mkdir -p "$gadget/strings/0x409"
printf 'X1C10-XDCI-TEST' > "$gadget/strings/0x409/serialnumber"
printf 'Linux xDCI Research' > "$gadget/strings/0x409/manufacturer"
printf 'xDCI HID Test Gadget' > "$gadget/strings/0x409/product"

mkdir -p "$gadget/configs/c.1/strings/0x409"
printf 'HID test configuration' > "$gadget/configs/c.1/strings/0x409/configuration"
printf '120' > "$gadget/configs/c.1/MaxPower"

mkdir -p "$gadget/functions/hid.usb0"
printf '1' > "$gadget/functions/hid.usb0/protocol"
printf '1' > "$gadget/functions/hid.usb0/subclass"
printf '8' > "$gadget/functions/hid.usb0/report_length"
printf '\x05\x01\x09\x06\xa1\x01\x05\x07\x19\xe0\x29\xe7\x15\x00\x25\x01\x75\x01\x95\x08\x81\x02\x95\x01\x75\x08\x81\x01\x95\x05\x75\x01\x05\x08\x19\x01\x29\x05\x91\x02\x95\x01\x75\x03\x91\x01\x95\x06\x75\x08\x15\x00\x25\x65\x05\x07\x19\x00\x29\x65\x81\x00\xc0' > "$gadget/functions/hid.usb0/report_desc"

ln -s "$gadget/functions/hid.usb0" "$gadget/configs/c.1/hid.usb0"

if [[ ! -e /sys/class/udc/$udc ]]; then
  echo "UDC $udc is missing." >&2
  exit 1
fi

printf '%s' "$udc" > "$gadget/UDC"
echo "Bound HID test gadget to $udc."

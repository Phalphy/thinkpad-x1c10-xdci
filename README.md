# Enable native USB gadget mode on a ThinkPad X1 Carbon Gen 10

## Result

On 2026-09-24, a stock ThinkPad X1 Carbon Gen 10 was made to expose its hidden
Intel TCSS xDCI controller without an SPI programmer or added USB hardware. The
controller is a real DWC3 USB Device Controller and registers with Linux's USB
Gadget subsystem.

This is a verified result for the following machine and firmware:

| Item | Verified value |
| --- | --- |
| ThinkPad type | `21CCS4MF00` |
| BIOS | `N3AET87W` 1.52, 2025-08-06 |
| Target variable | `SaSetup`, GUID `72c5e28c-7783-43a1-8767-fad73fccafa4` |
| Target payload byte | `0xBF` |
| Old/new value | `0x00` -> `0x01` |
| xDCI PCI function | `00:0d.1`, `8086:460e` |
| Linux driver | `dwc3-pci` |
| Registered UDC | `dwc3.1.auto`, `USB_UDC_NAME=dwc3-gadget` |

Do not reuse the `SaSetup` offset on a different BIOS build without extracting
and checking that build's IFR. The USB-marker offsets described below are disk
byte offsets; the `SaSetup` offset is an offset inside the firmware variable.

## What was new in this reproduction

The Lenovo service-marker method originated in a ThinkPad community post. That
post reports X1 Carbon Gen 10 Advanced-menu access with marker `0x7A` and also
documents the combined `0x7A` + `0xF0` form as an NVRAM-unprotect mechanism.
This project did not discover those marker values.

The contribution established here is the complete machine-specific chain:

1. extract the exact Gen-10 `SaSetup[0xBF]` TCSS xDCI setting from BIOS 1.52;
2. confirm that a normal EFI `SetVariable` call returns
   `EFI_WRITE_PROTECTED`;
3. apply both Lenovo service markers to the same bootable modGRUB USB medium;
4. change only `SaSetup[0xBF]` from `0` to `1`;
5. verify the expected `8086:460e` PCI function, `dwc3-pci`, and a live Linux
   UDC after reboot.

Source for the Lenovo marker mechanism:
<https://www.reddit.com/r/thinkpad/comments/1vj1udn/how_to_enter_advanced_bios_options_on_gen_1_t15gp/>

Technical precedent for ThinkPad xDCI, on a Gen 6 with a different variable and
PCI function: <https://xairy.io/articles/thinkpad-xdci>

## Why the first write failed

With only decimal byte 10 set to `0x7A`, modGRUB could read the target but the
write was rejected:

```text
setup_var_cv SaSetup 0xBF 0x01 0x01
error: can't set variable using efi (error: 0x8000000000000008)
```

UEFI status code 8 is `EFI_WRITE_PROTECTED`. Repeating the operation through
efivarfs, CHIPSEC, RU.efi, or another frontend would still hit the protected
firmware variable service.

Official status-code reference:
<https://uefi.org/specs/UEFI/2.10/Apx_D_Status_Codes.html>

The successful medium also had decimal byte 21 changed from `0xF8` to `0xF0`.
The same write then succeeded, and an immediate read returned `0x01`.

## Critical offset warning

The marker commands use **decimal offsets** because `dd seek=10` and `seek=21`
interpret their arguments as decimal numbers:

```bash
printf '\x7a' | sudo dd of=/dev/sdX bs=1 seek=10 count=1 conv=notrunc,fsync
printf '\xf0' | sudo dd of=/dev/sdX bs=1 seek=21 count=1 conv=notrunc,fsync
```

Do not translate them to hexadecimal offsets `0x10` and `0x21`, which are
decimal 16 and 33. Those locations are FAT BPB geometry fields; writing there
can make the medium appear corrupt or non-bootable.

Marker `0xF0` deliberately makes the boot-sector media byte differ from the
first FAT entry. Some userspace FAT tools reject that mismatch. OVMF and the
physical X1 Carbon both booted the tested medium to the GRUB prompt, and
`fsck.fat -n` still found all files. Reformat the disposable medium after use.

## Reproduction procedure

### 1. Confirm the exact firmware setting

For BIOS N3AET87W 1.52, the verified target is:

```text
SaSetup GUID: 72c5e28c-7783-43a1-8767-fad73fccafa4
payload size: 0x4E7
TCSS xDCI Support: offset 0xBF, size 1, disabled=0, enabled=1
```

Firmware analysis also showed that this setting gates ACPI/PCI device `TXDC`
at `00:0d.1`, expected device ID `8086:460e`.

### 2. Create a disposable UEFI boot medium

Format the complete USB medium as FAT32, not a partition, and install:

```text
/EFI/BOOT/BOOTX64.EFI  modGRUBShell 1.4
/tools/setup_var.efi   setup_var.efi 0.3.1
```

The binaries used in the successful test had these hashes:

```text
9b469c1a41d0d73e2432c09bfd3ee33be0b40a00bd8927fd4f8a003637b9d54d  BOOTX64.EFI
cbe5777b61276d3f3506a28b34845326e92f6c171bff59177e3912fe20f49840  setup_var.efi
```

Upstream projects:

- <https://github.com/datasone/grub-mod-setup_var>
- <https://github.com/datasone/setup_var.efi>

### 3. Apply both Lenovo markers

Resolve the removable drive carefully, unmount it, and run:

```bash
sudo ./scripts/set-x1c10-nvram-unprotect-marker.sh /dev/sdX APPLY
```

The script refuses partitions, mounted devices, non-USB/non-removable disks,
unexpected starting bytes, and media without a boot-sector signature. It does
not format the drive or copy files.

Expected final verification:

```text
After: byte[10]=0x7a, byte[21]=0xf0
```

### 4. Change the single firmware byte

Fully power off the ThinkPad, boot the USB medium through the F12 menu, and run:

```text
setup_var_cv SaSetup 0xBF
setup_var_cv SaSetup 0xBF 0x01 0x01
setup_var_cv SaSetup 0xBF
```

The first read should show `0x00`; the final read must show:

```text
offset 0xbf is: 0x01
```

Reboot and remove the USB medium.

### 5. Validate Linux gadget support

```bash
lspci -nnk -s 00:0d.1
ls -l /sys/class/udc
cat /sys/class/udc/dwc3.1.auto/uevent
cat /sys/class/udc/dwc3.1.auto/maximum_speed
```

Verified output:

```text
00:0d.1 USB controller [0c03]: Intel Corporation Device [8086:460e]
        Kernel driver in use: dwc3-pci

USB_UDC_NAME=dwc3-gadget
super-speed
```

Both Type-C class ports additionally reported `host [device]` for data role and
`source [sink]` for power role. Physical receptacle mapping and enumeration
against an external USB host remain the next empirical tests.

## Minimal gadget smoke test

This repository contains a no-keystroke HID descriptor for enumeration testing:

```bash
sudo ./scripts/start-xdci-hid-test-gadget.sh
cat /sys/class/udc/dwc3.1.auto/state
sudo ./scripts/stop-xdci-test-gadget.sh
```

Before attachment, the expected state is `not attached`. After connecting a
known USB host to the xDCI-routed receptacle, state should progress through USB
enumeration and normally reach `configured`.

## Rollback

The firmware change is one byte. Boot the same service-marker medium and run:

```text
setup_var_cv SaSetup 0xBF 0x01 0x00
setup_var_cv SaSetup 0xBF
```

The final value must be `0x00`. After reboot, `00:0d.1` and the UDC should no
longer be present. Reformat the disposable USB medium to remove its service
markers and restore normal FAT-tool compatibility.

## Confidence boundary

- **Certain:** the result and outputs above were measured on type 21CCS4MF00,
  BIOS N3AET87W 1.52.
- **High confidence:** the combined service marker is what removed the variable
  write protection; the same command failed immediately before it was applied.
- **Unverified:** other X1 Carbon Gen 10 BIOS revisions, other Lenovo models,
  physical port mapping, VBUS behavior, suspend/resume, and end-use protocols.

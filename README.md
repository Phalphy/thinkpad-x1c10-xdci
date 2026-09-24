# Enable native USB gadget mode on a ThinkPad X1 Carbon Gen 10

## Result

On 2026-09-24, a stock ThinkPad X1 Carbon Gen 10 was made to expose both hidden
Intel xDCI functions without an SPI programmer or added USB hardware. The TCSS
and PCH functions both bind to Linux's DWC3 driver and register separate UDCs
with the USB Gadget subsystem.

This is a verified result for the following machine and firmware:

| Item | Verified value |
| --- | --- |
| ThinkPad type | `21CCS4MF00` |
| BIOS | `N3AET87W` 1.52, 2025-08-06 |
| TCSS variable | `SaSetup[0xBF]`, GUID `72c5e28c-7783-43a1-8767-fad73fccafa4` |
| PCH variable | `PchSetup[0x47]`, GUID `4570b7f1-ade8-4943-8dc3-406472842384` |
| Old/new value | `0x00` -> `0x01` for both bytes |
| TCSS xDCI function | `00:0d.1`, `8086:460e`, UDC `dwc3.1.auto` |
| PCH xDCI function | `00:14.1`, `8086:51ee`, UDC `dwc3.2.auto` |
| Linux driver | `dwc3-pci` |

Do not reuse either variable offset on a different BIOS build without extracting
and checking that build's IFR. The USB-marker offsets described below are disk
byte offsets; the setup offsets are payload offsets inside firmware variables.

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
4. change `SaSetup[0xBF]` from `0` to `1` and verify the resulting TCSS UDC;
5. establish through a live USB-host test that TCSS-only activation leaves the
   UDC `not attached` despite correct Type-C role negotiation and active
   DWC3/PHY;
6. change `PchSetup[0x47]` from `0` to `1` and verify the second, PCH-side xDCI
   function and UDC after reboot.

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

PchSetup GUID: 4570b7f1-ade8-4943-8dc3-406472842384
payload size: 0x852
xDCI Support (USB OTG Device): offset 0x47, size 1, disabled=0, enabled=1
```

Firmware analysis showed that the TCSS setting gates ACPI/PCI device `TXDC` at
`00:0d.1`, expected device ID `8086:460e`. The PCH setting subsequently exposed
`00:14.1`, device ID `8086:51ee`, exactly as measured after reboot.

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

### 4. Enable both split-xDCI firmware bytes

Fully power off the ThinkPad, boot the USB medium through the F12 menu, and run:

```text
setup_var_cv SaSetup 0xBF
setup_var_cv SaSetup 0xBF 0x01 0x01
setup_var_cv SaSetup 0xBF
setup_var_cv PchSetup 0x47
setup_var_cv PchSetup 0x47 0x01 0x01
setup_var_cv PchSetup 0x47
```

The first reads should show `0x00`; both final reads must show:

```text
offset 0xbf is: 0x01
offset 0x47 is: 0x01
```

Reboot and remove the USB medium.

### 5. Validate Linux gadget support

```bash
lspci -nnk -s 00:0d.1
lspci -nnk -s 00:14.1
ls -l /sys/class/udc
cat /sys/class/udc/dwc3.1.auto/uevent
cat /sys/class/udc/dwc3.2.auto/uevent
```

Verified output:

```text
00:0d.1 USB controller [0c03]: Intel Corporation Device [8086:460e]
        Kernel driver in use: dwc3-pci

00:14.1 USB controller [0c03]: Intel Corporation Device [8086:51ee]
        Kernel driver in use: dwc3-pci

/sys/class/udc/dwc3.1.auto
/sys/class/udc/dwc3.2.auto
```

With only `SaSetup[0xBF]` enabled, both Type-C class ports reported
`host [device]` for data role and `source [sink]` for power role against an
external USB host, but `dwc3.1.auto` remained `not attached` on both
receptacles. Direct read-only MMIO inspection showed peripheral mode, RUN/STOP
active, and the TCSS USB2/USB3 PHY powered.

The second setting exposed `00:14.1 [8086:51ee]` and `dwc3.2.auto`, matching
Intel's documented Alder Lake split-xDCI architecture. A gadget binds to that
UDC. Physical attachment after the second change is not yet tested.

Sources for the split-controller interpretation:

- <https://edc.intel.com/content/www/pl/pl/design/ipla/software-development-platforms/client/platforms/alder-lake-desktop/intel-600-series-chipset-family-platform-controller-hub-pch-datasheet-volume/001/usb-dual-role-support-extensible-device-controller-interface-xdci-controller/>
- <https://lkml.iu.edu/hypermail/linux/kernel/2209.1/05223.html>
- <https://github.com/torvalds/linux/blob/master/drivers/usb/dwc3/dwc3-pci.c>

## Minimal gadget smoke test

This repository contains a no-keystroke HID descriptor for enumeration testing:

```bash
sudo ./scripts/start-xdci-hid-test-gadget.sh dwc3.2.auto
cat /sys/class/udc/dwc3.2.auto/state
sudo ./scripts/stop-xdci-test-gadget.sh
```

Before attachment, the expected state is `not attached`. After connecting a
known USB host to the xDCI-routed receptacle, state should progress through USB
enumeration and normally reach `configured`.

## Proposed rollback (not yet tested)

The verified enable commands wrote one-byte values of `0x01`:

```text
setup_var_cv SaSetup 0xBF 0x01 0x01
setup_var_cv PchSetup 0x47 0x01 0x01
```

According to the upstream `setup_var_cv` syntax, the third argument is the
variable size and the fourth is the value. The syntactic inverse is therefore
to write the one-byte value `0x00`. This rollback has **not** been executed on
the tested machine. If you choose to test it, boot the same service-marker
medium, read the current value first, write zero, and read it back:

```text
setup_var_cv SaSetup 0xBF
setup_var_cv SaSetup 0xBF 0x01 0x00
setup_var_cv SaSetup 0xBF
setup_var_cv PchSetup 0x47
setup_var_cv PchSetup 0x47 0x01 0x00
setup_var_cv PchSetup 0x47
```

Both expected final values are `0x00`. Based on the decoded firmware conditions,
`00:0d.1`, `00:14.1`, and their UDCs are then expected to disappear after
reboot, but neither rollback nor either post-reboot result has been verified.
Reformat the disposable USB medium afterward to remove its service markers and
restore normal FAT-tool compatibility.

## Confidence boundary

- **Certain:** both firmware writes, PCI functions, driver bindings, UDCs, and
  the TCSS-only negative attachment test above were measured on type
  21CCS4MF00, BIOS N3AET87W 1.52.
- **High confidence:** the combined service marker is what removed the variable
  write protection; the same command failed immediately before it was applied.
- **Unverified:** rollback to `0x00`, other X1 Carbon Gen 10 BIOS revisions,
  other Lenovo models, attachment through `dwc3.2.auto`, VBUS behavior,
  suspend/resume, and end-use protocols.

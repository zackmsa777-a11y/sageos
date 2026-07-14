#!/bin/bash
# ============================================================
# SageOS — ISO assembly step (BIOS + UEFI hybrid)
# Run this against a staged ISO tree (isolinux/, boot/, EFI/, efi.img)
# to produce the final bootable .iso.
#
# SUPERSEDED: build.sh in this same directory is now the real, current,
# versioned build script (debootstrap + OpenRC + sage-pkg pipeline,
# v5.3+) and includes this exact ISO-packing step as its Stage 9 —
# this standalone file is kept only for quick reference/manual reruns
# against an already-staged ISO tree. Prefer build.sh end-to-end.
# ============================================================
set -e

ISO_TREE="${1:-iso-tree}"     # directory with isolinux/, boot/, EFI/, efi.img
OUTPUT="${2:-sageos.iso}"
VOLID="${3:-SAGEOS}"

xorriso -as mkisofs -iso-level 3 -full-iso9660-filenames -volid "$VOLID" \
  -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \
  -eltorito-boot isolinux/isolinux.bin -eltorito-catalog isolinux/boot.cat \
  -no-emul-boot -boot-load-size 4 -boot-info-table \
  -eltorito-alt-boot -e efi.img -no-emul-boot -isohybrid-gpt-basdat \
  -output "$OUTPUT" "$ISO_TREE"

# ------------------------------------------------------------
# Two hard-won fixes baked into this command / the tree it reads:
#
# 1. UEFI boot entry MUST point at the FAT-formatted `efi.img` file
#    (`-e efi.img`), NOT at the raw `EFI/BOOT/BOOTX64.EFI` executable
#    path inside the ISO9660 tree. Real UEFI firmware (tested with
#    OVMF/EDK II) expects the El Torito alt-boot entry to be a block
#    device image it can mount and then find \EFI\BOOT\BOOTX64.EFI
#    inside — pointing it at the bare .EFI file instead makes
#    firmware report "BdsDxe: failed to load Boot0001 ... Not Found"
#    and fall through to the UEFI interactive shell / PXE, never
#    reaching GRUB. (Root-caused & fixed in v5.1-beta6.)
#
# 2. Kernel cmdline in boot/grub/grub.cfg and isolinux/isolinux.cfg
#    MUST list `console=ttyS0 console=tty0` in that order — tty0
#    LAST. Linux binds /dev/console to whichever console= is listed
#    last, and /dev/console is what our init script's stdout, the
#    banner, fastfetch, and the login shell all write to. Listing
#    ttyS0 last (the previous, wrong order) sent all of that only to
#    serial, leaving the screen dark forever after early kernel
#    messages — looked exactly like a boot hang in VirtualBox/QEMU
#    GUI/UTM, even though the system booted fine underneath.
#    (Root-caused & fixed in v5.1-beta5.)
# ------------------------------------------------------------

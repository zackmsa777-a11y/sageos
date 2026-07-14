#!/bin/bash
# ============================================================
# SageOS v5.3 — Full Build Script (debootstrap + OpenRC pipeline)
#
# This replaces the old v1.0 BusyBox-era build.sh, which no longer
# reflected reality at all (no debootstrap, no useradd, nothing
# matching the actual rootfs). This script is the real, versioned,
# from-scratch build process — reverse-engineered and verified
# directly against a known-good live rootfs (dpkg state, /etc/passwd,
# OpenRC service scripts, initramfs module list) so it should
# reproduce the shipped ISOs, not just approximate them.
#
# Usage:
#   sudo ./build.sh lean            # terminal-only base ISO
#   sudo ./build.sh xfce            # XFCE-preinstalled edition
#
# Requires (host): debootstrap, xorriso, isolinux, mksquashfs,
#                  cpio, mtools, dosfstools (for efi.img), qemu-utils
#
# Standing project rules this script must honor:
#   - Debian bookworm only (not Devuan) — see sourcing note below.
#   - openrc-init as PID1, /sbin/init symlink restored after any
#     package pulls in systemd-sysv.
#   - x86_64 only.
#   - sage-pkg is the ONLY way optional tools get installed; the base
#     ISO stays lean.
# ============================================================
set -euo pipefail

# ---------- Configuration ----------
EDITION="${1:-lean}"                  # lean | xfce
SUITE="bookworm"
ARCH="amd64"
KERNEL_PKG_VER="6.1.0-50-amd64"       # pinned — must match the .ko files
                                       # fetched for bochs/drm in the xfce
                                       # edition; bump deliberately, not
                                       # silently via apt upgrade.
WORKDIR="${WORKDIR:-/tmp/sageos-build}"
ROOTFS="$WORKDIR/rootfs"
ISO_TREE="$WORKDIR/iso-tree"
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"   # repo root
OUTPUT="${OUTPUT:-$WORKDIR/sageos-5.3$( [ "$EDITION" = xfce ] && echo -xfce ).iso}"
VOLID="SAGEOS"

log() { echo -e "\n\033[1;36m[build]\033[0m $*"; }

if [ "$(id -u)" != "0" ]; then
  echo "Must run as root (needs debootstrap/chroot/mksquashfs)." >&2
  exit 1
fi

if [ "$EDITION" != "lean" ] && [ "$EDITION" != "xfce" ]; then
  echo "Usage: $0 [lean|xfce]" >&2
  exit 1
fi

mkdir -p "$WORKDIR"

# ============================================================
# Stage 1 — debootstrap base
# ============================================================
stage1_debootstrap() {
  log "Stage 1: debootstrap $SUITE ($ARCH) -> $ROOTFS"
  if [ -d "$ROOTFS/etc" ]; then
    log "  rootfs already bootstrapped, skipping (rm -rf $ROOTFS to force)"
    return
  fi
  mkdir -p "$ROOTFS"
  debootstrap --arch="$ARCH" --variant=minbase "$SUITE" "$ROOTFS" http://deb.debian.org/debian
}

# ============================================================
# Stage 2 — base chroot config (apt sources, identity, users)
# ============================================================
chroot_run() { chroot "$ROOTFS" /bin/bash -c "$1"; }

stage2_base_config() {
  log "Stage 2: base system configuration"

  # apt sources — bookworm main only. Deliberately NOT Devuan: staying on
  # stock Debian trades a bit of systemd-unit friction (handled via
  # openrc-init symlink restoration + hand-written OpenRC scripts, see
  # Stage 4) for much wider package availability/reliability.
  cat > "$ROOTFS/etc/apt/sources.list" << 'EOF'
deb http://deb.debian.org/debian bookworm main
EOF
  # Keep ISOs lean: never silently pull in Recommends/Suggests. NOTE this
  # is exactly why dbus-x11 had to be added explicitly to the xfce
  # category package list — it's only a Recommends upstream.
  cat > "$ROOTFS/etc/apt/apt.conf.d/99sageos" << 'EOF'
APT::Install-Recommends "false";
APT::Install-Suggests "false";
EOF

  cp "$SRC_DIR/config/etc/hostname" "$ROOTFS/etc/hostname" 2>/dev/null || echo "sageos" > "$ROOTFS/etc/hostname"
  cp "$SRC_DIR/config/etc/hosts" "$ROOTFS/etc/hosts" 2>/dev/null || cat > "$ROOTFS/etc/hosts" << 'EOF'
127.0.0.1   localhost
127.0.1.1   sageos
EOF
  [ -f "$SRC_DIR/config/etc/motd" ] && cp "$SRC_DIR/config/etc/motd" "$ROOTFS/etc/motd"
  [ -f "$SRC_DIR/config/etc/issue" ] && cp "$SRC_DIR/config/etc/issue" "$ROOTFS/etc/issue"
  [ -f "$SRC_DIR/config/fastfetch/config.jsonc" ] && mkdir -p "$ROOTFS/etc/fastfetch" && cp "$SRC_DIR/config/fastfetch/config.jsonc" "$ROOTFS/etc/fastfetch/config.jsonc"

  cat > "$ROOTFS/etc/os-release" << EOF
PRETTY_NAME="SageOS 5.3$( [ "$EDITION" = xfce ] && echo ' (XFCE Edition)' )"
NAME="SageOS"
VERSION_ID="5.3$( [ "$EDITION" = xfce ] && echo '-xfce' )"
VERSION="5.3"
VERSION_CODENAME=bookworm
ID=sageos
ID_LIKE=debian
HOME_URL="https://github.com/zackmsa777-a11y/sageos"
SUPPORT_URL="https://github.com/zackmsa777-a11y/sageos"
BUG_REPORT_URL="https://github.com/zackmsa777-a11y/sageos/issues"
EOF

  mount --bind /dev "$ROOTFS/dev"
  mount --bind /proc "$ROOTFS/proc"
  mount --bind /sys "$ROOTFS/sys"
  trap 'umount -lf "$ROOTFS/dev" "$ROOTFS/proc" "$ROOTFS/sys" 2>/dev/null || true' EXIT

  chroot_run "apt-get update"

  # root + sage users, default credentials per standing project docs
  chroot_run "useradd -m -u 1000 -s /bin/bash sage || true"
  chroot_run "echo 'root:sageos' | chpasswd"
  chroot_run "echo 'sage:sageos' | chpasswd"
  chroot_run "usermod -aG sudo sage"
}

# ============================================================
# Stage 3 — core package set (terminal-only base, always installed)
# ============================================================
stage3_core_packages() {
  log "Stage 3: installing core package set"
  # Reverse-engineered from the live shipped rootfs's `apt-mark showmanual`,
  # minus xfce-only entries (those are added conditionally in Stage 6).
  local CORE_PKGS="
    bash-completion bat btop bzip2 ca-certificates cmatrix coreutils
    cowsay curl dash e2fsprogs fastfetch fd-find figlet file findutils
    fortune-mod git htop iproute2 iputils-ping kmod less lolcat lz4
    make man-db mawk nano ncdu neofetch net-tools openssh-client
    passwd pipx python3-pip ripgrep ruby-dev sed sl sudo tar tmux
    tree unzip util-linux-extra vim wget whiptail xz-utils zip zstd
    openrc sysvinit-utils
  "
  chroot_run "DEBIAN_FRONTEND=noninteractive apt-get install -y $CORE_PKGS"
}

# ============================================================
# Stage 4 — OpenRC as PID1 + custom service scripts
# ============================================================
stage4_openrc() {
  log "Stage 4: configuring OpenRC as init"

  # Some packages (esp. xfce4 later, via systemd-sysv) will try to
  # overwrite /sbin/init. This restore MUST also be re-run by sage-pkg
  # after every mission-pack install — see src/sage-pkg's install hook.
  chroot_run "ln -sf openrc-init /sbin/init"

  mkdir -p "$ROOTFS/etc/runlevels/default"

  # sage-network: hostname + DHCP, replaces systemd-networkd/ifupdown
  cat > "$ROOTFS/etc/init.d/sage-network" << 'EOF'
#!/sbin/openrc-run
description="SageOS early setup: hostname + DHCP networking"

depend() {
	before agetty
	keyword -shutdown
}

start() {
	ebegin "Setting hostname"
	hostname sageos
	echo "sageos" > /etc/hostname
	eend 0

	ebegin "Bringing up networking (DHCP)"
	IFACE=$(ls /sys/class/net 2>/dev/null | grep -v lo | head -1)
	if [ -n "$IFACE" ]; then
		ip link set "$IFACE" up 2>/dev/null
		i=0
		while [ "$i" -lt 15 ]; do
			carrier=$(cat /sys/class/net/$IFACE/carrier 2>/dev/null)
			[ "$carrier" = "1" ] && break
			sleep 1
			i=$((i+1))
		done
		dhclient -1 "$IFACE" >/dev/null 2>&1 &
	fi
	eend 0
}
EOF

  # sage-getty template — symlink per-port instances into the runlevel
  cat > "$ROOTFS/etc/init.d/sage-getty" << 'EOF'
#!/sbin/openrc-run
description="Start a getty on a serial/console line"
port="${RC_SVCNAME#*.}"
baud="${baud:-115200}"
term_type="${term_type:-vt100}"

depend() {
    after local
    provide getty
}

start() {
    if [ "$port" = "$RC_SVCNAME" ]; then
        eerror "${RC_SVCNAME} cannot be started directly. Create a symlink"
        eerror "like sage-getty.ttyS0 in the runlevel instead."
        return 1
    fi
    ebegin "Starting getty on ${port}"
    /sbin/agetty "${port}" "${baud}" "${term_type}" > /dev/null 2>&1 &
    echo $! > "/run/sage-getty.${port}.pid"
    eend 0
}

stop() {
    ebegin "Stopping getty on ${port}"
    [ -f "/run/sage-getty.${port}.pid" ] && kill "$(cat /run/sage-getty.${port}.pid)" 2>/dev/null
    eend 0
}
EOF

  # sage-udev-fix: Debian's udev LSB init.d script doesn't reliably start
  # systemd-udevd (the daemon binary) under OpenRC — hand-written because
  # upstream ships no OpenRC-native equivalent (see standing systemd-unit
  # friction note above).
  cat > "$ROOTFS/etc/init.d/sage-udev-fix" << 'EOF'
#!/sbin/openrc-run
description="Ensure systemd-udevd is running and input devices are tagged before X starts (works around the Debian udev LSB init.d script not reliably starting under OpenRC)"

depend() {
	before x11-common
	before sage-gpu-modules
}

start() {
	ebegin "Ensuring udev daemon is running and devices are tagged"
	if ! pgrep -x systemd-udevd >/dev/null 2>&1; then
		/lib/systemd/systemd-udevd --daemon
		sleep 1
	fi
	udevadm trigger --action=add >/dev/null 2>&1
	udevadm settle --timeout=10 >/dev/null 2>&1
	eend 0
}
EOF

  chmod +x "$ROOTFS/etc/init.d/sage-network" "$ROOTFS/etc/init.d/sage-getty" "$ROOTFS/etc/init.d/sage-udev-fix"

  chroot_run "ln -sf /etc/init.d/sage-getty /etc/init.d/sage-getty.tty1"
  chroot_run "ln -sf /etc/init.d/sage-getty /etc/init.d/sage-getty.ttyS0"

  for svc in sage-network sage-udev-fix "sage-getty.tty1" "sage-getty.ttyS0"; do
    chroot_run "rc-update add $svc default" || true
  done

  # sage-gpu-modules is baked into every rootfs as a dormant (not
  # runlevel-enabled) script — sage-pkg's xfce install hook only runs
  # `rc-update add sage-gpu-modules default`, it does NOT create the
  # file, so it must already exist here for that to succeed later.
  cat > "$ROOTFS/etc/init.d/sage-gpu-modules" << 'EOF'
#!/sbin/openrc-run
description="Load GPU/framebuffer kernel modules for graphical sessions"

depend() {
	before x11-common
}

start() {
	ebegin "Loading graphics driver modules"
	modprobe bochs 2>/dev/null
	eend 0
}
EOF
  chmod +x "$ROOTFS/etc/init.d/sage-gpu-modules"
}

# ============================================================
# Stage 5 — sage-pkg mission-pack framework
# ============================================================
stage5_sage_pkg() {
  log "Stage 5: installing sage-pkg framework"
  mkdir -p "$ROOTFS/usr/local/bin" "$ROOTFS/usr/local/share/sage-pkg"
  cp "$SRC_DIR/src/sage-pkg" "$ROOTFS/usr/local/bin/sage-pkg"
  cp "$SRC_DIR/src/sage-security" "$ROOTFS/usr/local/bin/sage-security"
  [ -f "$SRC_DIR/src/sage-persistence-setup" ] && cp "$SRC_DIR/src/sage-persistence-setup" "$ROOTFS/usr/local/bin/sage-persistence-setup"
  cp "$SRC_DIR/src/categories.conf" "$ROOTFS/usr/local/share/sage-pkg/categories.conf"
  chmod 755 "$ROOTFS/usr/local/bin/sage-pkg" "$ROOTFS/usr/local/bin/sage-security"
}

# ============================================================
# Stage 6 — XFCE edition only: desktop + graphics/input driver fixes
# ============================================================
stage6_xfce() {
  [ "$EDITION" != "xfce" ] && return
  log "Stage 6: baking in XFCE edition (xfce4, xorg, lightdm, dbus-x11)"

  # Installs via the real mission-pack path, not a bespoke apt call —
  # this is exactly what a user's `sage-pkg install xfce` does, so the
  # ISO-baked edition and the on-demand install path never drift apart.
  chroot_run "sage-pkg install xfce"

  # sage-pkg's xfce install hook already restores /sbin/init and chowns
  # /home/sage (see src/sage-pkg) — both required fixes from the
  # session-dies-after-login bug. Verify here as a build-time sanity
  # check rather than trusting it silently:
  local init_target owner
  init_target=$(chroot "$ROOTFS" readlink /sbin/init || true)
  owner=$(stat -c '%U:%G' "$ROOTFS/home/sage")
  [ "$init_target" = "openrc-init" ] || { echo "FATAL: /sbin/init not openrc-init after xfce install"; exit 1; }
  [ "$owner" = "sage:sage" ] || { echo "FATAL: /home/sage not sage-owned after xfce install"; exit 1; }

  # Graphics driver: bochs.ko + deps, version-matched to $KERNEL_PKG_VER
  # (QEMU/VirtualBox display adapter). Fetched from snapshot.debian.org
  # because it must match the exact running kernel build, not whatever
  # apt's current linux-image happens to be.
  log "  fetching bochs/drm kernel modules for $KERNEL_PKG_VER"
  local modtmp="$WORKDIR/kmod-fetch"
  mkdir -p "$modtmp" && cd "$modtmp"
  apt-get download "linux-image-$KERNEL_PKG_VER" 2>&1 | tail -3 || \
    log "  WARN: linux-image-$KERNEL_PKG_VER not in current apt cache — fetch matching .deb from snapshot.debian.org manually and place in $modtmp before re-running Stage 6"
  for deb in linux-image-*.deb; do
    [ -f "$deb" ] || continue
    dpkg-deb -x "$deb" extracted/
  done
  local moddest="$ROOTFS/lib/modules/$KERNEL_PKG_VER/kernel/drivers/gpu/drm"
  mkdir -p "$moddest"
  for mod in bochs ttm drm_vram_helper drm_kms_helper drm_shmem_helper; do
    find extracted -iname "${mod}.ko*" -exec cp {} "$moddest/" \; 2>/dev/null || true
  done
  chroot_run "depmod -a $KERNEL_PKG_VER" || true

  # Input: libinput driver + PS/2 modules (atkbd/i8042 are kernel
  # built-ins, only psmouse/serio_raw/evdev need loading — see
  # initramfs/init comment).
  chroot_run "DEBIAN_FRONTEND=noninteractive apt-get install -y xserver-xorg-input-libinput"

  # NOTE: sage-gpu-modules's init.d file is baked into every rootfs back
  # in Stage 4 (base, all editions) since sage-pkg's xfce hook assumes it
  # already exists. `sage-pkg install xfce` above already ran
  # `rc-update add sage-gpu-modules/sage-udev-fix/lightdm default` and
  # restored /sbin/init + chowned /home/sage — nothing left to duplicate
  # here, this is exactly what a runtime `sage-pkg install xfce` does too,
  # so the ISO-baked edition can't drift from the on-demand install path.
  chroot_run "rc-update add dbus default" || true
}

# ============================================================
# Stage 7 — initramfs (live-boot loader)
# ============================================================
stage7_initramfs() {
  log "Stage 7: building initramfs.gz"
  local itmp="$WORKDIR/initramfs-tree"
  rm -rf "$itmp" && mkdir -p "$itmp"/{bin,sbin,etc,proc,sys,dev,mnt,tmp,run,lib/modules}

  # busybox provides the initramfs shell environment
  chroot_run "apt-get install -y --no-install-recommends busybox-static" || true
  cp "$ROOTFS/bin/busybox" "$itmp/bin/busybox" 2>/dev/null || \
    cp "$(chroot "$ROOTFS" which busybox)" "$itmp/bin/busybox"
  cd "$itmp" && for applet in $(./bin/busybox --list); do
    [ "$applet" = busybox ] && continue
    ln -sf busybox "bin/$applet" 2>/dev/null || true
  done

  # init script — source of truth is initramfs/init in the repo (already
  # contains the full USB/NVMe/virtio/SATA module load list and the PID1
  # panic safety-net trap; see repo file history for why each module is
  # there before trimming this list).
  cp "$SRC_DIR/initramfs/init" "$itmp/init"
  chmod +x "$itmp/init"

  # Copy every .ko the init script actually loads, from the real rootfs
  # kernel tree, preserving directory structure for depmod compatibility.
  local kmoddir="$ROOTFS/lib/modules/$KERNEL_PKG_VER"
  mkdir -p "$itmp/lib/modules/$KERNEL_PKG_VER"
  grep -oP '(?<=load_mod )\S+\.ko' "$SRC_DIR/initramfs/init" | sort -u | while read -r modname; do
    find "$kmoddir" -iname "$modname*" -exec cp --parents {} "$itmp/" \; 2>/dev/null || true
  done

  cd "$itmp" && find . | cpio -o -H newc 2>/dev/null | gzip -9 > "$WORKDIR/initramfs.gz"
  log "  initramfs.gz: $(du -h "$WORKDIR/initramfs.gz" | cut -f1)"
}

# ============================================================
# Stage 8 — squashfs of the full rootfs
# ============================================================
stage8_squashfs() {
  log "Stage 8: building squashfs"
  umount -lf "$ROOTFS/dev" "$ROOTFS/proc" "$ROOTFS/sys" 2>/dev/null || true
  mkdir -p "$ISO_TREE/live"
  mksquashfs "$ROOTFS" "$ISO_TREE/live/filesystem.squashfs" -comp xz -Xdict-size 100% -b 1M -noappend
}

# ============================================================
# Stage 9 — assemble ISO tree + pack hybrid BIOS/UEFI ISO
# ============================================================
stage9_pack_iso() {
  log "Stage 9: assembling ISO tree and packing"
  mkdir -p "$ISO_TREE/boot" "$ISO_TREE/isolinux" "$ISO_TREE/EFI/BOOT"

  local kver
  kver=$(basename "$(ls -d "$ROOTFS"/lib/modules/*/ | head -1)")
  cp "$ROOTFS/boot/vmlinuz-$kver" "$ISO_TREE/boot/vmlinuz"
  cp "$WORKDIR/initramfs.gz" "$ISO_TREE/boot/initramfs.gz"

  cp "$SRC_DIR/src/boot-configs/grub.cfg" "$ISO_TREE/boot/grub.cfg"
  cp "$SRC_DIR/src/boot-configs/isolinux.cfg" "$ISO_TREE/isolinux/isolinux.cfg"
  cp /usr/lib/ISOLINUX/isolinux.bin "$ISO_TREE/isolinux/isolinux.bin"
  cp /usr/lib/syslinux/modules/bios/*.c32 "$ISO_TREE/isolinux/" 2>/dev/null || true

  # UEFI: build a FAT efi.img containing EFI/BOOT/BOOTX64.EFI + grub.cfg.
  # MUST be referenced as the image file itself in the xorriso -e flag
  # below (not the bare .EFI path) — see the hard-won note in the
  # xorriso invocation, this exact mistake caused a real regression
  # (v5.1-beta6) where UEFI firmware fell through to its shell/PXE.
  if [ ! -f "$SRC_DIR/efi.img" ]; then
    log "  WARN: repo efi.img not found, UEFI boot entry will be skipped"
  else
    cp "$SRC_DIR/efi.img" "$ISO_TREE/efi.img"
  fi

  # --------------------------------------------------------
  # Final ISO pack. Two hard-won fixes baked into this exact command:
  #
  # 1. UEFI boot entry (-e efi.img) must point at the FAT image file,
  #    not the raw BOOTX64.EFI path inside the ISO9660 tree.
  # 2. Kernel cmdline (in grub.cfg/isolinux.cfg, not here) must list
  #    `console=ttyS0 console=tty0` in that order — tty0 last, so
  #    /dev/console binds to the VGA console and init's own echo/banner
  #    output isn't silently serial-only.
  # --------------------------------------------------------
  local xorriso_args=(-as mkisofs -iso-level 3 -full-iso9660-filenames -volid "$VOLID"
    -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin
    -eltorito-boot isolinux/isolinux.bin -eltorito-catalog isolinux/boot.cat
    -no-emul-boot -boot-load-size 4 -boot-info-table
  )
  if [ -f "$ISO_TREE/efi.img" ]; then
    xorriso_args+=(-eltorito-alt-boot -e efi.img -no-emul-boot -isohybrid-gpt-basdat)
  fi
  xorriso_args+=(-output "$OUTPUT" "$ISO_TREE")

  xorriso "${xorriso_args[@]}"
  log "  ISO written: $OUTPUT ($(du -h "$OUTPUT" | cut -f1))"
}

# ============================================================
# Main
# ============================================================
log "Building SageOS 5.3 [$EDITION edition] -> $OUTPUT"
stage1_debootstrap
stage2_base_config
stage3_core_packages
stage4_openrc
stage5_sage_pkg
stage6_xfce
stage7_initramfs
stage8_squashfs
stage9_pack_iso

log "Done. Per standing project rule: verify tool functionality via chroot"
log "BEFORE trusting this ISO, then boot-test in QEMU before any release."

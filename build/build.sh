#!/bin/bash
# ============================================================
# SageOS v1.0 — Build Script
# A minimal Linux distribution built with BusyBox userspace
# ============================================================
set -e

DISTRO="/app/sagedistro"
ROOTFS="$DISTRO/initramfs"

# --- Prerequisites ---
# apt-get install -y busybox-static linux-image-amd64 xorriso isolinux syslinux-common

# --- 1. Create rootfs structure ---
mkdir -p "$ROOTFS"/{bin,sbin,etc,proc,sys,dev,usr/bin,usr/sbin,root,tmp,home}
chmod 1777 "$ROOTFS/tmp"

# --- 2. Install BusyBox ---
cp -L /bin/busybox "$ROOTFS/bin/busybox"
chmod +x "$ROOTFS/bin/busybox"

# Create symlinks for all applets (except busybox itself)
cd "$ROOTFS"
for applet in $(./bin/busybox --list); do
  [ "$applet" = "busybox" ] && continue
  ln -sf /bin/busybox "bin/$applet" 2>/dev/null || true
done
cd - >/dev/null

# --- 3. Custom init script ---
cat > "$ROOTFS/init" << 'INIT'
#!/bin/busybox sh
/bin/busybox mount -t proc none /proc
/bin/busybox mount -t sysfs none /sys
/bin/busybox mount -t devtmpfs none /dev 2>/dev/null || /bin/busybox mdev -s
hostname sageos
cat << 'BANNER'

   _____                  ___  _____  ___ 
  / ___/___  ______ _   / __ \/ __  / / __ \
  \__ \/ _ \/ ___/ /  / /_/ / /_/ / / /_/ /
 ___/ /  __/ /  / /__/ _, _/ _, _/ / _, _/ 
/____/\___/_/   \___/_/ |_/_/ |_| /_/ |_|  

   v1.0  -  Built with Sage  -  Powered by Linux + BusyBox

BANNER
echo "Welcome to SageOS! Type 'help' for available commands."
echo "Kernel: $(uname -r)  -  Host: $(hostname)"
echo ""
exec /bin/busybox sh
INIT
chmod +x "$ROOTFS/init"

# --- 4. Config files ---
echo "sageos" > "$ROOTFS/etc/hostname"
cat > "$ROOTFS/etc/profile" << 'EOF'
export PATH=/bin:/sbin:/usr/bin:/usr/sbin
export HOME=/root
export PS1='sageos:~# '
alias ll='ls -la'
EOF

# --- 5. Package initramfs ---
mkdir -p "$DISTRO/iso/boot" "$DISTRO/iso/isolinux"
cd "$ROOTFS"
find . | cpio -H newc -o | gzip > "$DISTRO/iso/boot/initramfs.gz"
cd - >/dev/null

# --- 6. Copy kernel ---
cp /boot/vmlinuz-* "$DISTRO/iso/boot/vmlinuz"

# --- 7. ISOLINUX bootloader config ---
cat > "$DISTRO/iso/isolinux/isolinux.cfg" << 'EOF'
DEFAULT sageos
PROMPT 0
TIMEOUT 10
LABEL sageos
  KERNEL /boot/vmlinuz
  APPEND initrd=/boot/initramfs.gz console=ttyS0 console=tty0
EOF
cp /usr/lib/ISOLINUX/isolinux.bin "$DISTRO/iso/isolinux/"
cp /usr/lib/syslinux/modules/bios/ldlinux.c32 "$DISTRO/iso/isolinux/" 2>/dev/null || true

# --- 8. Build bootable ISO ---
xorriso -as mkisofs \
  -o "$DISTRO/sageos-1.0.iso" \
  -b isolinux/isolinux.bin \
  -c isolinux/boot.cat \
  -no-emul-boot \
  -boot-load-size 4 \
  -boot-info-table \
  -V "SAGEOS" \
  -J -R \
  "$DISTRO/iso/"

echo ""
echo "============================================"
echo " SageOS v1.0 build complete!"
echo " ISO: $DISTRO/sageos-1.0.iso"
echo " Size: $(du -h "$DISTRO/sageos-1.0.iso" | cut -f1)"
echo "============================================"

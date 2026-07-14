# XFCE edition — real graphical desktop verification (2026-07-14, take 2)

Corrected a login-flow misunderstanding from an earlier test: the lightdm-gtk-greeter
entry box always displays the static label "Enter your password" even when the
underlying PAM conversation is actually asking for the **username** first (lightdm
invokes PAM with a null username here, so pam_unix itself prompts "login:" then
"Password:" as two separate round trips — the greeter's label text doesn't update
to reflect which one it currently is).

Correct login sequence confirmed via lightdm.log root-shell inspection:
1. Type `sage` (username) + Enter — despite the greeter label saying "password".
2. Wait for the entry to redisplay confirming `sage`.
3. Type `sageos` (actual password) + Enter.

This reached a real XFCE desktop: visible top panel, "File System" and "Home"
desktop icons, taskbar. Screenshot: `xfce-desktop-screenshot.png` (raw QEMU VGA
console capture, 1280x800).

Boot media: sageos-5.3-xfce.iso (local rebuild — dbus-x11 + /home/sage chown fixes
+ USB/NVMe initramfs fix all present).

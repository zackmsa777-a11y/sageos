# XFCE edition boot test — 2026-07-13

QEMU graphical boot test of `sageos-5.3-xfce.iso` (downloaded fresh from the
v5.3 GitHub release, checksum-verified against `sageos-5.3-checksums.txt`).

- `01-boot-graphical-console.png` — kernel handoff to the bochs-drm
  framebuffer console right after boot (`fbcon: bochs-drmdrmfb (fb0) is
  primary device`, switched to 160x50 colour framebuffer).
- `02-lightdm-greeter.png` — lightdm greeter loaded successfully: top panel
  shows hostname `sageos`, live clock, and status icons; "Log In" button
  visible.
- `03-lightdm-greeter-after-login-attempt.png` — screen state after sending
  `sage` + Enter + `sageos` + Enter via the QEMU monitor's `sendkey`
  interface. Visually identical to (02) — login did not appear to submit.

## Status: in progress
lightdm/Xorg render correctly (no black screen, no missing driver issue —
that earlier bug is confirmed fixed). The remaining open question is why
keystrokes sent via QEMU monitor `sendkey` aren't landing in the greeter's
username field this time, despite this exact flow (typed username + Enter +
password + Enter) having worked in an earlier verification pass. Next steps:
try slower per-key timing, try Tab-to-focus before typing, and check
whether an on-screen "user list" (avatar picker) needs a click before a
text entry even appears, rather than assuming a pre-focused text field.

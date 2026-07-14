# XFCE session-dies-after-login — root cause fully confirmed & fixed (2026-07-14)

## Symptom
lightdm greeter renders fine, keyboard/mouse work, login authenticates
successfully — but the session exits with return code 1 almost instantly
and bounces back to the greeter. Looked like a login/auth bug but wasn't.

## Root causes (two, both required)

**1. Missing `dbus-x11`** (already fixed, see `src/categories.conf`)
Debian's `dbus-x11` (provides `dbus-launch`) is only a *Recommends* of
xfce4/lightdm, not a hard dependency — and SageOS sets
`APT::Install-Recommends "false"` globally to stay lean, so it silently
never got pulled in. xfce4-session hard-requires `dbus-launch` and exits
immediately when it's missing. Fixed by adding `dbus-x11` to the xfce
category's package list.

**2. `/home/sage` owned by root, not sage** (new finding, the deeper bug)
Even with `dbus-launch` present, the session still died. Direct root-shell
inspection (`ls -ld /home/sage`) showed the directory was `root:root`
with `755` perms — the `sage` user (uid 1000) only has read+execute on
its own home directory, so it can't write `.Xauthority`, `.ICEauthority`,
`.cache/`, `.config/` — anything XFCE's session needs to initialize.
This isn't scripted anywhere in version control (the user was apparently
created/populated once manually in an earlier build pass and the wrong
ownership just got carried forward in every rootfs snapshot since).

**Fix:** `chown -R sage:sage /home/sage`. Added as a safety check in
`src/sage-pkg`'s xfce install hook (runs every time the xfce mission pack
is installed, right alongside the existing `/sbin/init` symlink restore),
so this self-heals even if a future rootfs regenerates the bug.

## Verification
Rebuilt the XFCE test ISO with both fixes, booted fresh in QEMU, clicked
through the lightdm greeter, logged in as `sage` — session now reaches an
actual XFCE desktop (taskbar with Applications menu + username indicator,
desktop icons for File System / Home). See `desktop-after-login.png`.

Confirmed via OCR: greeter previously OCR'd only "Log In" + clock; this
capture OCRs "Applications", "sage" (panel), "File System", "Home"
(desktop icons) — unambiguous evidence of a real desktop session, not a
greeter bounce-back.

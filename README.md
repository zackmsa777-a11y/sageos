# SageOS

A lean, Debian-based Linux distro for security work, built around one idea: **the base system stays small, and everything else updates itself.**

**[Homepage & downloads](https://zackmsa777-a11y.github.io/sageos/) · [Package catalog](https://zackmsa777-a11y.github.io/sageos/packages.html) · [Changelog](https://zackmsa777-a11y.github.io/sageos/changelog.html) · [Releases](https://github.com/zackmsa777-a11y/sageos/releases)**

---

## What this is

SageOS is a personal distro project — built from Debian bookworm via `debootstrap`, running OpenRC instead of systemd, with tools organized into installable "mission pack" categories (networking, web app testing, forensics, etc.) rather than shipped all at once in a bloated ISO.

It exists because most security-distro live images have the same problem: they ship every tool up front, the image is huge, and the moment you burn it to a USB stick it starts going stale. Six months later you're either re-downloading a multi-GB ISO or manually chasing updates tool by tool. SageOS tries to avoid that by keeping the base minimal and pushing everything — tool installs, tool updates, even the package manager's own code — through the network, on demand.

## Principles

These are the actual design constraints the project holds itself to. If a change doesn't fit one of these, it doesn't belong in SageOS.

1. **The base image stays small.** Nothing goes into the default ISO "just in case." If a tool isn't needed by every user on every boot, it's a mission pack, not baked-in.
2. **Updates never require a new ISO.** `sage-pkg update` upgrades installed tools; `sage-pkg update-catalog` refreshes the tool list *and* upgrades `sage-pkg` itself, live, from GitHub. A SageOS install from six months ago should be able to fully catch up without a re-download.
3. **One tool, three install sources, no seams.** `sage-pkg` wraps `apt`, GitHub release binaries, and `pip` behind a single interface. The user shouldn't need to know or care which one a given tool actually comes from.
4. **GitHub is the single source of truth.** Not the sandbox this was built in, not whatever's sitting on a build machine's disk — the `main` branch and its releases. Every fix that matters is a commit, not a one-off patch to a running system.
5. **Verify before shipping.** Every fix in this repo's history was confirmed in a real chroot or QEMU boot before being called done — not assumed correct from reading the diff.
6. **x86_64 only, QEMU + VirtualBox tested.** No architecture sprawl, no untested hypervisor claims.

## Goals

- Be a distro that's actually still useful a year after you installed it, without re-flashing anything.
- Make the mission-pack catalog genuinely browsable and versioned — you should be able to see exactly what changed between catalog updates, not guess from commit history.
- Keep the whole system honest about what's real: this README, the catalog, and the release notes should never claim something that hasn't actually been booted and checked.
- Whether this goes anywhere beyond a personal project or not, the code and the process behind it should hold up to scrutiny on their own terms.

## What's in the box

| Piece | What it does |
|---|---|
| `sage-pkg` | The package manager. `install`, `remove`, `list`, `search`, `update`, `update-catalog`. Hybrid apt/GitHub-release/pip backend, self-updating. |
| `sage-security` | A whiptail-based menu UI in front of `sage-pkg`, for anyone who'd rather not remember command syntax. |
| Mission packs | Categories defined in `src/categories.conf` — networking/recon, web app testing, forensics, and others. See the [live catalog](https://zackmsa777-a11y.github.io/sageos/packages.html) for the current full list. |
| Two ISO editions | `sageos-X.X.iso` — lean, terminal-only base. `sageos-X.X-xfce.iso` — same base with XFCE + lightdm pre-installed, boots to a graphical login. |
| GitHub Pages site | Homepage, browsable package catalog, and versioned changelog, all generated from the same `src/` files `sage-pkg` reads from — they can't drift apart. |

## Architecture, briefly

- **Base:** Debian bookworm rootfs via `debootstrap`, `APT::Install-Recommends` disabled to stay lean (this has bitten the project more than once — see `dbus-x11`/`xfce4-terminal` history in the changelog, both were Recommends-only deps that silently didn't get pulled in).
- **Init:** OpenRC. Mission packs that pull in `systemd-sysv` as a side-effect dependency (XFCE via lightdm does) get their `/sbin/init → openrc-init` symlink restored automatically by the install hook.
- **Boot:** hybrid BIOS/UEFI ISO (isolinux + GRUB via `xorriso`), with a custom `initramfs/init` that loads SATA/USB/NVMe/virtio storage drivers, finds the boot media, and either mounts a squashfs rootfs read-only or sets up an overlay with a persistence volume if one's present.
- **Package manager:** `sage-pkg`, a single bash script. Category type in `categories.conf` (`apt` / `fetch` / `pip` / `mixed` / `builtin`) determines the default install path per mission pack, with per-tool `@apt`/`@fetch`/`@pip` overrides for exceptions.
- **Catalog:** `src/sage-pkg-catalog/` mirrors the live config files sage-pkg fetches over the network; `tools/gen_catalog_index.py` generates the versioned JSON + changelog served on GitHub Pages from those same files.

## Getting it

Two editions on the [releases page](https://github.com/zackmsa777-a11y/sageos/releases) — direct ISO download, magnet link, `.torrent`, checksums, and a full-source zip on every release. Default login on both: `sage`/`sageos` or `root`/`sageos`.

```
sage-pkg list                 # see every mission pack + tool
sage-pkg install web          # install a whole category
sage-pkg update                # upgrade everything installed, and sage-pkg itself
```

## Status

Actively developed, single-maintainer personal project. Not audited, not hardened for production use — treat it the way you'd treat any small distro project: useful to poke at, not something to bet critical infrastructure on. Issues and forks welcome.

## License

See [LICENSE](LICENSE) if present in this repo, otherwise treat as all-rights-reserved by the author pending an explicit license being added.

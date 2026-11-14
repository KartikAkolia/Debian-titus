# Changelog

## 2026-11-14 (later): Alacritty as the default terminal

- Alacritty is now installed and made the default terminal. dwm-titus's terminal launcher (`dwm-terminal`) already tries Alacritty before kitty, and dwm-titus seeds and themes its config.
- The installer sets `x-terminal-emulator` to Alacritty, because both Alacritty and kitty register at priority 20 and kitty was being picked.
- It also sets Alacritty as the terminal in `mimeapps.list`, on existing installs too, and puts it first in the rofi applets' terminal entry.
- kitty stays installed with its config.

## 2026-11-14: Debian 13 (trixie) audit and fix

This branch picks up from upstream `ChrisTitusTech/Debian-titus` at `f5533bc` (2024-04-21), which no longer worked on current Debian. Each item below was confirmed against the Debian archive, the upstream project, or a run in a throwaway trixie VM. The VM-tested results are in `README.md`'s Testing section.

### Install-breaking bugs

- **`neofetch` aborted the whole second package line.** `neofetch` was removed from Debian in January 2025 (RM bug #1031619), so on trixie the `nala install` on line 59 failed outright. That meant no `lightdm`, which meant no X server, because X was only arriving as one of lightdm's Recommends. It's now `fastfetch`.
- **`git` was never installed**, but four steps run `git clone`. `curl`, the X server, `xinit` and `pkgconf` were also only present by accident or not at all, and are now installed explicitly. `gpg`, which the old script needed for `--dearmor`, isn't needed any more: apt reads the armored Floorp key directly.
- **No error handling.** Without `set -e`, a failed step let the script carry on, and it still exited 0. If the Nordzy clone failed, `cd Nordzy-cursors` failed too and `./install.sh` re-ran Debian-titus's own installer, recursively. The script now runs under `set -Eeuo pipefail` with an ERR trap that names the failing line.
- **dwm-titus couldn't build or start.** Three separate failures:
   - Upstream dropped Debian support on 2026-08-17 (`57e4bbd`), and its HEAD installer is Fedora-only.
   - Under sudo, the Makefile builds as `$SUDO_USER` inside a root-owned clone, so it can't write `config.h`. `libimlib2-dev` was also missing.
   - Line 128 then copied the raw `dwm.desktop` template, `Exec=@PREFIX@/bin/dwm`, over the correct one, so LightDM could never start the session.

  dwm-titus is now pinned at `afebb4ae`. Root fetches it into a root-owned staging directory and runs `make all install-system` there, then the user runs `make install-user`, the same split the Makefile's own `install` target uses. The script checks the installed session file's `Exec=` line.
- **Quickshell, dwm-titus's bar, isn't in trixie main.** The script adds `trixie-backports` (deb822, signed by the Debian archive keyring) and installs it from there. It first checks `apt-cache policy` for an existing source rather than grepping files, so a disabled or `-sloppy` entry doesn't count.
- **The target user was hard-coded as UID 1000.** With no UID 1000, files went to `/home/.config`. The user is now `$SUDO_USER`, or the first argument when run from a root shell. It's resolved through `getent passwd`, which also turns a numeric UID into the user's name.
- **The script depended on `sudo`.** A netinstall with a root password set doesn't install sudo. The script no longer calls it, and `./install.sh <username>` works from `su -`.
- **mybash set up root, not the user.** sudo's `env_reset` makes `HOME=/root`, so mybash's `setup.sh` configured `/root`. Its packages and Starship are now installed by apt, and its `install_configs` step runs as the user at a pinned commit.
- **Thorium had nothing to download.** It hasn't published a Linux `.deb` since M138 (2026-02-18), and its newer assets aren't named `amd64.deb`, so the `grep` matched nothing. The script then installed a 0-byte file. Its only APT repo is unsigned (`trusted=yes`), and M138 is 18 major versions behind trixie's security-supported Chromium. **The Thorium option is replaced by Debian's `chromium`**, offered only on the architectures where trixie-security still ships current Chromium (amd64, arm64, i386, ppc64el; armhf stopped at 150).
- **`mv user-dirs.dirs` and `mv dotfonts/fontawesome/otfs/*.otf` referenced files that don't exist.** They're replaced by `xdg-user-dirs-update`, and the Font Awesome step by the `fonts-font-awesome` package. The empty `dotfonts/` directory is removed.
- **`sudo -u … systemctl --user enable wireplumber` always failed** with "Failed to connect to bus". It's dropped: trixie's `wireplumber` package already enables itself for all users.
- **LightDM couldn't take over from another display manager.** Older Debian-titus versions installed SDDM, and `systemctl enable lightdm` fails while another display manager owns `display-manager.service`. LightDM is now preselected through debconf, written to `/etc/X11/default-display-manager`, and enabled with `--force`.
- **LightDM preselected "Default Xsession".** A new user who just typed their password got no dwm. A `lightdm.conf.d` drop-in now sets `user-session=dwm`.

### Security and supply chain

- **Pins and checksums.** Every third-party download is now pinned to a commit or checked against a SHA-256:
   - dwm-titus, mybash and Nordic are fetched at fixed commits.
   - The Floorp key, the Nerd Fonts and the Nordzy cursors are checked against a SHA-256.
   - Nerd Fonts v2.1.0 publishes no checksums. Those two sums were computed from the release assets on 2026-11-14, so they are trust-on-first-use.
   - Verified downloads are cached in `/var/cache/debian-titus/`, so a re-run doesn't fetch them again.
   - Nordic and Nordzy record the installed pin, so changing a pin replaces an older or unpinned copy.
- **Floorp's APT source.** It now uses the current `ppa.floorp.app` host with a deb822 source and an armored key in `/etc/apt/keyrings/floorp.asc`. Previously the script `curl`ed without `-f`, so an HTTP error page could become a sources file.
- **Root never runs or installs anything the user can write.** That matters when a non-sudo user is set up from a root shell:
   - The script refuses to run from a checkout that anyone but root or the invoking sudo user could change while it runs. Such a checkout is one where the checkout or any directory above it has another owner, or is group- or world-writable (sticky directories excepted). An ACL that grants anyone write access shows up as group-write through the ACL mask, so it's refused too. Group-write is allowed only when the group is the sudo user's own private group. Debian's default user umask of 002 makes every clone group-writable, and only that user can write it anyway.
   - The script runs from a `main` function, called inside a `{ …; exit; }` group, so bash parses all of it before running any of it, and `set -e` still applies inside `main`. Right after checking the checkout it copies the scripts, configs and wallpaper it needs into root-owned staging and never reads the checkout again. A `git pull` or an editor saving files mid-run can't change what root executes.
   - It sets its own `PATH`, because a plain `su` without `-` leaves `/usr/sbin` out.
   - Every file in the user's home is written by the user, through `scripts/user-setup` and dwm-titus's `install-user`.
   - dwm-titus is built and installed from a root-owned copy, so a planted `GNUmakefile` or edited source can't run as root.
   - The script sets `umask 022`, and Nordic is unpacked with a 022 umask instead of `git archive`'s group-writable default.
   - The old blanket `chown -R` of the whole home directory is gone.
   - Staging lives under `/var/cache/debian-titus/` rather than `/var/tmp`, which hardened systems often mount noexec, because dwm-titus's `install-user` runs scripts from it.
   - Commands run as the user get a clean environment, without root's D-Bus, display or XDG variables.
   - Root-owned leftovers of older versions in the user's home are handed back: `~/.use-nala`, and directories such as `~/.config/fastfetch` that mybash created as root.
      - Only plain directories, and a singly linked `~/.use-nala`, are handed back. `chown -h` and `find -execdir` mean a planted link can't redirect it.
      - It walks only those paths and stops at any mount point, bind mounts included, so a shared disk mounted at one of them is left as it is. Root-owned font caches (`~/.cache/fontconfig`) are handed back too, and a font cache that can't be written no longer aborts the install.
      - An unreadable entry, such as a FUSE mount, only produces a warning.
   - Older versions also ran mybash as root, which could leave `/root/.bashrc` as a symlink into a user's checkout, so root's shell ran a file the user controls. The same applies to root's Starship and fastfetch configs, its `starship-theme` command, and the `.config`/`.local` directories holding them.
      - A symlink is kept only if it's a single hop to a real file or directory under `/root`.
      - Anything else is moved aside, and `.bashrc` gets Debian's default back.
- **`kitty.conf` had `allow_remote_control yes`**, which lets any program running inside the terminal drive it. Nothing uses it, so it's now `no`.
- **Removed `dotconfig/GIMP/`**, which shipped a stripped, prebuilt ELF plug-in (`plug-ins/webexport`) of unknown origin into users' home directories. GIMP was never installed, the plug-in links against GIMP 2 libraries that trixie (GIMP 3) doesn't have, and the folder carried another machine's paths.
- **Removed `deb-packages/sddm_0.19.0-4_amd64.deb`.** It was unreferenced since the 2024 switch to LightDM, and installing it would be a downgrade on trixie.

### Packages

- Replaced `neofetch` with `fastfetch`, and `pipewire` with the `pipewire-audio` metapackage, which adds pipewire-pulse, pipewire-alsa and the Bluetooth plugin per the Debian wiki.
- Dropped `nitrogen`, `apt-transport-https` and the duplicate `lxappearance`:
   - `nitrogen` was removed from Debian testing on 2025-12-09 as unmaintained GTK 2, and feh already sets the wallpaper.
   - `apt-transport-https` is an empty transitional package.
- Added the dwm-titus runtime helpers from its `check-deps.sh`: `xclip xdotool dex jq bluez blueman maim alsa-utils`.
- The script uses `apt-get` rather than `apt`, whose CLI isn't stable for scripts. Its system update is `apt-get full-upgrade`, because `apt-get upgrade`, unlike the old script's `apt upgrade`, would hold back a kernel security update that needs a new `linux-image-<abi>` package.

### Configuration

- **kitty 0.41:** removed `open_url_modifiers`, which was dropped in 0.21.
   - dwm-titus's theme switcher edits `kitty.conf` at every login, so it's only installed when missing.
   - kitty colours don't follow dwm-titus theme changes, because this `kitty.conf` includes its own `theme.conf` last. dwm-titus's own `kitty.conf` has the same problem with `nord.conf` (noted in `ROADMAP.md`).
- **picom 12:** removed the deprecated `refresh-rate`, and dropped the ignored `:c` type specifier on `_GTK_FRAME_EXTENTS`.
- **MangoHud 0.7:**
   - `gamepad_battery` → `device_battery=gamepad`.
   - `position=left` → `top-left`, which is what it silently meant.
   - `custom_text=Fedora` → `Debian`.
- **GTK:**
   - The cursor theme is set to the installed `Nordzy-cursors`. GTK 3 named `Layan-cursors`, which was never installed, and GTK 2 named `Adwaita`.
   - The GTK 2 file is now installed where GTK 2 reads it, `~/.gtkrc-2.0`.
   - Added `gtk-4.0/settings.ini`, because trixie's pavucontrol is GTK 4.
   - dwm-titus's theme switcher rewrites all three, so they're only installed when missing.
- **`mimeapps.list`:**
   - The default browser was Brave, which neither option installs. It's now the browser you pick.
   - Directories opened in ranger; they now open in Thunar.
   - Removed entries for software that isn't in Debian (Synology Drive, Spotify, Google Calendar import, nufraw).
- **rofi:**
   - Fixed `sidetab.rasi`'s broken `@import` path.
   - Fixed `usedram` reading `ShMem` instead of `/proc/meminfo`'s `Shmem`.
   - Removed five launcher symlinks pointing at a `launchers/` directory that was never committed.
   - The applets' browser entries and quicklinks now find Floorp.
   - The power menu's logout now works under dwm. It sends dwm `SIGUSR2`, dwm-titus's clean-exit signal, so its `autostop.sh` cleanup runs.
- **Re-running.** Configs are installed file by file. A file that differs from the repo's copy is backed up to `<name>.bak.<timestamp>` before it's replaced, never overwritten in place.
   - Files other programs add to the same directories are left alone. So is a file that you've reached through your own symlink and whose content already matches. A file in a directory you can't write is skipped with a warning instead of aborting the install.
   - Files that something else edits later are only installed when missing. These are `kitty.conf`, the GTK settings, `mimeapps.list`, the wallpaper (backups would join feh's random rotation), and mybash's Starship and fastfetch links. An existing `~/.use-nala` is kept too.
   - Files an older Debian-titus installed are moved aside, but only if they're unchanged, so upgraded systems get the fixed versions too. That covers its `kitty.conf`, `mimeapps.list` and GTK 3 settings, plus the GIMP ELF plug-in, which is also made non-executable, and the dangling rofi launcher links.
   - Other leftovers from the old script are cleaned up as well: its `Floorp.list`, and the stray *file* at `/usr/share/xsessions`, which its `cp` created when the directory didn't exist yet and which blocks every session file install.
   - The old script also cloned mybash and dwm-titus as root inside its checkout, leaving files the user can't delete. The installer lists any such clone that contains root-owned files, and how to remove it. It doesn't remove them itself, because root doesn't write into the user's home.
   - A backup of a file or link that an old run left root-owned is made as a copy the user owns, so no root-owned `.bak` files pile up in the home.
   - An earlier run's Floorp keeps its repository even if this run picks Chromium.
   - A dangling `.bashrc` symlink, left by an old mybash checkout, is replaced with Debian's default `.bashrc` before the nala hook is added. Dangling links count as missing for the seed-only files too, so a link into a deleted old checkout is replaced.
- **Console font.** The Terminus font is applied to the active console even when sudo runs the script on a pty, which Debian's default `use_pty` does. As before, it lasts until reboot.

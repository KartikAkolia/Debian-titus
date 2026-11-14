# Debian-titus

Turns a fresh, minimal Debian 13 "trixie" install into Chris Titus's [dwm-titus](https://github.com/ChrisTitusTech/dwm-titus) desktop, with LightDM, PipeWire, kitty, Thunar, the Nordic GTK theme, Nerd Fonts and [mybash](https://github.com/ChrisTitusTech/mybash).

This is a maintained copy of [ChrisTitusTech/Debian-titus](https://github.com/ChrisTitusTech/Debian-titus), whose last change was in April 2024. `CHANGELOG.md` lists everything that changed and why. `ROADMAP.md` lists what's next.

## Requirements

- **Debian 13 (trixie) only.** The script stops on any other release, because its package list was checked against trixie specifically.
- **A minimal install.** Use a netinstall and select only "standard system utilities" when it asks which software to install, with no desktop environment.
- **A regular user account** to set up, which the Debian installer creates.
- **A supported architecture for your browser.** Floorp's APT repository is amd64-only. Debian ships current Chromium security updates for amd64, arm64, i386 and ppc64el; armhf stopped at version 150.

## Install

On a fresh netinstall, git isn't installed yet. As root (`su -`):

```sh
apt install git
```

Then clone this repository and run the installer. From your own account, if it can use sudo:

```sh
git clone https://github.com/KartikAkolia/Debian-titus
cd Debian-titus
sudo ./install.sh
```

If you set a root password during installation, the installer leaves sudo out. In that case, clone and run it in the root shell, naming the user to set up:

```sh
git clone https://github.com/KartikAkolia/Debian-titus
cd Debian-titus
./install.sh <username>
```

The installer refuses to run from a checkout that anyone other than root (or the sudo user who started it) owns or can write, because root runs scripts from it.

The repository is private, so cloning it needs your GitHub credentials (a personal access token, or `gh auth login`).

The installer asks once which browser to install, then runs unattended. Reboot when it finishes. LightDM preselects the dwm-titus session, so just log in.

## What it installs

- **Session:** Xorg, LightDM with the GTK greeter, and dwm-titus with its Quickshell bar.
   - dwm-titus is built from a pinned commit in a temporary root-owned directory. Its runtime files end up in `~/.local/share/dwm-titus`.
   - Quickshell comes from `trixie-backports`, which the script enables.
- **Desktop programs:** Alacritty (the default terminal), kitty, rofi, picom, Thunar, feh, lxpolkit, flameshot, pavucontrol, lxappearance, fastfetch, MangoHud, vim and neovim.
- **Audio:** PipeWire through the `pipewire-audio` metapackage, which adds the PulseAudio, ALSA and Bluetooth pieces.
- **Browser, your choice of two:**
   - Floorp, from its official APT repository.
   - Chromium, from Debian, with Debian security updates.

  Thorium was dropped because it has no current Linux builds.
- **Look and feel:**
   - Nordic GTK theme, Papirus-Dark icons and Nordzy cursors.
   - FiraCode and Meslo Nerd Fonts (v2.1.0) and JetBrainsMono Nerd Font.
   - Noto Color Emoji and Font Awesome.
   - The Terminus console font, while the installer runs (it lasts until reboot).
- **Shell:** mybash's `.bashrc`, Starship prompt, fzf, zoxide and bat, plus an `apt` → `nala` wrapper for the user's and root's interactive shells.
- **Configs:**
   - Everything in `dotconfig/` (kitty, picom, rofi, MangoHud, GTK, default applications) is copied into `~/.config`.
   - GTK 2 settings go to `~/.gtkrc-2.0`, and the wallpaper goes to `~/Pictures/backgrounds`.

## Pinned third-party sources

Each one is fetched at a fixed commit or checked against a SHA-256 before use. `install.sh` holds the exact values.

| Component | Pin |
| --- | --- |
| dwm-titus | commit `afebb4ae`, the last commit known to build on Debian after upstream went Fedora-only |
| mybash | commit `b96e064f` |
| Nordic GTK theme | commit `be5bda37` |
| Nerd Fonts (FiraCode, Meslo) | v2.1.0, SHA-256 computed on 2026-11-14 because upstream publishes none for v2 |
| JetBrainsMono Nerd Font | v3.5.1, SHA-256 from the release's `SHA-256.txt` |
| Nordzy cursors | v2.5.0 tarball, SHA-256 |
| Floorp signing key | SHA-256 of `ppa.floorp.app/KEY.gpg` |

## Re-running

The installer is safe to run again:

- **Your files:**
   - Configs are installed file by file. If one in your home differs from the repo's copy, it's moved to `<name>.bak.<timestamp>` first, never overwritten in place.
   - Some files are only installed when missing, because something else edits them later:
      - `kitty.conf` and the GTK settings files, which dwm-titus's theme switcher rewrites at every login;
      - `mimeapps.list`, which dwm-titus's default-apps tool edits (the browser you pick is still set as the default);
      - the wallpaper, because dwm-titus picks a random image from that directory and would show backup copies too;
      - the Starship and fastfetch config links, which mybash's `starship-theme` replaces.
   - A file you've reached through your own symlink (GNU stow, say) is left alone if its content already matches.
   - Files that an older Debian-titus installed are moved aside, but only if they're unchanged, so the fixed versions take their place. That covers its kitty config, `mimeapps.list` and GTK 3 settings, plus the GIMP plug-in binary and the dangling rofi launcher links.
   - Everything in your home directory is written as your user, not as root.
- **Downloads:** verified downloads are cached in `/var/cache/debian-titus/downloads/`, so a re-run doesn't fetch them again. You can delete `/var/cache/debian-titus/` once you're done.

## Testing

Tested on 2026-11-14 in throwaway KVM virtual machines (rootless QEMU, 4 vCPUs, 4 GiB RAM, virtio GPU). Two kinds of fresh Debian 13 system were used:

- **Debian's official trixie cloud image** (`debian-13-generic-amd64`, build 20261111-2659, SHA512-verified), with the user created by cloud-init.
- **A real netinstall** from `debian-13.7.0-amd64-netinst.iso`, whose SHA512 and Debian CD signing key were verified. It was installed unattended with a preseed:
   - a root password is set, so the installer leaves sudo out;
   - "standard system utilities", plus an SSH server for the test harness.

What passed:

- **The sudo path.** This is a clone made with Debian's default umask of 002, then `sudo ./install.sh`. The install finished in about 4½ minutes and a re-run took 13 seconds. Neither created a backup, and nothing in the home directory was left owned by another user.
- **The root-shell path on the real netinstall.** This used `su -`, `apt install git`, a clone in `/root` and `./install.sh <user>`, with no sudo anywhere. The install finished in about 4½ minutes and added its own backports source. After a reboot, LightDM preselected the dwm-titus session, and logging in gave dwm, the Quickshell bar and picom. A re-run after login was clean. This was tested on the build just before the last sudo-path fixes, which don't change this path.
- **Both browsers:** Floorp from its repository, and Chromium from Debian.
- **Upgrading over the original 2024 script's leftovers.** The stray `/usr/share/xsessions` file, the GIMP binary, the old configs, `Floorp.list` and the root-owned files were all cleaned up, and the old root-owned clones were listed.
- **Replacing an existing SDDM** as the display manager, and moving aside root dotfile symlinks that pointed into a user's home.
- **The checkout trust check.** It refuses a root-owned clone inside a user-owned home, a world-writable file, and a group-writable file whose group isn't the user's private group.
- **Failure handling.** A failed download (GitHub blocked) stops the install with an error and exit status 1.
- **Edits during a run.** Changing the checkout while the installer runs doesn't change what it runs.

Not tested:

- UEFI boot (the VMs used SeaBIOS).
- Real hardware and GPUs (the VMs render with llvmpipe).
- Sound output (the VMs have no sound card, though PipeWire ran).
- Wi-Fi.

Known limits:

- **Network icon.** dwm-titus's network icon shows as disconnected, because it asks NetworkManager, which a netinstall doesn't use.
- **Terminus.** The console font lasts only until reboot.
- **kitty theme.** kitty's colours don't follow dwm-titus theme changes.
- **Cursors.** dwm-titus's theme switcher sets its own Capitaine cursors at every login, so the Nordzy cursors are installed but not shown by default.

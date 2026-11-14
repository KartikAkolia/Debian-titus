# Roadmap

Debian-titus targets Debian 13 "trixie" only. These are the next directions, in the order they unblock each other. Nothing here is started yet.

## 1. Automated VM test

The 2026-11-14 audit tested `install.sh` in throwaway trixie VMs: the official `debian-13-generic-amd64` cloud image and a preseeded `debian-13.7.0-amd64-netinst.iso` install, on qcow2 overlays, with rootless QEMU, SSH and QMP screenshots. That harness (`vm.sh`, `vm-netinst.sh`, the commented `preseed.cfg` and the end-state checks) lives outside the repo under `/var/tmp/claude-debian-titus/`, where a reboot or cleanup can remove it. Turning that into a repeatable script in this repo would re-run the installer on a fresh image after every change. It would check the end state (`dwm` installed, the session file's `Exec=`, LightDM enabled) and screenshot the greeter. A GitHub Actions version needs KVM on the runner, so start with a local script.

## 2. Own a Debian-compatible dwm-titus fork

Upstream dwm-titus has been Fedora-only since 2026-08-17 (`57e4bbd`). `install.sh` pins `afebb4ae`, a week after that change, because its Makefile still builds on Debian. A fork would let Debian-specific fixes land and track selected upstream changes on purpose rather than being frozen at one commit. The private Arch port `KartikAkolia/dwm-titus-arch`, made on 2026-11-14, is a model for one. For example, kitty doesn't follow dwm-titus theme changes. Both dwm-titus's `kitty.conf` and this repo's include a fixed colour file after `theme-apply.sh`'s `include active-theme.conf`; dwm-titus's also sets `allow_remote_control yes`. v0.8.0 (`529e772c`) would also need `libxcb-xfixes0-dev`.

## 3. Unattended install ISO

A preseeded Debian netinstall ISO that creates the user and runs Debian-titus on first boot, for zero-touch installs. This depends on the VM test so the ISO can be checked automatically.

## Smaller follow-ups

- **Rofi applets.** The bundled applets still call tools the installer doesn't install: `i3lock`/`betterlockscreen`, `mpc`, `nmcli`, `acpi`, `scrot`, `brightnessctl` and `notify-send`. Current dwm-titus uses Quickshell, not rofi, so decide whether to keep these applets at all.
- **Nerd Fonts v3.** The rofi configs use ten Nerd Fonts v2-only icon codepoints. Moving to v3.5.1, which publishes SHA-256 sums, needs a codepoint remap first.
- **`nala` wrapper.** It forwards every `apt` subcommand to nala, including ones nala doesn't have, such as `apt policy`.
- **Network icon.** dwm-titus's bar asks NetworkManager for network status, so it shows as disconnected on a netinstall, which uses ifupdown. Decide whether to install `network-manager`; it leaves interfaces in `/etc/network/interfaces` alone.
- **Cursor theme.** dwm-titus's theme switcher sets Capitaine cursors at every login, so the Nordzy cursors Debian-titus installs aren't used by default. Either drop Nordzy or make it dwm-titus's theme cursor.

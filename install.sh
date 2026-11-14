#!/usr/bin/env bash
#
# Debian-titus: turn a minimal Debian 13 (trixie) install into Chris Titus's
# dwm-titus desktop.
#
# Usage, from the repository directory:
#   sudo ./install.sh          from the account you want set up
#   ./install.sh <username>    from a root shell (e.g. after `su -`), when
#                              sudo isn't installed; clone the repo as root
#
# Every apt package name below was checked against the Debian archive for
# trixie on 2026-11-14. Third-party downloads are pinned to a commit or
# verified against a SHA-256; CHANGELOG.md records where each pin came from.
# Root only writes system paths and builds from root-owned copies; everything
# in the user's home is written by the user (scripts/user-setup and
# dwm-titus's install-user target).
#
# The work happens in main(), called at the end, so bash has parsed the
# whole script before running any of it, and main copies the scripts and
# configs it uses into a root-owned staging directory straight after checking
# the checkout: editing or pulling the checkout while it runs can't change
# what root executes.

set -Eeuo pipefail
umask 022
# A known PATH: `su` without `-` leaves out /usr/sbin (dpkg needs ldconfig),
# and find -execdir refuses a PATH with relative entries.
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

log() {
  printf '\n[+] %s\n' "$*"
}

trap 'printf "Error: install.sh failed at line %s: %s\n" "$LINENO" "$BASH_COMMAND" >&2' ERR

# Pinned third-party sources.
# dwm-titus dropped Debian support upstream on 2026-08-17 (commit 57e4bbd); this
# commit's Makefile still builds and installs on Debian with the packages below.
dwm_titus_commit=afebb4ae15b9ab4eef3f0e35f56ebfaebf4817c4
# Bumping this? Re-check scripts/user-setup's mybash file and link lists
# against install_configs in the new commit's setup.sh.
mybash_commit=b96e064f232e056efb413baa396e1c5320f8f950
nordic_commit=be5bda37ba01139650e34238336e58e065d2f406
floorp_key_sha256=40566be79e7ee77dbcbadc03fd4b7d5e7b4183d815edbf8efdd57a755f0f8678
# Nerd Fonts v2.1.0 publishes no checksums; these were computed from the
# release assets on 2026-11-14. v2 is kept because the rofi configs use v2-only
# icon codepoints.
declare -A nerd_font_sha256=(
  [FiraCode]=21de9aa0edaa3fd2dc1d87fb9ecec0b67c9b3b18bd1998a19904158067fea7e7
  [Meslo]=f0630f93b2f8c27b0cda8c4a2bae2b7a67bdd70786500e109f38c3a9b145f523
)
# mybash wants JetBrainsMono Nerd Font; pinned from v3.5.1's SHA-256.txt.
jetbrains_mono_url=https://github.com/ryanoasis/nerd-fonts/releases/download/v3.5.1/JetBrainsMono.tar.xz
jetbrains_mono_sha256=04d5e8f903693f9dd13e16f867e994834e681eb3c72c0d337a770dcda09010cf
nordzy_url=https://gitlab.com/-/project/81427113/uploads/0c5aed7b5e3953e4802196a1072f6a91/Nordzy-cursors.tar.gz
nordzy_sha256=88f2a1ed293d7b8145208d8e29537951a237e59acd756805964a8d7494df4900
# Verified downloads are cached (named by SHA-256) so re-runs skip them, and
# the per-run staging directory lives here too: unlike /tmp and /var/tmp,
# /var/cache isn't commonly mounted noexec, and dwm-titus's install-user runs
# scripts from the staged tree.
state_dir=/var/cache/debian-titus
download_cache=$state_dir/downloads

# Run a command as the target user with a clean session environment: HOME,
# XDG_RUNTIME_DIR and no desktop-session variables inherited from root.
as_user() {
  runuser -u "$username" -- env \
    -u DBUS_SESSION_BUS_ADDRESS -u DISPLAY -u WAYLAND_DISPLAY -u XAUTHORITY \
    -u XDG_CURRENT_DESKTOP -u XDG_SESSION_TYPE -u XDG_CONFIG_HOME \
    -u XDG_DATA_HOME -u XDG_CACHE_HOME -u XDG_STATE_HOME -u TMPDIR \
    HOME="$userhome" XDG_RUNTIME_DIR="/run/user/$useruid" "$@"
}

# Download url to dest and check its SHA-256, reusing a verified cached copy.
fetch_verified() {
  local url=$1 sha256=$2 dest=$3
  local cached=$download_cache/$sha256
  if [[ -f $cached ]] && printf '%s  %s\n' "$sha256" "$cached" | sha256sum -c --quiet - >/dev/null 2>&1; then
    cp -- "$cached" "$dest"
    return 0
  fi
  curl -fsSL --retry 3 -o "$dest" "$url" || die "download failed: $url"
  printf '%s  %s\n' "$sha256" "$dest" | sha256sum -c --quiet - ||
    die "checksum mismatch for $url"
  install -m 0644 -- "$dest" "$cached"
}

# Shallow-fetch exactly one pinned commit into a new root-owned dir.
fetch_commit() {
  local url=$1 commit=$2 dir=$3
  git init -q "$dir"
  git -C "$dir" fetch -q --depth 1 "$url" "$commit"
  git -C "$dir" -c advice.detachedHead=false checkout -q FETCH_HEAD
}

# Refuse to run from a checkout that anyone but root or the sudo user could
# change while root runs scripts and copies files from it. The checkout and
# every directory above it must belong to root (or the sudo user, who is
# root-equivalent anyway) and mustn't be group- or world-writable (sticky
# directories such as /tmp excepted). An ACL that grants anyone write access
# shows up as group-write through the ACL mask, so it is refused too.
check_checkout() {
  local trusted=(-user root) owners=root clone_hint bad dir pgid
  local parents=() group_ok=()
  if [[ -n ${SUDO_USER:-} ]]; then
    trusted=(\( -user root -o -user "$SUDO_USER" \))
    owners="root or $SUDO_USER"
    # Debian's default umask for users is 002 (pam_umask with USERGROUPS_ENAB),
    # so a plain git clone is group-writable. That's harmless when the group
    # is the sudo user's private group: same name, no listed members, and no
    # other account's primary group.
    pgid=$(id -g -- "$SUDO_USER")
    if [[ $(getent group "$pgid" | cut -d: -f1,4) == "$SUDO_USER:" ]] &&
      [[ $(getent passwd | awk -F: -v g="$pgid" '$4 == g' | wc -l) -eq 1 ]]; then
      group_ok=(\! -group "$pgid")
    fi
  fi
  clone_hint="clone the repository into a directory only $owners can write (e.g. /root) and run it from there"
  dir=$builddir
  while [[ $dir != / ]]; do
    dir=$(dirname -- "$dir")
    parents+=("$dir")
  done
  # Group-write counts unless the group is that private group. Symlinks are
  # always mode 0777, so only their owner is checked.
  local writable=(\( -perm -002 -o \( -perm -020 "${group_ok[@]}" \) \))
  bad=$(find "$builddir" \( \! "${trusted[@]}" -o \( \! -type l "${writable[@]}" \) \) -print -quit)
  [[ -z $bad ]] || die "$bad is owned or writable by someone other than $owners; $clone_hint"
  for dir in "${parents[@]}"; do
    bad=$(find "$dir" -maxdepth 0 \( \! "${trusted[@]}" -o \( "${writable[@]}" \! -perm -1000 \) \) -print)
    [[ -z $bad ]] || die "$bad is owned or writable by someone other than $owners; $clone_hint"
  done
}

# Undo what older versions of this script left behind.
clean_up_old_install() {
  # Its Floorp.list points at the old ppa.ablaze.one host; a source that stops
  # answering would make the first apt-get update fail.
  rm -f /etc/apt/sources.list.d/Floorp.list /usr/share/keyrings/Floorp.gpg
  # Its `cp dwm.desktop /usr/share/xsessions` created a regular file when the
  # directory didn't exist yet, which breaks every session file install.
  if [[ -f /usr/share/xsessions && ! -L /usr/share/xsessions ]]; then
    mv -- /usr/share/xsessions "/usr/share/xsessions.debian-titus-old.$stamp"
    printf '  moved the stray file /usr/share/xsessions to %s\n' \
      "/usr/share/xsessions.debian-titus-old.$stamp"
  fi
  # It (and the mybash and fc-cache it ran as root) created these in the
  # user's home as root, which would stop user-setup writing into them. Only
  # directories are handed back (they can't be hard links), chown -h never
  # follows a link, and -execdir works from the directory find actually
  # walked into, so a swapped-in symlink can't redirect it. Their contents
  # stay as they are; the user can replace entries in a directory they own.
  # find runs from inside the home with relative paths, walks only these
  # paths and their parents (everything else is pruned), and stops at any
  # mount point, bind mounts included, so a shared disk mounted at
  # ~/Pictures stays as it is. (stat doesn't trigger automounts since Linux
  # 4.14, and an unmounted automount point is itself a mount point.)
  local -a dirs=(.cache/fontconfig .config/fastfetch .local/bin .local/share/mybash
    .local/share/fonts/JetBrainsMonoNerdFont .fonts Pictures/backgrounds)
  local -A wanted=()
  local -a listed=()
  local d slashes maxdepth=1
  for d in "${dirs[@]}"; do
    while :; do
      wanted[$d]=1
      if [[ $d != */* ]]; then
        break
      fi
      d=${d%/*}
    done
  done
  for d in "${!wanted[@]}"; do
    listed+=(-o -path "./$d")
    slashes=${d//[^\/]/}
    if ((${#slashes} + 1 > maxdepth)); then
      maxdepth=$((${#slashes} + 1))
    fi
  done
  (
    cd -P -- "$userhome" || exit 0
    find . -mindepth 1 -maxdepth "$maxdepth" \
      \( \! \( "${listed[@]:1}" \) -prune \) -o \
      \( -exec mountpoint -q {} \; -prune \) -o \
      \( -type d -user root -execdir chown -h "$username:" {} + \) || true
    # Its usenala wrote ~/.use-nala as root. Only a plain, singly linked
    # file is handed back.
    find . -maxdepth 1 -name .use-nala -type f -links 1 -user root \
      -execdir chown -h "$username:" {} + || true
  )
}

main() {
  if [[ $EUID -ne 0 ]]; then
    die "run this as root: sudo ./install.sh (or ./install.sh <username> from a root shell)"
  fi

  # shellcheck source=/dev/null
  . /etc/os-release
  if [[ ${ID:-} != debian || ${VERSION_CODENAME:-} != trixie ]]; then
    die "this script supports Debian 13 (trixie) only; this system is ${PRETTY_NAME:-unknown}"
  fi

  local requested_user=${1:-${SUDO_USER:-}}
  if [[ -z $requested_user ]]; then
    die "can't tell which user to set up: run sudo ./install.sh from that user's account, or ./install.sh <username> as root"
  fi
  local passwd_entry
  passwd_entry=$(getent passwd "$requested_user") || die "no such user: $requested_user"
  # getent also accepts a numeric UID; use the name it resolves to.
  username=$(cut -d: -f1 <<<"$passwd_entry")
  useruid=$(cut -d: -f3 <<<"$passwd_entry")
  # Normalised (no trailing or doubled slashes); symlinks are kept as they are.
  userhome=$(realpath -m -s -- "$(cut -d: -f6 <<<"$passwd_entry")")
  [[ $useruid -ne 0 ]] || die "set up a regular user, not root"
  [[ -d $userhome ]] || die "home directory $userhome for $username does not exist"

  builddir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
  check_checkout
  # Everything below uses absolute paths; don't leave the target user's
  # commands in a directory they may not be able to read (e.g. under /root).
  cd /

  export DEBIAN_FRONTEND=noninteractive
  local apt_opts=(-y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)
  stamp=$(date +%Y%m%d%H%M%S)
  # Root-owned staging area for verified downloads, pinned sources and the
  # files user-setup installs.
  install -d -m 0755 "$state_dir" "$download_cache"
  workdir=$(mktemp -d -p "$state_dir" work.XXXXXX)
  trap 'rm -rf -- "$workdir"' EXIT
  # Root-owned copy of what root uses from the checkout, taken straight after
  # checking it; nothing below reads the checkout again.
  local repo=$workdir/repo
  install -d -m 0755 "$repo"
  cp -R -P --preserve=mode,timestamps -- "$builddir/scripts" "$builddir/dotconfig" \
    "$builddir/bg.jpg" "$repo/"

  clean_up_old_install

  log "Installing the Terminus console font"
  apt-get update
  apt-get install "${apt_opts[@]}" fonts-terminus console-setup kbd
  # setfont finds the active virtual console itself (as root it can, even
  # from a pty under sudo or SSH); it only lasts until reboot, as before.
  local console_font=/usr/share/consolefonts/Uni3-TerminusBold28x14.psf.gz
  if [[ -f $console_font ]]; then
    setfont "$console_font" 2>/dev/null || true
  fi
  if [[ -t 1 ]]; then
    clear || true
  fi

  # Let the user choose which web browser to install.
  printf 'Please select the web browser:\n'
  local browser='' choice browser_pkg browser_desktop arch
  PS3='Browser number: '
  select choice in Floorp Chromium; do
    case $choice in
      Floorp | Chromium)
        browser=$choice
        break
        ;;
      *) printf 'Please enter 1 or 2.\n' >&2 ;;
    esac
  done || true
  [[ -n $browser ]] || die "no browser selected"
  arch=$(dpkg --print-architecture)
  case $browser in
    Floorp)
      [[ $arch == amd64 ]] ||
        die "Floorp's APT repository only has amd64 builds; choose Chromium instead"
      browser_pkg=floorp
      browser_desktop=floorp.desktop
      ;;
    Chromium)
      # The architectures trixie-security still ships current Chromium for
      # (armhf stopped at 150 while the others moved on).
      case $arch in
        amd64 | arm64 | i386 | ppc64el) ;;
        *) die "Debian no longer provides Chromium security updates for $arch" ;;
      esac
      browser_pkg=chromium
      browser_desktop=chromium.desktop
      ;;
  esac

  log "Updating the system"
  # full-upgrade: apt-get's plain upgrade holds back linux-image-amd64
  # whenever a kernel security update needs a new linux-image-<abi> package.
  apt-get full-upgrade "${apt_opts[@]}"
  apt-get install "${apt_opts[@]}" ca-certificates curl git

  # Quickshell (dwm-titus's bar) is only in trixie-backports. Ask apt whether
  # an enabled backports source is already configured rather than grepping.
  local apt_policy keyring
  apt_policy=$(apt-cache policy)
  if [[ $apt_policy != *n=trixie-backports,* ]]; then
    keyring=/usr/share/keyrings/debian-archive-keyring.pgp
    [[ -f $keyring ]] || keyring=/usr/share/keyrings/debian-archive-keyring.gpg
    cat >/etc/apt/sources.list.d/debian-titus-backports.sources <<EOF
Types: deb
URIs: http://deb.debian.org/debian
Suites: trixie-backports
Components: main
Signed-By: $keyring
EOF
  fi

  # Floorp's repository: when it's the chosen browser, or when an earlier run
  # installed it (so it keeps getting updates after its old source was
  # removed).
  local floorp_status
  floorp_status=$(dpkg-query -W -f='${db:Status-Status}' floorp 2>/dev/null || true)
  if [[ $browser == Floorp || $floorp_status == installed ]]; then
    [[ $arch == amd64 ]] || die "Floorp's APT repository only has amd64 builds"
    install -d -m 0755 /etc/apt/keyrings
    fetch_verified https://ppa.floorp.app/KEY.gpg "$floorp_key_sha256" "$workdir/floorp.asc"
    install -m 0644 "$workdir/floorp.asc" /etc/apt/keyrings/floorp.asc
    cat >/etc/apt/sources.list.d/floorp.sources <<'EOF'
Types: deb
URIs: https://ppa.floorp.app/amd64/
Suites: ./
Signed-By: /etc/apt/keyrings/floorp.asc
EOF
  fi
  apt-get update

  local packages=(
    # Package manager front end and tools this script relies on
    nala unzip wget xz-utils psmisc
    # X server, display manager and session plumbing
    xserver-xorg xinit x11-xserver-utils lightdm lightdm-gtk-greeter
    dbus-user-session xdg-user-dirs xdg-utils
    # dwm-titus build dependencies (the pkg-config modules its Makefile checks)
    build-essential pkgconf libx11-dev libxft-dev libxinerama-dev libxrender-dev
    libimlib2-dev libx11-xcb-dev libxcb1-dev libxcb-res0-dev libfreetype-dev
    libfontconfig-dev
    # Audio: the full PipeWire stack the Debian wiki recommends
    pipewire-audio wireplumber pavucontrol alsa-utils
    # Essential programs
    kitty rofi picom thunar feh lxpolkit zoxide
    # dwm-titus runtime helpers (from its scripts/check-deps.sh)
    xclip xdotool dex jq bluez blueman maim
    # Less important programs (fastfetch replaces neofetch, which trixie dropped)
    fastfetch flameshot mangohud vim lxappearance papirus-icon-theme
    fonts-noto-color-emoji fonts-font-awesome fontconfig
    # mybash's dependencies (it would otherwise install them via sudo itself)
    bash-completion bat tree multitail neovim trash-cli fzf starship
    # The chosen web browser
    "$browser_pkg"
  )
  log "Installing packages"
  # Make LightDM the display manager even if another one (older Debian-titus
  # versions shipped SDDM) is already installed.
  printf 'lightdm shared/default-x-display-manager select lightdm\n' | debconf-set-selections
  apt-get install "${apt_opts[@]}" "${packages[@]}"
  apt-get install "${apt_opts[@]}" -t trixie-backports quickshell

  log "Downloading fonts and mybash"
  local font
  for font in FiraCode Meslo; do
    fetch_verified "https://github.com/ryanoasis/nerd-fonts/releases/download/v2.1.0/$font.zip" \
      "${nerd_font_sha256[$font]}" "$workdir/$font.zip"
  done
  fetch_verified "$jetbrains_mono_url" "$jetbrains_mono_sha256" "$workdir/JetBrainsMono.tar.xz"
  fetch_commit https://github.com/ChrisTitusTech/mybash.git "$mybash_commit" "$workdir/mybash"
  # Source the apt -> nala wrapper from mybash's .bashrc here, using
  # usenala's own hook text, so the installed copy is identical every run.
  bash "$repo/scripts/usenala" --print-hook "$userhome/.use-nala" >>"$workdir/mybash/.bashrc"

  log "Setting up $username's home directory"
  mv -- "$repo/dotconfig" "$workdir/dotconfig"
  # GTK 2 only reads ~/.gtkrc-2.0, and mimeapps.list is handled separately.
  mv -- "$workdir/dotconfig/gtk-2.0/gtkrc-2.0" "$workdir/gtkrc-2.0"
  rmdir -- "$workdir/dotconfig/gtk-2.0"
  mv -- "$workdir/dotconfig/mimeapps.list" "$workdir/mimeapps.list"
  mv -- "$repo/bg.jpg" "$workdir/"
  cp -- "$repo/scripts/user-setup" "$workdir/"
  chmod -R a+rX -- "$workdir"
  as_user bash "$workdir/user-setup" "$workdir" "$stamp" "$browser_desktop"

  log "Installing the Nordic GTK theme"
  local nordic_dir=/usr/share/themes/Nordic installed_nordic=''
  if [[ -f $nordic_dir/.debian-titus-commit ]]; then
    installed_nordic=$(<"$nordic_dir/.debian-titus-commit")
  fi
  if [[ $installed_nordic != "$nordic_commit" ]]; then
    fetch_commit https://github.com/EliverLara/Nordic.git "$nordic_commit" "$workdir/Nordic"
    rm -rf -- "$nordic_dir"
    install -d -m 0755 "$nordic_dir"
    git -C "$workdir/Nordic" -c tar.umask=0022 archive --format=tar HEAD |
      tar -x -C "$nordic_dir" --no-same-owner
    printf '%s\n' "$nordic_commit" >"$nordic_dir/.debian-titus-commit"
  fi

  log "Installing the Nordzy cursor theme"
  local nordzy_dir=/usr/share/icons/Nordzy-cursors installed_nordzy=''
  if [[ -f $nordzy_dir/.debian-titus-sha256 ]]; then
    installed_nordzy=$(<"$nordzy_dir/.debian-titus-sha256")
  fi
  if [[ $installed_nordzy != "$nordzy_sha256" ]]; then
    fetch_verified "$nordzy_url" "$nordzy_sha256" "$workdir/Nordzy-cursors.tar.gz"
    rm -rf -- "$nordzy_dir"
    tar -xzf "$workdir/Nordzy-cursors.tar.gz" -C /usr/share/icons --no-same-owner
    [[ -f $nordzy_dir/index.theme ]] ||
      die "the Nordzy-cursors archive didn't contain the expected theme"
    printf '%s\n' "$nordzy_sha256" >"$nordzy_dir/.debian-titus-sha256"
  fi

  log "Building and installing dwm-titus (pinned at ${dwm_titus_commit:0:8})"
  # Build and install the system files from a root-owned copy of the pinned
  # commit, so nothing the user can write is run or installed by root; then
  # install the user files as the user, the same way the Makefile's own
  # install target does.
  local dwm_src=$workdir/dwm-titus
  fetch_commit https://github.com/ChrisTitusTech/dwm-titus.git "$dwm_titus_commit" "$dwm_src"
  make -C "$dwm_src" all
  make -C "$dwm_src" install-system
  chmod -R a+rX -- "$dwm_src"
  as_user make -C "$dwm_src" install-user OWNER="$username" USER_HOME="$userhome"
  grep -qx 'Exec=/usr/local/bin/dwm' /usr/share/xsessions/dwm.desktop ||
    die "/usr/share/xsessions/dwm.desktop wasn't installed correctly"

  log "Enabling the graphical login"
  # Without this the greeter preselects "Default Xsession" for a new user.
  install -d -m 0755 /etc/lightdm/lightdm.conf.d
  printf '[Seat:*]\nuser-session=dwm\n' >/etc/lightdm/lightdm.conf.d/50-debian-titus.conf
  # --force replaces another display manager's display-manager.service alias.
  printf '/usr/sbin/lightdm\n' >/etc/X11/default-display-manager
  systemctl enable --force lightdm.service
  systemctl set-default graphical.target

  log "Configuring bash to use nala"
  bash "$repo/scripts/usenala" "$username" "$stamp"

  # Older versions also cloned mybash and dwm-titus as root inside the
  # checkout they ran from, leaving files the user can't delete. Root doesn't
  # write into the user's home, so only point them out. The old checkout's
  # mybash directory was the user's own (an empty submodule path) with
  # root-owned contents, so look for any root-owned entry, not the top only.
  local -a old_clones
  mapfile -t old_clones < <(find -H "$userhome" -xdev -mindepth 2 -maxdepth 3 -type d \
    \( -name dwm-titus -o -name mybash \) \
    -exec sh -c '[ -n "$(find "$1" -user root -print -quit)" ]' sh {} \; \
    -prune -print 2>/dev/null)
  if ((${#old_clones[@]})); then
    printf '\nNote: an older Debian-titus run left these root-owned clones in %s:\n' "$userhome"
    printf '  %s\n' "${old_clones[@]}"
    printf 'They are no longer used; remove them as root with: rm -rf <path>\n'
  fi

  log "Installation complete. Reboot, then log in to the dwm-titus session from LightDM."
}

# One compound command, so bash has parsed the exit before main runs. (Not
# `main "$@" && exit`: that would switch off set -e and the ERR trap
# inside main.)
{
  main "$@"
  exit
}

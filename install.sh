#!/bin/bash

# Check if Script is Run as Root
if [[ $EUID -ne 0 ]]; then
  echo "You must be a root user to run this script. Please run: sudo ./install.sh" >&2
  exit 1
fi

username=$(id -u -n 1000)
builddir=$(pwd)

# Configure bash to use Nala wrapper instead of apt
user_nala_config="/home/$username/.use-nala"
root_nala_config="/root/.use-nala"
user_bashrc="/home/$username/.bashrc"
root_bashrc="/root/.bashrc"

create_nala_wrapper() {
  local target_config="$1"
  local bashrc_file="$2"

  if [ ! -f "$target_config" ]; then
    cat << 'EOF' > "$target_config"
apt() {
  command nala "$@"
}
sudo() {
  if [ "$1" = "apt" ]; then
    shift
    command sudo nala "$@"
  else
    command sudo "$@"
  fi
}
EOF
    echo "if [ -f \"$target_config\" ]; then . \"$target_config\"; fi" >> "$bashrc_file"
  fi
}

# Create Nala wrapper for the user and root
create_nala_wrapper "$user_nala_config" "$user_bashrc"
create_nala_wrapper "$root_nala_config" "$root_bashrc"

# Update packages list and upgrade the system
nala update
nala upgrade -y

# Install essential programs
nala install -y gpg libimlib2-dev nala feh kitty rofi picom thunar nitrogen lxpolkit x11-xserver-utils unzip wget \
  pipewire wireplumber pavucontrol build-essential libx11-dev libxft-dev libxinerama-dev libx11-xcb-dev \
  libxcb-res0-dev zoxide xdg-utils neofetch flameshot psmisc mangohud vim lxappearance papirus-icon-theme \
  lxappearance fonts-noto-color-emoji lightdm

# Set up Google Chrome
echo "[ACTION] Installing Google Chrome..."
wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | gpg --dearmor -o /usr/share/keyrings/google-chrome.gpg
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome.gpg] http://dl.google.com/linux/chrome/deb/ stable main" > /etc/apt/sources.list.d/google-chrome.list
nala update
nala install -y google-chrome-stable
echo "[SUCCESS] Google Chrome has been installed successfully."

# Download Nordic Theme
cd /usr/share/themes/ || exit
git clone https://github.com/EliverLara/Nordic.git

# Install fonts
cd "$builddir" || exit
nala install -y fonts-font-awesome
wget https://github.com/ryanoasis/nerd-fonts/releases/download/v2.1.0/FiraCode.zip
unzip FiraCode.zip -d /home/$username/.fonts
wget https://github.com/ryanoasis/nerd-fonts/releases/download/v2.1.0/Meslo.zip
unzip Meslo.zip -d /home/$username/.fonts
mv dotfonts/fontawesome/otfs/*.otf /home/$username/.fonts/
chown -R "$username":"$username" /home/$username/.fonts

# Reload fonts cache and remove zip files
fc-cache -vf
rm ./FiraCode.zip ./Meslo.zip

# Install Nordzy cursor
git clone https://github.com/alvatip/Nordzy-cursors
cd Nordzy-cursors || exit
./install.sh
cd "$builddir" || exit
rm -rf Nordzy-cursors

# Enable graphical login and set target to GUI
systemctl enable lightdm
systemctl set-default graphical.target

# Enable wireplumber service for the user
sudo -u "$username" systemctl --user enable wireplumber.service

# Set up Beautiful Bash
git clone https://github.com/ChrisTitusTech/mybash
cd mybash || exit
bash setup.sh
cd "$builddir" || exit

# Set up DWM
git clone https://github.com/ChrisTitusTech/dwm-titus
cd dwm-titus || exit
make clean install
cp dwm.desktop /usr/share/xsessions
cd "$builddir" || exit

# Final success message
echo "[SUCCESS] System setup completed successfully!"

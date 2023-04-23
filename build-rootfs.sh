#!/bin/bash

set -x

CODE_NAME='stable'
[ -n "$1" ] && CODE_NAME="$1"

read -r -d '' SOURCE_LST << EOF
deb http://deb.debian.org/debian $CODE_NAME main contrib non-free

deb http://deb.debian.org/debian-security/ $CODE_NAME-security main contrib non-free

deb http://deb.debian.org/debian $CODE_NAME-updates main contrib non-free

EOF

read -r -d '' APT_CONF <<'EOF'
APT::Install-Recommends "0";
APT::Install-Suggests "0";
Acquire::GzipIndexes "true";
Acquire::Languages "none";
EOF

read -r -d '' DPKG_CONF <<'EOF'
path-exclude=/usr/share/locale/*
path-exclude=/usr/share/gnome/help/*/*
path-exclude=/usr/share/omf/*/*-*.emf
path-exclude=/usr/share/tcltk/t*/msgs/*.msg
path-exclude=/usr/share/aptitude/*.*
path-exclude=/usr/share/help/*
path-exclude=/usr/share/doc/*
path-exclude=/usr/share/man/*
path-exclude=/usr/share/info/*
path-exclude=/usr/share/vim/vim*/lang/*
path-include=/usr/share/locale/locale.alias
path-include=/usr/share/locale/en/*
path-include=/usr/share/locale/en_US.UTF-8/*
path-include=/usr/share/omf/*/*-en.emf
path-include=/usr/share/omf/*/*-en_US.UTF-8.emf
path-include=/usr/share/omf/*/*-C.emf
path-include=/usr/share/locale/languages
path-include=/usr/share/locale/all_languages
path-include=/usr/share/locale/currency/*
path-include=/usr/share/locale/l10n/*
path-include=/usr/share/vim/vim*/lang/en/*
path-include=/usr/share/vim/vim*/lang/en_US.UTF-8/*
path-include=/usr/share/vim/vim*/lang/*.*
EOF

on_err(){
printf "%s\n" "$1"
exit 1
}

[ "$(id -u)" -eq 0 ] || on_err "must run as root"

apt-get update
apt-get install --no-install-recommends mmdebstrap dosfstools gdisk btrfs-progs unzip xz-utils -y
modprobe btrfs

mmdebstrap --variant=minbase \
--components="main contrib non-free" \
--dpkgopt=<(printf "%s" "$DPKG_CONF") \
--aptopt=<(printf "%s" "$APT_CONF") \
--include='systemd,systemd-sysv,udev,
ifupdown,iproute2,netbase,isc-dhcp-client,iputils-ping,
psmisc,net-tools,zstd,unzip,xz-utils,
btrfs-progs,gdisk,fdisk,e2fsprogs,parted,
openssh-server,
ca-certificates,curl,wget,
sudo,htop,ncdu,screen,
vim-tiny,nano,
zsh' \
"$CODE_NAME" "debian_$CODE_NAME".tar.gz - <<<"$SOURCE_LST" || on_err 'mmdebstrap failed'

sha256sum "debian_$CODE_NAME".tar.gz > "debian_$CODE_NAME".tar.gz.sha256

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
apt-get install --no-install-recommends mmdebstrap dosfstools gdisk btrfs-progs unzip xz-utils duperemove -y
modprobe btrfs

mmdebstrap --variant=minbase \
--components="main contrib non-free" \
--dpkgopt=<(printf "%s" "$DPKG_CONF") \
--aptopt=<(printf "%s" "$APT_CONF") \
--include='systemd,systemd-sysv,dbus,
chrony,cron,
ifupdown,iproute2,netbase,isc-dhcp-client,iputils-ping,
psmisc,net-tools,zstd,unzip,xz-utils,
btrfs-progs,gdisk,fdisk,e2fsprogs,
openssh-server,
linux-image-cloud-amd64,grub-efi,grub-pc-bin,efibootmgr,
cloud-init,cloud-initramfs-growroot,
wireguard-tools,resolvconf,iptables,dnsmasq,
locales,
ca-certificates,curl,wget,sudo,mtr-tiny,
htop,ncdu,screen,
vim-tiny,nano,
zsh' \
"$CODE_NAME" rootfs.tar - <<<"$SOURCE_LST" || on_err 'mmdebstrap failed'

RAW_DISK="debian_$CODE_NAME".img

dd if=/dev/zero of="$RAW_DISK" bs=1M count=420
LOOP_DEV=$(losetup -fP --show "$RAW_DISK")
test -z "$LOOP_DEV" && on_err 'Set up loop device failed'


sgdisk "$LOOP_DEV" -o \
-n25::+2m -t25:ef02 -c25:"BIOS Boot Partition" \
-n26::+16m -t26:ef00 -c26:"EFI system partition" \
-n27::+128m -t27:8200 -c27:"Linux swap" \
-n1 -t1:4f68bce3-e8cd-4db1-96e7-fbcaf984b709 -c1:"Root Partition" \
-p || on_err 'part loop device failed'

ROOT_DEV="$LOOP_DEV"p1
EFI_DEV="$LOOP_DEV"p26
SWAP_DEV="$LOOP_DEV"p27

MNT_POINT=$(mktemp -d)

mkfs.btrfs "$ROOT_DEV" -M -m single -f
mount -t btrfs "$ROOT_DEV" "$MNT_POINT"
btrfs subvolume create "${MNT_POINT}/@rootfs"
umount "$MNT_POINT"
mount -t btrfs -o noatime,compress-force=zstd:15,subvol=@rootfs "$ROOT_DEV" "$MNT_POINT"
tar -C "$MNT_POINT" --xattrs --xattrs-include='*' --numeric-owner -xf rootfs.tar 
chattr -R +C "${MNT_POINT}/var/"{log,cache}

mkswap "$SWAP_DEV"
mkfs.vfat "$EFI_DEV"
mkdir -p "$MNT_POINT"/boot/efi

#获取分区UUID
ROOT_UUID=$(blkid -s UUID -o value "$ROOT_DEV")
EFI_UUID=$(blkid -s UUID -o value "$EFI_DEV")
SWAP_UUID=$(blkid -s UUID -o value "$SWAP_DEV")

#检查是否成功
test -z "$ROOT_UUID" && on_err "get rootfs uuid failed"
test -z "$EFI_UUID" && on_err "get efi uuid failed"
test -z "$SWAP_UUID" && on_err "get swap uuid failed"

echo "UUID=$ROOT_UUID / btrfs rw,noatime,compress=lzo,subvol=@rootfs,x-systemd.growfs 0 1" > "${MNT_POINT}/etc/fstab"
echo "UUID=$EFI_UUID /boot/efi vfat defaults 0 0" >> "${MNT_POINT}/etc/fstab"
echo "UUID=$SWAP_UUID  none swap nofail 0 0" >> "${MNT_POINT}/etc/fstab"

sed -i '/disable_root:/c disable_root: false' "$MNT_POINT"/etc/cloud/cloud.cfg

#在chroot 中安装grub
mount -t proc proc -o nosuid,noexec,nodev "${MNT_POINT}/proc"
mount -t sysfs sys -o nosuid,noexec,nodev,ro "${MNT_POINT}/sys"
mount -t devtmpfs -o mode=0755,nosuid udev "${MNT_POINT}/dev"
mount -t devpts devpts "${MNT_POINT}/dev/pts"
mount -t tmpfs -o nosuid,nodev,mode=0755 run "${MNT_POINT}/run"

#This file is taken from package grub-cloud-amd64
cat > "$MNT_POINT"/etc/default/grub << 'EOF'
# If you change this file, run 'update-grub' afterwards to update
# /boot/grub/grub.cfg.

GRUB_DEFAULT=0
GRUB_TIMEOUT=1
GRUB_DISTRIBUTOR=`lsb_release -i -s 2> /dev/null || echo Debian`
GRUB_CMDLINE_LINUX_DEFAULT=""
GRUB_CMDLINE_LINUX="console=tty0 console=ttyS0,115200 earlyprintk=ttyS0,115200 consoleblank=0 net.ifnames=0 biosdevname=0"
GRUB_TERMINAL="console serial"
GRUB_SERIAL_COMMAND="serial --speed=115200"

EOF

chroot "$MNT_POINT" /bin/bash  <<EOF
set -e
mount -t vfat "$EFI_DEV" /boot/efi/

cat > /boot/efi/startup.nsh <<EONSH
fs0:
cd EFI\Debian
.\grubx64.efi
EONSH

grub-install "$LOOP_DEV" --target=i386-pc
grub-install "$LOOP_DEV" --target=x86_64-efi
update-grub
grep -E '^\s*en_US.UTF-8' /etc/locale.gen || echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
update-locale LANG=en_US.UTF-8
umount /boot/efi/
EOF

# 限制systemd日志大小
sed '/^\s*SystemMaxUse=.*$/d' "$MNT_POINT"/etc/systemd/journald.conf -Ei &&
echo 'SystemMaxUse=64M' >> "$MNT_POINT"/etc/systemd/journald.conf

# 设置IPv4 WARP
wget "https://github.com/ViRb3/wgcf/releases/download/v2.2.15/wgcf_2.2.15_linux_amd64" \
-O "${MNT_POINT}/usr/local/bin/wgcf"
chmod +x "${MNT_POINT}/usr/local/bin/wgcf"

cat > "${MNT_POINT}/etc/systemd/system/setup-warp.service" << 'EOF'
[Unit]
Description=Set up Cloudflare WARP
ConditionFileNotEmpty=!/etc/wireguard/cf.conf
ConditionFileIsExecutable=/usr/local/bin/wgcf
ConditionFileIsExecutable=/usr/local/lib/setup_warp.sh
After=network-online.target
Wants=network-online.target
[Service]
Type=oneshot
User=root
ExecStart=/usr/local/lib/setup_warp.sh
[Install]
WantedBy=multi-user.target

EOF

cat > "${MNT_POINT}/usr/local/lib/setup_warp.sh" << 'EOF'
#!/bin/sh
WORK_DIR=$(mktemp -d)
mkdir -p /etc/wireguard/
cd "$WORK_DIR" || exit 1
RETRY=0
until [ -e wgcf-account.toml ]; do
  wgcf register --accept-tos && break
  RETRY=$(( RETRY+1 ))
  [ "$RETRY" -gt 10 ] && echo "Retried too much times!"&& exit 1
  sleep 10
done
wgcf generate
sed -e '10s/^/#/' \
-i wgcf-profile.conf
systemctl stop wg-quick@cf
V4origin=$(ip route get 1.1.1.1 | grep -oP 'src \K\S+')
[ -n "$V4origin" ] && ! ip route get 1.1.1.1|grep cf &&
sed -e "6aPostUp = ip -4 rule add from $V4origin lookup main" \
-e "6aPostDown = ip -4 rule delete from $V4origin lookup main" \
-i wgcf-profile.conf
mv wgcf-profile.conf /etc/wireguard/cf.conf
systemctl start wg-quick@cf &&
systemctl enable wg-quick@cf
rm -rf "$WORK_DIR"

EOF

chmod a+x "${MNT_POINT}/usr/local/lib/setup_warp.sh"
ln -srf "${MNT_POINT}/etc/systemd/system/setup-warp.service" "${MNT_POINT}/etc/systemd/system/multi-user.target.wants/setup-warp.service"

sed -Ei \
-e '/^\s*server=.*/d' \
-e '/^\s*listen-address=.*/d' \
-e '/^\s*bind-interfaces.*/d' \
-e '/^\s*no-resolv.*/d' \
"$MNT_POINT"/etc/dnsmasq.conf &&
cat >> "$MNT_POINT"/etc/dnsmasq.conf << EOF
listen-address=::1,127.0.0.1
bind-interfaces
no-resolv
server=2606:4700:4700::1111
server=2606:4700:4700::1001
server=1.1.1.1
server=1.0.0.1

EOF

# bbr
cat >> "$MNT_POINT"/etc/sysctl.conf << EOF
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr

EOF

#Install ohmyzsh
wget https://github.com/ohmyzsh/ohmyzsh/archive/refs/heads/master.zip
unzip -q master.zip && rm master.zip
find ./ohmyzsh-master -iname '*.gif' -delete
mv ohmyzsh-master "${MNT_POINT}/root/.oh-my-zsh"
cp "${MNT_POINT}/root/.oh-my-zsh/templates/zshrc.zsh-template" "${MNT_POINT}/root/.zshrc"
sed -e 's/^\s*ZSH_THEME="robbyrussell"/ZSH_THEME="fino"/' \
-e 's/^\s*plugins=(git)/plugins=()/' \
-e "1i zstyle ':omz:update' mode disabled" \
"${MNT_POINT}/root/.zshrc" -i
sed '/root/s#/bin/bash#/bin/zsh#g' -i "$MNT_POINT"/etc/passwd

duperemove -dhr --dedupe-options=same,partial "$MNT_POINT"

umount "${MNT_POINT}/dev/pts"
umount "${MNT_POINT}/dev"
umount "${MNT_POINT}/run"
umount "${MNT_POINT}/sys"
umount "${MNT_POINT}/proc"

umount "$MNT_POINT"
losetup -d "$LOOP_DEV"
rm -rf "$MNT_POINT"
rm -rf rootfs.tar

gzip "$RAW_DISK"
sha256sum "$RAW_DISK".gz > "$RAW_DISK".gz.sha256

#!/bin/bash
set -e

export WORKDIR=$(pwd)
export CHROOT=$WORKDIR/chroot
export IMAGE=$WORKDIR/image

echo "=== Building Osiris Linux (Ubuntu Noble base) ==="

# 1. Bootstrap
sudo debootstrap --arch=amd64 --variant=minbase noble $CHROOT http://archive.ubuntu.com/ubuntu/

# Mounts
sudo mount --bind /dev $CHROOT/dev
sudo mount --bind /run $CHROOT/run

# Chroot and configure
sudo chroot $CHROOT /bin/bash << 'CHROOT_END'
set -e
mount -t proc none /proc
mount -t sysfs none /sys
mount -t devpts none /dev/pts

export HOME=/root
export LC_ALL=C

echo "osiris" > /etc/hostname
echo "127.0.1.1 osiris" >> /etc/hosts

cat << EOF > /etc/apt/sources.list
deb http://archive.ubuntu.com/ubuntu/ noble main restricted universe multiverse
deb-src http://archive.ubuntu.com/ubuntu/ noble main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu/ noble-security main restricted universe multiverse
deb-src http://security.ubuntu.com/ubuntu/ noble-security main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu/ noble-updates main restricted universe multiverse
deb-src http://archive.ubuntu.com/ubuntu/ noble-updates main restricted universe multiverse
EOF

apt-get update && apt-get upgrade -y

# Basic live system packages
apt-get install -y sudo ubuntu-standard casper discover laptop-detect os-prober \
    network-manager net-tools wireless-tools wpagui locales \
    grub-common grub-pc grub-efi-amd64-signed shim-signed mtools binutils

apt-get install -y --no-install-recommends linux-generic

# Desktop (XFCE lighter)
apt-get install -y xfce4 xfce4-goodies plymouth-themes

# Installer
apt-get install -y ubiquity ubiquity-casper ubiquity-frontend-gtk ubiquity-slideshow-ubuntu

# Osiris tools
apt-get install -y neofetch htop curl git vim nano terminator

# Custom motd
cat << EOF > /etc/motd
   _____  _____ _____ _____ ____  _____ 
  |  _  \/  ___/  ___|  ___|  _ \|  __ \\
  | | | |\ `--.| |__ | |__ | |_) | |__) |
  | | | | `--. \  __||  __||  _ <|  ___/ 
  | |/ / /\__/ / |___| |___| |_) | |     
  |___/  \____/\____/\____/|____/|_|     
              Rise from the ashes
EOF

useradd -m -s /bin/bash osiris
echo "osiris:osiris" | chpasswd
usermod -aG sudo osiris
echo "osiris ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/osiris

dpkg-reconfigure locales

apt-get autoremove -y && apt-get clean
CHROOT_END

# Create image structure
sudo mkdir -p $IMAGE/{casper,isolinux,install}

# Copy kernel
sudo cp $CHROOT/boot/vmlinuz-*-generic $IMAGE/casper/vmlinuz || true
sudo cp $CHROOT/boot/initrd.img-*-generic $IMAGE/casper/initrd || true

# GRUB config
sudo mkdir -p $IMAGE/boot/grub
sudo cat << 'EOF' > $IMAGE/boot/grub/grub.cfg
set timeout=10
menuentry "Osiris Live" {
    linux /casper/vmlinuz boot=casper quiet splash
    initrd /casper/initrd
}
menuentry "Install Osiris" {
    linux /casper/vmlinuz boot=casper only-ubiquity quiet splash
    initrd /casper/initrd
}
EOF

touch $IMAGE/ubuntu

# Squashfs
echo "Building squashfs..."
sudo mksquashfs $CHROOT $IMAGE/casper/filesystem.squashfs -e boot -e proc -e run -e sys -e tmp -e dev || true

# ISO (simplified - note: full xorriso may need adjustment)
cd $IMAGE
sudo xorriso -as mkisofs -r -V "Osiris" -J -l \
    -o $WORKDIR/osiris.iso . || echo "ISO creation may need tweaks"

echo "Osiris build completed!"
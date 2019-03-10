#!/bin/bash

# see http://redsymbol.net/articles/unofficial-bash-strict-mode/
# To silent an error || true
set -euo pipefail
IFS=$'\n\t'

if [ "${1:-}" = "--verbose" ] || [ "${1:-}" = "-v" ]; then
	set -x
fi

# defaults
[ -v $SWAPSIZE ] && SWAPSIZE=2G
[ -v $NEW_USERNAME ] && NEW_HOSTNAME=guest
[ -v $NEW_HOSTNAME ] && NEW_HOSTNAME=arch

#----------------------
# partitioning /dev/sda
# * sda1 : EFI Filesystem : 256MB
# * sda2 : BootSystem : 256MB
# * sda3 : LVM : 100%
#----------------------
cat /proc/partitions | grep -E 'sda.+' | awk '{ print $2 }' | xargs -I{} parted -s /dev/sda rm {}
parted -s /dev/sda mklabel gpt
parted -s /dev/sda mkpart primary fat32 1MiB 256MiB 
parted -s /dev/sda set 1 boot on
parted -s /dev/sda set 1 esp on
parted -s /dev/sda mkpart primary 256MiB 512MiB
parted -s /dev/sda mkpart primary 512MiB 100%

#----------------------
# file system /dev/sda
# * sda1 : FAT32
# * sda2 : ext4(crypt)
# * sda3 : swap + root(ext4)
#----------------------
mkfs.vfat -F32 /dev/sda1
cryptsetup luksFormat /dev/sda2
cryptsetup luksOpen /dev/sda2 cryptboot
mkfs.ext4 /dev/mapper/cryptboot
cryptsetup luksFormat /dev/sda3
cryptsetup luksOpen /dev/sda3 lvm
pvcreate /dev/mapper/lvm
vgcreate arch /dev/mapper/lvm
lvcreate -L $SWAPSIZE arch -n swap
lvcreate -l +100%FREE arch -n root
mkswap -L swap /dev/mapper/arch-swap

#----------------------
# mounting
# * /mnt(arch-root)
#    └ boot(cryptboot)
#       └ efi(/dev/sda1)
# * swap(arch-swap)
#----------------------
mount /dev/mapper/arch-root /mnt
mkdir /mnt/boot
mount /dev/mapper/cryptboot /mnt/boot
mkdir /mnt/boot/efi
mount /dev/sda1 /mnt/boot/efi
swapon /dev/mapper/arch-swap


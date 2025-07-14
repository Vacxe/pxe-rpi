#!/bin/bash

set -e

# Customize device and volume
SD_DEV="/dev/sdq"
VOLUME="/volume2"
SERVER_IP="192.168.1.100"

BOOT_MNT="/mnt/pi-boot"
ROOT_MNT="/mnt/pi-root"

# Mount partitions
sudo mkdir -p "$BOOT_MNT" "$ROOT_MNT"
sudo mount "${SD_DEV}1" "$BOOT_MNT"
sudo mount "${SD_DEV}2" "$ROOT_MNT"

# Get serial input
SERIAL=$(sudo grep Serial "$ROOT_MNT/proc/cpuinfo" | awk '{print $3}')
read -p "👉 Enter Raspberry Pi serial (leave blank to use [$SERIAL]): " USER_SERIAL
if [ -n "$USER_SERIAL" ]; then
  SERIAL="$USER_SERIAL"
fi
if [ -z "$SERIAL" ]; then
  echo "❌ Serial is empty. Aborting."
  exit 1
fi

# Prompt for hostname
read -p "🔤 Enter hostname for this Pi (e.g. pi-node-01): " HOSTNAME
if [ -z "$HOSTNAME" ]; then
  echo "❌ Hostname cannot be empty. Aborting."
  exit 1
fi

# Set target paths
TFTP_DIR="$VOLUME/rpi-tftpboot/$SERIAL"
PXE_DIR="$VOLUME/rpi-pxe/$SERIAL"

# Create folders
echo "📦 Creating folders:"
sudo mkdir -p "$TFTP_DIR"
sudo mkdir -p "$PXE_DIR"

# Copy boot files
echo "📂 Copying boot files to $TFTP_DIR..."
sudo cp -r "$BOOT_MNT/"* "$TFTP_DIR/"

# Confirm copy
echo "📁 Boot folder contents:"
ls -l "$TFTP_DIR"

# Generate cmdline.txt
CMDLINE="console=serial0,115200 console=tty1 root=/dev/nfs nfsroot=${SERVER_IP}:$PXE_DIR,vers=3 rw ip=dhcp rootwait elevator=deadline cgroup_enable=memory cgroup_memory=1"
echo "$CMDLINE" | sudo tee "$TFTP_DIR/cmdline.txt" > /dev/null

# Copy root filesystem
echo "📦 Copying root filesystem to $PXE_DIR..."
sudo rsync -a --exclude boot "$ROOT_MNT/" "$PXE_DIR/"

# Set hostname
echo "$HOSTNAME" | sudo tee "$PXE_DIR/etc/hostname" > /dev/null
sudo sed -i "s/127.0.1.1.*/127.0.1.1\t$HOSTNAME/" "$PXE_DIR/etc/hosts" || \
echo -e "127.0.1.1\t$HOSTNAME" | sudo tee -a "$PXE_DIR/etc/hosts" > /dev/null

# Fix /etc/fstab for NFS boot
echo "🛠️  Adjusting /etc/fstab for network boot..."
echo "proc            /proc           proc    defaults          0       0" | sudo tee "$PXE_DIR/etc/fstab" > /dev/null
echo "${SERVER_IP}:$TFTP_DIR /boot nfs defaults,ver=3,proto=tcp 0 0" | sudo tee -a "$PXE_DIR/etc/fstab" > /dev/null

# Enable SSH
# echo "🔐 Enabling SSH service..."
# sudo ln -sf /lib/systemd/system/ssh.service "$PXE_DIR/etc/systemd/system/multi-user.target.wants/ssh.service"

# Unmount partitions
sudo umount "$BOOT_MNT"
sudo umount "$ROOT_MNT"

echo
echo "✅ PXE setup complete for Pi:"
echo "📛 Hostname:   $HOSTNAME"
echo "🔗 Serial:     $SERIAL"
echo "📁 TFTP boot:  $TFTP_DIR"
echo "📁 NFS root:   $PXE_DIR"

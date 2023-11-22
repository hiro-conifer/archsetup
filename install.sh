#!/bin/sh
set -e

# Setting Pacman
sed -i -e 's/#\(Color\|ParallelDownloads = 5\)/\1/' /etc/pacman.conf
echo Server = http://ftp.tsukuba.wide.ad.jp/Linux/archlinux/\$repo/os/\$arch > /etc/pacman.d/mirrorlist

# Setting Partition
echo -n -e "\n"
echo -n Type Partition:
read part
sgdisk -Z $part
sgdisk -o $part

sgdisk -n 1::+300M -t 1:ef00 $part
sgdisk -n 2::+512M -t 2:8200 $part
sgdisk -n 3:: -t 3:8304 $part

mkfs.vfat -F32 ${part}1
mkswap ${part}2
mkfs.ext4 ${part}3

# Mount
mount ${part}3 /mnt
swapon ${part}2
mount --mkdir ${part}1 /mnt/boot

# Install Kernel
pacstrap /mnt base base-devel linux-zen linux-firmware linux-zen-headers

# Genfstab
genfstab -U /mnt >> /mnt/etc/fstab

# Create Shellfile
shfile=install2.sh
cat <<_END_> /mnt/$shfile
#!/bin/sh
# Set Timezone
ln -sf /usr/share/zoneinfo/Asia/Tokyo /etc/localtime
hwclock --systohc

# Locale-Gen
sed -i -e 's/^#\(en_US\|ja_JP\)\(.UTF-8.*\)/\1\2/' /etc/locale.gen
locale-gen
echo LANG=en_US.UTF-8 > /etc/locale.conf
echo KEYMAP=jp106 > /etc/vconsole.conf

# Set Hostname
echo -n -e "\n"
echo -n Type Hostname:
read hostname
echo \$hostname > /etc/hostname
target=/etc/hosts
echo 127.0.0.1 localhost > \$target
echo ::1 localhost >> \$target
echo 127.0.1.1 \${hostname}.localdomain \${hostname}>> \$target

# Set Root Password
echo -n -e "\n"
echo -n Type Root Password:
read pw
echo root:\$pw | chpasswd

# Create User and Set User Password
echo -n -e "\n"
echo -n Type New User:
read user
useradd -m -g users -G wheel -s /bin/bash \${user}
echo -n -e "\n"
echo -n Type \${user} Password:
read pw
echo \$user:\$pw
echo \$user:\$pw | chpasswd

# Setting Sudoer
pacman -S --noconfirm sudo
sed -i -e 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# Check CPU Vendor
cpu=\`lscpu | grep "Model name"\`
if [[ "\$cpu" ==  *Intel* ]] ; then
	ucode="intel-ucode"
elif [[ "\$cpu" ==  *AMD* ]] ; then
	ucode="amd-ucode"
fi

# Install Package
pacman -S --noconfirm booster \$ucode neovim clamav ufw networkmanager pacman-contrib

# Systemd-boot
bootctl install

target=/boot/loader/loader.conf
echo default arch.conf > \$target
echo console-mode max >> \$target
echo editor no >> \$target

target=/boot/loader/entries/arch.conf
option=\`blkid -o export ${part}3 | grep ^PARTUUID\`
echo title Arch Linux > \$target
echo linux /vmlinuz-linux-zen >> \$target
echo initrd /\${ucode}.img >> \$target
echo initrd /booster-linux-zen.img >> \$target
echo options root=\${option} rw >> \$target

# Setting Network
systemctl enable NetworkManager.service

# Setting Pacman
sed -i -e 's/#\(Color\|ParallelDownloads = 5\)/\1/' /etc/pacman.conf
systemctl enable paccache.timer

_END_

chmod +x /mnt/$shfile
arch-chroot /mnt /$shfile

umount -R /mnt

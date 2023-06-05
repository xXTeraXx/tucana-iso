#!/bin/bash
# Build a Tucana ISO from mercury
set -e
# The build directory, must be absolute path not relative
BUILD_DIR=/blfs/builds/iso
# Mercury repo server
REPO=http://192.168.1.143:88
# Tucana kernel version
KERNEL_VERSION=6.3.5

# Don't touch
ROOT=$BUILD_DIR/squashfs-root

# Cleanup old build stuff (if there is any)
mkdir -p $BUILD_DIR
cd $BUILD_DIR
rm -rf *

# Make root folder
mkdir -p $ROOT

# Get mercury
git clone https://github.com/xXTeraXx/tucana.git
cd tucana/mercury
sed -i "s|INSTALL_PATH=.*|INSTALL_PATH=$ROOT|" mercury-sync
sed -i "s|INSTALL_PATH=.*|INSTALL_PATH=$ROOT|" mercury-install
sed -i "s|REPO=.*|REPO=$REPO|" mercury-install
sed -i "s|REPO=.*|REPO=$REPO|" mercury-sync

# Install base system
chmod +x mercury-sync mercury-install
./mercury-sync
printf "y\n" | ./mercury-install base

# Chroot commands

# Mount temp filesystems
mount --bind /dev $ROOT/dev
mount --bind /proc $ROOT/proc
mount --bind /sys $ROOT/sys

# Install 
chroot $ROOT /bin/bash -c "systemd-machine-id-setup && systemctl preset-all" 

# Basic first-install things
echo "nameserver 1.1.1.1" > $BUILD_DIR/squashfs-root/etc/resolv.conf
chroot $ROOT /bin/bash -c "make-ca -g --force"
chroot $ROOT /bin/bash -c "pwconv"
# Install network manager and the kernel
chroot $ROOT /bin/bash -c "mercury-sync"
chroot $ROOT /bin/bash -c "printf 'y\n' | mercury-install linux-tucana network-manager mpc linux-firmware"
chroot $ROOT /bin/bash -c "systemctl enable NetworkManager"
# Locales
echo "Building Locales"
chroot $ROOT /bin/bash -c "mkdir -pv /usr/lib/locale
localedef -i POSIX -f UTF-8 C.UTF-8 2> /dev/null || true
localedef -i cs_CZ -f UTF-8 cs_CZ.UTF-8
localedef -i de_DE -f ISO-8859-1 de_DE
localedef -i de_DE@euro -f ISO-8859-15 de_DE@euro
localedef -i de_DE -f UTF-8 de_DE.UTF-8
localedef -i el_GR -f ISO-8859-7 el_GR
localedef -i en_GB -f ISO-8859-1 en_GB
localedef -i en_GB -f UTF-8 en_GB.UTF-8
localedef -i en_HK -f ISO-8859-1 en_HK
localedef -i en_PH -f ISO-8859-1 en_PH
localedef -i en_US -f ISO-8859-1 en_US
localedef -i en_US -f UTF-8 en_US.UTF-8
localedef -i es_ES -f ISO-8859-15 es_ES@euro
localedef -i es_MX -f ISO-8859-1 es_MX
localedef -i fa_IR -f UTF-8 fa_IR
localedef -i fr_FR -f ISO-8859-1 fr_FR
localedef -i fr_FR@euro -f ISO-8859-15 fr_FR@euro
localedef -i fr_FR -f UTF-8 fr_FR.UTF-8
localedef -i is_IS -f ISO-8859-1 is_IS
localedef -i is_IS -f UTF-8 is_IS.UTF-8
localedef -i it_IT -f ISO-8859-1 it_IT
localedef -i it_IT -f ISO-8859-15 it_IT@euro
localedef -i it_IT -f UTF-8 it_IT.UTF-8
localedef -i ja_JP -f EUC-JP ja_JP
localedef -i ja_JP -f SHIFT_JIS ja_JP.SJIS 2> /dev/null || true
localedef -i ja_JP -f UTF-8 ja_JP.UTF-8
localedef -i nl_NL@euro -f ISO-8859-15 nl_NL@euro
localedef -i ru_RU -f KOI8-R ru_RU.KOI8-R
localedef -i ru_RU -f UTF-8 ru_RU.UTF-8
localedef -i se_NO -f UTF-8 se_NO.UTF-8
localedef -i ta_IN -f UTF-8 ta_IN.UTF-8
localedef -i tr_TR -f UTF-8 tr_TR.UTF-8
localedef -i zh_CN -f GB18030 zh_CN.GB18030
localedef -i zh_HK -f BIG5-HKSCS zh_HK.BIG5-HKSCS
localedef -i zh_TW -f UTF-8 zh_TW.UTF-8"

# User account setup
chroot $ROOT /bin/bash -c "useradd -m live"
chroot $ROOT /bin/bash -c "printf 'tucana\ntucana\n' | passwd live"
chroot $ROOT /bin/bash -c "gpasswd -a live wheel"
  # Disable password for sudo
cat > $ROOT/etc/sudoers.d/00-sudo << "EOF"
Defaults secure_path="/usr/sbin:/usr/bin"
%wheel ALL=(ALL) NOPASSWD: ALL
EOF
cp $BUILD_DIR/tucana/tucana-installer.sh $ROOT/home/live
cp $BUILD_DIR/tucana/guisetup.sh $ROOT/home/live
chmod +x $ROOT/home/live/tucana-installer.sh $ROOT/home/live/guisetup.sh
# Copy any custom config files
if [[ -d $BUILD_DIR/custom_config ]]; then
	cp -r $BUILD_DIR/custom_config $ROOT
fi

# Install a desktop enviorment and any other packages (you can choose here)
# Gnome
chroot $ROOT /bin/bash -c "printf 'y\n' | mercury-install gnome gparted firefox lightdm xdg-user-dirs gedit vim flatpak gnome-tweaks xdg-user-dirs gedit file-roller openssh"
# XFCE 
#chroot $ROOT /bin/bash -c "printf 'y\n' | mercury-install xfce4 lightdm gedit polkit-gnome firefox lightdm xdg-user-dirs vim flatpak gnome-software libsoup3 openssh"
#chroot $ROOT /bin/bash -c "printf 'y\n' | mercury-install plasma-desktop-full gparted firefox lightdm xdg-user-dirs kate vim flatpak"
chroot $ROOT /bin/bash -c "chown -R live:live /home/live"
# Add the desktop, music documents, downloads and other folders
chroot $ROOT /bin/bash -c "su live -c xdg-user-dirs-update"
 # Setup autologin
chroot $ROOT /bin/bash -c "systemctl enable lightdm"
sed -i 's/#autologin-user=/autologin-user=live/' $ROOT/etc/lightdm/lightdm.conf

# Change the init script 
echo '#!/bin/sh

PATH=/usr/bin:/usr/sbin
export PATH

problem()
{
   printf "Encountered a problem!\n\nDropping you to a shell.\n\n"
   sh
}

no_device()
{
   printf "The device %s, which is supposed to contain the\n" $1
   printf "root file system, does not exist.\n"
   printf "Please fix this problem and exit this shell.\n\n"
}

no_mount()
{
   printf "Could not mount device %s\n" $1
   printf "Sleeping forever. Please reboot and fix the kernel command line.\n\n"
   printf "Maybe the device is formatted with an unsupported file system?\n\n"
   printf "Or maybe filesystem type autodetection went wrong, in which case\n"
   printf "you should add the rootfstype=... parameter to the kernel command line.\n\n"
   printf "Available partitions:\n"
}

do_mount_root()
{
   mkdir /.root
   mkdir -p /mnt
   mkdir -p /squash
   mknod /dev/loop0 b 7 0
   device="/dev/disk/by-label/tucana"
   # Mount Rootfs
   echo "Mounting USB Container Drive"
   mount $device /mnt
   echo "Mounting squashfs as overlay"
   mkdir -p /cow
   mount -t tmpfs tmpfs /cow
   mkdir -p /cow/mod
   mkdir -p /cow/buffer

   mount /mnt/boot/tucana.squashfs /squash -t squashfs -o loop
   mount -t overlay -o lowerdir=/squash,upperdir=/cow/mod,workdir=/cow/buffer overlay /.root
   mkdir -p /.root/mnt/changes
   mkdir -p /.root/mnt/container
   mount --bind /cow/mod /.root/mnt/changes
   mount --bind /mnt /.root/mnt/container
}

do_try_resume()
{
   case "$resume" in
      UUID=* ) eval $resume; resume="/dev/disk/by-uuid/$UUID"  ;;
      LABEL=*) eval $resume; resume="/dev/disk/by-label/$LABEL" ;;
   esac

   if $noresume || ! [ -b "$resume" ]; then return; fi

   ls -lH "$resume" | ( read x x x x maj min x
       echo -n ${maj%,}:$min > /sys/power/resume )
}

init=/sbin/init
root=
rootdelay=
rootfstype=auto
ro="ro"
rootflags=
device=
resume=
noresume=false

mount -n -t devtmpfs devtmpfs /dev
mount -n -t proc     proc     /proc
mount -n -t sysfs    sysfs    /sys
mount -n -t tmpfs    tmpfs    /run

read -r cmdline < /proc/cmdline

for param in $cmdline ; do
  case $param in
    init=*      ) init=${param#init=}             ;;
    root=*      ) root=${param#root=}             ;;
    rootdelay=* ) rootdelay=${param#rootdelay=}   ;;
    rootfstype=*) rootfstype=${param#rootfstype=} ;;
    rootflags=* ) rootflags=${param#rootflags=}   ;;
    resume=*    ) resume=${param#resume=}         ;;
    noresume    ) noresume=true                   ;;
    ro          ) ro="ro"                         ;;
    rw          ) ro="rw"                         ;;
  esac
done

# udevd location depends on version
if [ -x /sbin/udevd ]; then
  UDEVD=/sbin/udevd
elif [ -x /lib/udev/udevd ]; then
  UDEVD=/lib/udev/udevd
elif [ -x /lib/systemd/systemd-udevd ]; then
  UDEVD=/lib/systemd/systemd-udevd
else
  echo "Cannot find udevd nor systemd-udevd"
  problem
fi

${UDEVD} --daemon --resolve-names=never
udevadm trigger
udevadm settle

if [ -f /etc/mdadm.conf ] ; then mdadm -As                       ; fi
if [ -x /sbin/vgchange  ] ; then /sbin/vgchange -a y > /dev/null ; fi
if [ -n "$rootdelay"    ] ; then sleep "$rootdelay"              ; fi

do_try_resume # This function will not return if resuming from disk
do_mount_root

killall -w ${UDEVD##*/}

exec switch_root /.root "$init" "$@"' > $ROOT/usr/share/mkinitramfs/init.in

# Generate initrd

chroot $ROOT /bin/bash -c "mkinitramfs $KERNEL_VERSION-tucana"
# Makes gnome work
chroot $ROOT /bin/bash -c "gdk-pixbuf-query-loaders --update-cache"

# Setup flatpak
chroot $ROOT /bin/bash -c "flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo"

# Unmount temp filesystems and generate squashfs
cd $BUILD_DIR
umount $ROOT/dev
umount $ROOT/proc
umount $ROOT/sys
mksquashfs squashfs-root tucana.squashfs


# Start building the iso
git clone https://github.com/xXTeraXx/tucana-iso.git

mkdir -p iso
cd iso
mkdir -p boot/grub buffer mod isolinux unmod
# Copy some stuff and build the efi.img file
cp -rpv $BUILD_DIR/tucana-iso/isolinux/* isolinux
cp -rpv $BUILD_DIR/tucana-iso/grub boot/
cd boot/grub
bash .mkefi
cd ../../

# Copy the squashfs, initramfs and kernel
cp -pv $ROOT/boot/vmlinuz-* $BUILD_DIR/iso/boot
cp -pv $ROOT/initrd* $BUILD_DIR/iso/boot
cp -pv $BUILD_DIR/tucana.squashfs $BUILD_DIR/iso/boot

# Build the iso
xorriso -as mkisofs \
  -isohybrid-mbr $BUILD_DIR/tucana-iso/isohdpfx.bin \
  -c isolinux/boot.cat \
  -b isolinux/isolinux.bin \
  -no-emul-boot \
  -boot-load-size 4 \
  -boot-info-table \
  -eltorito-alt-boot \
  -e boot/grub/efi.img \
  -no-emul-boot \
  -isohybrid-gpt-basdat \
  -o tucana.iso -V tucana \
  .
mv tucana.iso ../






#!/bin/bash
#set -e
set -x
# Parse command line flags
while [ "$1" != "" ]; do
        case "$1" in
                -h|--help ) usage ; exit 1 ;;
                -i_iso    ) shift; i_iso=$1 ;;
                -o_iso    ) shift; o_iso=$1 ;;
                -work_dir ) shift; work_dir=$1 ;;
                -apt      ) shift; apt_file=$1; export apt_file ;;
                -d|--debug) set -x   ;;
        esac
        shift
done

usage () {
        cat << EOF
        usage: $(basename $0) -i_iso <Original Source ISO> -o_iso [Output_iso] -work_dir [directory] -apt [File lists all apt to install]

        Must be executed as SU.
        This will take Original Ubuntu_Desktop ISO. Modify the Image and repack it with name custom.iso.
        For Modifications see Modifications/Chroot Section.

        OPTIONS:
                -h              - Print this help menu.
                -i_iso          - Input ISO Original.
                -o_iso          - Output ISO file. Default is CWD/custom.iso.
                -work_dir       - Directory to dump all the files temporarily. Default is CWD.
                -apt            - File listing all apt pkgs to install on the custom ISO. Default installs none.
                -d|--debug      - Enable command printing for debugging.
EOF
}

## Setup Mount, Edit, Extract Dirs
setup_dirs () {
        set +e mkdir /mnt 2>/dev/null
        echo "Mounting $i_iso on /mnt"
        mount $i_iso /mnt >/dev/null 2>&1
        #rm -r $edit_dir 2>/dev/null
        set +e mkdir $extract_dir 2>/dev/null
        echo -e "Copying contents to Edit Directory"
        #rsync -avh --exclude=casper/filesystem.squashfs /mnt/ $extract_dir
        echo -e "UnSquashing to Extract Directory"
        unsquashfs -d $edit_dir /mnt/casper/filesystem.squashfs

        ## Make these files available to chroot from host
        [[ ! -z $apt_file ]] && cp $apt_file $edit_dir/tmp/apt_file
}

function setup_chroot () {
        echo "Setting UP CHROOT Environment"
        mount -t proc /proc $edit_dir/proc
        mount -t sysfs /sys $edit_dir/sys
        mount -o bind /run $edit_dir/run
        mount --bind /dev $edit_dir/dev
}
function clean_up () {
        echo "UnMounting CHROOT Directories..."
        umount $edit_dir/proc
        umount $edit_dir/sys
        umount $edit_dir/run
        umount $edit_dir/dev
        umount /mnt
        rm -r $edit_dir 2>/dev/null
        rm -r $extract_dir 2>/dev/null
}
install_pkgs () {
## Please Update Below IF Using different OS/Distro
cat <<-EOF > /etc/apt/sources.list
        deb http://archive.ubuntu.com/ubuntu/ jammy main restricted
        deb http://security.ubuntu.com/ubuntu/ jammy-security main restricted
        deb http://archive.ubuntu.com/ubuntu/ jammy-updates main restricted
EOF
        cat /tmp/apt_file
        apt-get update
        while read -r line; do
                apt-get install -y $line ;
        done < /tmp/apt_file
}
export -f install_pkgs
## Check if Required Args Missing
echo $i_iso
[[ -z $i_iso ]] && usage && echo -e "\nInput ISO File Not Specified" && exit 1
[[ -z $o_iso ]] && echo -e "\nOutput ISO File Not Specified\ncustom.iso will be created in dir: $work_dir" && o_iso=${work_dir}/custom.iso
[[ ! -z $o_iso ]] && echo -e "\nOutput ISO File: $o_iso"

echo "pwd: ${0%/*}"

## If Default WO_Dir is CWD if Not provided
[[ -z $work_dir ]] && work_dir=${0%/*} && echo "Work Directory Not Provided ! Using ${0%/*} as work directory"

edit_dir="${work_dir}/edit"
extract_dir="${work_dir}/extract"
echo "work_directory set to $work_dir"
echo "edit_directory set to $edit_dir"
echo "extract_directory set to $extract_dir"

setup_dirs
setup_chroot

## Add all your Chroot-MODS here !!!!
## Enter CHROOT, Do Modifications....
chroot $edit_dir  /bin/bash <<EOF
set -x
echo "Inside CHRoot"
ls /

## Installing APT Packages Listed in $apt_file
[ ! -z /tmp/apt_file ] && echo "Installing Packages Listed In APT_File: /tmp/apt_file" && install_pkgs || echo "Skipping apt-install NO APT File Provided"

## Set HostName
echo "live" > /etc/hostname

## Add User ## Make User Sudoers
username="live"
password="just4root"
echo "Creating user \$username:\$password"
useradd -m -s /bin/bash \$username
echo "\$username:\$password" | chpasswd \$username

## Setup SSHD
echo "Setting Up SSHD"
sed -i 's/^.PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
sed -i 's/^.PermitEmptyPasswords.*/PermitEmptyPasswords yes/' /etc/ssh/sshd_config

EOF

## Wrap UP FS & New Pkg_List
chmod +w ${extract_dir}/casper/filesystem.manifest
chroot ${edit_dir} dpkg-query -W --showformat='${Package} ${Version} \n' > $extract_dir/casper/filesystem.manifest
cp $extract_dir/casper/filesystem.manifest $extract_dir/casper/filesystem.manifest-desktop
sed -i '/ubiquity/d' $extract_dir/casper/filesystem.manifest-desktop
sed -i '/casper/d' $extract_dir/casper/filesystem.manifest-desktop

## Remove Existing Squash-FS
rm $extract_dir/filesystem.squashfs
rm $extract_dir/filesystem.squashfs.gpg

## Re-Create Squash-FS
mksquashfs $edit_dir $extract_dir/casper/filesystem.squashfs -comp xz
printf $(du -sx --block-size=1 edit | cut -f1) > extracted/casper/filesystem.size  ## New Size of Squashfs

## Remove OLD MD5SUM & Replace with new one's..
pushd $extract_dir
rm md5sum.txt
find -type f -print0 | xargs -0 md5sum | grep -v isolinux/boot.cat | tee md5sum.txt
popd

## Create NEW Custom Live ISO Image
sector_size=$(fdisk -l $i_iso | awk '/Sector size/ {print $(NF-1)}' )
efi_start=$(fdisk -l $i_iso | awk '/EFI System/ {print $3}' )
efi_count=$(fdisk -l $i_iso | awk '/EFI System/ {print $5}' )
dd bs=1 count=446 if=$i_iso of=${}/mbr.img ## Capture Bios-MBR from Original ISO
dd bs=$sector_size count=$efi_count skip=$efi_start if=$i_iso of=EFI.img ## Capture EFI Partition from Original ISO.

## Get required flags for xorriso
load_size=$(xorriso -indev $i_iso -report_el_torito cmd | awk -F '=' '/load_size/ {a=$NF} END{print a}')
xorriso -outdev custom.iso -map $extract_dir / -- -volid "Custom ISO" -boot_image grub grub2_mbr=${extract_dir}/mbr.img -boot_image any partition_table=on -boot_image any partition_cyl_align=off -boot_image any partition_offset=16 -boot_image any mbr_force_bootable=on -append_partition 2 28732ac11ff8d211ba4b00a0c93ec93b ${extract_dir}/EFI.img -boot_image any appended_part_as=gpt -boot_image any iso_mbr_part_type=a2a0d0ebe5b9334487c068b6b72699c7 -boot_image any cat_path='/boot.catalog' -boot_image grub bin_path='/boot/grub/i386-pc/eltorito.img' -boot_image any platform_id=0x00 -boot_image any emul_type=no_emulation -boot_image any load_size=2048 -boot_image any boot_info_table=on -boot_image grub grub2_boot_info=on -boot_image any next -boot_image any efi_path=--interval:appended_partition_2:all:: -boot_image any platform_id=0xef -boot_image any emul_type=no_emulation -boot_image any load_size=$load_size

## Clean UP All the JUNK & UNMOUNT !
clean_up

#exec <&-
## exit Chroot
echo "Exiting CHRoot from $target_dir"
exit 0

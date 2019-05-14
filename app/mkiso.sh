#!/bin/bash

# Reset
Color_Off='\033[0m'	# Text Reset

# Regular Colors
Red='\033[0;31m'	# Red
Green='\033[0;32m'	# Green

error_die () {
	echo -e "${Red}ERROR:${Color_Off} $1"
	[ "$(ls -A /mnt)" ] && umount "/mnt"
	exit 1
}

popd () {
	command popd "$@" > /dev/null
}

pushd () {
	command pushd "$@" > /dev/null
}

show_info () {
	echo -e "${Green}$(date -R) ---${Color_Off} $1."
}

# --------------------------------------------------------------------------------------------------------------------------------------------------
# Replace env variables
while IFS='=' read -r name value ; do
	if [[ "${name}" = "MKISO_"* ]]; then
		echo "${name}=\"${value}\"" >> /tmp/mkiso.env
		VARNAME=$(echo "${name}" | cut -d_ -f2-)
		sed -i "s/%${VARNAME}%/${value}/g" "/var/app/preseed.cfg"
	fi
done < <(env | sort)

# --------------------------------------------------------------------------------------------------------------------------------------------------
# Create directories
TMPDIR=$(mktemp -d)
mkdir "${TMPDIR}/extracted" "${TMPDIR}/initrd"

# --------------------------------------------------------------------------------------------------------------------------------------------------
# Download mini.iso
show_info "Downloading mini.iso"
wget -qO "${TMPDIR}/mini.iso" "http://ftp.${MKISO_COUNTRYCODE}.debian.org/debian/dists/stable/main/installer-amd64/current/images/netboot/gtk/mini.iso"

# --------------------------------------------------------------------------------------------------------------------------------------------------
# Extract image
show_info "Extracting image"
mount -r -o loop "${TMPDIR}/mini.iso" "/mnt" || error_die "Could not mount image"
rsync -a "/mnt/" "${TMPDIR}/extracted" || error_die "Could not extract image"
umount "/mnt"

# --------------------------------------------------------------------------------------------------------------------------------------------------
# Customizing image
show_info "Customizing image"
pushd "${TMPDIR}/extracted"
mv "/tmp/mkiso.env" .
rm -rf *.{bin,c32,cfg,exe,ini,txt} .disk g2ldr* || error_die "Could not remove superfluous files"
perl -i -pe "BEGIN{undef $/;} s/submenu.*{.*}//smg" "boot/grub/grub.cfg"
sed -i "s/\/isolinux//" "boot/grub/grub.cfg"
sed -i "N; s/440 1\nmenuentry/440 1\nset timeout=5\n\nmenuentry/" "boot/grub/grub.cfg"
sed -i "s/vga=788/auto=true priority=critical vga=788/" "boot/grub/grub.cfg"
popd

# --------------------------------------------------------------------------------------------------------------------------------------------------
# Customizing EFI
show_info "Customizing EFI"
mount -o loop "${TMPDIR}/extracted/boot/grub/efi.img" "/mnt/" || error_die "Could not mount EFI image"
GRUBCFG_OFFSET=$(grep -aob "/.disk/info" "/mnt/efi/boot/bootx64.efi" | cut -d: -f1)
echo "/mkiso.env " | dd of="/mnt/efi/boot/bootx64.efi" bs=1 seek=${GRUBCFG_OFFSET} count=11 conv=notrunc 2>/dev/null || error_die "Could not update efi grub.cfg"
umount "/mnt"

# --------------------------------------------------------------------------------------------------------------------------------------------------
# Customize initrd
show_info "Unpacking initrd"
pushd "${TMPDIR}/initrd"
zcat "${TMPDIR}/extracted/initrd.gz" | cpio --quiet -i -d || error_die "Could not extract initrd"

# Add custom data
cp "/var/app/preseed.cfg" "${TMPDIR}/initrd/preseed.cfg" || error_die "Could not copy preseed"
cat <<-EOF > "${TMPDIR}/initrd/installer.sh" || error_die "Could not write installer.sh"
	#!/bin/sh

	# Allow ssh logins for root
	sed -i "s/#PermitRoot.*/PermitRootLogin yes/" /target/etc/ssh/sshd_config

	# Remove grub boot delay
	sed -i "s/GRUB_TIMEOUT=.*$/GRUB_TIMEOUT=0/" /target/etc/default/grub

	# Recreate grub config
	in-target update-grub
EOF
chmod +x "${TMPDIR}/initrd/installer.sh" || error_die "Could not make installer.sh executable"

mkdir -p "${TMPDIR}/initrd/usr/share/debootstrap/scripts" || error_die "Could not create debootstrap scripts directory"
ln -sf "sid" "${TMPDIR}/initrd/usr/share/debootstrap/scripts/testing" || error_die "Could not create testing script link"

# Repack initrd
show_info "Repacking initrd"
find . | cpio --quiet -o -H newc | gzip -9 > "${TMPDIR}/extracted/initrd.gz" || error_die "Could not repack initrd"
popd

# --------------------------------------------------------------------------------------------------------------------------------------------------
# Repack image
show_info "Repacking image"
xorriso -as mkisofs -o "/data/debian-installer-$(date +%F-%H_%M).iso" -c "boot.cat" -J -joliet-long \
	-eltorito-alt-boot -e "boot/grub/efi.img" -no-emul-boot \
	"${TMPDIR}/extracted" -- &>"${TMPDIR}/xorriso.log" || error_die "Could not repack image"

show_info "Done"

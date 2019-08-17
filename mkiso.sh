#!/bin/bash

set -exo pipefail

if [ "${1}" != "entry" ]; then
	/var/app/mkiso.sh "entry" 2>&1 | ts
	exit 0
fi

SPACER="------------------------------"
DEB_ISO_URL="http://ftp.debian.org/debian/dists/stable/main/installer-amd64/current/images/netboot/gtk/mini.iso"

# --------------------------------------------------------------------------------------------------------------------------------------------------
# Replace env variables
IFS="="
while read -r name value; do
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
echo "${SPACER} Downloading mini.iso"
wget --progress=dot:giga "${DEB_ISO_URL}" -O "${TMPDIR}/mini.iso"

# --------------------------------------------------------------------------------------------------------------------------------------------------
# Extract image
echo "${SPACER} Extracting image"
xorriso -osirrox on -indev "${TMPDIR}/mini.iso" -extract / "${TMPDIR}/extracted" &>>"${TMPDIR}/xorriso.log"

# --------------------------------------------------------------------------------------------------------------------------------------------------
# Customizing image
echo "${SPACER} Customizing image"
pushd "${TMPDIR}/extracted"
mv "/tmp/mkiso.env" .
rm -rf -- *.{bin,c32,cfg,exe,ini,txt} .disk g2ldr*
perl -i -pe "BEGIN{undef $/;} s/submenu.*{.*}//smg" "boot/grub/grub.cfg"
sed -i "s/\/isolinux//" "boot/grub/grub.cfg"
sed -i "N; s/440 1\nmenuentry/440 1\nset timeout=5\n\nmenuentry/" "boot/grub/grub.cfg"
sed -i "s/vga=788/auto=true priority=critical vga=788/" "boot/grub/grub.cfg"
popd

# --------------------------------------------------------------------------------------------------------------------------------------------------
# Customizing EFI
echo "${SPACER} Customizing EFI"
mcopy -i "${TMPDIR}/extracted/boot/grub/efi.img" ::efi/debian/grub.cfg "${TMPDIR}/bootx64.efi"
mdel -i "${TMPDIR}/extracted/boot/grub/efi.img" ::efi/debian/grub.cfg
sed -i "s/mkiso.env/.disk\/info/" "${TMPDIR}/bootx64.efi"
mcopy -i "${TMPDIR}/extracted/boot/grub/efi.img" "${TMPDIR}/bootx64.efi" ::efi/debian/grub.cfg

# --------------------------------------------------------------------------------------------------------------------------------------------------
# Customize initrd
echo "${SPACER} Unpacking initrd"
pushd "${TMPDIR}/initrd"
zcat "${TMPDIR}/extracted/initrd.gz" | cpio --quiet -i -d

# Add custom data
cp "/var/app/preseed.cfg" "${TMPDIR}/initrd/preseed.cfg"

mkdir -p "${TMPDIR}/initrd/usr/share/debootstrap/scripts"
ln -sf "sid" "${TMPDIR}/initrd/usr/share/debootstrap/scripts/testing"

# Repack initrd
echo "${SPACER} Repacking initrd"
find . | cpio --quiet -o -H newc | gzip > "${TMPDIR}/extracted/initrd.gz"
popd

# --------------------------------------------------------------------------------------------------------------------------------------------------
# Repack image
echo "${SPACER} Repacking image"
xorriso -as mkisofs -o "/data/debian-devel.iso" -c "boot.cat" -J -joliet-long \
	-eltorito-alt-boot -e "boot/grub/efi.img" -no-emul-boot \
	"${TMPDIR}/extracted" -- &>>"${TMPDIR}/xorriso.log"

echo "${SPACER} Done"

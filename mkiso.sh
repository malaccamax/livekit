LIVEKITDATA=/tmp/iso
_ISOHDPFX=$(pwd)/isohdpfx.bin
cd $LIVEKITDATA && xorriso -as mkisofs -o /tmp/iso.iso -v -J -R -D \
	-isohybrid-mbr ${_ISOHDPFX} -partition_offset 16 \
	-no-emul-boot -boot-info-table -boot-load-size 4 \
	-b slax/boot/isolinux.bin -c slax/boot/isolinux.boot . 

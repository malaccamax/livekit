LIVEKITDATA=/tmp/iso
cd $LIVEKITDATA && xorriso -as mkisofs -o /tmp/iso.iso -v -J -R -D \
	-no-emul-boot -boot-info-table -boot-load-size 4 \
	-b slax/boot/isolinux.bin -c slax/boot/isolinux.boot . 

build:
	@echo "Run 'make install' to install fido2luks"

clean:
	@echo "Nothing to do"

install:
	install -D -m 0755 keyscript.sh $(DESTDIR)/usr/lib/fido2luks/keyscript.sh
	install -D -m 0755 initramfs-hook $(DESTDIR)/etc/initramfs-tools/hooks/fido2luks

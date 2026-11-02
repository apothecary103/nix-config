# SPDX-License-Identifier: GPL-2.0-only
# Out-of-tree build of apple-jpeg.ko and apple-jpeg-overlay.ko.
#   make KDIR=/lib/modules/$(uname -r)/build
# Needs dtc and python3 for the overlay blobs (no -@: see the .dts files).
KDIR ?= /lib/modules/$(shell uname -r)/build
PWD  := $(shell pwd)
DTBO_H := jpeg_overlay_core0_dtbo.h jpeg_overlay_core1_dtbo.h

all: $(DTBO_H)
	$(MAKE) -C $(KDIR) M=$(PWD) modules

jpeg_overlay_%_dtbo.h: jpeg-overlay-%.dtbo mkhdr.py
	python3 mkhdr.py $< jpeg_overlay_$*_dtbo $@

jpeg-overlay-%.dtbo: jpeg-overlay-%.dts
	# sentinel phandles trip these two checks by design
	dtc -Wno-power_domains_property -Wno-interrupts_property -I dts -O dtb -o $@ $<

modules_install:
	$(MAKE) -C $(KDIR) M=$(PWD) modules_install

clean:
	$(MAKE) -C $(KDIR) M=$(PWD) clean
	rm -f $(DTBO_H) jpeg-overlay-*.dtbo

.PHONY: all modules_install clean

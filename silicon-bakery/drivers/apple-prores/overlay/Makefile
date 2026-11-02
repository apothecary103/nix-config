# SPDX-License-Identifier: GPL-2.0-only
# The runtime DT overlay for kernels without patches/linux-prores.
KDIR ?= /lib/modules/$(shell uname -r)/build
PWD  := $(shell pwd)
DTC  ?= dtc

all: prores_overlay_dtbo.h
	$(MAKE) -C $(KDIR) M=$(PWD) modules

prores_overlay_dtbo.h: prores-overlay-t6020.dtbo
	python3 mkhdr.py $< prores_overlay_dtbo $@

prores-overlay-t6020.dtbo: prores-overlay-t6020.dts
	$(DTC) -@ -I dts -O dtb -o $@ $<

clean:
	$(MAKE) -C $(KDIR) M=$(PWD) clean
	rm -f prores_overlay_dtbo.h prores-overlay-t6020.dtbo

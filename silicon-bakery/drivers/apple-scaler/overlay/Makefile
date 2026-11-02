# SPDX-License-Identifier: GPL-2.0-only
# Runtime DT overlay for the M2Scaler: make KDIR=... (needs dtc, python3)
KDIR ?= /lib/modules/$(shell uname -r)/build
DTC ?= dtc
PYTHON ?= python3

all: scaler_overlay_t6020_dtbo.h
	$(MAKE) -C $(KDIR) M=$(CURDIR) modules

scaler-overlay-t6020.dtbo: scaler-overlay-t6020.dts
	$(DTC) -q -@ -I dts -O dtb -o $@ $<

scaler_overlay_t6020_dtbo.h: scaler-overlay-t6020.dtbo mkhdr.py
	$(PYTHON) mkhdr.py $< scaler_overlay_t6020_dtbo $@

clean:
	$(MAKE) -C $(KDIR) M=$(CURDIR) clean
	rm -f scaler-overlay-t6020.dtbo scaler_overlay_t6020_dtbo.h

.PHONY: all clean

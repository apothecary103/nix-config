# SPDX-License-Identifier: GPL-2.0-only
# Out-of-tree build: make KDIR=/path/to/kernel/build [-C overlay as well]
KDIR ?= /lib/modules/$(shell uname -r)/build
PWD  := $(shell pwd)

all:
	$(MAKE) -C $(KDIR) M=$(PWD) modules

install:
	$(MAKE) -C $(KDIR) M=$(PWD) modules_install

clean:
	$(MAKE) -C $(KDIR) M=$(PWD) clean

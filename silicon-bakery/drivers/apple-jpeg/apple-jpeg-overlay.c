// SPDX-License-Identifier: GPL-2.0-only
/*
 * Bring-up aid: applies the t6020 JPEG nodes (jpeg0/jpeg1 and their DARTs)
 * to the live device tree, for the apple-jpeg driver, when the kernel's own
 * DT lacks them (patches/linux-jpeg not applied).
 *
 * Modelled on the community AVE driver's test/ave_overlay_mod.c
 * (github.com/aquarat/apple-m-series-ave-driver 9ab14e45, GPL-2.0-only):
 * the embedded dtbos carry sentinel phandles because the base tree has no
 * __symbols__, and the sentinels are replaced with live phandles found by
 * compatible (the AIC) and by power-domain label (ps_jpg = "jpg").
 *
 * Applied once per boot: there is no module_exit, so the module cannot be
 * unloaded and the nodes stay until reboot. Not yet run on hardware.
 */
#include <linux/module.h>
#include <linux/of.h>
#include <linux/slab.h>
#include <linux/string.h>

#include "jpeg_overlay_core0_dtbo.h"
#include "jpeg_overlay_core1_dtbo.h"

#define AJO_SENTINEL_AIC	0x4a500001u
#define AJO_SENTINEL_JPG	0x4a500002u
#define AJO_SENTINEL_MASK	0xffffff00u
#define AJO_SENTINEL_BASE	0x4a500000u

static unsigned int cores = 3;
module_param(cores, uint, 0444);
MODULE_PARM_DESC(cores, "which engines to add: bit 0 jpeg0, bit 1 jpeg1 (default 3)");

static int ajo_find_pd(const char *label, u32 *phandle)
{
	struct device_node *np, *hit = NULL;
	const char *l;

	for_each_node_with_property(np, "#power-domain-cells") {
		if (of_property_read_string(np, "label", &l) || strcmp(l, label))
			continue;
		if (hit) {
			pr_err("apple-jpeg-overlay: two power domains labelled %s: %pOF, %pOF\n",
			       label, hit, np);
			of_node_put(np);
			of_node_put(hit);
			return -EEXIST;
		}
		hit = of_node_get(np);
	}
	if (!hit || !hit->phandle) {
		pr_err("apple-jpeg-overlay: no power domain labelled %s with a phandle\n", label);
		of_node_put(hit);
		return -ENODEV;
	}
	*phandle = hit->phandle;
	of_node_put(hit);
	return 0;
}

static int ajo_find_aic(u32 *phandle)
{
	struct device_node *np = of_find_compatible_node(NULL, NULL, "apple,aic2");
	int ret = 0;

	if (!np || !of_property_read_bool(np, "interrupt-controller") || !np->phandle) {
		pr_err("apple-jpeg-overlay: no apple,aic2 interrupt controller with a phandle\n");
		ret = -ENODEV;
	} else {
		*phandle = np->phandle;
	}
	of_node_put(np);
	return ret;
}

/*
 * A fixed-up copy of fdt (kfree it) or an ERR_PTR. Sentinels are matched
 * as whole big-endian cells on 4-byte boundaries; 0x4a 0x50 0x00 is not
 * text that the strings block could hold at a cell boundary followed by
 * 0x01/0x02, and every unknown 0x4a5000xx cell is refused.
 */
static void *ajo_fixup(const void *fdt, unsigned int len, u32 aic, u32 jpg)
{
	unsigned int n_aic = 0, n_jpg = 0;
	u8 *copy = kmemdup(fdt, len, GFP_KERNEL);

	if (!copy)
		return ERR_PTR(-ENOMEM);
	for (unsigned int off = 0; off + 4 <= len; off += 4) {
		__be32 *cell = (__be32 *)(copy + off);
		u32 v = be32_to_cpup(cell);

		if ((v & AJO_SENTINEL_MASK) != AJO_SENTINEL_BASE)
			continue;
		if (v == AJO_SENTINEL_AIC) {
			*cell = cpu_to_be32(aic);
			n_aic++;
		} else if (v == AJO_SENTINEL_JPG) {
			*cell = cpu_to_be32(jpg);
			n_jpg++;
		} else {
			pr_err("apple-jpeg-overlay: unknown sentinel %#x at dtbo offset %#x\n", v, off);
			kfree(copy);
			return ERR_PTR(-EINVAL);
		}
	}
	/* two interrupt-parents and two power-domains per core */
	if (n_aic != 2 || n_jpg != 2) {
		pr_err("apple-jpeg-overlay: dtbo has %u AIC / %u jpg sentinels, expected 2/2\n",
		       n_aic, n_jpg);
		kfree(copy);
		return ERR_PTR(-EINVAL);
	}
	return copy;
}

static int ajo_apply(unsigned int core, const void *fdt, unsigned int len, u32 aic, u32 jpg)
{
	void *fixed = ajo_fixup(fdt, len, aic, jpg);
	int ovcs_id = 0, ret;

	if (IS_ERR(fixed))
		return PTR_ERR(fixed);
	ret = of_overlay_fdt_apply(fixed, len, &ovcs_id, NULL);
	kfree(fixed);
	if (ret) {
		pr_err("apple-jpeg-overlay: jpeg%u overlay failed: %d\n", core, ret);
		return ret;
	}
	pr_info("apple-jpeg-overlay: jpeg%u and its DART added (changeset %d)\n", core, ovcs_id);
	return 0;
}

static int __init ajo_init(void)
{
	struct device_node *np;
	u32 aic, jpg;
	int ret;

	if (!cores || cores > 3) {
		pr_err("apple-jpeg-overlay: cores=%u is not 1-3; refusing\n", cores);
		return -EINVAL;
	}
	if (!of_machine_is_compatible("apple,t6020")) {
		pr_err("apple-jpeg-overlay: not an apple,t6020 (M2 Pro) machine; refusing\n");
		return -ENODEV;
	}
	np = of_find_compatible_node(NULL, NULL, "apple,t6020-jpeg");
	if (np) {
		pr_err("apple-jpeg-overlay: %pOF already exists (kernel DT patch?); refusing\n", np);
		of_node_put(np);
		return -EEXIST;
	}
	ret = ajo_find_aic(&aic);
	if (ret)
		return ret;
	ret = ajo_find_pd("jpg", &jpg);
	if (ret)
		return ret;
	pr_info("apple-jpeg-overlay: aic -> phandle %#x, ps_jpg -> phandle %#x\n", aic, jpg);

	if (cores & 1) {
		ret = ajo_apply(0, jpeg_overlay_core0_dtbo, jpeg_overlay_core0_dtbo_len, aic, jpg);
		if (ret)
			return ret;
	}
	if (cores & 2) {
		ret = ajo_apply(1, jpeg_overlay_core1_dtbo, jpeg_overlay_core1_dtbo_len, aic, jpg);
		/* jpeg0's nodes stay applied: no exit, a reboot removes them */
		if (ret)
			return ret;
	}
	return 0;
}
module_init(ajo_init);

MODULE_DESCRIPTION("Runtime DT overlay: t6020 JPEG engines for apple-jpeg (bring-up aid)");
MODULE_LICENSE("GPL");

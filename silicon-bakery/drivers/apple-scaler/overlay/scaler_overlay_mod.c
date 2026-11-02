// SPDX-License-Identifier: GPL-2.0-only
/*
 * Bring-up aid: adds the t6020 M2Scaler and its DART to the live device tree
 * (scaler-overlay-t6020.dts) so apple-scaler has something to bind to,
 * without rebuilding the boot DT. Same approach as the community AVE
 * driver's test/ave_overlay_mod.c (aquarat, 9ab14e45): phandles of base-tree
 * nodes are sentinels in the dtbo, resolved here by label.
 *
 * Applying it makes apple-dart probe the new DART, which powers ps_msr0 and
 * resets the DART. ps_msr0 is the power state macOS uses for this block
 * [ADT clock-gates / KEXT13.5], so this is expected to be safe; it is still
 * the first Linux access to the block. Run `sync` first.
 *
 * There is no module_exit on purpose: removing the overlay would unbind the
 * DART while its power domain may be off (see the AVE incident notes in
 * docs/ave-port.txt). Apply once per boot; iterate with rmmod/modprobe of
 * apple-scaler only.
 */
#include <linux/module.h>
#include <linux/of.h>
#include <linux/slab.h>

#include "scaler_overlay_t6020_dtbo.h"

#define SOV_SENTINEL(nn)	(0xa7e00000u | (nn))
#define SOV_SENTINEL_MASK	0xffffff00u

static const struct {
	u32		sentinel;
	const char	*label;		/* power-domain label; NULL = the AIC */
} sov_refs[] = {
	{ SOV_SENTINEL(0x13), NULL },
	{ SOV_SENTINEL(0x21), "msr0" },
	{ SOV_SENTINEL(0x22), "msr0_ase_core" },
};

static int ovcs_id;

static int sov_find_pd(const char *label, u32 *phandle)
{
	struct device_node *np, *hit = NULL;
	const char *l;

	for_each_node_with_property(np, "#power-domain-cells") {
		if (of_property_read_string(np, "label", &l) || strcmp(l, label))
			continue;
		if (hit) {
			pr_err("scaler-overlay: two power domains labelled %s\n", label);
			of_node_put(np);
			of_node_put(hit);
			return -EEXIST;
		}
		hit = of_node_get(np);
	}
	if (!hit || !hit->phandle) {
		pr_err("scaler-overlay: no power domain labelled %s with a phandle\n", label);
		of_node_put(hit);
		return -ENODEV;
	}
	*phandle = hit->phandle;
	of_node_put(hit);
	return 0;
}

static int sov_find_aic(u32 *phandle)
{
	struct device_node *np = of_find_compatible_node(NULL, NULL, "apple,aic2");
	int ret = 0;

	if (!np || !of_property_read_bool(np, "interrupt-controller") || !np->phandle) {
		pr_err("scaler-overlay: no apple,aic2 with a phandle\n");
		ret = -ENODEV;
	} else {
		*phandle = np->phandle;
	}
	of_node_put(np);
	return ret;
}

static void *sov_fixup(const void *fdt, unsigned int len)
{
	unsigned int n[ARRAY_SIZE(sov_refs)] = { 0 };
	__be32 live[ARRAY_SIZE(sov_refs)];
	bool known[ARRAY_SIZE(sov_refs)] = { 0 };
	unsigned int off, i;
	u8 *copy;
	int ret;

	copy = kmemdup(fdt, len, GFP_KERNEL);
	if (!copy)
		return ERR_PTR(-ENOMEM);
	for (off = 0; off + 4 <= len; off += 4) {
		u32 v = be32_to_cpup((const __be32 *)(copy + off));

		if ((v & SOV_SENTINEL_MASK) != SOV_SENTINEL(0))
			continue;
		for (i = 0; i < ARRAY_SIZE(sov_refs); i++)
			if (v == sov_refs[i].sentinel)
				break;
		if (i == ARRAY_SIZE(sov_refs)) {
			pr_err("scaler-overlay: unknown sentinel %#x at %#x\n", v, off);
			ret = -EINVAL;
			goto fail;
		}
		if (!known[i]) {
			u32 ph;

			ret = sov_refs[i].label ? sov_find_pd(sov_refs[i].label, &ph) :
						  sov_find_aic(&ph);
			if (ret)
				goto fail;
			live[i] = cpu_to_be32(ph);
			known[i] = true;
		}
		memcpy(copy + off, &live[i], 4);
		n[i]++;
	}
	for (i = 0; i < ARRAY_SIZE(sov_refs); i++) {
		if (!n[i]) {
			pr_err("scaler-overlay: sentinel %#x unused; stale dtbo\n",
			       sov_refs[i].sentinel);
			ret = -EINVAL;
			goto fail;
		}
		pr_info("scaler-overlay: %s -> phandle %#x (x%u)\n",
			sov_refs[i].label ?: "aic", be32_to_cpu(live[i]), n[i]);
	}
	return copy;
fail:
	kfree(copy);
	return ERR_PTR(ret);
}

static int __init sov_init(void)
{
	struct device_node *np;
	void *fixed;
	int ret;

	if (!of_machine_is_compatible("apple,t6020")) {
		pr_err("scaler-overlay: not an apple,t6020 machine; refusing\n");
		return -ENODEV;
	}
	np = of_find_compatible_node(NULL, NULL, "apple,t6020-scaler");
	if (np) {
		pr_err("scaler-overlay: %pOF already exists (patched DT or second load); refusing\n",
		       np);
		of_node_put(np);
		return -EEXIST;
	}

	fixed = sov_fixup(scaler_overlay_t6020_dtbo, scaler_overlay_t6020_dtbo_len);
	if (IS_ERR(fixed))
		return PTR_ERR(fixed);
	ret = of_overlay_fdt_apply(fixed, scaler_overlay_t6020_dtbo_len, &ovcs_id, NULL);
	kfree(fixed);
	if (ret) {
		pr_err("scaler-overlay: apply failed: %d\n", ret);
		return ret;
	}
	pr_info("scaler-overlay: applied, ovcs_id=%d\n", ovcs_id);
	return 0;
}
module_init(sov_init);

MODULE_DESCRIPTION("Runtime device-tree overlay for the t6020 M2Scaler");
MODULE_LICENSE("GPL");

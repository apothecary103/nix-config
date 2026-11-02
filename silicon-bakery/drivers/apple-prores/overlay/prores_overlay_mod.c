// SPDX-License-Identifier: GPL-2.0-only
/*
 * Bring-up aid: applies prores-overlay-t6020.dtbo (the t6020 ProRes engine
 * and its DART) to the live device tree, for kernels whose DT does not carry
 * patches/linux-prores. A port of aquarat's test/ave_overlay_mod.c
 * (apple-m-series-ave-driver, GPL-2.0-only, commit 9ab14e45), cut down to
 * one SoC and two sentinels.
 *
 * Applying it creates a DART that apple-dart binds and programs, in the
 * ps_scodec power domain. Read docs/prores-port.txt before loading it.
 *
 * There is deliberately no module_exit: removing the overlay unbinds the
 * DART, and apple_dart_remove() writes DART registers after its power
 * domain may already be off, which hangs the fabric (the AVE driver's first
 * DART attempt died exactly there). Apply once per boot; iterate with
 * rmmod/insmod of apple_prores only.
 */
#include <linux/module.h>
#include <linux/of.h>
#include <linux/slab.h>
#include "prores_overlay_dtbo.h"

static int ovcs_id;

#define PR_OV_SENTINEL(nn)	(0xa7e00000u | (nn))
#define PR_OV_SENTINEL_MASK	0xffffff00u

static const struct {
	u32		sentinel;
	const char	*label;		/* a power domain's label, or NULL: the AIC */
} pr_ov_refs[] = {
	{ PR_OV_SENTINEL(0x13), NULL },
	{ PR_OV_SENTINEL(0x34), "scodec" },	/* pmgr device 0x34 SCODEC [ADT] */
};

static int pr_ov_find_pd(const char *label, u32 *phandle)
{
	struct device_node *np, *hit = NULL;
	const char *l;

	for_each_node_with_property(np, "#power-domain-cells") {
		if (of_property_read_string(np, "label", &l) || strcmp(l, label))
			continue;
		if (hit) {
			pr_err("prores-overlay: two power domains labelled %s: %pOF, %pOF\n",
			       label, hit, np);
			of_node_put(np);
			of_node_put(hit);
			return -EEXIST;
		}
		hit = of_node_get(np);
	}
	if (!hit || !hit->phandle) {
		pr_err("prores-overlay: no power domain labelled %s with a phandle\n", label);
		of_node_put(hit);
		return -ENODEV;
	}
	/* ps_scodec must be a pmgr pwrstate that can also reset. */
	if (!of_property_present(hit, "#reset-cells")) {
		pr_err("prores-overlay: %pOF has no #reset-cells\n", hit);
		of_node_put(hit);
		return -ENODEV;
	}
	*phandle = hit->phandle;
	of_node_put(hit);
	return 0;
}

static int pr_ov_find_aic(u32 *phandle)
{
	struct device_node *np = of_find_compatible_node(NULL, NULL, "apple,aic2");
	int ret = 0;

	if (!np || !of_property_read_bool(np, "interrupt-controller") || !np->phandle) {
		pr_err("prores-overlay: no apple,aic2 interrupt controller with a phandle\n");
		ret = -ENODEV;
	} else {
		*phandle = np->phandle;
	}
	of_node_put(np);
	return ret;
}

/* A fixed-up copy of the dtbo (kfree it), or an ERR_PTR. */
static void *pr_ov_fixup(const void *fdt, unsigned int len)
{
	unsigned int n[ARRAY_SIZE(pr_ov_refs)] = {};
	__be32 live[ARRAY_SIZE(pr_ov_refs)];
	bool known[ARRAY_SIZE(pr_ov_refs)] = {};
	unsigned int off;
	u8 *copy;
	int i, ret;

	copy = kmemdup(fdt, len, GFP_KERNEL);
	if (!copy)
		return ERR_PTR(-ENOMEM);
	for (off = 0; off + 4 <= len; off += 4) {
		u32 v = be32_to_cpup((const __be32 *)(copy + off));

		if ((v & PR_OV_SENTINEL_MASK) != PR_OV_SENTINEL(0))
			continue;
		for (i = 0; i < ARRAY_SIZE(pr_ov_refs); i++)
			if (v == pr_ov_refs[i].sentinel)
				break;
		if (i == ARRAY_SIZE(pr_ov_refs)) {
			pr_err("prores-overlay: unknown sentinel %#x at dtbo offset %#x\n", v, off);
			ret = -EINVAL;
			goto fail;
		}
		if (!known[i]) {
			u32 ph;

			ret = pr_ov_refs[i].label ? pr_ov_find_pd(pr_ov_refs[i].label, &ph) :
						     pr_ov_find_aic(&ph);
			if (ret)
				goto fail;
			live[i] = cpu_to_be32(ph);
			known[i] = true;
		}
		memcpy(copy + off, &live[i], 4);
		n[i]++;
	}
	/* AIC: dart + engine; scodec: two power-domains + resets */
	if (n[0] != 2 || n[1] != 3) {
		pr_err("prores-overlay: dtbo has %u/%u sentinels, expected 2/3\n", n[0], n[1]);
		ret = -EINVAL;
		goto fail;
	}
	for (i = 0; i < ARRAY_SIZE(pr_ov_refs); i++)
		pr_info("prores-overlay: %s -> phandle %#x (x%u)\n",
			pr_ov_refs[i].label ?: "aic", be32_to_cpu(live[i]), n[i]);
	return copy;
fail:
	kfree(copy);
	return ERR_PTR(ret);
}

static int __init pr_ov_init(void)
{
	struct device_node *np;
	void *fixed;
	int ret;

	if (!of_machine_is_compatible("apple,t6020")) {
		pr_err("prores-overlay: not a t6020 (M2 Pro); refusing\n");
		return -ENODEV;
	}
	np = of_find_compatible_node(NULL, NULL, "apple,t6020-prores");
	if (np) {
		pr_err("prores-overlay: %pOF already exists (DT patch applied?); refusing\n", np);
		of_node_put(np);
		return -EEXIST;
	}
	fixed = pr_ov_fixup(prores_overlay_dtbo, prores_overlay_dtbo_len);
	if (IS_ERR(fixed))
		return PTR_ERR(fixed);
	ret = of_overlay_fdt_apply(fixed, prores_overlay_dtbo_len, &ovcs_id, NULL);
	kfree(fixed);
	if (ret) {
		pr_err("prores-overlay: apply failed: %d\n", ret);
		return ret;
	}
	pr_info("prores-overlay: applied, ovcs_id=%d\n", ovcs_id);
	return 0;
}
module_init(pr_ov_init);

MODULE_DESCRIPTION("Apply the t6020 ProRes device-tree overlay");
MODULE_LICENSE("GPL");

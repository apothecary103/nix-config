// SPDX-License-Identifier: GPL-2.0-only
/*
 * Apple M2Scaler (t6020, hw-version 14): register programming of one pass.
 * Plain MMIO in the order macOS queues the same registers into APIODMA
 * [KEXT13.5 MsrAPIODMA::write callers]; m1n1's M1 Max experiment shows plain
 * MMIO works [M1N1]. APIODMA (the register-sequence DMA) is not used.
 */
#include <linux/delay.h>
#include <linux/dma-mapping.h>
#include <linux/iopoll.h>
#include <linux/kernel.h>
#include <linux/slab.h>

#include "apple_scaler.h"

/*
 * DPE (power estimator) start values, 14 entries (hw14 = DPE MSR14 -> MSR11
 * layout: enables at 0x404+4i, value pairs at 0x43c+8i). [KEXT13.5
 * IosaDPEControlMSR11::startDPE, table at fffffe00073f8b08]. Whether the
 * scaler needs the DPE running is not known; dpe=0 skips it.
 */
static const u16 as_dpe_vals[AS_DPE_ENTRIES] = {
	0x10, 0x06, 0x00, 0x05, 0x15, 0x18, 0x13,
	0x09, 0x33, 0x15, 0x0e, 0x27, 0x15, 0x00,
};

void as_hw_dpe_start(struct as_dev *d)
{
	int i;

	if (!d->dpe || !as_param_dpe)
		return;
	writel_relaxed(1, d->dpe + AS_DPE_EN0);
	for (i = 0; i < AS_DPE_ENTRIES; i++) {
		writel_relaxed(1, d->dpe + AS_DPE_EN(i));
		writel_relaxed(as_dpe_vals[i] & 0x1ff, d->dpe + AS_DPE_VAL(i));
		writel_relaxed(as_dpe_vals[i] & 0x1ff, d->dpe + AS_DPE_VAL(i) + 4);
	}
	writel_relaxed(0x1000, d->dpe + AS_DPE_CFG);
	writel(0x101, d->dpe + AS_DPE_CTRL);
}

void as_hw_dpe_stop(struct as_dev *d)
{
	u32 v;

	if (!d->dpe || !as_param_dpe)
		return;
	/* [KEXT13.5 IosaDPEControlMSR11 stop] */
	writel(0x101, d->dpe + AS_DPE_CTRL);
	writel(2, d->dpe + AS_DPE_STATE);
	if (readl_poll_timeout_atomic(d->dpe + AS_DPE_STATE, v,
				      (v & 0xc) == 4, 1, 1000))
		dev_warn(d->dev, "DPE stop: state %#x\n", v);
	writel(0x100, d->dpe + AS_DPE_CTRL);
	writel(readl(d->dpe + AS_DPE_STATE) & ~BIT(1), d->dpe + AS_DPE_STATE);
}

/* [KEXT13.5 AppleM2ScalerCSCHalMSR8::resetScaler, APIODMA not in use] */
void as_hw_soft_reset(struct as_dev *d)
{
	writel(1, d->base + AS_RESET);
	udelay(10);
	writel(0, d->base + AS_RESET);
	writel(0, d->base + AS_RESET_APIODMA);
	d->fkey[0].valid = d->fkey[1].valid = 0;
}

int as_hw_init(struct as_dev *d)
{
	as_hw_soft_reset(d);
	/* everything off that a plain conversion does not use */
	as_wr(d, AS_ASE_ENHANCE, 0);
	as_wr(d, AS_ASE_3X1, 0);
	as_wr(d, AS_ASE_CFG, 0);
	as_wr(d, AS_CM_CTRL, 0);
	as_wr(d, AS_HISTOGRAM_CTRL, 0);
	as_wr(d, AS_HISTOGRAM_EN, 0);
	as_wr(d, AS_SPILL_LO, 0);
	as_wr(d, AS_SPILL_HI, 0);
	as_wr(d, AS_SPILL_SIZE, 0);
	writel(0xffffffff, d->base + AS_IRQ_STATUS);
	writel(AS_IRQ_ENABLE_VAL, d->base + AS_IRQ_ENABLE);
	as_hw_dpe_start(d);
	return 0;
}

/* ---------------------------------------------------------------- scaling */

#define U422_ONE	(1u << 22)

static u32 as_ratio(u32 num, u32 den)
{
	u64 r = div_u64((u64)num << 22, den);

	return min_t(u64, r, 0x3ffffff) & 0x3fffffc;
}

static u32 as_dda(u32 ratio)
{
	s64 v = 0;

	/* centre alignment: first output centre at (ratio - 1)/2 [INF] */
	if (as_param_dda_center)
		v = ((s64)ratio - U422_ONE) / 2;
	v = clamp_t(s64, v, -(s64)U422_ONE, U422_ONE - 1);	/* S1.22 */
	return (u32)v & 0x7fffff;
}

static void as_program_filters(struct as_dev *d, int dir, u32 rl, u32 rc)
{
	unsigned int taps = dir ? AS_H_TAPS : AS_V_TAPS;
	unsigned int used = dir ? clamp(as_param_h_taps, 3u, (unsigned int)AS_H_TAPS) :
				  AS_V_TAPS;
	u32 b0 = dir ? AS_SCL_H_COEF0 : AS_SCL_V_COEF0;
	u32 b1 = dir ? AS_SCL_H_COEF1 : AS_SCL_V_COEF1;
	struct as_filter_key *key = &d->fkey[dir];
	s16 *fl, *fc;
	unsigned int t, p;

	if (key->valid && key->ratio_luma == rl && key->ratio_chroma == rc &&
	    key->taps == used)
		return;

	fl = kcalloc(2 * AS_H_TAPS * AS_PHASES, sizeof(*fl), GFP_ATOMIC);
	if (!fl)
		return;		/* keeps the old filter; still a valid filter */
	fc = fl + AS_H_TAPS * AS_PHASES;
	as_make_filter(fl, taps, used, rl, as_param_kernel, as_param_phase_neg);
	as_make_filter(fc, taps, used, rc, as_param_kernel, as_param_phase_neg);

	for (t = 0; t < taps; t++) {
		for (p = 0; p < AS_PHASES; p++) {
			u32 i = t * AS_PHASES + p;

			as_wr(d, b0 + 4 * i, (u16)fl[i] | ((u32)(u16)fc[i] << 16));
		}
		for (p = 0; p < AS_PHASES; p += 2) {
			u32 i = t * AS_PHASES + p;

			as_wr(d, b1 + 4 * (t * AS_PHASES / 2 + p / 2),
			      (u16)fl[i] | ((u32)(u16)fl[i + 1] << 16));
		}
	}
	kfree(fl);
	key->ratio_luma = rl;
	key->ratio_chroma = rc;
	key->taps = used;
	key->valid = 1;
}

/*
 * dir 0 = V (0x1000), 1 = H (0x2000). Lengths are in source orientation:
 * with 90/270 rotation the scaler pairs the source width with the
 * destination height [KEXT13.5 resolveVHForRotation].
 */
static void as_program_scale(struct as_dev *d, int dir, u32 src, u32 dst,
			     u32 csrc, bool ycbcr)
{
	u32 base = dir ? AS_SCL_H : AS_SCL_V;
	u32 rl = as_ratio(src, dst), rc = as_ratio(csrc, dst);
	u32 il = as_ratio(dst, src), ic = as_ratio(dst, csrc);
	u32 flags = 0;

	if (rl != U422_ONE || rc != U422_ONE || as_param_dda_center)
		flags |= BIT(0);
	if (ycbcr)
		flags |= BIT(1);

	as_wr(d, base + AS_SCL_DDA_LUMA, as_dda(rl));
	as_wr(d, base + AS_SCL_DDA_CHROMA, as_dda(rc) & 0x7ffffc);
	as_wr(d, base + AS_SCL_DDA_ALPHA, as_dda(rl));
	as_wr(d, base + AS_SCL_RATIO_LUMA, rl);
	as_wr(d, base + AS_SCL_RATIO_CHROMA, rc);
	as_wr(d, base + AS_SCL_INV_LUMA, il);
	as_wr(d, base + AS_SCL_INV_CHROMA, ic);
	as_wr(d, base + AS_SCL_RATIO_ALPHA, rl);
	/* macOS: V writes 1/luma, H 1/chroma here [KEXT13.5, KEXT27] */
	as_wr(d, base + AS_SCL_INV_ALPHA, dir ? ic : il);
	if (flags & BIT(0))
		as_program_filters(d, dir, rl, rc);
	as_wr(d, base + AS_SCL_FLAGS, flags);
}

/* ---------------------------------------------------------------- CSC */

static u32 s312(s32 q24)
{
	s32 v = clamp(DIV_ROUND_CLOSEST(q24, 1 << 12), -32768, 32767);

	return (u32)v & 0xffff;
}

static u32 s016(s32 q24)	/* prescaler offsets: S0.16 in 17 bits */
{
	s32 v = clamp(DIV_ROUND_CLOSEST(q24, 1 << 8), -65536, 65535);

	return (u32)v & 0x1ffff;
}

static u32 s224(s32 q24)	/* CM location-1 offsets: S2.24 in 26 bits */
{
	return (u32)q24 & 0x3ffffff;
}

static void as_program_csc(struct as_dev *d, const struct as_pass *p,
			   bool upsample)
{
	const struct as_csc *c = &p->csc;
	int i;

	as_wr(d, AS_LEGACY_CSC, 0);
	if (!c->enable) {
		as_wr(d, AS_PRE3X3_CTRL, 0xc);
		as_wr(d, AS_CM_CTRL, 0);
		return;
	}
	if (as_param_csc_loc == 0) {
		/* prescaler 3x3, before the scaler */
		for (i = 0; i < 3; i++) {
			as_wr(d, AS_PRE3X3_PRE(i), s016(c->pre[i]));
			as_wr(d, AS_PRE3X3_POST(i), s016(c->post[i]));
		}
		for (i = 0; i < 9; i++)
			as_wr(d, AS_PRE3X3_COEF(i), s312(c->coef[i]));
		as_wr(d, AS_PRE3X3_CTRL, BIT(31) | 12);
		as_wr(d, AS_CM_CTRL, 0);
	} else {
		/* colour manager src2Rgb 3x3 ("location 1"), after the scaler */
		as_wr(d, AS_PRE3X3_CTRL, 0xc);
		as_wr(d, AS_CM_L1_SHIFT, 12);
		for (i = 0; i < 3; i++) {
			as_wr(d, AS_CM_L1_PRE(i), s224(c->pre[i]));
			as_wr(d, AS_CM_L1_POST(i), s224(c->post[i]));
		}
		for (i = 0; i < 9; i++)
			as_wr(d, AS_CM_L1_COEF(i), s312(c->coef[i]));
		as_wr(d, AS_CM_CTRL, BIT(0) | BIT(1));
	}
}

/* ---------------------------------------------------------------- pass */

static void as_wr64(struct as_dev *d, u32 lo, u32 hi, dma_addr_t a)
{
	as_wr(d, lo, lower_32_bits(a));
	as_wr(d, hi, upper_32_bits(a));
}

int as_hw_program_pass(struct as_dev *d, const struct as_pass *p)
{
	const struct as_surface *s = &p->src, *t = &p->dst;
	const struct as_fmt *sf = s->fmt, *df = t->fmt;
	bool syuv = sf->class != AS_RGB;
	bool rot90 = p->rot & 1;
	bool same_sub = sf->hsub == df->hsub && sf->vsub == df->vsub &&
			df->class == AS_YUV;
	bool upsample = p->csc.enable && as_param_csc_loc == 0 &&
			sf->class == AS_YUV && (sf->hsub > 1 || sf->vsub > 1);
	/* 4:4:4 inside the pipe (Apple: subsampling differs or CM active) */
	bool full444 = !same_sub || (p->csc.enable && as_param_csc_loc == 1);
	u32 dw = rot90 ? t->h : t->w, dh = rot90 ? t->w : t->h;
	u32 chs, cvs, v;
	int i;

	/* colour manager reset first, as m1n1/macOS do */
	as_wr(d, AS_CM_CTRL, 0);

	/* RDMA / WDMA formats (linear: mode 0, no footprint/ctype) */
	as_wr(d, AS_RDMA_CFG, sf->cfg);
	as_wr(d, AS_RDMA_FMT(0), sf->code[0]);
	as_wr(d, AS_RDMA_FMT(1), sf->planes > 1 ? sf->code[1] : 0);
	as_wr(d, AS_RDMA_FMT(2), 0);
	as_wr(d, AS_RDMA_FMT(3), 0);
	as_wr(d, AS_WDMA_CFG, df->cfg);
	as_wr(d, AS_WDMA_FMT(0), AS_WDMA_FMT_MARK | df->code[0]);
	as_wr(d, AS_WDMA_FMT(1), AS_WDMA_FMT_MARK |
	      (df->planes > 1 ? df->code[1] : 0));
	as_wr(d, AS_WDMA_FMT(2), AS_WDMA_FMT_MARK);

	/* flip / rotate; flip bit names from m1n1 [M1N1][INF] */
	as_wr(d, AS_FLIP_ROTATE, (p->rot & 3) | (p->vflip ? BIT(2) : 0) |
	      (p->hflip ? BIT(3) : 0));

	/* cache hints and DMA tunables (hw14) [KEXT13.5 MSR10j/MSR14] */
	for (i = 0; i < 4; i++) {
		as_wr(d, AS_SRC_CACHE0(i), 0x7d311);
		as_wr(d, AS_SRC_CACHE1(i), 0x707);
		as_wr(d, AS_SRC_TUNABLE(i), 0x20);
	}
	for (i = 0; i < 3; i++) {
		as_wr(d, AS_DST_CACHE0(i), 0xbd311);
		as_wr(d, AS_DST_CACHE1(i), 0xc0bd307);
		as_wr(d, AS_DST_TUNABLE(i), 0x04000620);
	}

	/* surfaces; the rect origin is already in the base address */
	for (i = 0; i < 3; i++) {
		dma_addr_t sa = i < sf->planes ? s->addr[i] : 0;
		dma_addr_t da = i < df->planes ? t->addr[i] : 0;

		as_wr64(d, AS_SRC_BASE_LO(i), AS_SRC_BASE_HI(i), sa);
		as_wr64(d, AS_DST_BASE_LO(i), AS_DST_BASE_HI(i), da);
		as_wr(d, AS_SRC_STRIDE(i), i < sf->planes ? s->stride[i] & 0xffffff : 0);
		as_wr(d, AS_DST_STRIDE(i), i < df->planes ? t->stride[i] & 0xffffff : 0);
		as_wr(d, AS_SRC_OFFSET(i), 0);
		as_wr(d, AS_DST_OFFSET(i), 0);
	}
	as_wr(d, AS_SRC_W, s->w & 0x1ffff);
	as_wr(d, AS_SRC_H, s->h & 0x1ffff);
	as_wr(d, AS_DST_W, t->w & 0x1ffff);
	as_wr(d, AS_DST_H, t->h & 0x1ffff);
	/* per-plane sizes after the tunables: 0x308 is also dst tunable #4 */
	for (i = 0; i < 3; i++) {
		u32 hs = i ? sf->hsub : 1, vs = i ? sf->vsub : 1;
		u32 hd = i ? df->hsub : 1, vd = i ? df->vsub : 1;
		bool sp = i < sf->planes, dp = i < df->planes;

		as_wr(d, AS_SRC_PLANE_W(i), sp ? (s->plane_w / hs) & 0x1ffff : 0);
		as_wr(d, AS_SRC_PLANE_H(i), sp ? (s->plane_h / vs) & 0x1ffff : 0);
		as_wr(d, AS_DST_PLANE_W(i), dp ? (t->plane_w / hd) & 0x1ffff : 0);
		as_wr(d, AS_DST_PLANE_H(i), dp ? (t->plane_h / vd) & 0x1ffff : 0);
	}

	as_wr(d, AS_SRC_SWIZZLE, sf->swizzle);
	as_wr(d, AS_DST_SWIZZLE, df->swizzle);

	as_wr(d, AS_PIXEL_AVERAGING, 0);
	as_wr(d, AS_ASE_ENHANCE, 0);
	as_wr(d, AS_ASE_3X1, 0);
	as_wr(d, AS_ASE_CFG, 0);

	/* chroma upsampler: two 2-tap 0.5/0.5 sets when on [KEXT13.5] */
	if (upsample) {
		static const u32 up[8] = { 0, 0x800, 0x800, 0, 0, 0x800, 0x800, 0 };

		for (i = 0; i < 8; i++)
			as_wr(d, AS_CHROMA_UP_COEF(i), up[i]);
		as_wr(d, AS_CHROMA_UPSAMPLE, 0xd);
	} else {
		as_wr(d, AS_CHROMA_UPSAMPLE, 0xc);
	}

	/* chroma downsampler: methods H1 V1 (cosite option 0) + enables */
	v = 0x10100;
	if (df->class == AS_YUV && full444) {
		if (df->hsub > 1)
			v |= BIT(0);
		if (df->vsub > 1)
			v |= BIT(1);
	}
	as_wr(d, AS_CHROMA_DOWNSAMPLE, v);

	/* polyphase: chroma length in luma units of the source */
	if (sf->class != AS_YUV || upsample) {
		chs = s->w;
		cvs = s->h;
	} else if (full444) {
		chs = s->w / sf->hsub;
		cvs = s->h / sf->vsub;
	} else {
		chs = s->w;	/* chroma planes scaled at their own size */
		cvs = s->h;
	}
	as_program_scale(d, 0, s->h, dh, cvs, syuv && !upsample);
	as_program_scale(d, 1, s->w, dw, chs, syuv && !upsample);

	as_wr(d, AS_PSEUDO_LINEAR, 0);
	as_wr(d, AS_RESHAPE_CTRL, 0);

	as_program_csc(d, p, upsample);

	as_wr(d, AS_ALPHA_OVERRIDE, 0xffff |
	      (!sf->alpha && df->alpha ? BIT(31) : 0));

	v = 0;
	if (as_param_dither && df->bits < sf->bits) {
		u32 f = min(7u, 16u - df->bits);

		v = f << 8 | f << 16 | f << 24;
	}
	as_wr(d, AS_DITHER, v);

	/* internal pipe convert / revert [KEXT13.5 IosaInternalPipeMSR10] */
	as_wr(d, AS_CONVERT_FP16_0, 0);
	as_wr(d, AS_CONVERT_FP16_1, 0);
	as_wr(d, AS_CONVERT_CTRL, 0);
	as_wr(d, AS_CONVERT_RANGE, 0);
	for (i = 0; i < 4; i++)
		as_wr(d, AS_CONVERT_MAP(i), sf->map[i]);
	as_wr(d, AS_REVERT_RANGE, 0);
	for (i = 0; i < 4; i++)
		as_wr(d, AS_REVERT_MAP(i), df->map[i]);
	as_wr(d, AS_REVERT_CTRL, 1);

	as_wr(d, AS_HISTOGRAM_CTRL, 0);
	as_wr(d, AS_HISTOGRAM_EN, 0);
	as_wr(d, AS_TRANSFORM_ID, ++d->transform_id);
	return 0;
}

void as_hw_start(struct as_dev *d)
{
	/* [KEXT13.5 AppleM2ScalerCSCHalMSR8::configureStart] */
	writel(0xfffffffe, d->base + AS_KICK_MASK);
	writel(1, d->base + AS_START);
}

/* ---------------------------------------------------------------- self-test */

/*
 * A 64x64 BGRA copy, polled (the IRQ is not requested yet). Proves DMA in
 * both directions through the DART and the done bit. Pattern: x, y, x^y, 0xff.
 */
int as_hw_selftest(struct as_dev *d)
{
	const unsigned int W = 64, H = 64, sz = W * H * 4;
	struct as_pass p = { };
	dma_addr_t sd, dd;
	u32 *sv, *dv, st;
	unsigned int i, bad = 0;
	int ret = 0;

	sv = dma_alloc_coherent(d->dev, sz, &sd, GFP_KERNEL);
	dv = dma_alloc_coherent(d->dev, sz, &dd, GFP_KERNEL);
	if (!sv || !dv) {
		ret = -ENOMEM;
		goto out;
	}
	for (i = 0; i < W * H; i++)
		sv[i] = 0xff000000 | ((i % W) << 16) | ((i / W) << 8) | ((i % W) ^ (i / W));
	memset(dv, 0xaa, sz);

	p.src.fmt = p.dst.fmt = as_find_fmt(V4L2_PIX_FMT_ABGR32);
	p.src.addr[0] = sd;
	p.dst.addr[0] = dd;
	p.src.stride[0] = p.dst.stride[0] = W * 4;
	p.src.w = p.dst.w = p.src.plane_w = p.dst.plane_w = W;
	p.src.h = p.dst.h = p.src.plane_h = p.dst.plane_h = H;

	writel(0xffffffff, d->base + AS_IRQ_STATUS);
	as_hw_program_pass(d, &p);
	wmb();
	as_hw_start(d);
	ret = readl_poll_timeout(d->base + AS_IRQ_STATUS, st,
				 st & (AS_IRQ_DONE | AS_IRQ_ERRORS), 20, 200000);
	writel(st, d->base + AS_IRQ_STATUS);
	dev_info(d->dev, "selftest: irq status %#x dbg %#x frames %u\n", st,
		 as_rd(d, AS_DBG_STATUS), as_rd(d, AS_FRAME_COUNT));
	if (ret) {
		dev_err(d->dev, "selftest: no completion in 200 ms (running=%#x)\n",
			as_rd(d, AS_IS_RUNNING));
		goto out;
	}
	if (st & AS_IRQ_ERRORS) {
		ret = -EIO;
		goto out;
	}
	for (i = 0; i < W * H; i++)
		if (dv[i] != sv[i] && bad++ < 4)
			dev_err(d->dev, "selftest: px %u: got %08x want %08x\n",
				i, dv[i], sv[i]);
	if (bad) {
		dev_err(d->dev, "selftest: %u of %u pixels differ\n", bad, W * H);
		ret = -EIO;
	} else {
		dev_info(d->dev, "selftest: 64x64 BGRA copy OK\n");
	}
out:
	if (sv)
		dma_free_coherent(d->dev, sz, sv, sd);
	if (dv)
		dma_free_coherent(d->dev, sz, dv, dd);
	as_hw_soft_reset(d);
	as_hw_init(d);
	return ret;
}

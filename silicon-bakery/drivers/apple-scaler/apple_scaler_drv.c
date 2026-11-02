// SPDX-License-Identifier: GPL-2.0-only
/*
 * Apple M2Scaler V4L2 mem2mem converter (t6020 "scaler0", hw-version 14).
 * Silicon Bakery, 2026-11-02. Modelled on rockchip-rga and imx-pxp.
 *
 * STATUS: written on the Mac14,9 under macOS from the 13.5/27.2 kext and
 * m1n1's M1 Max map; never compiled for or run on Linux. Read
 * docs/scaler-port.txt before loading it. Bring-up is staged (stop_after=).
 *
 * One /dev/videoN, single-planar API (both planes of NV12 etc. in one buffer),
 * OUTPUT = source, CAPTURE = destination. Crop on OUTPUT and compose on
 * CAPTURE via the selection API, V4L2_CID_ROTATE/HFLIP/VFLIP, colorimetry
 * (ycbcr_enc + quantization) converted by a 3x3 computed here; the
 * colour gamut and transfer function are passed through unchanged.
 */
#include <linux/delay.h>
#include <linux/dma-mapping.h>
#include <linux/interrupt.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/platform_device.h>
#include <linux/pm_domain.h>
#include <linux/pm_runtime.h>
#include <linux/reset.h>
#include <linux/slab.h>

#include <media/v4l2-event.h>
#include <media/v4l2-ioctl.h>
#include <media/videobuf2-dma-contig.h>

#include "apple_scaler.h"

/* ---------------------------------------------------------------- params */

static unsigned int stop_after;
module_param(stop_after, uint, 0444);
MODULE_PARM_DESC(stop_after, "probe stops after stage N (1 resources, 2 power on, 3 read version, 4 reset+init, 5 selftest, 6 irq, 7 v4l2); 0 = all");

static unsigned int step_ms;
module_param(step_ms, uint, 0644);
MODULE_PARM_DESC(step_ms, "sleep this many ms after each probe stage marker (lets the journal flush)");

static bool selftest = true;
module_param(selftest, bool, 0444);
MODULE_PARM_DESC(selftest, "run a polled 64x64 BGRA copy at probe stage 5");

static bool force_version;
module_param(force_version, bool, 0444);
MODULE_PARM_DESC(force_version, "continue although the version register is not 0x030c0013");

static bool version_poke = true;
module_param(version_poke, bool, 0444);
MODULE_PARM_DESC(version_poke, "if the first read of reg 0x0 is wrong, write 1 then 0 to it and read again, as macOS does");

static unsigned int timeout_ms = 1000;
module_param(timeout_ms, uint, 0644);
MODULE_PARM_DESC(timeout_ms, "per-pass watchdog");

static unsigned int hang_recovery = 1;
module_param(hang_recovery, uint, 0644);
MODULE_PARM_DESC(hang_recovery, "after a timeout: 0 nothing, 1 soft reset (reg 0x4), 2 + power cycle through runtime PM, 3 + pmgr reset of ps_msr0");

static unsigned int max_passes = AS_MAX_PASSES;
module_param(max_passes, uint, 0644);
MODULE_PARM_DESC(max_passes, "1..3 passes for ratios beyond one pass (8x up, 8x H / 4x V down)");

static unsigned int stride_align = 64;
module_param(stride_align, uint, 0644);
MODULE_PARM_DESC(stride_align, "bytesperline alignment the driver proposes (power of two, >= 4)");

unsigned int as_param_kernel;
module_param_named(kernel, as_param_kernel, uint, 0644);
MODULE_PARM_DESC(kernel, "scaling filter: 0 Lanczos-3, 1 bicubic (Catmull-Rom), 2 bilinear");

bool as_param_phase_neg;
module_param_named(phase_neg, as_param_phase_neg, bool, 0644);
MODULE_PARM_DESC(phase_neg, "mirror the filter phase direction (if output is shifted half a pixel per phase step)");

bool as_param_dda_center;
module_param_named(dda_center, as_param_dda_center, bool, 0644);
MODULE_PARM_DESC(dda_center, "add (ratio-1)/2 to the DDA start (pixel-centre alignment; macOS does not)");

unsigned int as_param_h_taps = 9;
module_param_named(h_taps, as_param_h_taps, uint, 0644);
MODULE_PARM_DESC(h_taps, "horizontal taps used, odd, 3..15 (macOS never uses more than 9)");

unsigned int as_param_csc_loc = 1;
module_param_named(csc_loc, as_param_csc_loc, uint, 0644);
MODULE_PARM_DESC(csc_loc, "3x3 used for colour conversion: 1 colour-manager src2Rgb after the scaler (macOS default), 0 prescaler before it");

bool as_param_dpe = true;
module_param_named(dpe, as_param_dpe, bool, 0444);
MODULE_PARM_DESC(dpe, "start the power estimator (DPE) like macOS");

bool as_param_dither = true;
module_param_named(dither, as_param_dither, bool, 0644);
MODULE_PARM_DESC(dither, "dither when the output has fewer bits than the input");

unsigned int as_param_uyvy_swizzle = 0x02010300;
module_param_named(uyvy_swizzle, as_param_uyvy_swizzle, uint, 0644);
MODULE_PARM_DESC(uyvy_swizzle, "swizzle word for UYVY (macOS has no UYVY; 0x02010300 or 0x00030102 are the candidates)");

static void as_stage(struct as_dev *d, unsigned int n, const char *what)
{
	d->stage = n;
	dev_info(d->dev, "stage %u: %s\n", n, what);
	if (step_ms)
		msleep(step_ms);
}

/* ---------------------------------------------------------------- formats */

#define M8	{ 8, 8, 8, 8 }
#define M10	{ 10, 10, 10, 10 }

/*
 * Codes [KEXT13.5 IosaRdmaControlMSR10::programDMA, MSR11 programFormat];
 * swizzles [KEXT13.5 _swzCrossbarElements]; native 32bpp order is B,G,R,A in
 * memory. Convert/revert maps are per-channel depth codes [KEXT13.5,
 * values for 565/2101010 INF].
 */
static const struct as_fmt as_formats[] = {
	/* 'XR24' = DRM XRGB8888 (B,G,R,X in memory) */
	{ V4L2_PIX_FMT_XBGR32, AS_RGB, 1, { 4 }, 1, 1, 8, 0, 0, { 0x1e }, 0x1, 0x03020100, M8 },
	/* 'AR24' = DRM ARGB8888 */
	{ V4L2_PIX_FMT_ABGR32, AS_RGB, 1, { 4 }, 1, 1, 8, 1, 0, { 0x1e }, 0x1, 0x03020100, M8 },
	/* 'XB24' = DRM XBGR8888 (R,G,B,X) */
	{ V4L2_PIX_FMT_RGBX32, AS_RGB, 1, { 4 }, 1, 1, 8, 0, 0, { 0x1e }, 0x1, 0x03000102, M8 },
	/* 'AB24' = DRM ABGR8888 (R,G,B,A) */
	{ V4L2_PIX_FMT_RGBA32, AS_RGB, 1, { 4 }, 1, 1, 8, 1, 0, { 0x1e }, 0x1, 0x03000102, M8 },
	/* 'RGBP' = DRM RGB565 ('L565') */
	{ V4L2_PIX_FMT_RGB565, AS_RGB, 1, { 2 }, 1, 1, 5, 0, 0, { 0x08 }, 0x1, 0x03020100, { 5, 6, 5, 0 } },
	/* 'AR30' = DRM ARGB2101010 ('l10r') */
	{ V4L2_PIX_FMT_ARGB2101010, AS_RGB, 1, { 4 }, 1, 1, 10, 1, 0, { 0x19 }, 0x1, 0x03020100, { 10, 10, 10, 2 } },
	/* 'YUYV' ('yuvs') */
	{ V4L2_PIX_FMT_YUYV, AS_YUV, 1, { 2 }, 2, 1, 8, 0, 0, { 0x1e }, 0x4, 0x03000201, M8 },
	/* 'UYVY': swizzle from the module parameter [INF] */
	{ V4L2_PIX_FMT_UYVY, AS_YUV, 1, { 2 }, 2, 1, 8, 0, 0, { 0x1e }, 0x4, 0, M8 },
	/* 2-plane 8-bit ('420v', '422v', '444v') */
	{ V4L2_PIX_FMT_NV12, AS_YUV, 2, { 1, 2 }, 2, 2, 8, 0, 0, { 0x01, 0x06 }, 0xc, 0x03000102, M8 },
	{ V4L2_PIX_FMT_NV21, AS_YUV, 2, { 1, 2 }, 2, 2, 8, 0, 1, { 0x01, 0x06 }, 0xc, 0x03000102, M8 },
	{ V4L2_PIX_FMT_NV16, AS_YUV, 2, { 1, 2 }, 2, 1, 8, 0, 0, { 0x01, 0x06 }, 0x4, 0x03000102, M8 },
	{ V4L2_PIX_FMT_NV24, AS_YUV, 2, { 1, 2 }, 1, 1, 8, 0, 0, { 0x01, 0x06 }, 0x0, 0x03000102, M8 },
	/* 'P010' ('x420', 10 bits in the top of 16) */
	{ V4L2_PIX_FMT_P010, AS_YUV, 2, { 2, 4 }, 2, 2, 10, 0, 0, { 0x02, 0x12 }, 0xc, 0x03000102, M10 },
	/* 'GREY' ('L008') */
	{ V4L2_PIX_FMT_GREY, AS_LUMA, 1, { 1 }, 1, 1, 8, 0, 0, { 0x01 }, 0x0, 0x03000102, M8 },
};

static struct as_fmt as_uyvy_rt;	/* UYVY with the current swizzle */

const struct as_fmt *as_find_fmt(u32 fourcc)
{
	unsigned int i;

	for (i = 0; i < ARRAY_SIZE(as_formats); i++) {
		if (as_formats[i].fourcc != fourcc)
			continue;
		if (fourcc == V4L2_PIX_FMT_UYVY) {
			as_uyvy_rt = as_formats[i];
			as_uyvy_rt.swizzle = as_param_uyvy_swizzle;
			return &as_uyvy_rt;
		}
		return &as_formats[i];
	}
	return NULL;
}

static u32 as_cbpl(const struct as_fmt *f, u32 bpl)
{
	if (f->planes < 2)
		return 0;
	return f->hsub == 1 ? 2 * bpl : bpl;	/* NV24: Cb,Cr per pixel */
}

static u32 as_sizeimage(const struct as_fmt *f, u32 bpl, u32 h)
{
	return bpl * h + as_cbpl(f, bpl) * DIV_ROUND_UP(h, f->vsub);
}

/* ---------------------------------------------------------------- context */

#define AS_MIN_W	4
#define AS_MAX_W	16384

static inline struct as_ctx *file2ctx(struct file *file)
{
	return container_of(file_to_v4l2_fh(file), struct as_ctx, fh);
}

static struct as_q *as_get_q(struct as_ctx *ctx, enum v4l2_buf_type type)
{
	return &ctx->q[V4L2_TYPE_IS_OUTPUT(type) ? 0 : 1];
}

static int as_querycap(struct file *file, void *priv, struct v4l2_capability *cap)
{
	strscpy(cap->driver, AS_NAME, sizeof(cap->driver));
	strscpy(cap->card, "Apple M2Scaler", sizeof(cap->card));
	return 0;
}

static int as_enum_fmt(struct file *file, void *priv, struct v4l2_fmtdesc *f)
{
	if (f->index >= ARRAY_SIZE(as_formats))
		return -EINVAL;
	f->pixelformat = as_formats[f->index].fourcc;
	if (!V4L2_TYPE_IS_OUTPUT(f->type) && as_formats[f->index].class != AS_RGB)
		f->flags |= V4L2_FMT_FLAG_CSC_YCBCR_ENC | V4L2_FMT_FLAG_CSC_QUANTIZATION;
	return 0;
}

static int as_enum_framesizes(struct file *file, void *priv,
			      struct v4l2_frmsizeenum *fs)
{
	const struct as_fmt *f;

	if (fs->index)
		return -EINVAL;
	f = as_find_fmt(fs->pixel_format);
	if (!f)
		return -EINVAL;
	fs->type = V4L2_FRMSIZE_TYPE_STEPWISE;
	fs->stepwise.min_width = AS_MIN_W;
	fs->stepwise.max_width = AS_MAX_W;
	fs->stepwise.step_width = f->hsub;
	fs->stepwise.min_height = AS_MIN_W;
	fs->stepwise.max_height = AS_MAX_W;
	fs->stepwise.step_height = f->vsub;
	return 0;
}

static int as_g_fmt(struct file *file, void *priv, struct v4l2_format *f)
{
	struct as_ctx *ctx = file2ctx(file);
	struct as_q *q = as_get_q(ctx, f->type);
	struct v4l2_pix_format *pix = &f->fmt.pix;

	pix->width = q->width;
	pix->height = q->height;
	pix->pixelformat = q->fmt->fourcc;
	pix->field = V4L2_FIELD_NONE;
	pix->bytesperline = q->bpl;
	pix->sizeimage = q->sizeimage;
	pix->colorspace = q->colorspace;
	pix->ycbcr_enc = q->ycbcr_enc;
	pix->quantization = q->quant;
	pix->xfer_func = q->xfer;
	pix->flags = 0;
	return 0;
}

static void as_fill_colorimetry(struct v4l2_pix_format *pix, const struct as_fmt *f)
{
	bool rgb = f->class == AS_RGB;

	if (pix->colorspace == V4L2_COLORSPACE_DEFAULT)
		pix->colorspace = rgb ? V4L2_COLORSPACE_SRGB : V4L2_COLORSPACE_REC709;
	if (pix->xfer_func == V4L2_XFER_FUNC_DEFAULT)
		pix->xfer_func = V4L2_MAP_XFER_FUNC_DEFAULT(pix->colorspace);
	if (pix->ycbcr_enc == V4L2_YCBCR_ENC_DEFAULT)
		pix->ycbcr_enc = V4L2_MAP_YCBCR_ENC_DEFAULT(pix->colorspace);
	if (pix->quantization == V4L2_QUANTIZATION_DEFAULT)
		pix->quantization = V4L2_MAP_QUANTIZATION_DEFAULT(rgb, pix->colorspace,
								  pix->ycbcr_enc);
}

static int as_try_fmt(struct file *file, void *priv, struct v4l2_format *f)
{
	struct as_ctx *ctx = file2ctx(file);
	struct v4l2_pix_format *pix = &f->fmt.pix;
	const struct as_fmt *fmt = as_find_fmt(pix->pixelformat);
	u32 align = max_t(u32, roundup_pow_of_two(stride_align ?: 4), 4);
	u32 minbpl;

	if (!fmt) {
		fmt = &as_formats[0];
		pix->pixelformat = fmt->fourcc;
	}
	pix->field = V4L2_FIELD_NONE;
	pix->width = clamp_t(u32, ALIGN(pix->width, fmt->hsub), AS_MIN_W, AS_MAX_W);
	pix->height = clamp_t(u32, ALIGN(pix->height, fmt->vsub), AS_MIN_W, AS_MAX_W);
	minbpl = pix->width * fmt->cpp[0];
	if (pix->bytesperline < minbpl || pix->bytesperline > 4 * AS_MAX_W * 2)
		pix->bytesperline = ALIGN(minbpl, align);
	pix->bytesperline = ALIGN(pix->bytesperline, 4);
	pix->sizeimage = as_sizeimage(fmt, pix->bytesperline, pix->height);

	if (V4L2_TYPE_IS_OUTPUT(f->type)) {
		as_fill_colorimetry(pix, fmt);
		pix->flags = 0;
	} else {
		struct as_q *src = &ctx->q[0];
		bool set_csc = pix->flags & V4L2_PIX_FMT_FLAG_SET_CSC;
		enum v4l2_ycbcr_encoding enc = pix->ycbcr_enc;
		enum v4l2_quantization qu = pix->quantization;

		/* gamut and transfer function are not converted */
		pix->colorspace = src->colorspace;
		pix->xfer_func = src->xfer;
		pix->ycbcr_enc = V4L2_YCBCR_ENC_DEFAULT;
		pix->quantization = V4L2_QUANTIZATION_DEFAULT;
		if (set_csc && fmt->class != AS_RGB) {
			if (enc != V4L2_YCBCR_ENC_DEFAULT)
				pix->ycbcr_enc = enc;
			if (qu != V4L2_QUANTIZATION_DEFAULT)
				pix->quantization = qu;
		} else if (fmt->class != AS_RGB && src->fmt->class != AS_RGB) {
			pix->ycbcr_enc = src->ycbcr_enc;
			pix->quantization = src->quant;
		}
		as_fill_colorimetry(pix, fmt);
		if (!set_csc)
			pix->flags = 0;
	}
	return 0;
}

static int as_s_fmt(struct file *file, void *priv, struct v4l2_format *f)
{
	struct as_ctx *ctx = file2ctx(file);
	struct vb2_queue *vq = v4l2_m2m_get_vq(ctx->fh.m2m_ctx, f->type);
	struct v4l2_pix_format *pix = &f->fmt.pix;
	struct as_q *q = as_get_q(ctx, f->type);
	int ret;

	if (vb2_is_busy(vq))
		return -EBUSY;
	ret = as_try_fmt(file, priv, f);
	if (ret)
		return ret;
	q->fmt = as_find_fmt(pix->pixelformat);
	q->width = pix->width;
	q->height = pix->height;
	q->bpl = pix->bytesperline;
	q->sizeimage = pix->sizeimage;
	q->colorspace = pix->colorspace;
	q->ycbcr_enc = pix->ycbcr_enc;
	q->quant = pix->quantization;
	q->xfer = pix->xfer_func;
	q->rect = (struct v4l2_rect){ 0, 0, q->width, q->height };

	/* a new source re-derives the destination colorimetry */
	if (V4L2_TYPE_IS_OUTPUT(f->type)) {
		struct as_q *dq = &ctx->q[1];
		struct v4l2_format df = { .type = V4L2_BUF_TYPE_VIDEO_CAPTURE };

		as_g_fmt(file, priv, &df);
		if (!vb2_is_busy(v4l2_m2m_get_dst_vq(ctx->fh.m2m_ctx))) {
			as_try_fmt(file, priv, &df);
			dq->colorspace = df.fmt.pix.colorspace;
			dq->xfer = df.fmt.pix.xfer_func;
			dq->ycbcr_enc = df.fmt.pix.ycbcr_enc;
			dq->quant = df.fmt.pix.quantization;
		}
	}
	return 0;
}

/* ---------------------------------------------------------------- selection */

static int as_g_selection(struct file *file, void *priv, struct v4l2_selection *s)
{
	struct as_ctx *ctx = file2ctx(file);
	bool out = V4L2_TYPE_IS_OUTPUT(s->type);
	struct as_q *q = as_get_q(ctx, s->type);

	switch (s->target) {
	case V4L2_SEL_TGT_CROP:
	case V4L2_SEL_TGT_CROP_DEFAULT:
	case V4L2_SEL_TGT_CROP_BOUNDS:
		if (!out)
			return -EINVAL;
		break;
	case V4L2_SEL_TGT_COMPOSE:
	case V4L2_SEL_TGT_COMPOSE_DEFAULT:
	case V4L2_SEL_TGT_COMPOSE_BOUNDS:
		if (out)
			return -EINVAL;
		break;
	default:
		return -EINVAL;
	}
	if (s->target == V4L2_SEL_TGT_CROP || s->target == V4L2_SEL_TGT_COMPOSE)
		s->r = q->rect;
	else
		s->r = (struct v4l2_rect){ 0, 0, q->width, q->height };
	return 0;
}

static int as_s_selection(struct file *file, void *priv, struct v4l2_selection *s)
{
	struct as_ctx *ctx = file2ctx(file);
	bool out = V4L2_TYPE_IS_OUTPUT(s->type);
	struct as_q *q = as_get_q(ctx, s->type);
	const struct as_fmt *f = q->fmt;
	struct v4l2_rect r = s->r;

	if (out ? s->target != V4L2_SEL_TGT_CROP : s->target != V4L2_SEL_TGT_COMPOSE)
		return -EINVAL;
	if (vb2_is_streaming(v4l2_m2m_get_vq(ctx->fh.m2m_ctx, s->type)))
		return -EBUSY;

	r.left = clamp_t(s32, r.left, 0, q->width - AS_MIN_W);
	r.top = clamp_t(s32, r.top, 0, q->height - AS_MIN_W);
	r.left = round_down(r.left, f->hsub);
	r.top = round_down(r.top, f->vsub);
	r.width = clamp_t(u32, r.width, AS_MIN_W, q->width - r.left);
	r.height = clamp_t(u32, r.height, AS_MIN_W, q->height - r.top);
	r.width = round_down(r.width, f->hsub);
	r.height = round_down(r.height, f->vsub);
	q->rect = r;
	s->r = r;
	return 0;
}

/* ---------------------------------------------------------------- controls */

static int as_s_ctrl(struct v4l2_ctrl *ctrl)
{
	struct as_ctx *ctx = container_of(ctrl->handler, struct as_ctx, hdl);

	switch (ctrl->id) {
	case V4L2_CID_HFLIP:
		ctx->hflip = ctrl->val;
		break;
	case V4L2_CID_VFLIP:
		ctx->vflip = ctrl->val;
		break;
	case V4L2_CID_ROTATE:
		/* the pass plan depends on it */
		if (vb2_is_streaming(v4l2_m2m_get_src_vq(ctx->fh.m2m_ctx)) ||
		    vb2_is_streaming(v4l2_m2m_get_dst_vq(ctx->fh.m2m_ctx)))
			return -EBUSY;
		ctx->rotate = ctrl->val;
		break;
	default:
		return -EINVAL;
	}
	return 0;
}

static const struct v4l2_ctrl_ops as_ctrl_ops = {
	.s_ctrl = as_s_ctrl,
};

/* ---------------------------------------------------------------- planning */

/*
 * Sizes of one direction through n passes, src first, dst last; returns n
 * or 0 if max_passes cannot do it. Earlier passes keep the source format
 * (same subsampling, no CSC): up 8, down `gdown`. The last pass converts; if
 * the source chroma is upsampled inside it, its luma upscale is limited to
 * 8/sub [KEXT13.5 checkPolyphaseScalingLimits, per plane].
 */
static unsigned int as_plan_dir(u32 src, u32 dst, u32 gdown, u32 lup,
				u32 align, u32 *mid /* [AS_MAX_PASSES-1] */)
{
	u32 sizes[AS_MAX_PASSES + 1], cur = dst;
	unsigned int n = 1, i, maxp = clamp(max_passes, 1u, (u32)AS_MAX_PASSES);
	u32 up = lup, down = gdown;

	sizes[0] = dst;
	for (;;) {
		/* src -> cur in one pass with limits up/down? */
		if ((u64)src <= (u64)cur * down && (u64)cur <= (u64)src * up)
			break;
		if (n == maxp)
			return 0;
		if (src > cur)
			cur = round_down(min_t(u64, (u64)cur * down, AS_MAX_W * 4), align);
		else
			cur = ALIGN(DIV_ROUND_UP(cur, up), align);
		cur = max(cur, (u32)AS_MIN_W);
		sizes[n++] = cur;
		up = 8;
		down = gdown;
	}
	/* sizes[n-1..1] are the intermediates, in pass order */
	for (i = 0; i + 1 < n; i++)
		mid[i] = sizes[n - 1 - i];
	return n;
}

static void as_free_tmp(struct as_ctx *ctx)
{
	struct device *dev = ctx->dev->dev;
	int i;

	for (i = 0; i < 2; i++) {
		if (ctx->tmp_cpu[i])
			dma_free_attrs(dev, ctx->tmp_size, ctx->tmp_cpu[i],
				       ctx->tmp_dma[i], DMA_ATTR_NO_KERNEL_MAPPING);
		ctx->tmp_cpu[i] = NULL;
	}
	ctx->tmp_size = 0;
}

static int as_plan(struct as_ctx *ctx)
{
	struct as_q *s = &ctx->q[0], *d = &ctx->q[1];
	const struct as_fmt *sf = s->fmt;
	bool rot90 = (ctx->rotate / 90) & 1;
	u32 dw = rot90 ? d->rect.height : d->rect.width;
	u32 dh = rot90 ? d->rect.width : d->rect.height;
	u32 mh[AS_MAX_PASSES - 1] = { 0 }, mv[AS_MAX_PASSES - 1] = { 0 };
	bool chroma_up = sf->class == AS_YUV &&
		(sf->hsub != d->fmt->hsub || sf->vsub != d->fmt->vsub ||
		 d->fmt->class != AS_YUV);
	unsigned int nh, nv, n, i;
	size_t sz = 0;

	nh = as_plan_dir(s->rect.width, dw, 8, chroma_up ? 8 / sf->hsub : 8,
			 sf->hsub, mh);
	nv = as_plan_dir(s->rect.height, dh, 4, chroma_up ? 8 / sf->vsub : 8,
			 sf->vsub, mv);
	if (!nh || !nv) {
		dev_dbg(ctx->dev->dev, "%ux%u -> %ux%u needs more than %u passes\n",
			s->rect.width, s->rect.height, dw, dh, max_passes);
		return -EINVAL;
	}
	n = max(nh, nv);
	/* the direction with fewer passes keeps the source size first */
	for (i = 0; i + 1 < n; i++) {
		int ih = (int)i - (int)(n - nh), iv = (int)i - (int)(n - nv);

		ctx->iw[i] = ih >= 0 ? mh[ih] : s->rect.width;
		ctx->ih[i] = iv >= 0 ? mv[iv] : s->rect.height;
		sz = max_t(size_t, sz, as_sizeimage(sf,
			ALIGN(ctx->iw[i] * sf->cpp[0], 64), ctx->ih[i]));
	}
	ctx->npasses = n;

	as_free_tmp(ctx);
	if (n > 1) {
		struct device *dev = ctx->dev->dev;

		ctx->tmp_size = PAGE_ALIGN(sz);
		for (i = 0; i < min(n - 1, 2u); i++) {
			ctx->tmp_cpu[i] = dma_alloc_attrs(dev, ctx->tmp_size,
							  &ctx->tmp_dma[i], GFP_KERNEL,
							  DMA_ATTR_NO_KERNEL_MAPPING);
			if (!ctx->tmp_cpu[i]) {
				as_free_tmp(ctx);
				return -ENOMEM;
			}
		}
		dev_dbg(dev, "%u passes, intermediate %ux%u\n", n, ctx->iw[0], ctx->ih[0]);
	}
	return 0;
}

/* a surface at rect r of a frame (base, fmt, bpl, frame w/h) */
static void as_surface(struct as_surface *sf, const struct as_fmt *f,
		       dma_addr_t base, u32 bpl, u32 fw, u32 fh,
		       const struct v4l2_rect *r)
{
	u32 cbpl = as_cbpl(f, bpl);

	sf->fmt = f;
	sf->stride[0] = bpl;
	sf->addr[0] = base + (u64)r->top * bpl + r->left * f->cpp[0];
	if (f->planes > 1) {
		sf->stride[1] = cbpl;
		sf->addr[1] = base + (u64)bpl * fh +
			(u64)(r->top / f->vsub) * cbpl + (r->left / f->hsub) * f->cpp[1];
	}
	sf->w = r->width;
	sf->h = r->height;
	sf->plane_w = fw - r->left;
	sf->plane_h = fh - r->top;
}

static void as_build_passes(struct as_ctx *ctx, dma_addr_t sa, dma_addr_t da)
{
	struct as_dev *dev = ctx->dev;
	struct as_q *s = &ctx->q[0], *d = &ctx->q[1];
	const struct as_fmt *sf = s->fmt;
	unsigned int i, n = ctx->npasses;
	dma_addr_t in = sa;
	u32 inbpl = s->bpl, inw = s->width, inh = s->height;
	struct v4l2_rect inr = s->rect;

	for (i = 0; i < n; i++) {
		struct as_pass *p = &dev->passes[i];

		memset(p, 0, sizeof(*p));
		as_surface(&p->src, sf, in, inbpl, inw, inh, &inr);
		if (i + 1 < n) {
			struct v4l2_rect r = { 0, 0, ctx->iw[i], ctx->ih[i] };
			u32 bpl = ALIGN(ctx->iw[i] * sf->cpp[0], 64);

			as_surface(&p->dst, sf, ctx->tmp_dma[i & 1], bpl,
				   r.width, r.height, &r);
			in = ctx->tmp_dma[i & 1];
			inbpl = bpl;
			inw = r.width;
			inh = r.height;
			inr = r;
		} else {
			as_surface(&p->dst, d->fmt, da, d->bpl, d->width, d->height,
				   &d->rect);
			p->rot = (ctx->rotate / 90) & 3;
			p->hflip = ctx->hflip;
			p->vflip = ctx->vflip;
			as_build_csc(&p->csc, sf, s->ycbcr_enc, s->quant,
				     d->fmt, d->ycbcr_enc, d->quant);
		}
	}
}

/* ---------------------------------------------------------------- jobs */

static void as_job_done(struct as_dev *dev, struct as_ctx *ctx,
			enum vb2_buffer_state state)
{
	struct vb2_v4l2_buffer *src, *dst;

	src = v4l2_m2m_next_src_buf(ctx->fh.m2m_ctx);
	dst = v4l2_m2m_next_dst_buf(ctx->fh.m2m_ctx);
	if (src && dst) {
		v4l2_m2m_buf_copy_metadata(src, dst);
		dst->sequence = ctx->q[1].sequence++;
		src->sequence = ctx->q[0].sequence++;
	}
	v4l2_m2m_buf_done_and_job_finish(dev->m2m_dev, ctx->fh.m2m_ctx, state);
}

static void as_device_run(void *priv)
{
	struct as_ctx *ctx = priv;
	struct as_dev *dev = ctx->dev;
	struct vb2_v4l2_buffer *src, *dst;
	unsigned long flags;

	src = v4l2_m2m_next_src_buf(ctx->fh.m2m_ctx);
	dst = v4l2_m2m_next_dst_buf(ctx->fh.m2m_ctx);

	spin_lock_irqsave(&dev->lock, flags);
	if (!ctx->npasses) {
		spin_unlock_irqrestore(&dev->lock, flags);
		as_job_done(dev, ctx, VB2_BUF_STATE_ERROR);
		return;
	}
	vb2_set_plane_payload(&dst->vb2_buf, 0, ctx->q[1].sizeimage);
	as_build_passes(ctx, vb2_dma_contig_plane_dma_addr(&src->vb2_buf, 0),
			vb2_dma_contig_plane_dma_addr(&dst->vb2_buf, 0));
	dev->cur = ctx;
	dev->cur_pass = 0;
	dev->job_failed = false;
	as_hw_program_pass(dev, &dev->passes[0]);
	wmb();
	as_hw_start(dev);
	spin_unlock_irqrestore(&dev->lock, flags);
	mod_delayed_work(system_wq, &dev->watchdog, msecs_to_jiffies(timeout_ms));
}

static irqreturn_t as_irq(int irq, void *data)
{
	struct as_dev *dev = data;
	struct as_ctx *ctx = NULL;
	enum vb2_buffer_state state = VB2_BUF_STATE_DONE;
	u32 st;

	spin_lock(&dev->lock);
	st = as_rd(dev, AS_IRQ_STATUS);
	if (!st) {
		spin_unlock(&dev->lock);
		return IRQ_NONE;
	}
	as_wr(dev, AS_IRQ_STATUS, st);	/* W1C */

	if (!dev->cur) {
		spin_unlock(&dev->lock);
		dev_warn_ratelimited(dev->dev, "irq %#x with no job\n", st);
		return IRQ_HANDLED;
	}
	if (st & AS_IRQ_ERRORS) {
		dev_err_ratelimited(dev->dev, "pass %u: irq %#x dbg %#x\n",
				    dev->cur_pass, st, as_rd(dev, AS_DBG_STATUS));
		dev->errors++;
		state = VB2_BUF_STATE_ERROR;
		as_hw_init(dev);	/* soft reset, filters reloaded next job */
	} else if (!(st & AS_IRQ_DONE)) {
		/* 0x200 alone (decompression) or context switch: wait for done */
		spin_unlock(&dev->lock);
		return IRQ_HANDLED;
	} else if (dev->cur_pass + 1 < dev->cur->npasses) {
		dev->cur_pass++;
		as_hw_program_pass(dev, &dev->passes[dev->cur_pass]);
		wmb();
		as_hw_start(dev);
		spin_unlock(&dev->lock);
		mod_delayed_work(system_wq, &dev->watchdog, msecs_to_jiffies(timeout_ms));
		return IRQ_HANDLED;
	}
	ctx = dev->cur;
	dev->cur = NULL;
	dev->jobs++;
	spin_unlock(&dev->lock);

	cancel_delayed_work(&dev->watchdog);
	as_job_done(dev, ctx, state);
	return IRQ_HANDLED;
}

static void as_recover(struct as_dev *dev)
{
	unsigned int lvl = hang_recovery;

	if (!lvl)
		return;
	dev->recoveries++;
	writel(0, dev->base + AS_IRQ_ENABLE);
	as_hw_soft_reset(dev);
	if (lvl >= 3 && dev->rst) {
		/* pmgr reset of ps_msr0, as macOS hangRecovery does [KEXT13.5];
		 * the DART shares the power state and may lose its tables [INF] */
		dev_warn(dev->dev, "recovery: pmgr reset\n");
		reset_control_reset(dev->rst);
	}
	if (lvl >= 2) {
		dev_warn(dev->dev, "recovery: power cycle\n");
		pm_runtime_force_suspend(dev->dev);
		pm_runtime_force_resume(dev->dev);
	}
	as_hw_init(dev);
}

static void as_watchdog(struct work_struct *w)
{
	struct as_dev *dev = container_of(to_delayed_work(w), struct as_dev, watchdog);
	struct as_ctx *ctx;
	unsigned long flags;

	spin_lock_irqsave(&dev->lock, flags);
	ctx = dev->cur;
	dev->cur = NULL;
	spin_unlock_irqrestore(&dev->lock, flags);
	if (!ctx)
		return;

	dev_err(dev->dev, "pass %u timed out: irq %#x running %#x dbg %#x frames %u\n",
		dev->cur_pass, as_rd(dev, AS_IRQ_STATUS), as_rd(dev, AS_IS_RUNNING),
		as_rd(dev, AS_DBG_STATUS), as_rd(dev, AS_FRAME_COUNT));
	dev->errors++;
	mutex_lock(&dev->mutex);
	as_recover(dev);
	mutex_unlock(&dev->mutex);
	as_job_done(dev, ctx, VB2_BUF_STATE_ERROR);
}

static const struct v4l2_m2m_ops as_m2m_ops = {
	.device_run = as_device_run,
};

/* ---------------------------------------------------------------- vb2 */

static int as_queue_setup(struct vb2_queue *vq, unsigned int *nbuffers,
			  unsigned int *nplanes, unsigned int sizes[],
			  struct device *alloc_devs[])
{
	struct as_ctx *ctx = vb2_get_drv_priv(vq);
	struct as_q *q = as_get_q(ctx, vq->type);

	if (*nplanes)
		return sizes[0] < q->sizeimage ? -EINVAL : 0;
	*nplanes = 1;
	sizes[0] = q->sizeimage;
	return 0;
}

static int as_buf_prepare(struct vb2_buffer *vb)
{
	struct vb2_v4l2_buffer *vbuf = to_vb2_v4l2_buffer(vb);
	struct as_ctx *ctx = vb2_get_drv_priv(vb->vb2_queue);
	struct as_q *q = as_get_q(ctx, vb->vb2_queue->type);

	if (V4L2_TYPE_IS_OUTPUT(vb->vb2_queue->type)) {
		if (vbuf->field == V4L2_FIELD_ANY)
			vbuf->field = V4L2_FIELD_NONE;
		if (vbuf->field != V4L2_FIELD_NONE)
			return -EINVAL;
	}
	if (vb2_plane_size(vb, 0) < q->sizeimage)
		return -EINVAL;
	if (!V4L2_TYPE_IS_OUTPUT(vb->vb2_queue->type))
		vb2_set_plane_payload(vb, 0, q->sizeimage);
	return 0;
}

static void as_buf_queue(struct vb2_buffer *vb)
{
	struct as_ctx *ctx = vb2_get_drv_priv(vb->vb2_queue);

	v4l2_m2m_buf_queue(ctx->fh.m2m_ctx, to_vb2_v4l2_buffer(vb));
}

static void as_return_bufs(struct as_ctx *ctx, struct vb2_queue *vq,
			   enum vb2_buffer_state state)
{
	struct vb2_v4l2_buffer *vb;

	for (;;) {
		vb = V4L2_TYPE_IS_OUTPUT(vq->type) ?
			v4l2_m2m_src_buf_remove(ctx->fh.m2m_ctx) :
			v4l2_m2m_dst_buf_remove(ctx->fh.m2m_ctx);
		if (!vb)
			return;
		v4l2_m2m_buf_done(vb, state);
	}
}

static int as_start_streaming(struct vb2_queue *vq, unsigned int count)
{
	struct as_ctx *ctx = vb2_get_drv_priv(vq);
	struct vb2_queue *other = V4L2_TYPE_IS_OUTPUT(vq->type) ?
		v4l2_m2m_get_dst_vq(ctx->fh.m2m_ctx) :
		v4l2_m2m_get_src_vq(ctx->fh.m2m_ctx);
	int ret;

	as_get_q(ctx, vq->type)->sequence = 0;
	if (!ctx->pm_held) {
		ret = pm_runtime_resume_and_get(ctx->dev->dev);
		if (ret)
			goto err;
		ctx->pm_held = true;
	}
	if (vb2_is_streaming(other)) {
		ret = as_plan(ctx);
		if (ret)
			goto err;
	}
	return 0;
err:
	as_return_bufs(ctx, vq, VB2_BUF_STATE_QUEUED);
	return ret;
}

static void as_stop_streaming(struct vb2_queue *vq)
{
	struct as_ctx *ctx = vb2_get_drv_priv(vq);
	struct vb2_queue *other = V4L2_TYPE_IS_OUTPUT(vq->type) ?
		v4l2_m2m_get_dst_vq(ctx->fh.m2m_ctx) :
		v4l2_m2m_get_src_vq(ctx->fh.m2m_ctx);

	as_return_bufs(ctx, vq, VB2_BUF_STATE_ERROR);
	ctx->npasses = 0;
	if (!vb2_is_streaming(other)) {
		as_free_tmp(ctx);
		if (ctx->pm_held) {
			pm_runtime_put_autosuspend(ctx->dev->dev);
			ctx->pm_held = false;
		}
	}
}

static const struct vb2_ops as_qops = {
	.queue_setup = as_queue_setup,
	.buf_prepare = as_buf_prepare,
	.buf_queue = as_buf_queue,
	.start_streaming = as_start_streaming,
	.stop_streaming = as_stop_streaming,
};

static int as_queue_init(void *priv, struct vb2_queue *src, struct vb2_queue *dst)
{
	struct as_ctx *ctx = priv;
	int ret;

	src->type = V4L2_BUF_TYPE_VIDEO_OUTPUT;
	src->io_modes = VB2_MMAP | VB2_DMABUF;
	src->drv_priv = ctx;
	src->buf_struct_size = sizeof(struct v4l2_m2m_buffer);
	src->ops = &as_qops;
	src->mem_ops = &vb2_dma_contig_memops;
	src->timestamp_flags = V4L2_BUF_FLAG_TIMESTAMP_COPY;
	src->lock = &ctx->dev->mutex;
	src->dev = ctx->dev->dev;
	ret = vb2_queue_init(src);
	if (ret)
		return ret;

	dst->type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
	dst->io_modes = VB2_MMAP | VB2_DMABUF;
	dst->drv_priv = ctx;
	dst->buf_struct_size = sizeof(struct v4l2_m2m_buffer);
	dst->ops = &as_qops;
	dst->mem_ops = &vb2_dma_contig_memops;
	dst->timestamp_flags = V4L2_BUF_FLAG_TIMESTAMP_COPY;
	dst->lock = &ctx->dev->mutex;
	dst->dev = ctx->dev->dev;
	return vb2_queue_init(dst);
}

/* ---------------------------------------------------------------- file ops */

static void as_default_q(struct as_q *q, const struct as_fmt *f)
{
	q->fmt = f;
	q->width = 640;
	q->height = 480;
	q->bpl = ALIGN(640 * f->cpp[0], 64);
	q->sizeimage = as_sizeimage(f, q->bpl, q->height);
	q->rect = (struct v4l2_rect){ 0, 0, 640, 480 };
	q->colorspace = f->class == AS_RGB ? V4L2_COLORSPACE_SRGB : V4L2_COLORSPACE_REC709;
	q->xfer = V4L2_MAP_XFER_FUNC_DEFAULT(q->colorspace);
	q->ycbcr_enc = V4L2_MAP_YCBCR_ENC_DEFAULT(q->colorspace);
	q->quant = V4L2_MAP_QUANTIZATION_DEFAULT(f->class == AS_RGB, q->colorspace,
						 q->ycbcr_enc);
}

static int as_open(struct file *file)
{
	struct as_dev *dev = video_drvdata(file);
	struct as_ctx *ctx;
	struct v4l2_ctrl_handler *hdl;
	int ret = 0;

	if (mutex_lock_interruptible(&dev->mutex))
		return -ERESTARTSYS;
	ctx = kzalloc(sizeof(*ctx), GFP_KERNEL);
	if (!ctx) {
		ret = -ENOMEM;
		goto unlock;
	}
	v4l2_fh_init(&ctx->fh, video_devdata(file));
	ctx->dev = dev;

	hdl = &ctx->hdl;
	v4l2_ctrl_handler_init(hdl, 3);
	v4l2_ctrl_new_std(hdl, &as_ctrl_ops, V4L2_CID_HFLIP, 0, 1, 1, 0);
	v4l2_ctrl_new_std(hdl, &as_ctrl_ops, V4L2_CID_VFLIP, 0, 1, 1, 0);
	v4l2_ctrl_new_std(hdl, &as_ctrl_ops, V4L2_CID_ROTATE, 0, 270, 90, 0);
	if (hdl->error) {
		ret = hdl->error;
		v4l2_ctrl_handler_free(hdl);
		v4l2_fh_exit(&ctx->fh);
		kfree(ctx);
		goto unlock;
	}
	ctx->fh.ctrl_handler = hdl;
	v4l2_ctrl_handler_setup(hdl);

	as_default_q(&ctx->q[0], as_find_fmt(V4L2_PIX_FMT_NV12));
	as_default_q(&ctx->q[1], as_find_fmt(V4L2_PIX_FMT_ABGR32));
	ctx->q[1].colorspace = ctx->q[0].colorspace;
	ctx->q[1].xfer = ctx->q[0].xfer;

	ctx->fh.m2m_ctx = v4l2_m2m_ctx_init(dev->m2m_dev, ctx, as_queue_init);
	if (IS_ERR(ctx->fh.m2m_ctx)) {
		ret = PTR_ERR(ctx->fh.m2m_ctx);
		v4l2_ctrl_handler_free(hdl);
		v4l2_fh_exit(&ctx->fh);
		kfree(ctx);
		goto unlock;
	}
	v4l2_fh_add(&ctx->fh, file);
unlock:
	mutex_unlock(&dev->mutex);
	return ret;
}

static int as_release(struct file *file)
{
	struct as_dev *dev = video_drvdata(file);
	struct as_ctx *ctx = file2ctx(file);

	mutex_lock(&dev->mutex);
	v4l2_m2m_ctx_release(ctx->fh.m2m_ctx);
	mutex_unlock(&dev->mutex);
	v4l2_fh_del(&ctx->fh, file);
	v4l2_fh_exit(&ctx->fh);
	v4l2_ctrl_handler_free(&ctx->hdl);
	as_free_tmp(ctx);
	if (ctx->pm_held)
		pm_runtime_put_autosuspend(dev->dev);
	kfree(ctx);
	return 0;
}

static const struct v4l2_file_operations as_fops = {
	.owner = THIS_MODULE,
	.open = as_open,
	.release = as_release,
	.poll = v4l2_m2m_fop_poll,
	.unlocked_ioctl = video_ioctl2,
	.mmap = v4l2_m2m_fop_mmap,
};

static const struct v4l2_ioctl_ops as_ioctl_ops = {
	.vidioc_querycap = as_querycap,
	.vidioc_enum_fmt_vid_cap = as_enum_fmt,
	.vidioc_enum_fmt_vid_out = as_enum_fmt,
	.vidioc_g_fmt_vid_cap = as_g_fmt,
	.vidioc_g_fmt_vid_out = as_g_fmt,
	.vidioc_try_fmt_vid_cap = as_try_fmt,
	.vidioc_try_fmt_vid_out = as_try_fmt,
	.vidioc_s_fmt_vid_cap = as_s_fmt,
	.vidioc_s_fmt_vid_out = as_s_fmt,
	.vidioc_enum_framesizes = as_enum_framesizes,
	.vidioc_g_selection = as_g_selection,
	.vidioc_s_selection = as_s_selection,

	.vidioc_reqbufs = v4l2_m2m_ioctl_reqbufs,
	.vidioc_querybuf = v4l2_m2m_ioctl_querybuf,
	.vidioc_qbuf = v4l2_m2m_ioctl_qbuf,
	.vidioc_dqbuf = v4l2_m2m_ioctl_dqbuf,
	.vidioc_prepare_buf = v4l2_m2m_ioctl_prepare_buf,
	.vidioc_create_bufs = v4l2_m2m_ioctl_create_bufs,
	.vidioc_expbuf = v4l2_m2m_ioctl_expbuf,
	.vidioc_streamon = v4l2_m2m_ioctl_streamon,
	.vidioc_streamoff = v4l2_m2m_ioctl_streamoff,

	.vidioc_subscribe_event = v4l2_ctrl_subscribe_event,
	.vidioc_unsubscribe_event = v4l2_event_unsubscribe,
};

static const struct video_device as_vdev = {
	.name = AS_NAME,
	.vfl_dir = VFL_DIR_M2M,
	.fops = &as_fops,
	.ioctl_ops = &as_ioctl_ops,
	.minor = -1,
	.release = video_device_release_empty,
	.device_caps = V4L2_CAP_VIDEO_M2M | V4L2_CAP_STREAMING,
};

/* ---------------------------------------------------------------- PM */

/* [KEXT13.5 AppleM2ScalerCSCHalMSR::detectHardwareVersion: 0x0 = 1, 0, read] */
u32 as_read_version(struct as_dev *dev)
{
	u32 v = readl(dev->base + AS_HW_VERSION);

	if (v != AS_HW_VERSION_T6020 && version_poke) {
		writel(1, dev->base + AS_HW_VERSION);
		writel(0, dev->base + AS_HW_VERSION);
		v = readl(dev->base + AS_HW_VERSION);
	}
	return v;
}

static int as_runtime_suspend(struct device *d)
{
	struct as_dev *dev = dev_get_drvdata(d);

	if (dev->stage < 4)
		return 0;
	writel(0, dev->base + AS_IRQ_ENABLE);
	as_hw_dpe_stop(dev);
	return 0;
}

static int as_runtime_resume(struct device *d)
{
	struct as_dev *dev = dev_get_drvdata(d);
	u32 v;

	if (dev->stage < 4)
		return 0;
	v = as_read_version(dev);
	if (v != AS_HW_VERSION_T6020 && !force_version) {
		dev_err(d, "resume: version %#x\n", v);
		return -EIO;
	}
	return as_hw_init(dev);
}

static const struct dev_pm_ops as_pm_ops = {
	SET_RUNTIME_PM_OPS(as_runtime_suspend, as_runtime_resume, NULL)
	SET_SYSTEM_SLEEP_PM_OPS(pm_runtime_force_suspend, pm_runtime_force_resume)
};

/* ---------------------------------------------------------------- probe */

static int as_probe(struct platform_device *pdev)
{
	struct device *d = &pdev->dev;
	struct as_dev *dev;
	u32 v;
	int ret;

	dev = devm_kzalloc(d, sizeof(*dev), GFP_KERNEL);
	if (!dev)
		return -ENOMEM;
	dev->dev = d;
	platform_set_drvdata(pdev, dev);
	spin_lock_init(&dev->lock);
	mutex_init(&dev->mutex);
	INIT_DELAYED_WORK(&dev->watchdog, as_watchdog);

	/* stage 1: resources, no hardware access */
	dev->base = devm_platform_ioremap_resource_byname(pdev, "scaler");
	if (IS_ERR(dev->base))
		return dev_err_probe(d, PTR_ERR(dev->base), "no 'scaler' reg\n");
	dev->dpe = devm_platform_ioremap_resource_byname(pdev, "dpe");
	if (IS_ERR(dev->dpe)) {
		dev_warn(d, "no 'dpe' reg, DPE not started\n");
		dev->dpe = NULL;
	}
	dev->irq = platform_get_irq(pdev, 0);
	if (dev->irq < 0)
		return dev->irq;
	ret = dma_set_mask_and_coherent(d, DMA_BIT_MASK(42));
	if (ret)
		return ret;
	dev->rst = devm_reset_control_get_optional_exclusive(d, NULL);
	if (IS_ERR(dev->rst))
		return PTR_ERR(dev->rst);
	as_stage(dev, 1, "resources mapped");
	if (stop_after == 1)
		return -ECANCELED;

	/* stage 2: power (ps_msr0 + ps_msr0_ase_core) */
	ret = devm_pm_domain_attach_list(d, NULL, &dev->pd_list);
	if (ret < 0 && ret != -EEXIST)
		return dev_err_probe(d, ret, "power domains\n");
	pm_runtime_set_autosuspend_delay(d, 1000);
	pm_runtime_use_autosuspend(d);
	ret = devm_pm_runtime_enable(d);
	if (ret)
		return ret;
	ret = pm_runtime_resume_and_get(d);
	if (ret)
		return dev_err_probe(d, ret, "power on\n");
	as_stage(dev, 2, "powered on");
	if (stop_after == 2) {
		ret = -ECANCELED;
		goto err_pm;
	}

	/* stage 3: read-only version check */
	v = readl(dev->base + AS_HW_VERSION);
	dev_info(d, "version register reads %#x\n", v);
	if (v != AS_HW_VERSION_T6020)
		v = as_read_version(dev);
	dev_info(d, "hardware version %#x (expect %#x), frame count %u\n",
		 v, AS_HW_VERSION_T6020, readl(dev->base + AS_FRAME_COUNT));
	if (v != AS_HW_VERSION_T6020 && !force_version) {
		dev_err(d, "unknown scaler version, refusing (force_version=1 overrides)\n");
		ret = -ENODEV;
		goto err_pm;
	}
	as_stage(dev, 3, "version checked");
	if (stop_after == 3) {
		ret = -ECANCELED;
		goto err_pm;
	}

	/* stage 4: first writes */
	as_hw_init(dev);
	as_stage(dev, 4, "reset and initialised");
	if (stop_after == 4) {
		ret = -ECANCELED;
		goto err_off;
	}

	/* stage 5: polled self-test (DMA through the DART) */
	if (selftest) {
		ret = as_hw_selftest(dev);
		if (ret)
			goto err_off;
	}
	as_stage(dev, 5, selftest ? "selftest passed" : "selftest skipped");
	if (stop_after == 5) {
		ret = -ECANCELED;
		goto err_off;
	}

	/* stage 6: interrupt */
	ret = devm_request_irq(d, dev->irq, as_irq, 0, dev_name(d), dev);
	if (ret)
		goto err_off;
	as_stage(dev, 6, "irq requested");
	if (stop_after == 6) {
		ret = -ECANCELED;
		goto err_off;
	}

	/* stage 7: V4L2 */
	ret = v4l2_device_register(d, &dev->v4l2_dev);
	if (ret)
		goto err_off;
	dev->m2m_dev = v4l2_m2m_init(&as_m2m_ops);
	if (IS_ERR(dev->m2m_dev)) {
		ret = PTR_ERR(dev->m2m_dev);
		goto err_v4l2;
	}
	dev->vfd = as_vdev;
	dev->vfd.lock = &dev->mutex;
	dev->vfd.v4l2_dev = &dev->v4l2_dev;
	video_set_drvdata(&dev->vfd, dev);
	ret = video_register_device(&dev->vfd, VFL_TYPE_VIDEO, -1);
	if (ret)
		goto err_m2m;
	as_stage(dev, 7, "registered");
	dev_info(d, "/dev/video%d: M2Scaler hw-version 14\n", dev->vfd.num);

	pm_runtime_put_autosuspend(d);
	return 0;

err_m2m:
	v4l2_m2m_release(dev->m2m_dev);
err_v4l2:
	v4l2_device_unregister(&dev->v4l2_dev);
err_off:
	writel(0, dev->base + AS_IRQ_ENABLE);
	as_hw_dpe_stop(dev);
err_pm:
	dev->stage = 0;
	pm_runtime_put_sync(d);
	if (ret == -ECANCELED)
		dev_info(d, "stopped after stage %u (stop_after)\n", stop_after);
	return ret;
}

static void as_remove(struct platform_device *pdev)
{
	struct as_dev *dev = platform_get_drvdata(pdev);

	video_unregister_device(&dev->vfd);
	cancel_delayed_work_sync(&dev->watchdog);
	v4l2_m2m_release(dev->m2m_dev);
	v4l2_device_unregister(&dev->v4l2_dev);
	pm_runtime_get_sync(dev->dev);
	writel(0, dev->base + AS_IRQ_ENABLE);
	as_hw_dpe_stop(dev);
	dev->stage = 0;
	pm_runtime_put_sync(dev->dev);
	pm_runtime_dont_use_autosuspend(dev->dev);
}

static const struct of_device_id as_of_match[] = {
	{ .compatible = "apple,t6020-scaler" },
	{ }
};
/*
 * No MODULE_DEVICE_TABLE on purpose: nothing autoloads this module while it
 * is untested; load it by hand (docs/scaler-port.txt).
 */

static struct platform_driver as_driver = {
	.probe = as_probe,
	.remove = as_remove,
	.driver = {
		.name = AS_NAME,
		.of_match_table = as_of_match,
		.pm = pm_ptr(&as_pm_ops),
	},
};
module_platform_driver(as_driver);

MODULE_DESCRIPTION("Apple M2Scaler (t6020) V4L2 mem2mem converter");
MODULE_LICENSE("GPL");

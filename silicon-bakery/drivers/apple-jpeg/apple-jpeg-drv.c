// SPDX-License-Identifier: GPL-2.0-only
/*
 * Apple M2 Pro (t6020) JPEG codec, V4L2 memory-to-memory encoder and
 * stateful decoder. One platform device per engine (jpeg0, jpeg1); each
 * registers an encoder and a decoder video node that share the engine.
 *
 * Forked from aurora-silicon/linux aurora-wip (27c8c52a),
 * drivers/media/platform/apple/jpeg/apple-jpeg-drv.c, Ryan Murray's T8140
 * encoder (GPL-2.0-only): the V4L2 skeleton, draining, runtime PM and the
 * job/IRQ/watchdog shape are theirs. Silicon Bakery added the t6020 MODE
 * values, reset with per-core tunables, the AXI wrapper drain, the staged
 * probe, more raw formats, chroma subsampling control, DRI insertion and
 * the decoder. Register facts and labels: apple-jpeg-hw.h. Untested on
 * hardware: written on the Mac14,9 under macOS.
 */
#include <linux/delay.h>
#include <linux/dma-mapping.h>
#include <linux/interrupt.h>
#include <linux/io.h>
#include <linux/iommu.h>
#include <linux/iopoll.h>
#include <linux/module.h>
#include <linux/mutex.h>
#include <linux/of.h>
#include <linux/platform_device.h>
#include <linux/pm_domain.h>
#include <linux/pm_runtime.h>
#include <linux/sizes.h>
#include <linux/slab.h>
#include <linux/spinlock.h>
#include <linux/workqueue.h>

#include <media/v4l2-ctrls.h>
#include <media/v4l2-device.h>
#include <media/v4l2-event.h>
#include <media/v4l2-fh.h>
#include <media/v4l2-ioctl.h>
#include <media/v4l2-jpeg.h>
#include <media/v4l2-mem2mem.h>
#include <media/videobuf2-dma-contig.h>

#include "apple-jpeg-hw.h"

#define AJ_NAME			"apple-jpeg"
#define AJ_MIN_SIZE		16
#define AJ_MAX_SIZE		16384	/* engine: 65535 [KEXT13.5]; buffers bound it here */
#define AJ_DEC_MIN_SIZE		1
#define AJ_DEC_MIN_BYTES	0x101	/* startDecoderGated refuses smaller [KEXT13.5] */
#define AJ_STRIDE_ALIGN		128	/* rddma alignment in compressed modes [KEXT13.5]; [INF] */
#define AJ_STAGE_MAX		5
#define AJ_DIE_STRIDE		0x2000000000ULL	/* pmgr die-stride [ADT] */

#define APPLE_JPEG_CID_DECODE_SCALE	(V4L2_CID_USER_BASE + 0x1f00)	/* private */

/* ---- parameters --------------------------------------------------------- */

static unsigned int stop_after = AJ_STAGE_MAX;
module_param(stop_after, uint, 0444);
MODULE_PARM_DESC(stop_after,
		 "stop probe after stage N and release everything: 1 resources (no hardware access), 2 power on + read-only reads, 3 version check, 4 one reset with tunables, 5 IRQ + V4L2 nodes (default)");

static unsigned int step_ms;
module_param(step_ms, uint, 0444);
MODULE_PARM_DESC(step_ms, "sleep this long after each probe stage marker, so the journal/pstore keeps it before the next step (default 0)");

static bool tunables = true;
module_param(tunables, bool, 0444);
MODULE_PARM_DESC(tunables, "apply macOS's per-core tunables at every reset (default 1)");

static bool axi_drain = true;
module_param(axi_drain, bool, 0444);
MODULE_PARM_DESC(axi_drain, "after a job that did not complete, drain the AXI wrapper as macOS does (default 1)");

static bool axi_init;
module_param(axi_init, bool, 0444);
MODULE_PARM_DESC(axi_init, "write the AXI wrapper's run value (0x0040000a) at probe; macOS only writes it after a drain (default 0)");

static unsigned int prefetch_mask = 1;
module_param_named(prefetch, prefetch_mask, uint, 0444);
MODULE_PARM_DESC(prefetch, "AXI prefetch: bit 0 encode (0x154=1, as aurora on T8140), bit 1 decode (0x158=1) (default 1)");

static bool encoder = true;
module_param(encoder, bool, 0444);
MODULE_PARM_DESC(encoder, "register the encoder node (default 1)");

static bool decoder = true;
module_param(decoder, bool, 0444);
MODULE_PARM_DESC(decoder, "register the decoder node (default 1)");

/* ---- types -------------------------------------------------------------- */

struct aj_fmt {
	u32 fourcc;
	enum aj_pixfmt hw;
	u8 mem_planes;
	bool yuyv;
};

static const struct aj_fmt aj_raw_fmts[] = {
	{ V4L2_PIX_FMT_NV12M, AJ_PIX_YUV420_2P, 2 },
	{ V4L2_PIX_FMT_NV12,  AJ_PIX_YUV420_2P, 1 },
	{ V4L2_PIX_FMT_NV16M, AJ_PIX_YUV422_2P, 2 },
	{ V4L2_PIX_FMT_NV16,  AJ_PIX_YUV422_2P, 1 },
	{ V4L2_PIX_FMT_NV24,  AJ_PIX_YUV444_2P, 1 },
	{ V4L2_PIX_FMT_YUYV,  AJ_PIX_YUV422_1P, 1, true },
	{ V4L2_PIX_FMT_UYVY,  AJ_PIX_YUV422_1P, 1, false },
};

struct aj_hdr {
	bool valid;
	u16 width, height;
	enum aj_codec codec;
};

struct aj_buf {
	struct v4l2_m2m_buffer m2m;	/* first: vb2 allocates buf_struct_size */
	struct aj_hdr hdr;		/* decoder OUTPUT: parsed at prepare */
};

struct aj_result {
	u32 status, int_status, debug, decomp, bytes;
};

struct apple_jpeg_ctx;

struct apple_jpeg {
	struct device *dev;
	void __iomem *regs;
	void __iomem *axi;		/* the core's ctrl/status pair, or NULL */
	unsigned int core;
	struct dev_pm_domain_list *pd_list;
	struct mutex lock;		/* serialises ioctls and queue state */
	struct v4l2_device v4l2_dev;
	struct video_device enc_vdev, dec_vdev;
	bool enc_registered, dec_registered;
	struct v4l2_m2m_dev *m2m_dev;
	int irq;

	spinlock_t hw_lock;		/* protects the fields below */
	struct apple_jpeg_ctx *active;	/* on the engine */
	struct apple_jpeg_ctx *done;	/* handed from the hard IRQ to the thread */
	struct aj_result res;
	bool broken;
	struct delayed_work watchdog;
	struct apple_jpeg_write writes[APPLE_JPEG_MAX_WRITES];
};

struct apple_jpeg_ctx {
	struct v4l2_fh fh;
	struct apple_jpeg *jpeg;
	bool dec;
	struct v4l2_ctrl_handler hdl;
	struct v4l2_ctrl *quality, *restart, *subsampling, *scale;
	struct v4l2_pix_format_mplane out;	/* OUTPUT queue */
	struct v4l2_pix_format_mplane cap;	/* CAPTURE queue */
	const struct aj_fmt *raw;		/* the raw side's format */
	struct aj_hdr hdr;			/* decoder: stream the CAPTURE format is for */
	bool wait_cap;				/* decoder: source change pending */
	u32 sequence;
	bool dri_warned;
};

static struct apple_jpeg_ctx *aj_file_to_ctx(struct file *file)
{
	return container_of(file_to_v4l2_fh(file), struct apple_jpeg_ctx, fh);
}

static struct aj_buf *aj_to_buf(struct vb2_v4l2_buffer *vbuf)
{
	return container_of(vbuf, struct aj_buf, m2m.vb);
}

static void aj_write(struct apple_jpeg *jpeg, u32 reg, u32 val)
{
	writel_relaxed(val, jpeg->regs + reg);
}

static u32 aj_read(struct apple_jpeg *jpeg, u32 reg)
{
	return readl_relaxed(jpeg->regs + reg);
}

static const struct aj_fmt *aj_find_fmt(u32 fourcc)
{
	for (unsigned int i = 0; i < ARRAY_SIZE(aj_raw_fmts); i++)
		if (aj_raw_fmts[i].fourcc == fourcc)
			return &aj_raw_fmts[i];
	return NULL;
}

static enum aj_codec aj_native_codec(const struct aj_fmt *f)
{
	switch (f->hw) {
	case AJ_PIX_YUV444_2P:
		return AJ_CODEC_444;
	case AJ_PIX_YUV420_2P:
		return AJ_CODEC_420;
	default:
		return AJ_CODEC_422;
	}
}

/* ---- hardware ----------------------------------------------------------- */

/*
 * reset_jpeg_block [KEXT13.5]: MODE 0x100, 0x13e, RUN 0, defaults, the
 * per-core tunables (mask 0xff), MODE 0x17f, COMMAND idle, RST_INTERVAL
 * read-back, clear the RST log/partial-decode registers, MODE 0x143.
 */
static int aj_reset(struct apple_jpeg *jpeg)
{
	static const u32 clear[] = {
		0x1dc, 0x1e4, 0x1e8, 0x1ec, 0x1f0, 0x1f8, 0x1fc, 0x200, 0x204,
		0x208, 0x20c, 0x210,
	};
	int n, ret;
	u32 v;

	aj_write(jpeg, AJ_MODE, AJ_MODE_RESET);
	aj_write(jpeg, AJ_MODE, AJ_MODE_SETUP);
	aj_write(jpeg, AJ_RUN, 0);
	n = apple_jpeg_defaults(false, jpeg->writes, ARRAY_SIZE(jpeg->writes));
	if (n < 0)
		return n;
	for (int i = 0; i < n; i++)
		aj_write(jpeg, jpeg->writes[i].offset, jpeg->writes[i].value);
	if (tunables) {
		for (int i = 0; i < APPLE_JPEG_NUM_TUNABLES; i++) {
			const struct apple_jpeg_tunable *t = &apple_jpeg_tunables[jpeg->core][i];

			v = aj_read(jpeg, t->offset);
			aj_write(jpeg, t->offset, (v & ~0xffu) | t->value);
		}
	}
	aj_write(jpeg, AJ_MODE, AJ_MODE_OPEN);
	ret = readl_relaxed_poll_timeout_atomic(jpeg->regs + AJ_COMMAND, v, !v, 1, 10000);
	if (ret)
		return ret;
	aj_write(jpeg, AJ_RST_INTERVAL, 1);
	ret = readl_relaxed_poll_timeout_atomic(jpeg->regs + AJ_RST_INTERVAL, v, v == 1, 1,
						10000);
	if (ret)
		return ret;
	aj_write(jpeg, AJ_RST_INTERVAL, 0);
	for (unsigned int i = 0; i < ARRAY_SIZE(clear); i++)
		aj_write(jpeg, clear[i], 0);
	aj_write(jpeg, AJ_MODE, AJ_MODE_IDLE);
	return 0;
}

/*
 * RadishFunctions::waitForAXI [KEXT13.5]: ctrl 0, wait for no outstanding
 * transactions (10001 polls), ctrl 0x0040000a. Called after an interrupt
 * that did not report completion, before the next reset.
 */
static void aj_axi_drain(struct apple_jpeg *jpeg)
{
	u32 v;

	if (!jpeg->axi || !axi_drain)
		return;
	writel(0, jpeg->axi + AJ_AXI_CTRL);
	if (readl_poll_timeout_atomic(jpeg->axi + AJ_AXI_STATUS, v, !v, 1, 10000))
		dev_err_ratelimited(jpeg->dev, "AXI wrapper: %#x transactions still outstanding\n", v);
	writel(AJ_AXI_CTRL_RUN, jpeg->axi + AJ_AXI_CTRL);
}

/* checkForInterrupt + finish*_gated success rules [KEXT13.5] */
static bool aj_result_ok(bool dec, const struct aj_result *r)
{
	u32 errs = r->status & AJ_STATUS_ERRORS;

	/* a lone macroblock error is ignored when DEBUG bit 2 is set */
	if (errs == AJ_STATUS_MB && (r->debug & BIT(2)))
		errs = 0;
	if (!(r->status & AJ_STATUS_DONE) || errs)
		return false;
	if (r->int_status != AJ_INT_STATUS_GOOD0 && r->int_status != AJ_INT_STATUS_GOOD1)
		return false;
	return !dec || !r->decomp;
}

/* Encoder: insert a DRI segment when the engine wrote restart markers without one */
static void aj_fixup_dri(struct apple_jpeg_ctx *ctx, struct vb2_v4l2_buffer *dst, u32 *bytes)
{
	u32 interval = v4l2_ctrl_g_ctrl(ctx->restart);
	void *vaddr;
	ssize_t n;

	if (!interval)
		return;
	vaddr = dst->vb2_buf.memory == VB2_MEMORY_MMAP ? vb2_plane_vaddr(&dst->vb2_buf, 0) : NULL;
	if (!vaddr) {
		if (!ctx->dri_warned)
			dev_warn(ctx->jpeg->dev, "restart interval set but the CAPTURE buffer has no kernel mapping: DRI not inserted\n");
		ctx->dri_warned = true;
		return;
	}
	n = apple_jpeg_insert_dri(vaddr, *bytes, vb2_plane_size(&dst->vb2_buf, 0), interval);
	if (n < 0) {
		dev_warn_ratelimited(ctx->jpeg->dev, "DRI insertion failed: %zd\n", n);
		return;
	}
	*bytes = n;
}

static void aj_finish(struct apple_jpeg *jpeg, struct apple_jpeg_ctx *ctx, int err,
		      u32 bytes, bool pm_held)
{
	struct v4l2_m2m_ctx *m2m = ctx->fh.m2m_ctx;
	struct vb2_v4l2_buffer *src, *dst;

	src = v4l2_m2m_src_buf_remove(m2m);
	dst = v4l2_m2m_dst_buf_remove(m2m);
	if (src && dst) {
		if (ctx->dec) {
			for (unsigned int i = 0; i < ctx->cap.num_planes; i++)
				vb2_set_plane_payload(&dst->vb2_buf, i,
						      err ? 0 : ctx->cap.plane_fmt[i].sizeimage);
		} else {
			if (!err && (bytes < 4 || bytes > vb2_plane_size(&dst->vb2_buf, 0)))
				err = -EIO;
			if (!err)
				aj_fixup_dri(ctx, dst, &bytes);
			vb2_set_plane_payload(&dst->vb2_buf, 0, err ? 0 : bytes);
		}
		v4l2_m2m_buf_copy_metadata(src, dst);
		dst->sequence = ctx->sequence++;
		dst->flags |= V4L2_BUF_FLAG_KEYFRAME;
		if (v4l2_m2m_is_last_draining_src_buf(m2m, src)) {
			static const struct v4l2_event eos = { .type = V4L2_EVENT_EOS };

			dst->flags |= V4L2_BUF_FLAG_LAST;
			v4l2_event_queue_fh(&ctx->fh, &eos);
			v4l2_m2m_mark_stopped(m2m);
		}
		v4l2_m2m_buf_done(src, err ? VB2_BUF_STATE_ERROR : VB2_BUF_STATE_DONE);
		v4l2_m2m_buf_done(dst, err ? VB2_BUF_STATE_ERROR : VB2_BUF_STATE_DONE);
	}
	if (pm_held) {
		pm_runtime_mark_last_busy(jpeg->dev);
		pm_runtime_put_autosuspend(jpeg->dev);
	}
	v4l2_m2m_job_finish(jpeg->m2m_dev, m2m);
}

/* Hard IRQ: snapshot, acknowledge and quiesce in the kext's order [KEXT13.5] */
static irqreturn_t aj_irq(int irq, void *data)
{
	struct apple_jpeg *jpeg = data;
	struct aj_result r;

	spin_lock(&jpeg->hw_lock);
	if (!jpeg->active) {
		spin_unlock(&jpeg->hw_lock);
		return IRQ_NONE;
	}
	aj_read(jpeg, AJ_CODEC_MODE);
	r.status = aj_read(jpeg, AJ_STATUS);
	r.int_status = aj_read(jpeg, AJ_INT_STATUS);
	r.debug = aj_read(jpeg, AJ_DEBUG);
	if (!r.int_status && !(r.status & (AJ_STATUS_DONE | AJ_STATUS_ERRORS))) {
		spin_unlock(&jpeg->hw_lock);
		return IRQ_NONE;
	}
	aj_write(jpeg, AJ_INT_STATUS, 0);
	aj_write(jpeg, AJ_RUN, 0);
	aj_write(jpeg, AJ_AXI_PREFETCH0, 0);
	aj_write(jpeg, AJ_AXI_PREFETCH1, 0);
	aj_write(jpeg, AJ_IRQ_MASK, 0);
	r.decomp = aj_read(jpeg, AJ_DECOMP_ERROR);
	r.bytes = aj_read(jpeg, AJ_COMPRESSED_BYTES);
	jpeg->res = r;
	jpeg->done = jpeg->active;
	jpeg->active = NULL;
	spin_unlock(&jpeg->hw_lock);
	return IRQ_WAKE_THREAD;
}

static irqreturn_t aj_irq_thread(int irq, void *data)
{
	struct apple_jpeg *jpeg = data;
	struct apple_jpeg_ctx *ctx;
	struct aj_result r;
	int err = 0;

	spin_lock_irq(&jpeg->hw_lock);
	ctx = jpeg->done;
	jpeg->done = NULL;
	r = jpeg->res;
	spin_unlock_irq(&jpeg->hw_lock);
	if (!ctx)
		return IRQ_HANDLED;
	cancel_delayed_work(&jpeg->watchdog);

	if (!aj_result_ok(ctx->dec, &r)) {
		dev_err_ratelimited(jpeg->dev,
				    "%s failed: status %#x int %#x debug %#x decomp %#x\n",
				    ctx->dec ? "decode" : "encode", r.status, r.int_status,
				    r.debug, r.decomp);
		err = -EIO;
	}
	if (!(r.status & AJ_STATUS_DONE))
		aj_axi_drain(jpeg);
	aj_finish(jpeg, ctx, err, r.bytes, true);
	return IRQ_HANDLED;
}

static void aj_watchdog(struct work_struct *work)
{
	struct apple_jpeg *jpeg = container_of(work, struct apple_jpeg, watchdog.work);
	struct apple_jpeg_ctx *ctx;
	unsigned long flags;

	spin_lock_irqsave(&jpeg->hw_lock, flags);
	ctx = jpeg->active;
	jpeg->active = NULL;
	if (ctx) {
		dev_err(jpeg->dev, "job timed out: status %#x int %#x debug %#x\n",
			aj_read(jpeg, AJ_STATUS), aj_read(jpeg, AJ_INT_STATUS),
			aj_read(jpeg, AJ_DEBUG));
		aj_write(jpeg, AJ_RUN, 0);
		aj_write(jpeg, AJ_IRQ_MASK, 0);
		aj_axi_drain(jpeg);
		/* the reset before the next job decides whether the engine recovered */
	}
	spin_unlock_irqrestore(&jpeg->hw_lock, flags);
	if (ctx)
		aj_finish(jpeg, ctx, -ETIMEDOUT, 0, true);
}

static dma_addr_t aj_addr(struct vb2_v4l2_buffer *vb, unsigned int plane)
{
	return vb2_dma_contig_plane_dma_addr(&vb->vb2_buf, plane);
}

/* Last byte of all memory planes, inclusive */
static u64 aj_buf_end(struct vb2_v4l2_buffer *vb)
{
	u64 end = 0;

	for (unsigned int i = 0; i < vb->vb2_buf.num_planes; i++)
		end = max_t(u64, end, aj_addr(vb, i) + vb2_plane_size(&vb->vb2_buf, i) - 1);
	return end;
}

/* Second component plane: own buffer, or after plane 0 in one buffer */
static u64 aj_plane1(struct vb2_v4l2_buffer *vb, const struct aj_fmt *f,
		     const struct v4l2_pix_format_mplane *pix)
{
	if (f->mem_planes == 2)
		return aj_addr(vb, 1);
	return aj_addr(vb, 0) + (u64)pix->plane_fmt[0].bytesperline * pix->height;
}

static u32 aj_stride1(const struct aj_fmt *f, const struct v4l2_pix_format_mplane *pix)
{
	u32 bpl0 = pix->plane_fmt[0].bytesperline;

	if (f->mem_planes == 2)
		return pix->plane_fmt[1].bytesperline;
	return f->hw == AJ_PIX_YUV444_2P ? 2 * bpl0 : bpl0;
}

static int aj_build_enc(struct apple_jpeg_ctx *ctx, struct vb2_v4l2_buffer *src,
			struct vb2_v4l2_buffer *dst, u32 *pixels)
{
	const struct aj_fmt *f = ctx->raw;
	enum aj_codec codec;
	struct apple_jpeg_enc_job job;

	switch (v4l2_ctrl_g_ctrl(ctx->subsampling)) {
	case V4L2_JPEG_CHROMA_SUBSAMPLING_444:
		codec = AJ_CODEC_444;
		break;
	case V4L2_JPEG_CHROMA_SUBSAMPLING_422:
		codec = AJ_CODEC_422;
		break;
	case V4L2_JPEG_CHROMA_SUBSAMPLING_GRAY:
		codec = AJ_CODEC_400;
		break;
	default:
		codec = AJ_CODEC_420;
		break;
	}
	if (!apple_jpeg_enc_supported(codec, f->hw)) {
		dev_warn_ratelimited(ctx->jpeg->dev,
				     "subsampling not available from %p4cc; using the input's\n",
				     &f->fourcc);
		codec = aj_native_codec(f);
	}
	job = (struct apple_jpeg_enc_job){
		.width = ctx->out.width,
		.height = ctx->out.height,
		.codec = codec,
		.fmt = f->hw,
		.yuyv = f->yuyv,
		.stride0 = ctx->out.plane_fmt[0].bytesperline,
		.stride1 = aj_stride1(f, &ctx->out),
		.plane0 = aj_addr(src, 0),
		.plane1 = aj_plane1(src, f, &ctx->out),
		.input_end = aj_buf_end(src),
		.output = aj_addr(dst, 0),
		.output_size = vb2_plane_size(&dst->vb2_buf, 0),
		.quality = v4l2_ctrl_g_ctrl(ctx->quality),
		.restart_interval = v4l2_ctrl_g_ctrl(ctx->restart),
		.prefetch = prefetch_mask & 1,
	};
	*pixels = job.width * job.height;
	return apple_jpeg_build_encode(&job, ctx->jpeg->writes, ARRAY_SIZE(ctx->jpeg->writes));
}

static int aj_build_dec(struct apple_jpeg_ctx *ctx, struct vb2_v4l2_buffer *src,
			struct vb2_v4l2_buffer *dst, u32 *pixels)
{
	const struct aj_fmt *f = ctx->raw;
	u64 in = aj_addr(src, 0);
	u64 last = in + vb2_plane_size(&src->vb2_buf, 0) - 1;
	u32 used = vb2_get_plane_payload(&src->vb2_buf, 0);
	struct apple_jpeg_dec_job job = {
		.width = ctx->hdr.width,
		.height = ctx->hdr.height,
		.codec = ctx->hdr.codec,
		.fmt = f->hw,
		.yuyv = f->yuyv,
		.scale = 1u << v4l2_ctrl_g_ctrl(ctx->scale),
		.stride0 = ctx->cap.plane_fmt[0].bytesperline,
		.stride1 = aj_stride1(f, &ctx->cap),
		.input = in,
		.input_end = min_t(u64, last, (in + used - 1) | 7),
		.plane0 = aj_addr(dst, 0),
		.plane1 = aj_plane1(dst, f, &ctx->cap),
		.output_end = aj_buf_end(dst),
		.prefetch = prefetch_mask & 2,
	};

	*pixels = job.width * job.height;
	return apple_jpeg_build_decode(&job, ctx->jpeg->writes, ARRAY_SIZE(ctx->jpeg->writes));
}

static void aj_fill_dec_cap(struct apple_jpeg_ctx *ctx, struct v4l2_pix_format_mplane *pix,
			    const struct aj_hdr *hdr);

/*
 * Decoder: the next bitstream buffer needs another CAPTURE format. Return
 * one empty CAPTURE buffer flagged LAST, signal the source change and wait
 * for the client to set CAPTURE up again (dev-decoder "dynamic resolution
 * change").
 */
static bool aj_dec_source_change(struct apple_jpeg_ctx *ctx, struct vb2_v4l2_buffer *src)
{
	static const struct v4l2_event ev = {
		.type = V4L2_EVENT_SOURCE_CHANGE,
		.u.src_change.changes = V4L2_EVENT_SRC_CH_RESOLUTION,
	};
	struct aj_hdr *hdr = &aj_to_buf(src)->hdr;
	struct v4l2_pix_format_mplane need = ctx->cap;
	struct vb2_v4l2_buffer *dst;
	bool fits = true;

	aj_fill_dec_cap(ctx, &need, hdr);
	dst = v4l2_m2m_next_dst_buf(ctx->fh.m2m_ctx);
	for (unsigned int i = 0; i < need.num_planes; i++)
		if (vb2_plane_size(&dst->vb2_buf, i) < need.plane_fmt[i].sizeimage)
			fits = false;
	if (fits && need.width == ctx->cap.width && need.height == ctx->cap.height &&
	    need.pixelformat == ctx->cap.pixelformat) {
		ctx->hdr = *hdr;
		return false;
	}
	ctx->hdr = *hdr;
	ctx->cap = need;
	ctx->raw = aj_find_fmt(need.pixelformat);
	ctx->wait_cap = true;
	dst = v4l2_m2m_dst_buf_remove(ctx->fh.m2m_ctx);
	for (unsigned int i = 0; i < dst->vb2_buf.num_planes; i++)
		vb2_set_plane_payload(&dst->vb2_buf, i, 0);
	dst->field = V4L2_FIELD_NONE;
	dst->flags |= V4L2_BUF_FLAG_LAST;
	v4l2_m2m_buf_done(dst, VB2_BUF_STATE_DONE);
	v4l2_event_queue_fh(&ctx->fh, &ev);
	return true;
}

static void aj_device_run(void *priv)
{
	struct apple_jpeg_ctx *ctx = priv;
	struct apple_jpeg *jpeg = ctx->jpeg;
	struct vb2_v4l2_buffer *src, *dst;
	unsigned long flags;
	u32 pixels = 0;
	int n, ret;

	src = v4l2_m2m_next_src_buf(ctx->fh.m2m_ctx);
	dst = v4l2_m2m_next_dst_buf(ctx->fh.m2m_ctx);
	if (ctx->dec) {
		if (!aj_to_buf(src)->hdr.valid) {
			aj_finish(jpeg, ctx, -EINVAL, 0, false);
			return;
		}
		if (aj_dec_source_change(ctx, src)) {
			v4l2_m2m_job_finish(jpeg->m2m_dev, ctx->fh.m2m_ctx);
			return;
		}
	}
	ret = pm_runtime_resume_and_get(jpeg->dev);
	if (ret < 0) {
		aj_finish(jpeg, ctx, ret, 0, false);
		return;
	}

	spin_lock_irqsave(&jpeg->hw_lock, flags);
	ret = jpeg->broken ? -EIO : aj_reset(jpeg);
	if (ret) {
		jpeg->broken = true;
		spin_unlock_irqrestore(&jpeg->hw_lock, flags);
		dev_err_ratelimited(jpeg->dev, "engine reset failed: %d\n", ret);
		aj_finish(jpeg, ctx, -EIO, 0, true);
		return;
	}
	n = ctx->dec ? aj_build_dec(ctx, src, dst, &pixels) : aj_build_enc(ctx, src, dst, &pixels);
	if (n < 0) {
		spin_unlock_irqrestore(&jpeg->hw_lock, flags);
		dev_err_ratelimited(jpeg->dev, "job refused: %d\n", n);
		aj_finish(jpeg, ctx, n, 0, true);
		return;
	}
	jpeg->active = ctx;
	/* Buffers must be visible before the start command, the last write. */
	dma_wmb();
	for (int i = 0; i < n; i++)
		writel(jpeg->writes[i].value, jpeg->regs + jpeg->writes[i].offset);
	spin_unlock_irqrestore(&jpeg->hw_lock, flags);
	/* 2 s plus 1 ms per 10k pixels: the engine's own timeout is cycles [INF] */
	schedule_delayed_work(&jpeg->watchdog, msecs_to_jiffies(2000 + pixels / 10000));
}

static int aj_job_ready(void *priv)
{
	struct apple_jpeg_ctx *ctx = priv;

	return !(ctx->dec && ctx->wait_cap);
}

static const struct v4l2_m2m_ops aj_m2m_ops = {
	.device_run = aj_device_run,
	.job_ready = aj_job_ready,
};

/* ---- formats ------------------------------------------------------------ */

/*
 * Raw planes as the engine reads/writes them (apple_jpeg_plane_sizes),
 * rows aligned to AJ_STRIDE_ALIGN. pad_rows > 1 rounds the allocation up to
 * whole MCU rows (encoder input, as aurora); the decoder writes exactly the
 * image (the kext checks w x h surfaces) [KEXT13.5].
 */
static void aj_fill_raw(struct v4l2_pix_format_mplane *pix, const struct aj_fmt *f,
			u32 w, u32 h, u32 pad_rows)
{
	u32 w0, w1, h1, bpl0, bpl1, rows0, rows1;

	apple_jpeg_plane_sizes(f->hw, w, h, &w0, &w1, &h1);
	bpl0 = ALIGN(w0, AJ_STRIDE_ALIGN);
	bpl1 = f->hw == AJ_PIX_YUV444_2P ? 2 * bpl0 : bpl0;
	rows0 = ALIGN(h, pad_rows);
	rows1 = f->hw == AJ_PIX_YUV420_2P ? rows0 / 2 + (rows0 & 1) : rows0;

	pix->pixelformat = f->fourcc;
	pix->width = w;
	pix->height = h;
	pix->field = V4L2_FIELD_NONE;
	pix->flags = 0;
	memset(pix->plane_fmt, 0, sizeof(pix->plane_fmt));
	memset(pix->reserved, 0, sizeof(pix->reserved));
	pix->plane_fmt[0].bytesperline = bpl0;
	if (f->mem_planes == 2) {
		pix->num_planes = 2;
		pix->plane_fmt[0].sizeimage = bpl0 * rows0;
		pix->plane_fmt[1].bytesperline = bpl1;
		pix->plane_fmt[1].sizeimage = bpl1 * rows1;
	} else {
		pix->num_planes = 1;
		/* one buffer: plane 1 at bpl0 * height (V4L2), the tail is padding */
		pix->plane_fmt[0].sizeimage = bpl0 * rows0 + (h1 ? bpl1 * rows1 : 0);
		if (h1 && rows0 != h)
			pix->plane_fmt[0].sizeimage += bpl0 * (rows0 - h);
	}
	/* JPEG carries full-range BT.601 (JFIF); no range conversion either way */
	pix->colorspace = V4L2_COLORSPACE_JPEG;
	pix->ycbcr_enc = V4L2_YCBCR_ENC_601;
	pix->quantization = V4L2_QUANTIZATION_FULL_RANGE;
	pix->xfer_func = V4L2_XFER_FUNC_SRGB;
}

static void aj_fill_enc_out(struct v4l2_pix_format_mplane *pix)
{
	const struct aj_fmt *f = aj_find_fmt(pix->pixelformat) ?: &aj_raw_fmts[0];
	u32 w = clamp_t(u32, ALIGN(pix->width, 2), AJ_MIN_SIZE, AJ_MAX_SIZE);
	u32 h = clamp_t(u32, pix->height, AJ_MIN_SIZE, AJ_MAX_SIZE);

	if (f->hw == AJ_PIX_YUV420_2P)
		h = ALIGN(h, 2);
	aj_fill_raw(pix, f, w, h, 16);
}

static void aj_fill_enc_cap(struct v4l2_pix_format_mplane *dst,
			    const struct v4l2_pix_format_mplane *src)
{
	*dst = *src;
	dst->pixelformat = V4L2_PIX_FMT_JPEG;
	dst->num_planes = 1;
	memset(dst->plane_fmt, 0, sizeof(dst->plane_fmt));
	/* Worst case at quality 100 plus headers [AURORA] */
	dst->plane_fmt[0].sizeimage = PAGE_ALIGN(src->width * src->height * 3 + SZ_16K);
}

static void aj_fill_dec_out(struct v4l2_pix_format_mplane *pix)
{
	u32 w = pix->width ? clamp_t(u32, pix->width, AJ_DEC_MIN_SIZE, AJ_MAX_SIZE) : 1920;
	u32 h = pix->height ? clamp_t(u32, pix->height, AJ_DEC_MIN_SIZE, AJ_MAX_SIZE) : 1080;
	u32 size = pix->plane_fmt[0].sizeimage;

	if (size < SZ_4K)
		size = PAGE_ALIGN(w * h * 3 / 2 + SZ_64K);
	size = min_t(u32, size, SZ_256M);
	pix->pixelformat = V4L2_PIX_FMT_JPEG;
	pix->width = w;
	pix->height = h;
	pix->field = V4L2_FIELD_NONE;
	pix->num_planes = 1;
	pix->flags = 0;
	memset(pix->plane_fmt, 0, sizeof(pix->plane_fmt));
	memset(pix->reserved, 0, sizeof(pix->reserved));
	pix->plane_fmt[0].sizeimage = size;
	pix->colorspace = V4L2_COLORSPACE_JPEG;
	pix->ycbcr_enc = V4L2_YCBCR_ENC_601;
	pix->quantization = V4L2_QUANTIZATION_FULL_RANGE;
	pix->xfer_func = V4L2_XFER_FUNC_SRGB;
}

static const struct aj_fmt *aj_dec_default_fmt(const struct aj_hdr *hdr)
{
	u32 fourcc = V4L2_PIX_FMT_NV12M;

	if (hdr && hdr->valid) {
		if (hdr->codec == AJ_CODEC_444)
			fourcc = V4L2_PIX_FMT_NV24;
		else if (hdr->codec == AJ_CODEC_422 || hdr->codec == AJ_CODEC_411)
			fourcc = V4L2_PIX_FMT_NV16M;
	}
	return aj_find_fmt(fourcc);
}

/* CAPTURE format for hdr (or the OUTPUT size hint) keeping pix's fourcc if it can */
static void aj_fill_dec_cap(struct apple_jpeg_ctx *ctx, struct v4l2_pix_format_mplane *pix,
			    const struct aj_hdr *hdr)
{
	const struct aj_fmt *f = aj_find_fmt(pix->pixelformat);
	u32 s = 1u << v4l2_ctrl_g_ctrl(ctx->scale);
	u32 w = ctx->out.width, h = ctx->out.height;

	if (hdr && hdr->valid) {
		w = hdr->width;
		h = hdr->height;
		if (f && !apple_jpeg_dec_supported(hdr->codec, f->hw))
			f = NULL;
	}
	if (!f)
		f = aj_dec_default_fmt(hdr);
	aj_fill_raw(pix, f, DIV_ROUND_UP(w, s), DIV_ROUND_UP(h, s), 1);
}

/*
 * Baseline sequential only: SOF0, 8-bit, 1 or 3 components, one
 * interleaved scan; progressive, 12-bit, lossless and arithmetic coding
 * are software on macOS too [KEXT13.5].
 */
static void aj_parse(void *data, size_t len, struct aj_hdr *hdr)
{
	struct v4l2_jpeg_scan_header scan = {};
	struct v4l2_jpeg_header h = { .scan = &scan };

	hdr->valid = false;
	if (!data || len < AJ_DEC_MIN_BYTES)
		return;
	if (v4l2_jpeg_parse_header(data, len, &h) < 0)
		return;
	/* sof.start points at the length; the marker byte precedes it */
	if (!h.sof.start || h.sof.start[-1] != 0xc0 || h.frame.precision != 8)
		return;
	if (h.frame.num_components != 1 && h.frame.num_components != 3)
		return;
	if (scan.num_components != h.frame.num_components)
		return;
	if (h.frame.width > AJ_MAX_SIZE || h.frame.height > AJ_MAX_SIZE)
		return;
	switch (h.frame.subsampling) {
	case V4L2_JPEG_CHROMA_SUBSAMPLING_444:
		hdr->codec = AJ_CODEC_444;
		break;
	case V4L2_JPEG_CHROMA_SUBSAMPLING_422:
		hdr->codec = AJ_CODEC_422;
		break;
	case V4L2_JPEG_CHROMA_SUBSAMPLING_420:
		hdr->codec = AJ_CODEC_420;
		break;
	case V4L2_JPEG_CHROMA_SUBSAMPLING_411:
		hdr->codec = AJ_CODEC_411;
		break;
	case V4L2_JPEG_CHROMA_SUBSAMPLING_GRAY:
		hdr->codec = AJ_CODEC_400;
		break;
	default:
		return;
	}
	hdr->width = h.frame.width;
	hdr->height = h.frame.height;
	hdr->valid = true;
}

static int aj_querycap(struct file *file, void *priv, struct v4l2_capability *cap)
{
	struct apple_jpeg_ctx *ctx = aj_file_to_ctx(file);

	strscpy(cap->driver, AJ_NAME, sizeof(cap->driver));
	snprintf(cap->card, sizeof(cap->card), "Apple JPEG %s (core %u)",
		 ctx->dec ? "decoder" : "encoder", ctx->jpeg->core);
	return 0;
}

static int aj_enum_raw(struct apple_jpeg_ctx *ctx, struct v4l2_fmtdesc *f)
{
	unsigned int n = 0;

	for (unsigned int i = 0; i < ARRAY_SIZE(aj_raw_fmts); i++) {
		const struct aj_fmt *rf = &aj_raw_fmts[i];

		if (ctx->dec && ctx->hdr.valid && !apple_jpeg_dec_supported(ctx->hdr.codec, rf->hw))
			continue;
		if (n++ == f->index) {
			f->pixelformat = rf->fourcc;
			return 0;
		}
	}
	return -EINVAL;
}

static int aj_enum_coded(struct v4l2_fmtdesc *f)
{
	if (f->index)
		return -EINVAL;
	f->pixelformat = V4L2_PIX_FMT_JPEG;
	f->flags = V4L2_FMT_FLAG_COMPRESSED;
	return 0;
}

static int aj_enum_fmt_out(struct file *file, void *priv, struct v4l2_fmtdesc *f)
{
	struct apple_jpeg_ctx *ctx = aj_file_to_ctx(file);

	return ctx->dec ? aj_enum_coded(f) : aj_enum_raw(ctx, f);
}

static int aj_enum_fmt_cap(struct file *file, void *priv, struct v4l2_fmtdesc *f)
{
	struct apple_jpeg_ctx *ctx = aj_file_to_ctx(file);

	return ctx->dec ? aj_enum_raw(ctx, f) : aj_enum_coded(f);
}

static int aj_enum_framesizes(struct file *file, void *priv, struct v4l2_frmsizeenum *fs)
{
	struct apple_jpeg_ctx *ctx = aj_file_to_ctx(file);

	if (fs->index || (fs->pixel_format != V4L2_PIX_FMT_JPEG &&
			  !aj_find_fmt(fs->pixel_format)))
		return -EINVAL;
	fs->type = V4L2_FRMSIZE_TYPE_STEPWISE;
	if (ctx->dec)
		fs->stepwise = (struct v4l2_frmsize_stepwise){
			AJ_DEC_MIN_SIZE, AJ_MAX_SIZE, 1, AJ_DEC_MIN_SIZE, AJ_MAX_SIZE, 1,
		};
	else
		fs->stepwise = (struct v4l2_frmsize_stepwise){
			AJ_MIN_SIZE, AJ_MAX_SIZE, 2, AJ_MIN_SIZE, AJ_MAX_SIZE, 1,
		};
	return 0;
}

static int aj_g_fmt_out(struct file *file, void *priv, struct v4l2_format *f)
{
	f->fmt.pix_mp = aj_file_to_ctx(file)->out;
	return 0;
}

static int aj_g_fmt_cap(struct file *file, void *priv, struct v4l2_format *f)
{
	f->fmt.pix_mp = aj_file_to_ctx(file)->cap;
	return 0;
}

static int aj_try_fmt_out(struct file *file, void *priv, struct v4l2_format *f)
{
	struct apple_jpeg_ctx *ctx = aj_file_to_ctx(file);

	if (ctx->dec)
		aj_fill_dec_out(&f->fmt.pix_mp);
	else
		aj_fill_enc_out(&f->fmt.pix_mp);
	return 0;
}

static int aj_try_fmt_cap(struct file *file, void *priv, struct v4l2_format *f)
{
	struct apple_jpeg_ctx *ctx = aj_file_to_ctx(file);

	if (ctx->dec)
		aj_fill_dec_cap(ctx, &f->fmt.pix_mp, &ctx->hdr);
	else
		aj_fill_enc_cap(&f->fmt.pix_mp, &ctx->out);
	return 0;
}

static int aj_s_fmt_out(struct file *file, void *priv, struct v4l2_format *f)
{
	struct apple_jpeg_ctx *ctx = aj_file_to_ctx(file);
	struct v4l2_m2m_ctx *m2m = ctx->fh.m2m_ctx;

	if (vb2_is_busy(v4l2_m2m_get_src_vq(m2m)))
		return -EBUSY;
	if (ctx->dec) {
		aj_fill_dec_out(&f->fmt.pix_mp);
		ctx->out = f->fmt.pix_mp;
		if (!ctx->hdr.valid && !vb2_is_busy(v4l2_m2m_get_dst_vq(m2m))) {
			aj_fill_dec_cap(ctx, &ctx->cap, NULL);
			ctx->raw = aj_find_fmt(ctx->cap.pixelformat);
		}
		return 0;
	}
	if (vb2_is_busy(v4l2_m2m_get_dst_vq(m2m)))
		return -EBUSY;
	aj_fill_enc_out(&f->fmt.pix_mp);
	ctx->out = f->fmt.pix_mp;
	ctx->raw = aj_find_fmt(ctx->out.pixelformat);
	aj_fill_enc_cap(&ctx->cap, &ctx->out);
	/* follow the input's own subsampling until the client picks another */
	switch (aj_native_codec(ctx->raw)) {
	case AJ_CODEC_444:
		v4l2_ctrl_s_ctrl(ctx->subsampling, V4L2_JPEG_CHROMA_SUBSAMPLING_444);
		break;
	case AJ_CODEC_422:
		v4l2_ctrl_s_ctrl(ctx->subsampling, V4L2_JPEG_CHROMA_SUBSAMPLING_422);
		break;
	default:
		v4l2_ctrl_s_ctrl(ctx->subsampling, V4L2_JPEG_CHROMA_SUBSAMPLING_420);
		break;
	}
	return 0;
}

static int aj_s_fmt_cap(struct file *file, void *priv, struct v4l2_format *f)
{
	struct apple_jpeg_ctx *ctx = aj_file_to_ctx(file);

	if (vb2_is_busy(v4l2_m2m_get_dst_vq(ctx->fh.m2m_ctx)))
		return -EBUSY;
	if (ctx->dec) {
		aj_fill_dec_cap(ctx, &f->fmt.pix_mp, &ctx->hdr);
		ctx->cap = f->fmt.pix_mp;
		ctx->raw = aj_find_fmt(ctx->cap.pixelformat);
	} else {
		aj_fill_enc_cap(&f->fmt.pix_mp, &ctx->out);
		ctx->cap = f->fmt.pix_mp;
	}
	return 0;
}

static int aj_g_selection(struct file *file, void *priv, struct v4l2_selection *s)
{
	struct apple_jpeg_ctx *ctx = aj_file_to_ctx(file);

	if (s->type != V4L2_BUF_TYPE_VIDEO_CAPTURE &&
	    s->type != V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE)
		return -EINVAL;
	switch (s->target) {
	case V4L2_SEL_TGT_COMPOSE:
	case V4L2_SEL_TGT_COMPOSE_DEFAULT:
	case V4L2_SEL_TGT_COMPOSE_BOUNDS:
	case V4L2_SEL_TGT_COMPOSE_PADDED:
		s->r = (struct v4l2_rect){ 0, 0, ctx->cap.width, ctx->cap.height };
		return 0;
	default:
		return -EINVAL;
	}
}

static int aj_subscribe_event(struct v4l2_fh *fh, const struct v4l2_event_subscription *sub)
{
	struct apple_jpeg_ctx *ctx = container_of(fh, struct apple_jpeg_ctx, fh);

	switch (sub->type) {
	case V4L2_EVENT_EOS:
		return v4l2_event_subscribe(fh, sub, 0, NULL);
	case V4L2_EVENT_SOURCE_CHANGE:
		if (ctx->dec)
			return v4l2_src_change_event_subscribe(fh, sub);
		return -EINVAL;
	default:
		return v4l2_ctrl_subscribe_event(fh, sub);
	}
}

#define AJ_COMMON_IOCTLS \
	.vidioc_querycap = aj_querycap, \
	.vidioc_enum_fmt_vid_out = aj_enum_fmt_out, \
	.vidioc_enum_fmt_vid_cap = aj_enum_fmt_cap, \
	.vidioc_enum_framesizes = aj_enum_framesizes, \
	.vidioc_g_fmt_vid_out_mplane = aj_g_fmt_out, \
	.vidioc_g_fmt_vid_cap_mplane = aj_g_fmt_cap, \
	.vidioc_try_fmt_vid_out_mplane = aj_try_fmt_out, \
	.vidioc_try_fmt_vid_cap_mplane = aj_try_fmt_cap, \
	.vidioc_s_fmt_vid_out_mplane = aj_s_fmt_out, \
	.vidioc_s_fmt_vid_cap_mplane = aj_s_fmt_cap, \
	.vidioc_reqbufs = v4l2_m2m_ioctl_reqbufs, \
	.vidioc_querybuf = v4l2_m2m_ioctl_querybuf, \
	.vidioc_qbuf = v4l2_m2m_ioctl_qbuf, \
	.vidioc_dqbuf = v4l2_m2m_ioctl_dqbuf, \
	.vidioc_prepare_buf = v4l2_m2m_ioctl_prepare_buf, \
	.vidioc_create_bufs = v4l2_m2m_ioctl_create_bufs, \
	.vidioc_expbuf = v4l2_m2m_ioctl_expbuf, \
	.vidioc_streamon = v4l2_m2m_ioctl_streamon, \
	.vidioc_streamoff = v4l2_m2m_ioctl_streamoff, \
	.vidioc_subscribe_event = aj_subscribe_event, \
	.vidioc_unsubscribe_event = v4l2_event_unsubscribe

static const struct v4l2_ioctl_ops aj_enc_ioctl_ops = {
	AJ_COMMON_IOCTLS,
	.vidioc_try_encoder_cmd = v4l2_m2m_ioctl_try_encoder_cmd,
	.vidioc_encoder_cmd = v4l2_m2m_ioctl_encoder_cmd,
};

static const struct v4l2_ioctl_ops aj_dec_ioctl_ops = {
	AJ_COMMON_IOCTLS,
	.vidioc_g_selection = aj_g_selection,
	.vidioc_try_decoder_cmd = v4l2_m2m_ioctl_try_decoder_cmd,
	.vidioc_decoder_cmd = v4l2_m2m_ioctl_decoder_cmd,
};

/* ---- queues ------------------------------------------------------------- */

static struct v4l2_pix_format_mplane *aj_q_fmt(struct apple_jpeg_ctx *ctx, u32 type)
{
	return V4L2_TYPE_IS_OUTPUT(type) ? &ctx->out : &ctx->cap;
}

static int aj_queue_setup(struct vb2_queue *q, unsigned int *nbufs, unsigned int *nplanes,
			  unsigned int sizes[], struct device *alloc_devs[])
{
	struct v4l2_pix_format_mplane *pix = aj_q_fmt(vb2_get_drv_priv(q), q->type);

	if (*nplanes) {
		if (*nplanes != pix->num_planes)
			return -EINVAL;
		for (unsigned int i = 0; i < *nplanes; i++)
			if (sizes[i] < pix->plane_fmt[i].sizeimage)
				return -EINVAL;
		return 0;
	}
	*nplanes = pix->num_planes;
	for (unsigned int i = 0; i < *nplanes; i++)
		sizes[i] = pix->plane_fmt[i].sizeimage;
	return 0;
}

static int aj_buf_prepare(struct vb2_buffer *vb)
{
	struct apple_jpeg_ctx *ctx = vb2_get_drv_priv(vb->vb2_queue);
	struct v4l2_pix_format_mplane *pix = aj_q_fmt(ctx, vb->type);
	bool coded_in = ctx->dec && V4L2_TYPE_IS_OUTPUT(vb->type);

	for (unsigned int i = 0; i < pix->num_planes; i++) {
		if (!coded_in && vb2_plane_size(vb, i) < pix->plane_fmt[i].sizeimage)
			return -EINVAL;
		if (vb2_dma_contig_plane_dma_addr(vb, i) & (AJ_STRIDE_ALIGN - 1))
			return -EINVAL;
		if (coded_in)
			continue;
		if (V4L2_TYPE_IS_OUTPUT(vb->type))
			vb2_set_plane_payload(vb, i, pix->plane_fmt[i].sizeimage);
		else
			vb2_set_plane_payload(vb, i, 0);
	}
	if (coded_in) {
		u32 used = vb2_get_plane_payload(vb, 0);

		if (!used || used > vb2_plane_size(vb, 0))
			return -EINVAL;
		aj_parse(vb2_plane_vaddr(vb, 0), used, &aj_to_buf(to_vb2_v4l2_buffer(vb))->hdr);
	}
	return 0;
}

static void aj_buf_queue(struct vb2_buffer *vb)
{
	struct apple_jpeg_ctx *ctx = vb2_get_drv_priv(vb->vb2_queue);
	struct vb2_v4l2_buffer *vbuf = to_vb2_v4l2_buffer(vb);
	struct v4l2_m2m_ctx *m2m = ctx->fh.m2m_ctx;

	if (!V4L2_TYPE_IS_OUTPUT(vb->type) && vb2_is_streaming(vb->vb2_queue) &&
	    v4l2_m2m_dst_buf_is_last(m2m)) {
		for (unsigned int i = 0; i < vb->num_planes; i++)
			vb2_set_plane_payload(vb, i, 0);
		vbuf->field = V4L2_FIELD_NONE;
		v4l2_m2m_last_buffer_done(m2m, vbuf);
		return;
	}
	/*
	 * Decoder initialisation: the first parsable header sets the CAPTURE
	 * format while CAPTURE is not streaming, and the client learns it
	 * from the source change event (dev-decoder "initialization").
	 */
	if (ctx->dec && V4L2_TYPE_IS_OUTPUT(vb->type) && aj_to_buf(vbuf)->hdr.valid &&
	    !vb2_is_streaming(v4l2_m2m_get_dst_vq(m2m))) {
		const struct aj_hdr *h = &aj_to_buf(vbuf)->hdr;

		if (!ctx->hdr.valid || h->width != ctx->hdr.width ||
		    h->height != ctx->hdr.height || h->codec != ctx->hdr.codec) {
			static const struct v4l2_event ev = {
				.type = V4L2_EVENT_SOURCE_CHANGE,
				.u.src_change.changes = V4L2_EVENT_SRC_CH_RESOLUTION,
			};

			ctx->hdr = *h;
			aj_fill_dec_cap(ctx, &ctx->cap, &ctx->hdr);
			ctx->raw = aj_find_fmt(ctx->cap.pixelformat);
			v4l2_event_queue_fh(&ctx->fh, &ev);
		}
	}
	v4l2_m2m_buf_queue(m2m, vbuf);
}

static int aj_start_streaming(struct vb2_queue *q, unsigned int count)
{
	struct apple_jpeg_ctx *ctx = vb2_get_drv_priv(q);

	if (V4L2_TYPE_IS_OUTPUT(q->type))
		ctx->sequence = 0;
	else
		ctx->wait_cap = false;	/* the client has set CAPTURE up (again) */
	v4l2_m2m_update_start_streaming_state(ctx->fh.m2m_ctx, q);
	return 0;
}

static void aj_stop_streaming(struct vb2_queue *q)
{
	struct apple_jpeg_ctx *ctx = vb2_get_drv_priv(q);
	struct vb2_v4l2_buffer *vbuf;

	for (;;) {
		vbuf = V4L2_TYPE_IS_OUTPUT(q->type) ? v4l2_m2m_src_buf_remove(ctx->fh.m2m_ctx) :
						      v4l2_m2m_dst_buf_remove(ctx->fh.m2m_ctx);
		if (!vbuf)
			break;
		v4l2_m2m_buf_done(vbuf, VB2_BUF_STATE_ERROR);
	}
	v4l2_m2m_update_stop_streaming_state(ctx->fh.m2m_ctx, q);
	if (V4L2_TYPE_IS_OUTPUT(q->type) && v4l2_m2m_has_stopped(ctx->fh.m2m_ctx)) {
		static const struct v4l2_event eos = { .type = V4L2_EVENT_EOS };

		v4l2_event_queue_fh(&ctx->fh, &eos);
	}
}

static const struct vb2_ops aj_qops = {
	.queue_setup = aj_queue_setup,
	.buf_prepare = aj_buf_prepare,
	.buf_queue = aj_buf_queue,
	.start_streaming = aj_start_streaming,
	.stop_streaming = aj_stop_streaming,
};

static int aj_init_queue(struct apple_jpeg_ctx *ctx, struct vb2_queue *q, u32 type)
{
	q->type = type;
	q->io_modes = VB2_MMAP | VB2_DMABUF;
	q->drv_priv = ctx;
	q->buf_struct_size = sizeof(struct aj_buf);
	q->ops = &aj_qops;
	q->mem_ops = &vb2_dma_contig_memops;
	q->timestamp_flags = V4L2_BUF_FLAG_TIMESTAMP_COPY;
	q->lock = &ctx->jpeg->lock;
	q->dev = ctx->jpeg->dev;
	return vb2_queue_init(q);
}

static int aj_queue_init(void *priv, struct vb2_queue *src, struct vb2_queue *dst)
{
	int ret = aj_init_queue(priv, src, V4L2_BUF_TYPE_VIDEO_OUTPUT_MPLANE);

	return ret ?: aj_init_queue(priv, dst, V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE);
}

/* ---- file operations ---------------------------------------------------- */

static int aj_s_ctrl(struct v4l2_ctrl *ctrl)
{
	return 0;	/* read when each job is built */
}

static const struct v4l2_ctrl_ops aj_ctrl_ops = {
	.s_ctrl = aj_s_ctrl,
};

static const s64 aj_scales[] = { 1, 2, 4, 8 };

/* DCT-domain downscale while decoding, DCTScaling=1 [LIVE] */
static const struct v4l2_ctrl_config aj_scale_cfg = {
	.ops = &aj_ctrl_ops,
	.id = APPLE_JPEG_CID_DECODE_SCALE,
	.name = "JPEG Decode Downscale",
	.type = V4L2_CTRL_TYPE_INTEGER_MENU,
	.max = ARRAY_SIZE(aj_scales) - 1,
	.def = 0,
	.qmenu_int = aj_scales,
};

static int aj_open(struct file *file)
{
	struct apple_jpeg *jpeg = video_drvdata(file);
	struct video_device *vdev = video_devdata(file);
	struct apple_jpeg_ctx *ctx;
	int ret;

	ctx = kzalloc_obj(*ctx);
	if (!ctx)
		return -ENOMEM;
	ctx->jpeg = jpeg;
	ctx->dec = vdev == &jpeg->dec_vdev;
	v4l2_fh_init(&ctx->fh, vdev);

	v4l2_ctrl_handler_init(&ctx->hdl, 3);
	if (ctx->dec) {
		ctx->scale = v4l2_ctrl_new_custom(&ctx->hdl, &aj_scale_cfg, NULL);
	} else {
		ctx->quality = v4l2_ctrl_new_std(&ctx->hdl, &aj_ctrl_ops,
						 V4L2_CID_JPEG_COMPRESSION_QUALITY, 1, 100, 1, 75);
		ctx->restart = v4l2_ctrl_new_std(&ctx->hdl, &aj_ctrl_ops,
						 V4L2_CID_JPEG_RESTART_INTERVAL, 0, U16_MAX, 1, 0);
		ctx->subsampling = v4l2_ctrl_new_std_menu(&ctx->hdl, &aj_ctrl_ops,
				V4L2_CID_JPEG_CHROMA_SUBSAMPLING,
				V4L2_JPEG_CHROMA_SUBSAMPLING_GRAY,
				BIT(V4L2_JPEG_CHROMA_SUBSAMPLING_411) |
				BIT(V4L2_JPEG_CHROMA_SUBSAMPLING_410),
				V4L2_JPEG_CHROMA_SUBSAMPLING_420);
	}
	if (ctx->hdl.error) {
		ret = ctx->hdl.error;
		goto err_ctrls;
	}
	ctx->fh.ctrl_handler = &ctx->hdl;

	if (ctx->dec) {
		ctx->out.width = 1920;
		ctx->out.height = 1080;
		aj_fill_dec_out(&ctx->out);
		ctx->cap.pixelformat = V4L2_PIX_FMT_NV12M;
		aj_fill_dec_cap(ctx, &ctx->cap, NULL);
		ctx->raw = aj_find_fmt(ctx->cap.pixelformat);
	} else {
		ctx->out.width = 1920;
		ctx->out.height = 1080;
		ctx->out.pixelformat = V4L2_PIX_FMT_NV12M;
		aj_fill_enc_out(&ctx->out);
		ctx->raw = aj_find_fmt(ctx->out.pixelformat);
		aj_fill_enc_cap(&ctx->cap, &ctx->out);
	}

	ctx->fh.m2m_ctx = v4l2_m2m_ctx_init(jpeg->m2m_dev, ctx, aj_queue_init);
	if (IS_ERR(ctx->fh.m2m_ctx)) {
		ret = PTR_ERR(ctx->fh.m2m_ctx);
		goto err_ctrls;
	}
	v4l2_fh_add(&ctx->fh, file);
	return 0;

err_ctrls:
	v4l2_ctrl_handler_free(&ctx->hdl);
	v4l2_fh_exit(&ctx->fh);
	kfree(ctx);
	return ret;
}

static int aj_release(struct file *file)
{
	struct apple_jpeg_ctx *ctx = aj_file_to_ctx(file);
	struct apple_jpeg *jpeg = ctx->jpeg;

	mutex_lock(&jpeg->lock);
	v4l2_m2m_ctx_release(ctx->fh.m2m_ctx);
	mutex_unlock(&jpeg->lock);
	v4l2_ctrl_handler_free(&ctx->hdl);
	v4l2_fh_del(&ctx->fh, file);
	v4l2_fh_exit(&ctx->fh);
	kfree(ctx);
	return 0;
}

static const struct v4l2_file_operations aj_fops = {
	.owner = THIS_MODULE,
	.open = aj_open,
	.release = aj_release,
	.poll = v4l2_m2m_fop_poll,
	.unlocked_ioctl = video_ioctl2,
	.mmap = v4l2_m2m_fop_mmap,
};

/* ---- power management and probe ----------------------------------------- */

static int aj_runtime_suspend(struct device *dev)
{
	return 0;
}

static int aj_runtime_resume(struct device *dev)
{
	struct apple_jpeg *jpeg = dev_get_drvdata(dev);

	/* The power-up state needs the reset before each job, done there. */
	jpeg->broken = false;
	return 0;
}

static int aj_suspend(struct device *dev)
{
	struct apple_jpeg *jpeg = dev_get_drvdata(dev);

	if (jpeg->m2m_dev)
		v4l2_m2m_suspend(jpeg->m2m_dev);
	return pm_runtime_force_suspend(dev);
}

static int aj_resume(struct device *dev)
{
	struct apple_jpeg *jpeg = dev_get_drvdata(dev);
	int ret = pm_runtime_force_resume(dev);

	if (ret)
		return ret;
	if (jpeg->m2m_dev)
		v4l2_m2m_resume(jpeg->m2m_dev);
	return 0;
}

static const struct dev_pm_ops aj_pm_ops = {
	RUNTIME_PM_OPS(aj_runtime_suspend, aj_runtime_resume, NULL)
	SYSTEM_SLEEP_PM_OPS(aj_suspend, aj_resume)
};

static void aj_cleanup(void *data)
{
	struct apple_jpeg *jpeg = data;

	cancel_delayed_work_sync(&jpeg->watchdog);
	if (jpeg->m2m_dev)
		v4l2_m2m_release(jpeg->m2m_dev);
	v4l2_device_unregister(&jpeg->v4l2_dev);
}

/* Returns true to go on to the next stage */
static bool aj_stage(struct apple_jpeg *jpeg, unsigned int stage, const char *what)
{
	dev_info(jpeg->dev, "stage %u: %s\n", stage, what);
	if (step_ms)
		msleep(step_ms);
	if (stage >= stop_after) {
		dev_info(jpeg->dev, "stop_after=%u: stopping here, nothing left running\n",
			 stop_after);
		return false;
	}
	return true;
}

/*
 * Which engine this is, from its physical address within a die: macOS
 * picks the AXI wrapper offsets and tunables the same way
 * (RadishFunctions::setupAXIRegisterOffset) [KEXT13.5].
 */
static int aj_identify_core(struct apple_jpeg *jpeg, struct resource *res, struct resource *axi)
{
	u64 off = res->start & (AJ_DIE_STRIDE - 1);
	static const u32 axi_off[] = { 0xb38, 0xb98 };

	if (off == 0x38d000000ULL)
		jpeg->core = 0;
	else if (off == 0x38d008000ULL)
		jpeg->core = 1;
	else
		return dev_err_probe(jpeg->dev, -ENODEV,
				     "%pR is not jpeg0/jpeg1 of a t602x die\n", res);
	if (axi && ((axi->start & 0xfff) != axi_off[jpeg->core] || resource_size(axi) != 8 ||
		    (axi->start & ~0xfffULL & (AJ_DIE_STRIDE - 1)) != 0x38c000000ULL))
		return dev_err_probe(jpeg->dev, -EINVAL,
				     "axi %pR is not core %u's wrapper pair (0x38c000%03x)\n",
				     axi, jpeg->core, axi_off[jpeg->core]);
	return 0;
}

static int aj_register_vdev(struct apple_jpeg *jpeg, struct video_device *vdev, bool dec)
{
	snprintf(vdev->name, sizeof(vdev->name), "apple-jpeg%u-%s", jpeg->core,
		 dec ? "dec" : "enc");
	vdev->fops = &aj_fops;
	vdev->ioctl_ops = dec ? &aj_dec_ioctl_ops : &aj_enc_ioctl_ops;
	vdev->release = video_device_release_empty;
	vdev->lock = &jpeg->lock;
	vdev->v4l2_dev = &jpeg->v4l2_dev;
	vdev->vfl_dir = VFL_DIR_M2M;
	vdev->device_caps = V4L2_CAP_VIDEO_M2M_MPLANE | V4L2_CAP_STREAMING;
	video_set_drvdata(vdev, jpeg);
	return video_register_device(vdev, VFL_TYPE_VIDEO, -1);
}

static int aj_probe(struct platform_device *pdev)
{
	struct device *dev = &pdev->dev;
	struct resource *res, *axi;
	struct apple_jpeg *jpeg;
	u32 v, mode, dbg, hwrev;
	int ret;

	jpeg = devm_kzalloc(dev, sizeof(*jpeg), GFP_KERNEL);
	if (!jpeg)
		return -ENOMEM;
	jpeg->dev = dev;
	mutex_init(&jpeg->lock);
	spin_lock_init(&jpeg->hw_lock);
	INIT_DELAYED_WORK(&jpeg->watchdog, aj_watchdog);
	platform_set_drvdata(pdev, jpeg);

	/* Stage 1: resources, no hardware access */
	res = platform_get_resource_byname(pdev, IORESOURCE_MEM, "jpeg") ?:
	      platform_get_resource(pdev, IORESOURCE_MEM, 0);
	if (!res || resource_size(res) != APPLE_JPEG_REG_SIZE)
		return dev_err_probe(dev, -EINVAL, "need a 0x4000 \"jpeg\" register window\n");
	axi = platform_get_resource_byname(pdev, IORESOURCE_MEM, "axi");
	ret = aj_identify_core(jpeg, res, axi);
	if (ret)
		return ret;
	jpeg->regs = devm_ioremap_resource(dev, res);
	if (IS_ERR(jpeg->regs))
		return PTR_ERR(jpeg->regs);
	if (axi) {
		/* not requested: the wrapper block is shared by both cores */
		jpeg->axi = devm_ioremap(dev, axi->start, resource_size(axi));
		if (!jpeg->axi)
			return -ENOMEM;
	} else {
		dev_warn(dev, "no \"axi\" register pair: no AXI drain after failed jobs\n");
	}
	if (!device_iommu_mapped(dev))
		return dev_err_probe(dev, -EPROBE_DEFER, "no IOMMU yet\n");
	/*
	 * A second power domain, "perf" (the PMP report entry pmp-jpg), is
	 * optional: attach both with runtime PM links when present [AURORA].
	 */
	if (of_count_phandle_with_args(dev->of_node, "power-domains",
				       "#power-domain-cells") > 1) {
		static const struct dev_pm_domain_attach_data pd_data = {
			.pd_flags = PD_FLAG_DEV_LINK_ON,
		};

		ret = devm_pm_domain_attach_list(dev, &pd_data, &jpeg->pd_list);
		if (ret < 0)
			return dev_err_probe(dev, ret, "failed to attach power domains\n");
	} else if (!dev->pm_domain) {
		return dev_err_probe(dev, -ENODEV, "requires a power domain (ps_jpg)\n");
	}
	/* 64-bit DMA pointers [KEXT13.5] */
	ret = dma_set_mask_and_coherent(dev, DMA_BIT_MASK(64));
	if (ret)
		return ret;
	jpeg->irq = platform_get_irq(pdev, 0);
	if (jpeg->irq < 0)
		return jpeg->irq;
	if (!aj_stage(jpeg, 1, "resources mapped, core identified"))
		return -ENODEV;

	/* Stage 2: power on, read-only */
	pm_runtime_set_autosuspend_delay(dev, 100);
	pm_runtime_use_autosuspend(dev);
	ret = devm_pm_runtime_enable(dev);
	if (ret)
		return ret;
	ret = pm_runtime_resume_and_get(dev);
	if (ret < 0)
		return dev_err_probe(dev, ret, "power on failed\n");
	mode = aj_read(jpeg, AJ_MODE);
	dbg = aj_read(jpeg, AJ_DEBUG);
	dev_info(dev, "core %u powered: MODE %#x DEBUG %#x\n", jpeg->core, mode, dbg);
	if (jpeg->axi)
		dev_info(dev, "AXI wrapper: ctrl %#x outstanding %#x\n",
			 readl(jpeg->axi + AJ_AXI_CTRL), readl(jpeg->axi + AJ_AXI_STATUS));
	if (!aj_stage(jpeg, 2, "power on, read-only reads done"))
		goto stop_put;

	/* Stage 3: identify; MODE must open the identity register first [KEXT13.5] */
	aj_write(jpeg, AJ_MODE, AJ_MODE_IDENTIFY);
	hwrev = aj_read(jpeg, AJ_HWREV);
	if (hwrev != AJ_HWREV_T6020) {
		pm_runtime_put_sync_suspend(dev);
		return dev_err_probe(dev, -ENODEV, "version %#x, expected %#x: refusing\n",
				     hwrev, AJ_HWREV_T6020);
	}
	dev_info(dev, "JPEG codec version %#x\n", hwrev);
	if (!aj_stage(jpeg, 3, "version checked"))
		goto stop_put;

	/* Stage 4: one reset with tunables, and the AXI wrapper if asked */
	if (jpeg->axi && axi_init)
		writel(AJ_AXI_CTRL_RUN, jpeg->axi + AJ_AXI_CTRL);
	spin_lock_irq(&jpeg->hw_lock);
	ret = aj_reset(jpeg);
	spin_unlock_irq(&jpeg->hw_lock);
	if (ret) {
		pm_runtime_put_sync_suspend(dev);
		return dev_err_probe(dev, ret, "reset failed (COMMAND or RST_INTERVAL stuck)\n");
	}
	for (int i = 0; tunables && i < APPLE_JPEG_NUM_TUNABLES; i++) {
		const struct apple_jpeg_tunable *t = &apple_jpeg_tunables[jpeg->core][i];

		v = aj_read(jpeg, t->offset);
		if ((v & 0xff) != t->value)
			dev_warn(dev, "tunable %#x reads %#x, wrote low byte %#x\n",
				 t->offset, v, t->value);
	}
	dev_info(dev, "reset OK, MODE %#x\n", aj_read(jpeg, AJ_MODE));
	pm_runtime_put_sync_suspend(dev);
	if (!aj_stage(jpeg, 4, "reset done"))
		return -ENODEV;

	/* Stage 5: interrupt and V4L2 */
	ret = devm_request_threaded_irq(dev, jpeg->irq, aj_irq, aj_irq_thread, IRQF_ONESHOT,
					dev_name(dev), jpeg);
	if (ret)
		return ret;
	ret = v4l2_device_register(dev, &jpeg->v4l2_dev);
	if (ret)
		return ret;
	ret = devm_add_action_or_reset(dev, aj_cleanup, jpeg);
	if (ret)
		return ret;
	jpeg->m2m_dev = v4l2_m2m_init(&aj_m2m_ops);
	if (IS_ERR(jpeg->m2m_dev)) {
		ret = PTR_ERR(jpeg->m2m_dev);
		jpeg->m2m_dev = NULL;
		return ret;
	}
	if (encoder) {
		ret = aj_register_vdev(jpeg, &jpeg->enc_vdev, false);
		if (ret)
			return ret;
		jpeg->enc_registered = true;
	}
	if (decoder) {
		ret = aj_register_vdev(jpeg, &jpeg->dec_vdev, true);
		if (ret) {
			if (jpeg->enc_registered)
				video_unregister_device(&jpeg->enc_vdev);
			jpeg->enc_registered = false;
			return ret;
		}
		jpeg->dec_registered = true;
	}
	dev_info(dev, "core %u: encoder %s, decoder %s\n", jpeg->core,
		 jpeg->enc_registered ? video_device_node_name(&jpeg->enc_vdev) : "off",
		 jpeg->dec_registered ? video_device_node_name(&jpeg->dec_vdev) : "off");
	aj_stage(jpeg, 5, "ready");
	return 0;

stop_put:
	pm_runtime_put_sync_suspend(dev);
	return -ENODEV;
}

static void aj_remove(struct platform_device *pdev)
{
	struct apple_jpeg *jpeg = platform_get_drvdata(pdev);

	if (jpeg->dec_registered)
		video_unregister_device(&jpeg->dec_vdev);
	if (jpeg->enc_registered)
		video_unregister_device(&jpeg->enc_vdev);
}

static const struct of_device_id aj_of_match[] = {
	{ .compatible = "apple,t6020-jpeg" },
	{ }
};
MODULE_DEVICE_TABLE(of, aj_of_match);

static struct platform_driver aj_driver = {
	.probe = aj_probe,
	.remove = aj_remove,
	.driver = {
		.name = AJ_NAME,
		.of_match_table = aj_of_match,
		.pm = pm_ptr(&aj_pm_ops),
	},
};
module_platform_driver(aj_driver);

MODULE_DESCRIPTION("Apple M2 Pro (t6020) JPEG encoder/decoder (Silicon Bakery, from aurora-silicon's T8140 encoder)");
MODULE_AUTHOR("Ryan Murray <ryan@aurorasilicon.org>");
MODULE_AUTHOR("Silicon Bakery");
MODULE_LICENSE("GPL");
#ifndef APPLE_JPEG_BUNDLED_V4L2_JPEG
/* the kernel's parser (CONFIG_V4L2_JPEG_HELPER); else v4l2-jpeg-bundled.c */
MODULE_SOFTDEP("pre: v4l2-jpeg");
#endif

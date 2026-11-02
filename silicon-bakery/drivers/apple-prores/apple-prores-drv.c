// SPDX-License-Identifier: GPL-2.0-only
/*
 * Apple ProRes engine (APR) on t6020 (M2 Pro): V4L2 memory-to-memory
 * encoder and (experimental) decoder.
 *
 * Forked from aurora-silicon/linux aurora-wip
 * drivers/media/platform/apple/prores/apple-prores-drv.c (GPL-2.0-only,
 * the T8140 encoder; itself based on Acelogic's J700 diagnostic and the m1n1
 * proxyclient ProRes experiment). Changes for t6020, with the provenance
 * labels of apple-prores.h:
 *
 *  - the version 0 descriptor (apple-prores-desc.c) instead of T8140's v1;
 *  - DMA-block tunables from a request_firmware() file
 *    (tools/bakery-prores-tables: AppleProResCTunablesD0_0, 64 writes),
 *    validated by sha256, instead of compiled-in T8140 values; no wrapper
 *    (AXI2AF) tunables, which the 13.5 kext does not have for this core;
 *  - the [KEXT13.5] bring-up order (activateDevice in [KEXT27]), stats
 *    buffer sized from the size registers the tunables set;
 *  - a ring that wraps the way the kext does (offset [23:7], bit 24
 *    toggled at each wrap, a descriptor may straddle the end);
 *  - the kext's cmd-splitter hang check (deferred head write);
 *  - a 1.5 s watchdog and the kext's recovery: drain the SCODEC wrapper's
 *    bulk and LLT transaction limiters, then reset (power-cycle, or the
 *    pmgr reset macOS uses) and reprogram;
 *  - a staged probe (stop_after=, step_ms=) for bring-up without a second
 *    machine, with stage markers at KERN_CRIT so journald writes them to
 *    disk before the next, riskier, step;
 *  - matrices computed in the driver; a decoder on a second video node.
 *
 * Not tested on hardware. docs/prores-port.txt has the bring-up plan.
 */
#include <crypto/sha2.h>
#include <linux/bitfield.h>
#include <linux/delay.h>
#include <linux/dma-mapping.h>
#include <linux/firmware.h>
#include <linux/interrupt.h>
#include <linux/io.h>
#include <linux/iommu.h>
#include <linux/iopoll.h>
#include <linux/module.h>
#include <linux/mutex.h>
#include <linux/of.h>
#include <linux/platform_device.h>
#include <linux/pm_runtime.h>
#include <linux/reset.h>
#include <linux/sizes.h>
#include <linux/slab.h>
#include <linux/spinlock.h>
#include <linux/unaligned.h>
#include <linux/workqueue.h>

#include <media/v4l2-ctrls.h>
#include <media/v4l2-device.h>
#include <media/v4l2-event.h>
#include <media/v4l2-fh.h>
#include <media/v4l2-ioctl.h>
#include <media/v4l2-mem2mem.h>
#include <media/videobuf2-dma-contig.h>

#include "apple-prores.h"
#include "apple-prores-uapi.h"

#define APR_NAME		"apple-prores"
#define APR_MIN_W		16
#define APR_MIN_H		16
#define APR_MAX_W		8192
#define APR_MAX_H		8192
#define APR_MAX_PIXELS		(8192 * 8192)	/* macOS caps at 50-67 MP [LIVE]; HW limit unknown */
#define APR_TIMEOUT_MS		1500		/* [KEXT13.5] timer 0x5dc ms */
#define APR_POLL_MS		4
#define APR_AUTOSUSPEND_MS	500
#define APR_TUNABLES_FW		"apple/prores-13.5-d0.bin"
#define APR_TUNABLES_MAGIC	"APRTUN01"
#define APR_TUNABLES_COUNT	64
#define APR_TUNABLES_DEVID	5	/* "apr,d0" [KEXT13.5] gs_sAPR_DevInfo_Conversion */
/* sha256 of the 64 (offset, mask, value) LE triples of 13.5 22G74's D0_0 */
static const u8 apr_tunables_sha256[SHA256_DIGEST_SIZE] = {
	0x58, 0x2e, 0xcb, 0x1c, 0xef, 0x6c, 0xb8, 0x1a, 0xd7, 0x80, 0x1b, 0x69,
	0x3f, 0xff, 0x53, 0x31, 0x93, 0x8b, 0xe2, 0xbf, 0x0e, 0x1e, 0x79, 0x1a,
	0xaf, 0x5d, 0x85, 0x5d, 0x89, 0x49, 0x8d, 0x8b,
};

/* Job types as the kext's CheckForCmdSplitterHangCondition sees them. */
enum apr_job_type {
	APR_JOB_DECODE = 0,	/* 0, 1: decode YCbCr / RAW */
	APR_JOB_ENCODE = 2,	/* 2, 3: encode YCbCr / RAW */
};

/* ---- module parameters --------------------------------------------------- */

static unsigned int stop_after;
module_param(stop_after, uint, 0444);
MODULE_PARM_DESC(stop_after,
		 "staged bring-up: stop probe after stage N (1 map, 2 power, 3 read-only checks, "
		 "4 tunables file, 5 tunables written, 6 ring/stats/matrices, 7 self-test encode, "
		 "8 video devices); 0 = all");

static unsigned int step_ms;
module_param(step_ms, uint, 0444);
MODULE_PARM_DESC(step_ms, "sleep this long after each stage marker (lets journald write it)");

static bool selftest;
module_param(selftest, bool, 0444);
MODULE_PARM_DESC(selftest, "stage 7: encode one 64x64 frame at probe, polled, before any video node exists");

static int recovery = 1;
module_param(recovery, int, 0644);
MODULE_PARM_DESC(recovery,
		 "after a hung job: 0 refuse further jobs, 1 drain + power-cycle (default), "
		 "2 drain + pmgr reset + power-cycle (macOS's order)");

static bool decoder;
module_param(decoder, bool, 0444);
MODULE_PARM_DESC(decoder, "also register the decoder node (experimental: decode mode value unknown)");

static uint enc_mode = 7;
module_param(enc_mode, uint, 0644);
MODULE_PARM_DESC(enc_mode, "descriptor cmd [11:8] for encodes: 7 (m1n1, M1 Max) or 6 (aurora, T8140)");

static uint enc_passes = 3;
module_param(enc_passes, uint, 0644);
MODULE_PARM_DESC(enc_passes, "descriptor cmd [5:4] (nPass) for encodes");

static uint dec_mode;
module_param(dec_mode, uint, 0644);
MODULE_PARM_DESC(dec_mode, "descriptor cmd [11:8] for decodes (unknown; plugin-supplied on macOS)");

static uint crc_ctl = 3;
module_param(crc_ctl, uint, 0644);
MODULE_PARM_DESC(crc_ctl, "encode descriptor 0x150 [1:0] (ControlCRC)");

static bool tunables_any;
module_param(tunables_any, bool, 0444);
MODULE_PARM_DESC(tunables_any, "accept a well-formed tunables file whose sha256 is not 13.5's D0_0");

static bool id_any;
module_param(id_any, bool, 0444);
MODULE_PARM_DESC(id_any, "accept an unknown ID register value");

static char *tunables_fw = APR_TUNABLES_FW;
module_param(tunables_fw, charp, 0444);
MODULE_PARM_DESC(tunables_fw, "firmware file with the DMA-block tunables (tools/bakery-prores-tables)");

/* ---- formats ----------------------------------------------------------- */

struct apr_fmt {
	u32 fourcc;
	enum apr_input input;
	u8 bytes;	/* per sample */
	bool is444;
	bool alpha;
	bool dec;	/* the decoder can write it */
	const char *desc;	/* V4L2 core does not know all of these */
};

static const struct apr_fmt apr_raw_fmts[] = {
	{ V4L2_PIX_FMT_NV16, APR_INPUT_422_8, 1, false, false, true, "Y/UV 4:2:2" },
	{ V4L2_PIX_FMT_P216, APR_INPUT_422_16, 2, false, false, true, "Y/UV 4:2:2 (16-bit)" },
	{ V4L2_PIX_FMT_NV24, APR_INPUT_444_8, 1, true, false, true, "Y/UV 4:4:4" },
	{ V4L2_PIX_FMT_P416, APR_INPUT_444_16, 2, true, false, true, "Y/UV 4:4:4 (16-bit)" },
	{ V4L2_PIX_FMT_APPLE_NV24A, APR_INPUT_444A_8, 1, true, true, false, "Y/UV/A 4:4:4:4" },
	{ V4L2_PIX_FMT_APPLE_P416A, APR_INPUT_444A_16, 2, true, true, false,
	  "Y/UV/A 4:4:4:4 (16-bit)" },
};

/* ---- device and context ------------------------------------------------ */

struct apr_tunable {
	u32 offset;
	u32 mask;
	u32 value;
};

struct apr_dev {
	struct device *dev;
	void __iomem *regs;
	void __iomem *wrapper;
	struct reset_control *reset;
	int irq;
	bool irq_ready;		/* handler installed: IRQ_ENABLE may be set */

	struct v4l2_device v4l2_dev;
	struct video_device enc_vdev;
	struct video_device dec_vdev;
	bool enc_registered, dec_registered;
	struct v4l2_m2m_dev *m2m_dev;	/* one engine: both nodes share the job queue */
	struct mutex vdev_lock;

	struct apr_tunable *tun;
	unsigned int ntun;
	u32 qm_luma[APR_QTABLES][32];
	u32 qm_chroma[APR_QTABLES][32];
	u32 id;
	int version;

	u8 *ring;
	dma_addr_t ring_dma;
	void *stats;
	dma_addr_t stats_dma;
	size_t stats_size;

	spinlock_t hw_lock;	/* protects the fields below and the ring */
	struct apr_ctx *active;	/* job in the engine, or NULL */
	enum apr_job_type active_type;
	u32 head;		/* producer pointer as the HEAD register encodes it */
	u32 tail_seen;		/* TAIL at the last completion */
	unsigned int inflight;
	bool head_deferred;	/* cmd-splitter workaround: HEAD not written yet */
	bool ring_ready;	/* programmed since power-up */
	bool broken;
	unsigned long started;
	struct delayed_work watchdog;
	u16 frame_id;
};

struct apr_ctx {
	struct v4l2_fh fh;
	struct apr_dev *apr;
	bool is_dec;
	struct v4l2_ctrl_handler hdl;
	struct v4l2_ctrl *profile;
	struct v4l2_ctrl *target_bytes;
	struct v4l2_ctrl *max_bytes;
	struct v4l2_ctrl *quant_index;
	struct v4l2_pix_format_mplane src_fmt;	/* OUTPUT queue */
	struct v4l2_pix_format_mplane dst_fmt;	/* CAPTURE queue */
	const struct apr_fmt *raw;		/* enc: OUTPUT, dec: CAPTURE */
	enum apr_profile stream_profile;
	u32 sequence;
};

static struct apr_ctx *apr_file_to_ctx(struct file *file)
{
	return container_of(file_to_v4l2_fh(file), struct apr_ctx, fh);
}

static void apr_write(struct apr_dev *apr, u32 reg, u32 val)
{
	writel_relaxed(val, apr->regs + reg);
}

static u32 apr_read(struct apr_dev *apr, u32 reg)
{
	return readl_relaxed(apr->regs + reg);
}

/* ---- staged bring-up --------------------------------------------------- */

/*
 * A stage marker. During a staged bring-up (stop_after or step_ms set) it is
 * printed at KERN_CRIT: journald syncs CRIT and above to disk at once, so
 * after a hard hang and reboot "journalctl -k -b -1" ends at the stage that
 * was running. Then sleep step_ms so the write can finish.
 */
static void apr_stage(struct apr_dev *apr, unsigned int n, const char *what)
{
	if (stop_after || step_ms)
		dev_crit(apr->dev, "stage %u: %s\n", n, what);
	else
		dev_dbg(apr->dev, "stage %u: %s\n", n, what);
	if (step_ms)
		msleep(step_ms);
}

static bool apr_stop_here(struct apr_dev *apr, unsigned int n)
{
	if (stop_after && n >= stop_after) {
		dev_crit(apr->dev, "stop_after=%u: stopping after stage %u\n", stop_after, n);
		return true;
	}
	return false;
}

/* ---- tunables ---------------------------------------------------------- */

static int apr_load_tunables(struct apr_dev *apr)
{
	const struct firmware *fw;
	u8 digest[SHA256_DIGEST_SIZE];
	const u8 *p;
	u32 n, devid;
	unsigned int i;
	int ret;

	ret = request_firmware(&fw, tunables_fw, apr->dev);
	if (ret)
		return dev_err_probe(apr->dev, ret,
				     "no %s: run tools/bakery-prores-tables on macOS and install it\n",
				     tunables_fw);
	ret = -EINVAL;
	if (fw->size < 0x18 || memcmp(fw->data, APR_TUNABLES_MAGIC, 8)) {
		dev_err(apr->dev, "%s: not an APRTUN01 file\n", tunables_fw);
		goto out;
	}
	n = get_unaligned_le32(fw->data + 8);
	devid = get_unaligned_le32(fw->data + 12);
	if (n != APR_TUNABLES_COUNT || devid != APR_TUNABLES_DEVID ||
	    fw->size != 0x18 + 12 * (size_t)n) {
		dev_err(apr->dev, "%s: %u entries for DevID %u, expected %u for DevID %u\n",
			tunables_fw, n, devid, APR_TUNABLES_COUNT, APR_TUNABLES_DEVID);
		goto out;
	}
	p = fw->data + 0x18;
	sha256(p, 12 * n, digest);
	if (memcmp(digest, apr_tunables_sha256, sizeof(digest))) {
		if (!tunables_any) {
			dev_err(apr->dev, "%s: table sha256 %*phN is not 13.5's D0_0 (tunables_any=1 to force)\n",
				tunables_fw, 8, digest);
			goto out;
		}
		dev_warn(apr->dev, "%s: not 13.5's D0_0 table; using it anyway\n", tunables_fw);
	}
	apr->tun = devm_kcalloc(apr->dev, n, sizeof(*apr->tun), GFP_KERNEL);
	if (!apr->tun) {
		ret = -ENOMEM;
		goto out;
	}
	for (i = 0; i < n; i++) {
		struct apr_tunable *t = &apr->tun[i];

		t->offset = get_unaligned_le32(p + 12 * i);
		t->mask = get_unaligned_le32(p + 12 * i + 4);
		t->value = get_unaligned_le32(p + 12 * i + 8);
		/* Never let a file write the ring, IRQ or matrix registers. */
		if (t->offset & 3 || t->offset >= APR_TUNABLE_LIMIT ||
		    t->value & ~t->mask ||
		    (t->offset >= APR_REG_IRQ_ENABLE && t->offset <= APR_REG_RING_TAIL)) {
			dev_err(apr->dev, "%s[%u]: %#x %#x/%#x is not a DMA-block field write\n",
				tunables_fw, i, t->offset, t->mask, t->value);
			goto out;
		}
	}
	apr->ntun = n;
	ret = 0;
	dev_info(apr->dev, "%s: %u tunables, %#x..%#x\n", tunables_fw, n,
		 apr->tun[0].offset, apr->tun[n - 1].offset);
out:
	release_firmware(fw);
	return ret;
}

/* ---- hardware ---------------------------------------------------------- */

/* [KEXT13.5] gs_sAPR_DevVersion_Conversion: ID register -> version. */
static int apr_version(u32 id)
{
	static const u32 ids[] = {
		0x10000, 0x10001, 0x20000, 0x30000, 0x30008, 0x30011, 0x30014,
		0x40000, 0x40002,
	};
	unsigned int i;

	for (i = 0; i < ARRAY_SIZE(ids); i++)
		if (ids[i] == id)
			return i;
	return -1;
}

static void apr_apply_tunables(struct apr_dev *apr)
{
	unsigned int i;

	for (i = 0; i < apr->ntun; i++) {
		const struct apr_tunable *t = &apr->tun[i];
		u32 v = readl_relaxed(apr->regs + t->offset);

		writel_relaxed((v & ~t->mask) | t->value, apr->regs + t->offset);
	}
}

/*
 * Program the engine from power-up state, [KEXT27] activateDevice's order:
 * MODE=0, tunables, ring, stats, MODE=0xd, IRQ enable, matrices, DC scale.
 * The ring pointers are zeroed while MODE is 0 (as m1n1 does) so a block
 * that kept power cannot fetch stale descriptors. Called with hw_lock held.
 */
static void apr_hw_init(struct apr_dev *apr)
{
	unsigned int t, i;

	apr_write(apr, APR_REG_MODE, APR_MODE_OFF);
	apr_write(apr, APR_REG_IRQ_ENABLE, 0);
	apr_apply_tunables(apr);
	apr_write(apr, APR_REG_RING_HEAD, 0);
	apr_write(apr, APR_REG_RING_TAIL, 0);
	apr_write(apr, APR_REG_RING_SIZE, APR_RING_BYTES);
	apr_write(apr, APR_REG_RING_LO, lower_32_bits(apr->ring_dma) & 0xffffff80);
	apr_write(apr, APR_REG_RING_HI, upper_32_bits(apr->ring_dma) & 0x3ff);
	if (apr->stats) {
		apr_write(apr, APR_REG_STATS0_LO, lower_32_bits(apr->stats_dma) & ~0x3fU);
		apr_write(apr, APR_REG_STATS0_HI, upper_32_bits(apr->stats_dma) & 0x3ff);
		apr_write(apr, APR_REG_STATS1_LO, lower_32_bits(apr->stats_dma) & ~0x3fU);
		apr_write(apr, APR_REG_STATS1_HI, upper_32_bits(apr->stats_dma) & 0x3ff);
	}
	apr_write(apr, APR_REG_MODE, APR_MODE_RUN);
	apr_write(apr, APR_REG_IRQ_STATUS, apr_read(apr, APR_REG_IRQ_STATUS));
	apr_write(apr, APR_REG_IRQ_ENABLE, apr->irq_ready ? APR_IRQ_DONE | APR_IRQ_ERROR : 0);
	for (t = 0; t < APR_QTABLES; t++) {
		for (i = 0; i < 32; i++) {
			apr_write(apr, APR_REG_QUANT_LUMA(t) + 4 * i, apr->qm_luma[t][i]);
			apr_write(apr, APR_REG_QUANT_CHROMA(t) + 4 * i, apr->qm_chroma[t][i]);
		}
	}
	for (i = 0; i < APR_DC_SCALE_ENTRIES; i++)
		apr_write(apr, APR_REG_DC_SCALE(i), apr_dc_scale_reg(i));
	wmb();	/* setup before any descriptor publication */
	apr->head = 0;
	apr->tail_seen = 0;
	apr->inflight = 0;
	apr->head_deferred = false;
	apr->ring_ready = true;
}

/*
 * [KEXT13.5] CheckForCmdSplitterHangCondition, on the "apr,d0" core (DevID
 * 4..13 need it): with exactly one job queued, a new job of the same class
 * as that one (encode after encode or decode after decode) must not move
 * HEAD while TAIL already equals HEAD (the queued job has been fetched and
 * is running). The kext then defers the HEAD write to the completion
 * interrupt; once deferred, every later HEAD write is deferred too until
 * then. This driver runs one job at a time, so inflight is 0 at every
 * submission and the condition cannot hold; it is kept for queueing.
 */
static bool apr_cmd_splitter_defer(struct apr_dev *apr, enum apr_job_type type)
{
	if (apr->head_deferred)
		return true;
	if (apr->inflight != 1)
		return false;
	if ((type > 1) != (apr->active_type < 2))
		return apr_read(apr, APR_REG_RING_TAIL) == apr->head;
	return false;
}

/* Copy a descriptor to the ring, wrapping like the kext. hw_lock held. */
static void apr_submit(struct apr_dev *apr, const u8 *desc, u32 len, enum apr_job_type type)
{
	u32 off = apr->head & APR_RING_OFF_MASK;
	u32 first = min(len, APR_RING_BYTES - off);
	u32 next = off + len, head;
	bool defer;

	memcpy(apr->ring + off, desc, first);
	if (first < len)
		memcpy(apr->ring, desc + first, len - first);
	if (next >= APR_RING_BYTES)
		head = ((next - APR_RING_BYTES) & APR_RING_OFF_MASK) |
		       ((apr->head & APR_RING_WRAP) ^ APR_RING_WRAP);
	else
		head = (next & APR_RING_OFF_MASK) | (apr->head & APR_RING_WRAP);

	defer = apr_cmd_splitter_defer(apr, type);
	apr->head = head;
	apr->active_type = type;
	apr->inflight++;
	/* Descriptor and buffers must be visible before the head moves. */
	dma_wmb();
	if (defer) {
		apr->head_deferred = true;
		dev_dbg(apr->dev, "cmd-splitter: HEAD %#x deferred\n", head);
	} else {
		writel(head, apr->regs + APR_REG_RING_HEAD);
	}
}

/*
 * Stop the engine's fabric traffic before a reset: [KEXT13.5]
 * quiesceHWBulkTraffic and quiesceHWLLTTraffic for the SCODEC-attached
 * core. Each limiter: write 0, wait up to 50 ms for outstanding reads, write
 * 0 again, wait for outstanding writes.
 */
static void apr_drain(struct apr_dev *apr, u32 ctl, u32 sts, const char *name)
{
	u32 v;

	writel(0, apr->wrapper + ctl);
	if (readl_poll_timeout(apr->wrapper + sts, v, !(v & APR_WRAP_RD_OUT), 1000, 50000))
		dev_err(apr->dev, "%s: %lu reads still outstanding\n", name,
			FIELD_GET(APR_WRAP_RD_OUT, v));
	writel(0, apr->wrapper + ctl);
	if (readl_poll_timeout(apr->wrapper + sts, v, !(v & APR_WRAP_WR_OUT), 1000, 50000))
		dev_err(apr->dev, "%s: %lu writes still outstanding\n", name,
			FIELD_GET(APR_WRAP_WR_OUT, v));
}

static void apr_quiesce(struct apr_dev *apr)
{
	apr_drain(apr, APR_WRAP_BULK0, APR_WRAP_BULK0, "bulk0");
	apr_drain(apr, APR_WRAP_BULK1, APR_WRAP_BULK1, "bulk1");
	apr_drain(apr, APR_WRAP_LLT_CTL, APR_WRAP_LLT_STS, "llt");
}

/* ---- colour ------------------------------------------------------------ */

static u32 apr_coded_size(u32 width, u32 height, bool is444, bool alpha)
{
	/* Worst case for 4444 XQ at the lowest quantiser, plus headers. */
	u64 size = (u64)ALIGN(width, 16) * ALIGN(height, 16) * (is444 ? 4 : 3) + SZ_64K;

	if (alpha)
		size += (u64)ALIGN(width, 16) * ALIGN(height, 16) * 2;
	return min_t(u64, PAGE_ALIGN(size), SZ_512M);
}

static u8 apr_color_primaries(const struct v4l2_pix_format_mplane *f)
{
	switch (f->colorspace) {
	case V4L2_COLORSPACE_REC709:
	case V4L2_COLORSPACE_SRGB:
		return 1;
	case V4L2_COLORSPACE_SMPTE170M:
		return 6;
	case V4L2_COLORSPACE_470_SYSTEM_BG:
		return 5;
	case V4L2_COLORSPACE_BT2020:
		return 9;
	case V4L2_COLORSPACE_DCI_P3:
		return 11;
	default:
		return 2;
	}
}

static u8 apr_color_transfer(const struct v4l2_pix_format_mplane *f)
{
	switch (f->xfer_func) {
	case V4L2_XFER_FUNC_709:
		return 1;
	case V4L2_XFER_FUNC_SMPTE2084:
		return 16;
	default:
		return f->colorspace == V4L2_COLORSPACE_REC709 ? 1 : 2;
	}
}

static u8 apr_color_matrix(const struct v4l2_pix_format_mplane *f)
{
	switch (f->ycbcr_enc) {
	case V4L2_YCBCR_ENC_709:
		return 1;
	case V4L2_YCBCR_ENC_601:
		return 6;
	case V4L2_YCBCR_ENC_BT2020:
		return 9;
	default:
		return f->colorspace == V4L2_COLORSPACE_REC709 ? 1 : 2;
	}
}

static void apr_knobs(struct apr_cmd_knobs *k)
{
	k->enc_mode = enc_mode & 0xf;
	k->enc_passes = enc_passes & 3;
	k->dec_mode = dec_mode & 0xf;
	k->crc_ctl = crc_ctl & 3;
}

/* ---- jobs -------------------------------------------------------------- */

static u32 apr_raw_stride(const struct v4l2_pix_format_mplane *pix)
{
	return pix->plane_fmt[0].bytesperline;
}

static int apr_build_job(struct apr_ctx *ctx, struct vb2_v4l2_buffer *src,
			 struct vb2_v4l2_buffer *dst, u16 fid, u8 *desc, u32 *len)
{
	struct apr_cmd_knobs k;

	apr_knobs(&k);
	if (!ctx->is_dec) {
		const struct v4l2_pix_format_mplane *s = &ctx->src_fmt;
		u32 ls = apr_raw_stride(s), cs = ls * (ctx->raw->is444 ? 2 : 1);
		u32 rows = ALIGN(s->height, 16);
		dma_addr_t in = vb2_dma_contig_plane_dma_addr(&src->vb2_buf, 0);
		struct apr_frame f = {
			.width = s->width,
			.height = s->height,
			.input = ctx->raw->input,
			.profile = ctx->stream_profile,
			.luma_stride = ls,
			.chroma_stride = cs,
			.alpha_stride = ctx->raw->alpha ? ls : 0,
			.luma = in,
			.chroma = in + (u64)ls * rows,
			.alpha = ctx->raw->alpha ? in + (u64)(ls + cs) * rows : 0,
			.output = vb2_dma_contig_plane_dma_addr(&dst->vb2_buf, 0),
			.output_size = vb2_plane_size(&dst->vb2_buf, 0),
			.target_bytes = v4l2_ctrl_g_ctrl(ctx->target_bytes),
			.max_bytes = v4l2_ctrl_g_ctrl(ctx->max_bytes),
			.quant_index = v4l2_ctrl_g_ctrl(ctx->quant_index),
			.frame_id = fid,
			.primaries = apr_color_primaries(s),
			.transfer = apr_color_transfer(s),
			.matrix = apr_color_matrix(s),
		};

		*len = APR_ENC_DESC_BYTES;
		return apr_build_enc_desc(&f, &k, desc);
	} else {
		const struct v4l2_pix_format_mplane *d = &ctx->dst_fmt;
		u32 ls = apr_raw_stride(d), cs = ls * (ctx->raw->is444 ? 2 : 1);
		dma_addr_t out = vb2_dma_contig_plane_dma_addr(&dst->vb2_buf, 0);
		const u8 *in = vb2_plane_vaddr(&src->vb2_buf, 0);
		u32 payload = vb2_get_plane_payload(&src->vb2_buf, 0);
		struct apr_frame_info fi;
		struct apr_dec_frame f = {
			.width = d->width,
			.height = d->height,
			.is444 = ctx->raw->is444,
			.deep = ctx->raw->bytes == 2,
			.luma_stride = ls,
			.chroma_stride = cs,
			.input = vb2_dma_contig_plane_dma_addr(&src->vb2_buf, 0),
			.luma = out,
			.chroma = out + (u64)ls * ALIGN(d->height, 16),
			.frame_id = fid,
		};

		/* The engine parses the frame; check it is the one configured. */
		if (!in || apr_parse_frame_header(in, payload, &fi))
			return -EINVAL;
		if (fi.width != d->width || fi.height != d->height || fi.interlace ||
		    (fi.chroma_format == 3) != ctx->raw->is444)
			return -EINVAL;
		f.input_size = fi.frame_size;
		*len = APR_DEC_DESC_BYTES;
		return apr_build_dec_desc(&f, &k, desc);
	}
}

static void apr_finish_job(struct apr_dev *apr, struct apr_ctx *ctx, int err,
			   bool power_cycle)
{
	struct v4l2_m2m_ctx *m2m = ctx->fh.m2m_ctx;
	struct vb2_v4l2_buffer *src, *dst;
	u32 bytes = 0;

	src = v4l2_m2m_src_buf_remove(m2m);
	dst = v4l2_m2m_dst_buf_remove(m2m);
	if (WARN_ON(!src || !dst))
		goto out;

	if (!err && !ctx->is_dec) {
		u8 *out = vb2_plane_vaddr(&dst->vb2_buf, 0);

		dma_rmb();
		err = out ? apr_check_output(out, vb2_plane_size(&dst->vb2_buf, 0), &bytes) : -EIO;
		if (err)
			dev_err_ratelimited(apr->dev, "engine returned no frame\n");
	} else if (!err) {
		bytes = ctx->dst_fmt.plane_fmt[0].sizeimage;
	}
	vb2_set_plane_payload(&dst->vb2_buf, 0, err ? 0 : bytes);
	v4l2_m2m_buf_copy_metadata(src, dst);
	dst->sequence = ctx->sequence++;
	if (!ctx->is_dec)
		dst->flags |= V4L2_BUF_FLAG_KEYFRAME;
	if (v4l2_m2m_is_last_draining_src_buf(m2m, src)) {
		static const struct v4l2_event eos = { .type = V4L2_EVENT_EOS };

		dst->flags |= V4L2_BUF_FLAG_LAST;
		v4l2_event_queue_fh(&ctx->fh, &eos);
		v4l2_m2m_mark_stopped(m2m);
	}
	v4l2_m2m_buf_done(src, err ? VB2_BUF_STATE_ERROR : VB2_BUF_STATE_DONE);
	v4l2_m2m_buf_done(dst, err ? VB2_BUF_STATE_ERROR : VB2_BUF_STATE_DONE);
out:
	if (power_cycle) {
		/* Drop the job's reference now and let the domain go off. */
		pm_runtime_put_sync_suspend(apr->dev);
		if (!pm_runtime_status_suspended(apr->dev))
			dev_warn(apr->dev, "recovery: the engine did not suspend; next job re-initialises a powered block\n");
	} else {
		pm_runtime_mark_last_busy(apr->dev);
		pm_runtime_put_autosuspend(apr->dev);
	}
	v4l2_m2m_job_finish(apr->m2m_dev, m2m);
}

/* Claim the active job if the engine has finished it. hw_lock held. */
static struct apr_ctx *apr_take_done(struct apr_dev *apr, int *err)
{
	struct apr_ctx *ctx = apr->active;
	u32 status, tail, st0, st1, st2, sten;

	status = apr_read(apr, APR_REG_IRQ_STATUS);
	if (!(status & (APR_IRQ_DONE | APR_IRQ_ERROR)))
		return NULL;
	/* [KEXT13.5] interruptHandler: deferred HEAD first, then clear. */
	if (apr->head_deferred) {
		writel(apr->head, apr->regs + APR_REG_RING_HEAD);
		apr->head_deferred = false;
	}
	st0 = apr_read(apr, APR_REG_ST0);
	st1 = apr_read(apr, APR_REG_ST1);
	st2 = apr_read(apr, APR_REG_ST2);
	sten = apr_read(apr, apr->active_type == APR_JOB_ENCODE ? APR_REG_ST_ENC : APR_REG_ST_DEC);
	apr_write(apr, APR_REG_IRQ_STATUS, status);
	tail = apr_read(apr, APR_REG_RING_TAIL);
	apr->tail_seen = tail;
	if (!ctx) {
		dev_warn_ratelimited(apr->dev, "completion without a job: status %#x\n", status);
		return NULL;
	}
	if (apr->inflight)
		apr->inflight--;
	*err = 0;
	if (status & APR_IRQ_ERROR) {
		dev_err_ratelimited(apr->dev,
				    "job failed (%s): status %#x st0 %#x st1 %#x st2 %#x (%s) res %#x tail %#x head %#x\n",
				    apr->active_type == APR_JOB_ENCODE ? "encode" : "decode",
				    status, st0, st1, st2,
				    (st2 & 3) == 1 ? "class 5/6" : "class 1/2", sten, tail, apr->head);
		*err = -EIO;
	} else {
		dev_dbg(apr->dev, "job done: st0 %#x (flag30 %u) st1 %#x st2 %#x res %#x tail %#x\n",
			st0, (st0 >> 30) & 1, st1, st2, sten, tail);
	}
	apr->active = NULL;
	return ctx;
}

static irqreturn_t apr_irq(int irq, void *data)
{
	struct apr_dev *apr = data;
	struct apr_ctx *ctx;
	int err = 0;
	u32 status;

	spin_lock(&apr->hw_lock);
	status = apr_read(apr, APR_REG_IRQ_STATUS);
	ctx = apr_take_done(apr, &err);
	spin_unlock(&apr->hw_lock);
	if (!ctx)
		return status & (APR_IRQ_DONE | APR_IRQ_ERROR) ? IRQ_HANDLED : IRQ_NONE;
	cancel_delayed_work(&apr->watchdog);
	apr_finish_job(apr, ctx, err, false);
	return IRQ_HANDLED;
}

static void apr_watchdog(struct work_struct *work)
{
	struct apr_dev *apr = container_of(work, struct apr_dev, watchdog.work);
	struct apr_ctx *ctx;
	unsigned long flags;
	int err = 0;

	spin_lock_irqsave(&apr->hw_lock, flags);
	ctx = apr_take_done(apr, &err);
	if (ctx) {
		spin_unlock_irqrestore(&apr->hw_lock, flags);
		dev_warn_once(apr->dev, "completion found without an interrupt\n");
		apr_finish_job(apr, ctx, err, false);
		return;
	}
	ctx = apr->active;
	if (!ctx) {
		spin_unlock_irqrestore(&apr->hw_lock, flags);
		return;
	}
	if (time_before(jiffies, apr->started + msecs_to_jiffies(APR_TIMEOUT_MS))) {
		spin_unlock_irqrestore(&apr->hw_lock, flags);
		schedule_delayed_work(&apr->watchdog, msecs_to_jiffies(APR_POLL_MS));
		return;
	}
	dev_err(apr->dev, "job hung: head %#x tail %#x st0 %#x st1 %#x st2 %#x mode %#x\n",
		apr->head, apr_read(apr, APR_REG_RING_TAIL), apr_read(apr, APR_REG_ST0),
		apr_read(apr, APR_REG_ST1), apr_read(apr, APR_REG_ST2),
		apr_read(apr, APR_REG_MODE));
	apr->active = NULL;
	apr->inflight = 0;
	apr->head_deferred = false;
	apr->ring_ready = false;
	apr_write(apr, APR_REG_IRQ_ENABLE, 0);
	spin_unlock_irqrestore(&apr->hw_lock, flags);

	if (recovery <= 0) {
		dev_err(apr->dev, "recovery=0: refusing further jobs\n");
		spin_lock_irqsave(&apr->hw_lock, flags);
		apr->broken = true;
		spin_unlock_irqrestore(&apr->hw_lock, flags);
		apr_finish_job(apr, ctx, -ETIMEDOUT, false);
		return;
	}
	apr_quiesce(apr);
	apr_write(apr, APR_REG_MODE, APR_MODE_OFF);
	if (recovery >= 2 && apr->reset) {
		/* function-device_reset: assert, 1 ms, deassert [KEXT13.5] */
		if (reset_control_assert(apr->reset) == 0) {
			usleep_range(1000, 2000);
			reset_control_deassert(apr->reset);
		}
	}
	dev_warn(apr->dev, "recovery: drained, power-cycling the engine\n");
	apr_finish_job(apr, ctx, -ETIMEDOUT, true);
}

static void apr_device_run(void *priv)
{
	struct apr_ctx *ctx = priv;
	struct apr_dev *apr = ctx->apr;
	struct vb2_v4l2_buffer *src, *dst;
	u8 desc[APR_ENC_DESC_BYTES];
	unsigned long flags;
	void *out;
	u32 len;
	u16 fid;
	int ret;

	src = v4l2_m2m_next_src_buf(ctx->fh.m2m_ctx);
	dst = v4l2_m2m_next_dst_buf(ctx->fh.m2m_ctx);

	ret = pm_runtime_resume_and_get(apr->dev);
	if (ret < 0) {
		pm_runtime_get_noresume(apr->dev);
		apr_finish_job(apr, ctx, ret, false);
		return;
	}
	fid = apr->frame_id++;
	ret = apr_build_job(ctx, src, dst, fid, desc, &len);
	if (ret) {
		apr_finish_job(apr, ctx, ret, false);
		return;
	}
	if (!ctx->is_dec) {
		/* Mark the output invalid so a frame the engine never wrote is caught. */
		out = vb2_plane_vaddr(&dst->vb2_buf, 0);
		if (!out) {
			apr_finish_job(apr, ctx, -EINVAL, false);
			return;
		}
		memset(out, 0, 8);
	}

	spin_lock_irqsave(&apr->hw_lock, flags);
	if (apr->broken) {
		spin_unlock_irqrestore(&apr->hw_lock, flags);
		apr_finish_job(apr, ctx, -EIO, false);
		return;
	}
	if (!apr->ring_ready)
		apr_hw_init(apr);
	apr->active = ctx;
	apr->started = jiffies;
	apr_submit(apr, desc, len, ctx->is_dec ? APR_JOB_DECODE : APR_JOB_ENCODE);
	spin_unlock_irqrestore(&apr->hw_lock, flags);
	schedule_delayed_work(&apr->watchdog, msecs_to_jiffies(APR_POLL_MS));
}

static const struct v4l2_m2m_ops apr_m2m_ops = {
	.device_run = apr_device_run,
};

/* ---- formats ----------------------------------------------------------- */

static const struct apr_fmt *apr_find_raw(u32 fourcc, bool dec)
{
	unsigned int i;

	for (i = 0; i < ARRAY_SIZE(apr_raw_fmts); i++)
		if (apr_raw_fmts[i].fourcc == fourcc && (!dec || apr_raw_fmts[i].dec))
			return &apr_raw_fmts[i];
	return NULL;
}

/*
 * One contiguous plane: Y rows, interleaved CbCr rows, then alpha rows if
 * any; each plane padded to whole 16-row macroblocks.
 */
static void apr_fill_raw(struct v4l2_pix_format_mplane *pix, const struct apr_fmt *fmt)
{
	u32 width = clamp_t(u32, ALIGN(pix->width, 2), APR_MIN_W, APR_MAX_W);
	u32 height = clamp_t(u32, pix->height, APR_MIN_H, APR_MAX_H);
	u32 min_stride = ALIGN(width * fmt->bytes, 64);
	u32 stride = ALIGN(pix->plane_fmt[0].bytesperline, 64);
	u32 cstride;

	if ((u64)width * height > APR_MAX_PIXELS)
		height = APR_MAX_PIXELS / width;
	if (stride < min_stride || stride > 2 * min_stride)
		stride = min_stride;
	cstride = stride * (fmt->is444 ? 2 : 1);
	pix->pixelformat = fmt->fourcc;
	pix->width = width;
	pix->height = height;
	pix->field = V4L2_FIELD_NONE;
	pix->num_planes = 1;
	pix->flags = 0;
	memset(pix->reserved, 0, sizeof(pix->reserved));
	memset(pix->plane_fmt, 0, sizeof(pix->plane_fmt));
	pix->plane_fmt[0].bytesperline = stride;
	pix->plane_fmt[0].sizeimage = (stride + cstride + (fmt->alpha ? stride : 0)) *
				      ALIGN(height, 16);
	if (pix->colorspace == V4L2_COLORSPACE_DEFAULT)
		pix->colorspace = V4L2_COLORSPACE_REC709;
	if (pix->xfer_func == V4L2_XFER_FUNC_DEFAULT)
		pix->xfer_func = V4L2_MAP_XFER_FUNC_DEFAULT(pix->colorspace);
	if (pix->ycbcr_enc == V4L2_YCBCR_ENC_DEFAULT)
		pix->ycbcr_enc = V4L2_MAP_YCBCR_ENC_DEFAULT(pix->colorspace);
	if (pix->quantization == V4L2_QUANTIZATION_DEFAULT)
		pix->quantization = V4L2_QUANTIZATION_LIM_RANGE;
}

static void apr_fill_coded(struct v4l2_pix_format_mplane *dst,
			   const struct v4l2_pix_format_mplane *src,
			   const struct apr_fmt *raw, u32 want_size)
{
	u32 size = apr_coded_size(src->width, src->height, raw->is444, raw->alpha);

	*dst = *src;
	dst->pixelformat = V4L2_PIX_FMT_PRORES;
	dst->num_planes = 1;
	memset(dst->plane_fmt, 0, sizeof(dst->plane_fmt));
	/* A decoder's bitstream buffers may be smaller than the worst case. */
	dst->plane_fmt[0].sizeimage = want_size ? clamp_t(u32, want_size, SZ_4K, size) : size;
}

static void apr_reset_fmts(struct apr_ctx *ctx)
{
	ctx->raw = &apr_raw_fmts[0];
	if (!ctx->is_dec) {
		memset(&ctx->src_fmt, 0, sizeof(ctx->src_fmt));
		ctx->src_fmt.width = 1920;
		ctx->src_fmt.height = 1080;
		apr_fill_raw(&ctx->src_fmt, ctx->raw);
		apr_fill_coded(&ctx->dst_fmt, &ctx->src_fmt, ctx->raw, 0);
	} else {
		memset(&ctx->dst_fmt, 0, sizeof(ctx->dst_fmt));
		ctx->dst_fmt.width = 1920;
		ctx->dst_fmt.height = 1080;
		apr_fill_raw(&ctx->dst_fmt, ctx->raw);
		apr_fill_coded(&ctx->src_fmt, &ctx->dst_fmt, ctx->raw, 0);
	}
}

/* The raw side's format: OUTPUT for the encoder, CAPTURE for the decoder. */
static struct v4l2_pix_format_mplane *apr_raw_side(struct apr_ctx *ctx)
{
	return ctx->is_dec ? &ctx->dst_fmt : &ctx->src_fmt;
}

static int apr_querycap(struct file *file, void *priv, struct v4l2_capability *cap)
{
	struct apr_ctx *ctx = apr_file_to_ctx(file);

	strscpy(cap->driver, APR_NAME, sizeof(cap->driver));
	strscpy(cap->card, ctx->is_dec ? "Apple ProRes decoder" : "Apple ProRes encoder",
		sizeof(cap->card));
	return 0;
}

static int apr_enum_raw(struct apr_ctx *ctx, struct v4l2_fmtdesc *f)
{
	unsigned int i, n = 0;

	for (i = 0; i < ARRAY_SIZE(apr_raw_fmts); i++) {
		if (ctx->is_dec && !apr_raw_fmts[i].dec)
			continue;
		if (n++ == f->index) {
			f->pixelformat = apr_raw_fmts[i].fourcc;
			strscpy(f->description, apr_raw_fmts[i].desc, sizeof(f->description));
			return 0;
		}
	}
	return -EINVAL;
}

static int apr_enum_coded(struct v4l2_fmtdesc *f)
{
	if (f->index)
		return -EINVAL;
	f->pixelformat = V4L2_PIX_FMT_PRORES;
	f->flags = V4L2_FMT_FLAG_COMPRESSED;
	strscpy(f->description, "Apple ProRes", sizeof(f->description));
	return 0;
}

static int apr_enum_fmt_out(struct file *file, void *priv, struct v4l2_fmtdesc *f)
{
	struct apr_ctx *ctx = apr_file_to_ctx(file);

	return ctx->is_dec ? apr_enum_coded(f) : apr_enum_raw(ctx, f);
}

static int apr_enum_fmt_cap(struct file *file, void *priv, struct v4l2_fmtdesc *f)
{
	struct apr_ctx *ctx = apr_file_to_ctx(file);

	return ctx->is_dec ? apr_enum_raw(ctx, f) : apr_enum_coded(f);
}

static int apr_enum_framesizes(struct file *file, void *priv, struct v4l2_frmsizeenum *fs)
{
	struct apr_ctx *ctx = apr_file_to_ctx(file);

	if (fs->index || (fs->pixel_format != V4L2_PIX_FMT_PRORES &&
			  !apr_find_raw(fs->pixel_format, ctx->is_dec)))
		return -EINVAL;
	fs->type = V4L2_FRMSIZE_TYPE_STEPWISE;
	fs->stepwise = (struct v4l2_frmsize_stepwise){
		APR_MIN_W, APR_MAX_W, 2, APR_MIN_H, APR_MAX_H, 1,
	};
	return 0;
}

static int apr_g_fmt_out(struct file *file, void *priv, struct v4l2_format *f)
{
	f->fmt.pix_mp = apr_file_to_ctx(file)->src_fmt;
	return 0;
}

static int apr_g_fmt_cap(struct file *file, void *priv, struct v4l2_format *f)
{
	f->fmt.pix_mp = apr_file_to_ctx(file)->dst_fmt;
	return 0;
}

/* Raw side: any supported raw format. Coded side: follows the raw size. */
static int apr_try_raw(struct apr_ctx *ctx, struct v4l2_format *f)
{
	const struct apr_fmt *fmt = apr_find_raw(f->fmt.pix_mp.pixelformat, ctx->is_dec);

	apr_fill_raw(&f->fmt.pix_mp, fmt ?: &apr_raw_fmts[0]);
	return 0;
}

static int apr_try_coded(struct apr_ctx *ctx, struct v4l2_format *f)
{
	struct v4l2_pix_format_mplane raw = *apr_raw_side(ctx);
	u32 want = f->fmt.pix_mp.plane_fmt[0].sizeimage;

	/* A decoder takes its size from the coded side (the frames' size). */
	if (ctx->is_dec && f->fmt.pix_mp.width && f->fmt.pix_mp.height) {
		raw.width = f->fmt.pix_mp.width;
		raw.height = f->fmt.pix_mp.height;
		apr_fill_raw(&raw, ctx->raw);
	}
	apr_fill_coded(&f->fmt.pix_mp, &raw, ctx->raw, ctx->is_dec ? want : 0);
	return 0;
}

static int apr_try_fmt_out(struct file *file, void *priv, struct v4l2_format *f)
{
	struct apr_ctx *ctx = apr_file_to_ctx(file);

	return ctx->is_dec ? apr_try_coded(ctx, f) : apr_try_raw(ctx, f);
}

static int apr_try_fmt_cap(struct file *file, void *priv, struct v4l2_format *f)
{
	struct apr_ctx *ctx = apr_file_to_ctx(file);

	return ctx->is_dec ? apr_try_raw(ctx, f) : apr_try_coded(ctx, f);
}

static bool apr_busy(struct apr_ctx *ctx)
{
	struct v4l2_m2m_ctx *m2m = ctx->fh.m2m_ctx;

	return vb2_is_busy(v4l2_m2m_get_src_vq(m2m)) || vb2_is_busy(v4l2_m2m_get_dst_vq(m2m));
}

static int apr_s_fmt_out(struct file *file, void *priv, struct v4l2_format *f)
{
	struct apr_ctx *ctx = apr_file_to_ctx(file);

	if (apr_busy(ctx))
		return -EBUSY;
	if (!ctx->is_dec) {
		apr_try_raw(ctx, f);
		ctx->src_fmt = f->fmt.pix_mp;
		ctx->raw = apr_find_raw(ctx->src_fmt.pixelformat, false);
		apr_fill_coded(&ctx->dst_fmt, &ctx->src_fmt, ctx->raw, 0);
		/* Keep the profile consistent with the chroma format. */
		if (ctx->raw->is444 != apr_profile_is_444(v4l2_ctrl_g_ctrl(ctx->profile)))
			v4l2_ctrl_s_ctrl(ctx->profile, ctx->raw->is444 ?
					 V4L2_MPEG_VIDEO_PRORES_PROFILE_4444 :
					 V4L2_MPEG_VIDEO_PRORES_PROFILE_STANDARD);
	} else {
		apr_try_coded(ctx, f);
		ctx->src_fmt = f->fmt.pix_mp;
		ctx->dst_fmt.width = ctx->src_fmt.width;
		ctx->dst_fmt.height = ctx->src_fmt.height;
		apr_fill_raw(&ctx->dst_fmt, ctx->raw);
	}
	return 0;
}

static int apr_s_fmt_cap(struct file *file, void *priv, struct v4l2_format *f)
{
	struct apr_ctx *ctx = apr_file_to_ctx(file);

	if (vb2_is_busy(v4l2_m2m_get_dst_vq(ctx->fh.m2m_ctx)))
		return -EBUSY;
	if (!ctx->is_dec) {
		apr_try_coded(ctx, f);
		ctx->dst_fmt = f->fmt.pix_mp;
	} else {
		/* The size is the stream's; only the pixel format is chosen here. */
		f->fmt.pix_mp.width = ctx->src_fmt.width;
		f->fmt.pix_mp.height = ctx->src_fmt.height;
		apr_try_raw(ctx, f);
		ctx->dst_fmt = f->fmt.pix_mp;
		ctx->raw = apr_find_raw(ctx->dst_fmt.pixelformat, true);
	}
	return 0;
}

static int apr_subscribe_event(struct v4l2_fh *fh, const struct v4l2_event_subscription *sub)
{
	if (sub->type == V4L2_EVENT_EOS)
		return v4l2_event_subscribe(fh, sub, 0, NULL);
	return v4l2_ctrl_subscribe_event(fh, sub);
}

#define APR_COMMON_IOCTLS \
	.vidioc_querycap = apr_querycap, \
	.vidioc_enum_fmt_vid_out = apr_enum_fmt_out, \
	.vidioc_enum_fmt_vid_cap = apr_enum_fmt_cap, \
	.vidioc_enum_framesizes = apr_enum_framesizes, \
	.vidioc_g_fmt_vid_out_mplane = apr_g_fmt_out, \
	.vidioc_g_fmt_vid_cap_mplane = apr_g_fmt_cap, \
	.vidioc_try_fmt_vid_out_mplane = apr_try_fmt_out, \
	.vidioc_try_fmt_vid_cap_mplane = apr_try_fmt_cap, \
	.vidioc_s_fmt_vid_out_mplane = apr_s_fmt_out, \
	.vidioc_s_fmt_vid_cap_mplane = apr_s_fmt_cap, \
	.vidioc_reqbufs = v4l2_m2m_ioctl_reqbufs, \
	.vidioc_querybuf = v4l2_m2m_ioctl_querybuf, \
	.vidioc_qbuf = v4l2_m2m_ioctl_qbuf, \
	.vidioc_dqbuf = v4l2_m2m_ioctl_dqbuf, \
	.vidioc_prepare_buf = v4l2_m2m_ioctl_prepare_buf, \
	.vidioc_create_bufs = v4l2_m2m_ioctl_create_bufs, \
	.vidioc_expbuf = v4l2_m2m_ioctl_expbuf, \
	.vidioc_streamon = v4l2_m2m_ioctl_streamon, \
	.vidioc_streamoff = v4l2_m2m_ioctl_streamoff, \
	.vidioc_subscribe_event = apr_subscribe_event, \
	.vidioc_unsubscribe_event = v4l2_event_unsubscribe

static const struct v4l2_ioctl_ops apr_enc_ioctl_ops = {
	APR_COMMON_IOCTLS,
	.vidioc_try_encoder_cmd = v4l2_m2m_ioctl_try_encoder_cmd,
	.vidioc_encoder_cmd = v4l2_m2m_ioctl_encoder_cmd,
};

static const struct v4l2_ioctl_ops apr_dec_ioctl_ops = {
	APR_COMMON_IOCTLS,
	.vidioc_try_decoder_cmd = v4l2_m2m_ioctl_try_decoder_cmd,
	.vidioc_decoder_cmd = v4l2_m2m_ioctl_decoder_cmd,
};

/* ---- queues ------------------------------------------------------------ */

static struct v4l2_pix_format_mplane *apr_q_fmt(struct apr_ctx *ctx, u32 type)
{
	return V4L2_TYPE_IS_OUTPUT(type) ? &ctx->src_fmt : &ctx->dst_fmt;
}

static int apr_queue_setup(struct vb2_queue *q, unsigned int *nbufs,
			   unsigned int *nplanes, unsigned int sizes[],
			   struct device *alloc_devs[])
{
	struct apr_ctx *ctx = vb2_get_drv_priv(q);
	u32 size = apr_q_fmt(ctx, q->type)->plane_fmt[0].sizeimage;

	if (*nplanes)
		return *nplanes == 1 && sizes[0] >= size ? 0 : -EINVAL;
	*nplanes = 1;
	sizes[0] = size;
	return 0;
}

static int apr_buf_prepare(struct vb2_buffer *vb)
{
	struct apr_ctx *ctx = vb2_get_drv_priv(vb->vb2_queue);
	u32 size = apr_q_fmt(ctx, vb->type)->plane_fmt[0].sizeimage;
	bool coded = V4L2_TYPE_IS_OUTPUT(vb->type) == ctx->is_dec;

	if (vb2_plane_size(vb, 0) < size)
		return -EINVAL;
	if (V4L2_TYPE_IS_OUTPUT(vb->type)) {
		/* Encoder: the engine reads the whole padded surface. */
		if (!coded)
			vb2_set_plane_payload(vb, 0, size);
		else if (!vb2_get_plane_payload(vb, 0))
			return -EINVAL;
	} else {
		vb2_set_plane_payload(vb, 0, 0);
	}
	return 0;
}

static void apr_buf_queue(struct vb2_buffer *vb)
{
	struct apr_ctx *ctx = vb2_get_drv_priv(vb->vb2_queue);
	struct vb2_v4l2_buffer *vbuf = to_vb2_v4l2_buffer(vb);

	if (!V4L2_TYPE_IS_OUTPUT(vb->type) && vb2_is_streaming(vb->vb2_queue) &&
	    v4l2_m2m_dst_buf_is_last(ctx->fh.m2m_ctx)) {
		vb2_set_plane_payload(vb, 0, 0);
		vbuf->field = V4L2_FIELD_NONE;
		v4l2_m2m_last_buffer_done(ctx->fh.m2m_ctx, vbuf);
		return;
	}
	v4l2_m2m_buf_queue(ctx->fh.m2m_ctx, vbuf);
}

static int apr_start_streaming(struct vb2_queue *q, unsigned int count)
{
	struct apr_ctx *ctx = vb2_get_drv_priv(q);

	if (V4L2_TYPE_IS_OUTPUT(q->type)) {
		if (!ctx->is_dec &&
		    ctx->raw->is444 != apr_profile_is_444(v4l2_ctrl_g_ctrl(ctx->profile))) {
			struct vb2_v4l2_buffer *vbuf;

			while ((vbuf = v4l2_m2m_src_buf_remove(ctx->fh.m2m_ctx)))
				v4l2_m2m_buf_done(vbuf, VB2_BUF_STATE_QUEUED);
			return -EINVAL;
		}
		if (!ctx->is_dec) {
			ctx->stream_profile = v4l2_ctrl_g_ctrl(ctx->profile);
			v4l2_ctrl_grab(ctx->profile, true);
		}
		ctx->sequence = 0;
	}
	v4l2_m2m_update_start_streaming_state(ctx->fh.m2m_ctx, q);
	return 0;
}

static void apr_stop_streaming(struct vb2_queue *q)
{
	struct apr_ctx *ctx = vb2_get_drv_priv(q);
	struct vb2_v4l2_buffer *vbuf;

	for (;;) {
		vbuf = V4L2_TYPE_IS_OUTPUT(q->type) ?
			v4l2_m2m_src_buf_remove(ctx->fh.m2m_ctx) :
			v4l2_m2m_dst_buf_remove(ctx->fh.m2m_ctx);
		if (!vbuf)
			break;
		v4l2_m2m_buf_done(vbuf, VB2_BUF_STATE_ERROR);
	}
	v4l2_m2m_update_stop_streaming_state(ctx->fh.m2m_ctx, q);
	if (V4L2_TYPE_IS_OUTPUT(q->type) && !ctx->is_dec)
		v4l2_ctrl_grab(ctx->profile, false);
	if (V4L2_TYPE_IS_OUTPUT(q->type) && v4l2_m2m_has_stopped(ctx->fh.m2m_ctx)) {
		static const struct v4l2_event eos = { .type = V4L2_EVENT_EOS };

		v4l2_event_queue_fh(&ctx->fh, &eos);
	}
}

static const struct vb2_ops apr_qops = {
	.queue_setup = apr_queue_setup,
	.buf_prepare = apr_buf_prepare,
	.buf_queue = apr_buf_queue,
	.start_streaming = apr_start_streaming,
	.stop_streaming = apr_stop_streaming,
};

static int apr_queue_init(void *priv, struct vb2_queue *src, struct vb2_queue *dst)
{
	struct apr_ctx *ctx = priv;
	int ret;

	src->type = V4L2_BUF_TYPE_VIDEO_OUTPUT_MPLANE;
	src->io_modes = VB2_MMAP | VB2_DMABUF;
	src->drv_priv = ctx;
	src->buf_struct_size = sizeof(struct v4l2_m2m_buffer);
	src->ops = &apr_qops;
	src->mem_ops = &vb2_dma_contig_memops;
	src->timestamp_flags = V4L2_BUF_FLAG_TIMESTAMP_COPY;
	src->lock = &ctx->apr->vdev_lock;
	src->dev = ctx->apr->dev;
	ret = vb2_queue_init(src);
	if (ret)
		return ret;

	dst->type = V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE;
	dst->io_modes = VB2_MMAP | VB2_DMABUF;
	dst->drv_priv = ctx;
	dst->buf_struct_size = sizeof(struct v4l2_m2m_buffer);
	dst->ops = &apr_qops;
	dst->mem_ops = &vb2_dma_contig_memops;
	dst->timestamp_flags = V4L2_BUF_FLAG_TIMESTAMP_COPY;
	dst->lock = &ctx->apr->vdev_lock;
	dst->dev = ctx->apr->dev;
	return vb2_queue_init(dst);
}

/* ---- controls and file operations -------------------------------------- */

static int apr_s_ctrl(struct v4l2_ctrl *ctrl)
{
	return 0;	/* read when a job is built */
}

static const struct v4l2_ctrl_ops apr_ctrl_ops = {
	.s_ctrl = apr_s_ctrl,
};

static const char *const apr_profile_menu[] = {
	"Proxy", "LT", "422", "HQ", "4444", "4444 XQ", NULL,
};

static const struct v4l2_ctrl_config apr_ctrl_profile = {
	.ops = &apr_ctrl_ops,
	.id = V4L2_CID_MPEG_VIDEO_PRORES_PROFILE,
	.name = "ProRes Profile",
	.type = V4L2_CTRL_TYPE_MENU,
	.max = V4L2_MPEG_VIDEO_PRORES_PROFILE_4444_XQ,
	.def = V4L2_MPEG_VIDEO_PRORES_PROFILE_STANDARD,
	.qmenu = apr_profile_menu,
};

static const struct v4l2_ctrl_config apr_ctrl_target = {
	.ops = &apr_ctrl_ops,
	.id = V4L2_CID_APPLE_PRORES_TARGET_BYTES,
	.name = "ProRes Target Frame Bytes",
	.type = V4L2_CTRL_TYPE_INTEGER,
	.min = 0, .max = SZ_256M, .step = 1, .def = 0,
};

static const struct v4l2_ctrl_config apr_ctrl_max = {
	.ops = &apr_ctrl_ops,
	.id = V4L2_CID_APPLE_PRORES_MAX_BYTES,
	.name = "ProRes Max Frame Bytes",
	.type = V4L2_CTRL_TYPE_INTEGER,
	.min = 0, .max = SZ_256M, .step = 1, .def = 0,
};

static const struct v4l2_ctrl_config apr_ctrl_qi = {
	.ops = &apr_ctrl_ops,
	.id = V4L2_CID_APPLE_PRORES_QUANT_INDEX,
	.name = "ProRes Start Quantiser",
	.type = V4L2_CTRL_TYPE_INTEGER,
	.min = 0, .max = 224, .step = 1, .def = 0,
};

static int apr_init_ctrls(struct apr_ctx *ctx)
{
	struct v4l2_ctrl_handler *hdl = &ctx->hdl;

	v4l2_ctrl_handler_init(hdl, 4);
	if (!ctx->is_dec) {
		/* Not a standard control in this kernel: always a custom one. */
		ctx->profile = v4l2_ctrl_new_custom(hdl, &apr_ctrl_profile, NULL);
		ctx->target_bytes = v4l2_ctrl_new_custom(hdl, &apr_ctrl_target, NULL);
		ctx->max_bytes = v4l2_ctrl_new_custom(hdl, &apr_ctrl_max, NULL);
		ctx->quant_index = v4l2_ctrl_new_custom(hdl, &apr_ctrl_qi, NULL);
	}
	if (hdl->error) {
		int ret = hdl->error;

		v4l2_ctrl_handler_free(hdl);
		return ret;
	}
	ctx->fh.ctrl_handler = hdl;
	return 0;
}

static int apr_open(struct file *file)
{
	struct apr_dev *apr = video_drvdata(file);
	struct video_device *vdev = video_devdata(file);
	struct apr_ctx *ctx;
	int ret;

	ctx = kzalloc(sizeof(*ctx), GFP_KERNEL);
	if (!ctx)
		return -ENOMEM;
	ctx->apr = apr;
	ctx->is_dec = vdev == &apr->dec_vdev;
	apr_reset_fmts(ctx);
	v4l2_fh_init(&ctx->fh, vdev);
	ret = apr_init_ctrls(ctx);
	if (ret)
		goto err_fh;
	ctx->fh.m2m_ctx = v4l2_m2m_ctx_init(apr->m2m_dev, ctx, apr_queue_init);
	if (IS_ERR(ctx->fh.m2m_ctx)) {
		ret = PTR_ERR(ctx->fh.m2m_ctx);
		goto err_ctrls;
	}
	v4l2_fh_add(&ctx->fh, file);
	return 0;

err_ctrls:
	v4l2_ctrl_handler_free(&ctx->hdl);
err_fh:
	v4l2_fh_exit(&ctx->fh);
	kfree(ctx);
	return ret;
}

static int apr_release(struct file *file)
{
	struct apr_ctx *ctx = apr_file_to_ctx(file);
	struct apr_dev *apr = ctx->apr;

	mutex_lock(&apr->vdev_lock);
	v4l2_m2m_ctx_release(ctx->fh.m2m_ctx);
	mutex_unlock(&apr->vdev_lock);
	v4l2_ctrl_handler_free(&ctx->hdl);
	v4l2_fh_del(&ctx->fh, file);
	v4l2_fh_exit(&ctx->fh);
	kfree(ctx);
	return 0;
}

static const struct v4l2_file_operations apr_fops = {
	.owner = THIS_MODULE,
	.open = apr_open,
	.release = apr_release,
	.poll = v4l2_m2m_fop_poll,
	.unlocked_ioctl = video_ioctl2,
	.mmap = v4l2_m2m_fop_mmap,
};

/* ---- power management -------------------------------------------------- */

static int apr_runtime_suspend(struct device *dev)
{
	struct apr_dev *apr = dev_get_drvdata(dev);
	unsigned long flags;

	spin_lock_irqsave(&apr->hw_lock, flags);
	if (apr->ring_ready) {
		/* Idle here (no job holds a reference): stop the engine first. */
		apr_write(apr, APR_REG_IRQ_ENABLE, 0);
		apr_write(apr, APR_REG_MODE, APR_MODE_OFF);
	}
	apr->ring_ready = false;
	spin_unlock_irqrestore(&apr->hw_lock, flags);
	return 0;
}

static int apr_runtime_resume(struct device *dev)
{
	return 0;	/* programmed lazily by the next job */
}

static int apr_suspend(struct device *dev)
{
	struct apr_dev *apr = dev_get_drvdata(dev);

	if (apr->m2m_dev)
		v4l2_m2m_suspend(apr->m2m_dev);
	return pm_runtime_force_suspend(dev);
}

static int apr_resume(struct device *dev)
{
	struct apr_dev *apr = dev_get_drvdata(dev);
	int ret;

	ret = pm_runtime_force_resume(dev);
	if (ret)
		return ret;
	if (apr->m2m_dev)
		v4l2_m2m_resume(apr->m2m_dev);
	return 0;
}

static const struct dev_pm_ops apr_pm_ops = {
	RUNTIME_PM_OPS(apr_runtime_suspend, apr_runtime_resume, NULL)
	SYSTEM_SLEEP_PM_OPS(apr_suspend, apr_resume)
};

/* ---- probe ------------------------------------------------------------- */

/* Stage 7: one 64x64 422 HQ encode, polled with the interrupt disabled. */
static int apr_selftest(struct apr_dev *apr)
{
	const u32 w = 64, h = 64, stride = 64, in_size = 2 * stride * h, out_size = SZ_64K;
	struct apr_cmd_knobs k;
	struct apr_frame f = {};
	unsigned long flags;
	dma_addr_t in_dma, out_dma;
	u8 *in, *out, desc[APR_ENC_DESC_BYTES];
	u32 st = 0, bytes = 0, x, y;
	int ret;

	in = dma_alloc_coherent(apr->dev, in_size, &in_dma, GFP_KERNEL);
	out = dma_alloc_coherent(apr->dev, out_size, &out_dma, GFP_KERNEL);
	if (!in || !out) {
		ret = -ENOMEM;
		goto free;
	}
	for (y = 0; y < h; y++)
		for (x = 0; x < w; x++) {
			in[y * stride + x] = 16 + (x + y) * 219 / 126;
			in[stride * h + y * stride + x] = (x & 1) ? 128 + y : 128 - y;
		}
	memset(out, 0xaa, out_size);
	f = (struct apr_frame){
		.width = w, .height = h, .input = APR_INPUT_422_8, .profile = APR_PROFILE_HQ,
		.luma_stride = stride, .chroma_stride = stride,
		.luma = in_dma, .chroma = in_dma + stride * h,
		.output = out_dma, .output_size = out_size,
		.primaries = 1, .transfer = 1, .matrix = 1,
	};
	apr_knobs(&k);
	ret = apr_build_enc_desc(&f, &k, desc);
	if (ret)
		goto free;

	spin_lock_irqsave(&apr->hw_lock, flags);
	apr_submit(apr, desc, APR_ENC_DESC_BYTES, APR_JOB_ENCODE);
	spin_unlock_irqrestore(&apr->hw_lock, flags);
	ret = readl_poll_timeout(apr->regs + APR_REG_IRQ_STATUS, st,
				 st & (APR_IRQ_DONE | APR_IRQ_ERROR), 1000,
				 APR_TIMEOUT_MS * 1000);
	dev_info(apr->dev, "self-test: status %#x st0 %#x st1 %#x st2 %#x res %#x tail %#x head %#x\n",
		 st, apr_read(apr, APR_REG_ST0), apr_read(apr, APR_REG_ST1),
		 apr_read(apr, APR_REG_ST2), apr_read(apr, APR_REG_ST_ENC),
		 apr_read(apr, APR_REG_RING_TAIL), apr->head);
	apr_write(apr, APR_REG_IRQ_STATUS, st);
	spin_lock_irqsave(&apr->hw_lock, flags);
	apr->inflight = 0;
	spin_unlock_irqrestore(&apr->hw_lock, flags);
	if (ret) {
		dev_err(apr->dev, "self-test: no completion in %u ms\n", APR_TIMEOUT_MS);
		apr_quiesce(apr);
		apr_write(apr, APR_REG_MODE, APR_MODE_OFF);
		ret = -ETIMEDOUT;
		goto free;
	}
	dma_rmb();
	if ((st & APR_IRQ_ERROR) || apr_check_output(out, out_size, &bytes)) {
		dev_err(apr->dev, "self-test: no frame (%*ph)\n", 16, out);
		ret = -EIO;
		goto free;
	}
	dev_info(apr->dev, "self-test: %u-byte ProRes 422 HQ frame, header %*ph\n",
		 bytes, 28, out);
	ret = 0;
free:
	if (in)
		dma_free_coherent(apr->dev, in_size, in, in_dma);
	if (out)
		dma_free_coherent(apr->dev, out_size, out, out_dma);
	return ret;
}

static int apr_register_vdev(struct apr_dev *apr, struct video_device *vdev, bool dec)
{
	strscpy(vdev->name, dec ? APR_NAME "-dec" : APR_NAME "-enc", sizeof(vdev->name));
	vdev->fops = &apr_fops;
	vdev->ioctl_ops = dec ? &apr_dec_ioctl_ops : &apr_enc_ioctl_ops;
	vdev->release = video_device_release_empty;
	vdev->lock = &apr->vdev_lock;
	vdev->v4l2_dev = &apr->v4l2_dev;
	vdev->vfl_dir = VFL_DIR_M2M;
	vdev->device_caps = V4L2_CAP_VIDEO_M2M_MPLANE | V4L2_CAP_STREAMING;
	video_set_drvdata(vdev, apr);
	return video_register_device(vdev, VFL_TYPE_VIDEO, -1);
}

static void apr_cleanup(void *data)
{
	struct apr_dev *apr = data;

	cancel_delayed_work_sync(&apr->watchdog);
	if (apr->m2m_dev)
		v4l2_m2m_release(apr->m2m_dev);
	v4l2_device_unregister(&apr->v4l2_dev);
}

static int apr_probe(struct platform_device *pdev)
{
	struct device *dev = &pdev->dev;
	struct apr_dev *apr;
	unsigned long flags;
	u32 s0, s1;
	int ret;

	apr = devm_kzalloc(dev, sizeof(*apr), GFP_KERNEL);
	if (!apr)
		return -ENOMEM;
	apr->dev = dev;
	mutex_init(&apr->vdev_lock);
	spin_lock_init(&apr->hw_lock);
	INIT_DELAYED_WORK(&apr->watchdog, apr_watchdog);
	platform_set_drvdata(pdev, apr);
	apr_qmat_build(apr->qm_luma, apr->qm_chroma);

	/* 1: resources; no hardware access. */
	apr_stage(apr, 1, "map registers, IRQ, reset, IOMMU");
	apr->regs = devm_platform_ioremap_resource_byname(pdev, "core");
	if (IS_ERR(apr->regs))
		return PTR_ERR(apr->regs);
	apr->wrapper = devm_platform_ioremap_resource_byname(pdev, "wrapper");
	if (IS_ERR(apr->wrapper))
		return PTR_ERR(apr->wrapper);
	apr->reset = devm_reset_control_get_optional_exclusive(dev, NULL);
	if (IS_ERR(apr->reset))
		return dev_err_probe(dev, PTR_ERR(apr->reset), "reset\n");
	apr->irq = platform_get_irq(pdev, 0);
	if (apr->irq < 0)
		return apr->irq;
	if (!device_iommu_mapped(dev))
		return dev_err_probe(dev, -ENODEV, "no IOMMU (dart-apr0 missing?)\n");
	ret = dma_set_mask_and_coherent(dev, DMA_BIT_MASK(42));
	if (ret)
		return ret;
	ret = v4l2_device_register(dev, &apr->v4l2_dev);
	if (ret)
		return ret;
	ret = devm_add_action_or_reset(dev, apr_cleanup, apr);
	if (ret)
		return ret;
	if (apr_stop_here(apr, 1))
		return -ECANCELED;

	/* 2: power: ps_scodec (and the DART, its supplier) on. */
	apr_stage(apr, 2, "power on (ps_scodec, dart-apr0)");
	pm_runtime_set_autosuspend_delay(dev, APR_AUTOSUSPEND_MS);
	pm_runtime_use_autosuspend(dev);
	ret = devm_pm_runtime_enable(dev);
	if (ret)
		return ret;
	ret = pm_runtime_resume_and_get(dev);
	if (ret < 0)
		return dev_err_probe(dev, ret, "power on\n");
	if (apr_stop_here(apr, 2)) {
		ret = -ECANCELED;
		goto put;
	}

	/* 3: read-only checks. */
	apr_stage(apr, 3, "read ID and ring/stats registers (reads only)");
	apr->id = apr_read(apr, APR_REG_ID);
	apr->version = apr_version(apr->id);
	s0 = apr_read(apr, APR_REG_STATS0_SIZE);
	s1 = apr_read(apr, APR_REG_STATS1_SIZE);
	dev_info(dev, "ID %#x (version %d) mode %#x irq %#x/%#x ring %#x/%#x:%#x head %#x tail %#x stats size %#x/%#x limiters %#x %#x %#x\n",
		 apr->id, apr->version, apr_read(apr, APR_REG_MODE),
		 apr_read(apr, APR_REG_IRQ_ENABLE), apr_read(apr, APR_REG_IRQ_STATUS),
		 apr_read(apr, APR_REG_RING_SIZE), apr_read(apr, APR_REG_RING_HI),
		 apr_read(apr, APR_REG_RING_LO), apr_read(apr, APR_REG_RING_HEAD),
		 apr_read(apr, APR_REG_RING_TAIL), s0, s1,
		 readl_relaxed(apr->wrapper + APR_WRAP_BULK0),
		 readl_relaxed(apr->wrapper + APR_WRAP_BULK1),
		 readl_relaxed(apr->wrapper + APR_WRAP_LLT_STS));
	if (apr->version < 3 && !id_any) {
		ret = dev_err_probe(dev, -ENODEV,
				    "ID %#x is not a version 3+ core (stats at 0x38c): refusing (id_any=1 overrides)\n",
				    apr->id);
		goto put;
	}
	if (apr_stop_here(apr, 3)) {
		ret = -ECANCELED;
		goto put;
	}

	/* 4: the tunables file; no hardware access. */
	apr_stage(apr, 4, "load tunables file");
	ret = apr_load_tunables(apr);
	if (ret)
		goto put;
	if (apr_stop_here(apr, 4)) {
		ret = -ECANCELED;
		goto put;
	}

	/* 5: first writes: MODE=0 and the DMA-block tunables. */
	apr_stage(apr, 5, "write MODE=0 and 64 DMA-block tunables (fabric-hang risk if wrong)");
	spin_lock_irqsave(&apr->hw_lock, flags);
	apr_write(apr, APR_REG_MODE, APR_MODE_OFF);
	apr_write(apr, APR_REG_IRQ_ENABLE, 0);
	apr_apply_tunables(apr);
	spin_unlock_irqrestore(&apr->hw_lock, flags);
	s0 = apr_read(apr, APR_REG_STATS0_SIZE) & ~0x3fU;
	s1 = apr_read(apr, APR_REG_STATS1_SIZE) & ~0x3fU;
	dev_info(dev, "tunables applied; stats size %#x/%#x\n", s0, s1);
	if (apr_stop_here(apr, 5)) {
		ret = -ECANCELED;
		goto put;
	}

	/* 6: ring, stats buffer, MODE=0xd, matrices. No descriptor yet. */
	apr_stage(apr, 6, "program ring, stats buffer, MODE=0xd, matrices");
	apr->stats_size = max(s0, s1);
	if (!apr->stats_size || apr->stats_size > APR_STATS_MAX) {
		ret = dev_err_probe(dev, -EINVAL, "implausible stats size %#zx\n", apr->stats_size);
		goto off;
	}
	apr->ring = dmam_alloc_coherent(dev, APR_RING_BYTES, &apr->ring_dma, GFP_KERNEL);
	apr->stats = dmam_alloc_coherent(dev, apr->stats_size, &apr->stats_dma, GFP_KERNEL);
	if (!apr->ring || !apr->stats) {
		ret = -ENOMEM;
		goto off;
	}
	dev_info(dev, "ring %pad, stats %pad+%#zx\n", &apr->ring_dma, &apr->stats_dma,
		 apr->stats_size);
	spin_lock_irqsave(&apr->hw_lock, flags);
	apr_hw_init(apr);
	spin_unlock_irqrestore(&apr->hw_lock, flags);
	dev_info(dev, "engine on: mode %#x head %#x tail %#x\n", apr_read(apr, APR_REG_MODE),
		 apr_read(apr, APR_REG_RING_HEAD), apr_read(apr, APR_REG_RING_TAIL));
	if (apr_stop_here(apr, 6)) {
		ret = -ECANCELED;
		goto off;
	}

	/* 7: the first DMA: one polled encode. */
	if (selftest) {
		apr_stage(apr, 7, "self-test encode: first descriptor, first DMA");
		ret = apr_selftest(apr);
		if (ret)
			goto off;
	}
	if (apr_stop_here(apr, 7)) {
		ret = -ECANCELED;
		goto off;
	}

	/* 8: interrupt and video devices. */
	apr_stage(apr, 8, "interrupt and video devices");
	ret = devm_request_irq(dev, apr->irq, apr_irq, 0, dev_name(dev), apr);
	if (ret)
		goto off;
	spin_lock_irqsave(&apr->hw_lock, flags);
	apr->irq_ready = true;
	apr_write(apr, APR_REG_IRQ_STATUS, apr_read(apr, APR_REG_IRQ_STATUS));
	apr_write(apr, APR_REG_IRQ_ENABLE, APR_IRQ_DONE | APR_IRQ_ERROR);
	spin_unlock_irqrestore(&apr->hw_lock, flags);
	apr->m2m_dev = v4l2_m2m_init(&apr_m2m_ops);
	if (IS_ERR(apr->m2m_dev)) {
		ret = PTR_ERR(apr->m2m_dev);
		apr->m2m_dev = NULL;
		goto off;
	}
	ret = apr_register_vdev(apr, &apr->enc_vdev, false);
	if (ret)
		goto off;
	apr->enc_registered = true;
	if (decoder) {
		ret = apr_register_vdev(apr, &apr->dec_vdev, true);
		if (ret)
			goto unreg;
		apr->dec_registered = true;
	}
	dev_info(dev, "ProRes engine ready: encoder %s%s%s\n",
		 video_device_node_name(&apr->enc_vdev),
		 decoder ? ", decoder " : "",
		 decoder ? video_device_node_name(&apr->dec_vdev) : "");
	pm_runtime_mark_last_busy(dev);
	pm_runtime_put_autosuspend(dev);
	return 0;

unreg:
	video_unregister_device(&apr->enc_vdev);
	apr->enc_registered = false;
off:
	spin_lock_irqsave(&apr->hw_lock, flags);
	apr_write(apr, APR_REG_IRQ_ENABLE, 0);
	apr_write(apr, APR_REG_MODE, APR_MODE_OFF);
	apr->ring_ready = false;
	apr->irq_ready = false;
	spin_unlock_irqrestore(&apr->hw_lock, flags);
put:
	pm_runtime_put_sync(dev);
	return ret;
}

static void apr_remove(struct platform_device *pdev)
{
	struct apr_dev *apr = platform_get_drvdata(pdev);

	if (apr->dec_registered)
		video_unregister_device(&apr->dec_vdev);
	if (apr->enc_registered)
		video_unregister_device(&apr->enc_vdev);
	/* Let the engine stop (runtime_suspend) and the domain go off now. */
	pm_runtime_dont_use_autosuspend(&pdev->dev);
}

static const struct of_device_id apr_of_match[] = {
	{ .compatible = "apple,t6020-prores" },
	{ }
};
MODULE_DEVICE_TABLE(of, apr_of_match);

static struct platform_driver apr_driver = {
	.probe = apr_probe,
	.remove = apr_remove,
	.driver = {
		.name = APR_NAME,
		.of_match_table = apr_of_match,
		.pm = pm_ptr(&apr_pm_ops),
	},
};
module_platform_driver(apr_driver);

MODULE_DESCRIPTION("Apple ProRes engine (t6020) V4L2 encoder/decoder");
MODULE_LICENSE("GPL");
MODULE_FIRMWARE(APR_TUNABLES_FW);

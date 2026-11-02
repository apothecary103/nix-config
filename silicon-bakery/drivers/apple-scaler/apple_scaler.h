/* SPDX-License-Identifier: GPL-2.0-only */
/*
 * Apple M2Scaler (t6020 "scaler0", hw-version 14) V4L2 mem2mem converter.
 * Silicon Bakery, 2026-11-02. Written on the Mac14,9 under macOS; never run.
 *
 * Provenance labels (docs/scaler-port.txt has the full list):
 *   [ADT]     macOS 13.5 j414sap / live 27.2 device tree
 *   [KEXT13.5] [KEXT27]  AppleM2ScalerCSCDriver behaviour (values only)
 *   [M1N1]    m1n1 proxyclient hw/scaler.py, experiments/scaler.py (M1 Max)
 *   [INF]     inference, needs a run on the machine
 * Offsets are bytes from the main block (0x4_0b00_0000 on t6020 [ADT]).
 */
#ifndef APPLE_SCALER_H
#define APPLE_SCALER_H

#include <linux/io.h>
#include <linux/spinlock.h>
#include <linux/mutex.h>
#include <linux/workqueue.h>
#include <media/v4l2-ctrls.h>
#include <media/v4l2-device.h>
#include <media/v4l2-mem2mem.h>

#define AS_NAME			"apple-scaler"

/* ---- control, IRQ [M1N1] [KEXT13.5] ---- */
#define AS_HW_VERSION		0x0000	/* 0x030c0013 on hw14 [KEXT13.5][LIVE ioreg] */
#define AS_HW_VERSION_T6020	0x030c0013
#define AS_RESET		0x0004	/* bit0 core; 1 then 0 */
#define AS_RESET_APIODMA	0x0008
#define AS_IS_RUNNING		0x000c	/* bit0 */
#define AS_IRQ_ENABLE		0x0018
#define AS_IRQ_ENABLE_VAL	0x121b	/* macOS value [M1N1][KEXT13.5] */
#define AS_IRQ_STATUS		0x001c	/* W1C */
#define  AS_IRQ_DONE		BIT(0)
#define  AS_IRQ_DBG_ERR		BIT(1)
#define  AS_IRQ_READ_ERR	BIT(3)
#define  AS_IRQ_WRITE_ERR	BIT(4)
#define  AS_IRQ_DECOMP_ERR	BIT(9)
#define  AS_IRQ_CTX_SWITCH	BIT(10)
#define  AS_IRQ_AXI_ERR		BIT(12)
#define  AS_IRQ_ERRORS		(AS_IRQ_DBG_ERR | AS_IRQ_READ_ERR | \
				 AS_IRQ_WRITE_ERR | AS_IRQ_AXI_ERR)
#define AS_FRAME_COUNT		0x0020
#define AS_START		0x0080
#define AS_ALPHA_OVERRIDE	0x008c	/* 0xffff; bit31 force [KEXT13.5][INF] */
#define AS_KICK_MASK		0x0098	/* 0xfffffffe before START [KEXT13.5] */
#define AS_DBG_STATUS		0x009c	/* error mask 0x3f3d [KEXT13.5] */
#define AS_PIXEL_AVERAGING	0x00e4	/* 0 off, 1 2:1, 2 4:1 (H) */
#define AS_RESHAPE_CTRL		0x00e8
#define AS_TRANSFORM_ID		0x0110
#define AS_SPILL_LO		0x0118	/* hw14 spill buffer, histogram only */
#define AS_SPILL_HI		0x011c
#define AS_SPILL_SIZE		0x0120
#define AS_HISTOGRAM_EN		0x0124

/* ---- RDMA (source) [KEXT13.5 IosaRdmaControlMSR11] ---- */
#define AS_RDMA_CFG		0x0180	/* b0 RGB class, b1 premul, b3:2 subsampling */
#define AS_RDMA_FMT(n)		(0x0184 + 4 * (n))	/* 4 slots */
#define AS_SRC_BASE_LO(p)	(0x0198 + 8 * (p))
#define AS_SRC_BASE_HI(p)	(0x019c + 8 * (p))
#define AS_SRC_STRIDE(p)	(0x01d8 + 4 * (p))
#define AS_SRC_OFFSET(p)	(0x01e8 + 4 * (p))	/* y<<16 | x, plane pixels */
#define AS_SRC_SWIZZLE		0x01f8
#define AS_SRC_W		0x01fc
#define AS_SRC_H		0x0200
#define AS_SRC_CACHE0(n)	(0x0204 + 4 * (n))	/* 4 */
#define AS_SRC_CACHE1(n)	(0x0214 + 4 * (n))	/* 4 */
#define AS_SRC_TUNABLE(n)	(0x0224 + 4 * (n))	/* 4 */
#define AS_SRC_PLANE_W(p)	(0x0234 + 4 * (p))
#define AS_SRC_PLANE_H(p)	(0x0244 + 4 * (p))

/* ---- WDMA (destination) [KEXT13.5 IosaWdmaControlMSR11] ---- */
#define AS_WDMA_CFG		0x0280
#define AS_WDMA_FMT(n)		(0x0284 + 4 * (n))	/* 3 slots, bit15 always */
#define  AS_WDMA_FMT_MARK	BIT(15)		/* hw14; 0x800 on M1 Max */
#define AS_DST_BASE_LO(p)	(0x0290 + 8 * (p))
#define AS_DST_BASE_HI(p)	(0x0294 + 8 * (p))
#define AS_DST_STRIDE(p)	(0x02c0 + 4 * (p))
#define AS_DST_OFFSET(p)	(0x02cc + 4 * (p))
#define AS_DST_SWIZZLE		0x02d8
#define AS_DST_W		0x02dc
#define AS_DST_H		0x02e0
#define AS_DST_CACHE0(n)	(0x02e4 + 4 * (n))	/* 3 */
#define AS_DST_CACHE1(n)	(0x02f0 + 4 * (n))	/* 3 */
#define AS_DST_TUNABLE(n)	(0x02fc + 4 * (n))	/* 3 */
#define AS_DST_PLANE_W(p)	(0x0308 + 4 * (p))
#define AS_DST_PLANE_H(p)	(0x0314 + 4 * (p))

#define AS_FLIP_ROTATE		0x0380	/* b1:0 rot cw, b2 flip up/down, b3 left/right */
#define AS_PSEUDO_LINEAR	0x0480
#define AS_LEGACY_CSC		0x0600	/* MSR2/4 only; 0 on hw14 */

/* ---- prescaler: chroma upsampler + 3x3 "location 0" [KEXT13.5] ---- */
#define AS_CHROMA_UPSAMPLE	0x0800	/* 0xc off, 0xd on */
#define AS_CHROMA_UP_COEF(n)	(0x0804 + 4 * (n))	/* 8 words */
#define AS_PRE3X3_CTRL		0x0824	/* b31 enable, b4:0 frac bits (12) */
#define AS_PRE3X3_PRE(n)	(0x0828 + 4 * (n))	/* S0.16 in 17 bits */
#define AS_PRE3X3_COEF(n)	(0x0834 + 4 * (n))	/* S3.12, row-major */
#define AS_PRE3X3_POST(n)	(0x0858 + 4 * (n))
#define AS_CHROMA_DOWNSAMPLE	0x0900	/* b0 H/2, b1 V/2, b9:8 H method, b17:16 V */
#define AS_DITHER		0x0a00

/* ---- polyphase scaler, V at 0x1000, H at 0x2000 [KEXT13.5][M1N1] ---- */
#define AS_SCL_V		0x1000
#define AS_SCL_H		0x2000
#define AS_SCL_FLAGS		0x00	/* b0 enable, b1 YCbCr source */
#define AS_SCL_DDA_LUMA		0x04	/* S1.22 */
#define AS_SCL_DDA_CHROMA	0x08
#define AS_SCL_RATIO_LUMA	0x0c	/* src/dst U4.22 */
#define AS_SCL_RATIO_CHROMA	0x10
#define AS_SCL_INV_LUMA		0x14	/* dst/src U4.22 */
#define AS_SCL_INV_CHROMA	0x18
#define AS_SCL_DDA_ALPHA	0x1c
#define AS_SCL_RATIO_ALPHA	0x20
#define AS_SCL_INV_ALPHA	0x24
#define AS_SCL_V_COEF0		0x1400	/* 9 taps x 32 phases, lo luma hi chroma */
#define AS_SCL_V_COEF1		0x1c00	/* 9 x 16, luma(alpha) packed 2 phases */
#define AS_SCL_H_COEF0		0x2400	/* 15 x 32 */
#define AS_SCL_H_COEF1		0x2c00	/* 15 x 16 */
#define AS_V_TAPS		9
#define AS_H_TAPS		15
#define AS_PHASES		32

/* ---- colour manager (MSR13 inherits MSR11/10/8) [KEXT13.5] ---- */
#define AS_HISTOGRAM_CTRL	0x3000
#define AS_CM_CTRL		0x3800	/* b0 CM on, b1 src2Rgb 3x3 (location 1) */
#define AS_CM_L1_SHIFT		0x3804	/* coefficient fraction bits (12) */
#define AS_CM_L1_PRE(n)		(0x3808 + 4 * (n))	/* S2.24 in 26 bits */
#define AS_CM_L1_COEF(n)	(0x3814 + 4 * (n))	/* S3.12 */
#define AS_CM_L1_POST(n)	(0x3838 + 4 * (n))

/* ---- internal pipe convert / revert [KEXT13.5][M1N1] ---- */
#define AS_CONVERT_CTRL		0x13800
#define AS_CONVERT_RANGE	0x13804
#define AS_CONVERT_FP16_0	0x13808
#define AS_CONVERT_FP16_1	0x1380c
#define AS_CONVERT_MAP(n)	(0x13810 + 4 * (n))	/* per-channel depth code */
#define AS_REVERT_CTRL		0x13c00
#define AS_REVERT_RANGE		0x13c04
#define AS_REVERT_MAP(n)	(0x13c10 + 4 * (n))

/* ---- ASE (enhancement / directional scaling): kept off ---- */
#define AS_ASE_CFG		0x16000
#define AS_ASE_3X1		0x16080
#define AS_ASE_ENHANCE		0x16800

/* ---- DPE (power estimator), reg index 2 [KEXT13.5 IosaDPEControlMSR11] ---- */
#define AS_DPE_CTRL		0x000
#define AS_DPE_CFG		0x004
#define AS_DPE_STATE		0x008
#define AS_DPE_EN0		0x400
#define AS_DPE_EN(i)		(0x404 + 4 * (i))
#define AS_DPE_VAL(i)		(0x43c + 8 * (i))
#define AS_DPE_ENTRIES		14

/* ---------------------------------------------------------------- */

enum as_class { AS_RGB, AS_YUV, AS_LUMA };

struct as_fmt {
	u32	fourcc;
	u8	class;		/* enum as_class */
	u8	planes;		/* memory planes inside one buffer: 1 or 2 */
	u8	cpp[2];		/* bytes per pixel (plane 1: per chroma sample pair) */
	u8	hsub, vsub;	/* chroma subsampling */
	u8	bits;		/* component depth */
	u8	alpha;
	u8	chroma_swap;	/* NV21: Cr before Cb */
	u8	code[2];	/* RDMA/WDMA format codes, plane 0 / 1 */
	u8	cfg;		/* 0x180 / 0x280 value */
	u32	swizzle;
	u8	map[4];		/* convert/revert per-channel depth codes */
};

struct as_q {
	const struct as_fmt	*fmt;
	u32			width, height;
	u32			bpl;		/* plane 0 bytesperline */
	u32			sizeimage;
	struct v4l2_rect	rect;		/* crop (OUTPUT) / compose (CAPTURE) */
	enum v4l2_colorspace	colorspace;
	enum v4l2_ycbcr_encoding ycbcr_enc;
	enum v4l2_quantization	quant;
	enum v4l2_xfer_func	xfer;
	u32			sequence;
};

/* one hardware pass */
struct as_surface {
	const struct as_fmt	*fmt;
	dma_addr_t		addr[2];	/* already offset to the rect origin */
	u32			stride[2];
	u32			w, h;		/* active rect */
	u32			plane_w, plane_h; /* from the rect origin to the frame end */
};

struct as_csc {
	bool	enable;
	s32	pre[3];		/* Q24 normalised */
	s32	coef[9];	/* Q24, row-major, rows out (R,G,B)/(Y,Cb,Cr) */
	s32	post[3];	/* Q24 */
};

struct as_pass {
	struct as_surface	src, dst;
	u32			rot;		/* 0..3, cw */
	bool			hflip, vflip;
	struct as_csc		csc;
	enum v4l2_quantization	src_quant;	/* for the record */
};

#define AS_MAX_PASSES		3

struct as_ctx {
	struct v4l2_fh		fh;
	struct as_dev		*dev;
	struct v4l2_ctrl_handler hdl;
	struct as_q		q[2];		/* 0 OUTPUT (src), 1 CAPTURE (dst) */
	u32			rotate;		/* degrees */
	bool			hflip, vflip;

	/* job plan, made at STREAMON of the second queue */
	unsigned int		npasses;
	u32			iw[AS_MAX_PASSES], ih[AS_MAX_PASSES];
	void			*tmp_cpu[2];
	dma_addr_t		tmp_dma[2];
	size_t			tmp_size;
	bool			pm_held;
};

struct as_filter_key {
	u32	ratio_luma, ratio_chroma;	/* U4.22 src/dst */
	u8	taps, valid;
};

struct as_dev {
	struct device		*dev;
	void __iomem		*base;
	void __iomem		*dpe;
	struct reset_control	*rst;
	struct dev_pm_domain_list *pd_list;
	int			irq;
	bool			irq_on;

	struct v4l2_device	v4l2_dev;
	struct video_device	vfd;
	struct v4l2_m2m_dev	*m2m_dev;
	struct mutex		mutex;
	spinlock_t		lock;

	/* running job */
	struct as_ctx		*cur;
	unsigned int		cur_pass;
	struct as_pass		passes[AS_MAX_PASSES];
	u32			transform_id;
	struct delayed_work	watchdog;
	struct work_struct	recover_work;
	bool			job_failed;
	u64			jobs, errors, recoveries;

	struct as_filter_key	fkey[2];	/* V, H currently in filter RAM */

	/* self-test / stage reporting */
	unsigned int		stage;
};

static inline u32 as_rd(struct as_dev *d, u32 reg)
{
	return readl_relaxed(d->base + reg);
}

static inline void as_wr(struct as_dev *d, u32 reg, u32 val)
{
	writel_relaxed(val, d->base + reg);
}

/* apple_scaler_drv.c */
const struct as_fmt *as_find_fmt(u32 fourcc);
u32 as_read_version(struct as_dev *d);

/* apple_scaler_math.c */
void as_make_filter(s16 *out, unsigned int taps, unsigned int used,
		    u32 ratio_u422, unsigned int kernel, bool phase_neg);
int as_build_csc(struct as_csc *csc,
		 const struct as_fmt *sf, enum v4l2_ycbcr_encoding senc,
		 enum v4l2_quantization squant,
		 const struct as_fmt *df, enum v4l2_ycbcr_encoding denc,
		 enum v4l2_quantization dquant);

/* apple_scaler_hw.c */
int as_hw_init(struct as_dev *d);
void as_hw_soft_reset(struct as_dev *d);
void as_hw_dpe_start(struct as_dev *d);
void as_hw_dpe_stop(struct as_dev *d);
int as_hw_program_pass(struct as_dev *d, const struct as_pass *p);
void as_hw_start(struct as_dev *d);
int as_hw_selftest(struct as_dev *d);

/* module parameters shared between files */
extern unsigned int as_param_kernel;
extern bool as_param_phase_neg;
extern bool as_param_dda_center;
extern unsigned int as_param_h_taps;
extern unsigned int as_param_csc_loc;
extern bool as_param_dpe;
extern bool as_param_dither;
extern unsigned int as_param_uyvy_swizzle;

#endif

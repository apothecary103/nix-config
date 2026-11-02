/* SPDX-License-Identifier: GPL-2.0-only */
/*
 * Apple ProRes engine (APR) on t6020 (M2 Pro): registers and the version 0
 * job descriptors.
 *
 * Forked from aurora-silicon/linux aurora-wip
 * drivers/media/platform/apple/prores/apple-prores.h (GPL-2.0-only, the
 * T8140 encoder), switched to the v0 descriptor that M1/M2-generation cores
 * use. Field names follow the m1n1 proxyclient (hw/prores.py,
 * experiments/prores.py, MIT/GPL-2.0+) and the names macOS 27.2's
 * AppleProResHW logs for them.
 *
 * Provenance labels:
 *   [KEXT13.5] AppleProResHW of the macOS 13.5 stub kernelcache (what the
 *              Linux boot's firmware pairs with), read from the decompile
 *   [KEXT27]   AppleProResHW of macOS 27.2 (this Mac), mostly its log strings
 *   [ADT]      the 13.5 j414sap ADT
 *   [M1N1]     m1n1's experiments/prores.py, a working encode on M1 Max
 *   [AURORA]   aurora's T8140 driver
 *   [SPEC]     SMPTE RDD 36 (ProRes bitstream), ffmpeg's ProRes tables
 *   [INF]      inferred, not observed
 */
#ifndef _APPLE_PRORES_H
#define _APPLE_PRORES_H

#include <linux/bits.h>
#include <linux/sizes.h>
#include <linux/types.h>

/* ---- core registers (reg "core", 16 KiB) ------------------------------- */

#define APR_REG_ID		0x0000	/* version; [KEXT13.5] APR_FindDevVersion */
#define APR_REG_MODE		0x0008	/* 0 = off, 0xd = run; bit 3 also a tunable */
#define APR_MODE_OFF		0x0
#define APR_MODE_RUN		0xd
#define APR_REG_IRQ_ENABLE	0x000c
#define APR_REG_IRQ_STATUS	0x0010	/* write 1 to clear */
#define APR_IRQ_DONE		BIT(0)
#define APR_IRQ_ERROR		BIT(1)
#define APR_REG_ST0		0x0014	/* bit 30 goes to the plugin as a frame flag */
#define APR_REG_ST1		0x0018
#define APR_REG_ST2		0x001c	/* [1:0] == 1: the "HW error" class 5/6 */
#define APR_REG_ST_DEC		0x003c	/* forwarded to the decode plugin */
#define APR_REG_ST_ENC		0x0044	/* forwarded to the encode plugin */
#define APR_REG_RING_SIZE	0x0100
#define APR_REG_RING_LO		0x0104	/* & 0xffffff80 */
#define APR_REG_RING_HI		0x0108	/* & 0x3ff */
#define APR_REG_RING_HEAD	0x010c	/* producer: offset [23:7], wrap toggle bit 24 */
#define APR_REG_RING_TAIL	0x0110	/* consumer, same encoding */
#define APR_RING_OFF_MASK	0x00ffff80
#define APR_RING_WRAP		BIT(24)

/* Statistics DMA, two channels sharing one buffer; version >= 3 cores. */
#define APR_REG_STATS0_LO	0x038c
#define APR_REG_STATS0_HI	0x0390
#define APR_REG_STATS0_SIZE	0x0394	/* set by the tunables (0x180000 on d0) */
#define APR_REG_STATS1_LO	0x070c
#define APR_REG_STATS1_HI	0x0710
#define APR_REG_STATS1_SIZE	0x0714
#define APR_STATS_MAX		SZ_4M

/* Matrices: five tables (XQ, HQ, 422, LT, Proxy) of 32 words per plane. */
#define APR_REG_QUANT_LUMA(t)	(0x0800 + (t) * 0x80)
#define APR_REG_QUANT_CHROMA(t)	(0x1000 + (t) * 0x80)
#define APR_REG_DC_SCALE(i)	(0x1800 + (i) * 4)
#define APR_DC_SCALE_ENTRIES	112

/* The DMA/control block the tunables may write. */
#define APR_TUNABLE_LIMIT	0x0800

/*
 * The SCODEC wrapper (reg "wrapper", 16 MiB at 0x3_1000_0000): only the
 * transaction limiters macOS drains before a reset. Write 0 to stop issue,
 * then outstanding reads [26:16] and writes [10:0] must reach 0.
 * [KEXT13.5] quiesceHWBulkTraffic / quiesceHWLLTTraffic, DevID 5 instance 0.
 */
#define APR_WRAP_BULK0		0x0f6c	/* control and status in one register */
#define APR_WRAP_BULK1		0x0e5c
#define APR_WRAP_LLT_CTL	0x0d48
#define APR_WRAP_LLT_STS	0x0d4c
#define APR_WRAP_RD_OUT		GENMASK(26, 16)
#define APR_WRAP_WR_OUT		GENMASK(10, 0)

#define APR_RING_BYTES		SZ_128K
#define APR_ENC_DESC_BYTES	0x180
#define APR_DEC_DESC_BYTES	0x100

enum apr_qtable {
	APR_QTABLE_XQ,
	APR_QTABLE_HQ,
	APR_QTABLE_STANDARD,
	APR_QTABLE_LT,
	APR_QTABLE_PROXY,
	APR_QTABLES,
};

enum apr_input {
	APR_INPUT_422_8,	/* NV16 */
	APR_INPUT_444_8,	/* NV24 */
	APR_INPUT_422_16,	/* P216 */
	APR_INPUT_444_16,	/* P416 */
	APR_INPUT_444A_8,	/* APA8: NV24 + alpha plane */
	APR_INPUT_444A_16,	/* APA6: P416 + alpha plane */
};

/* V4L2 profile menu order. */
enum apr_profile {
	APR_PROFILE_PROXY,
	APR_PROFILE_LT,
	APR_PROFILE_STANDARD,
	APR_PROFILE_HQ,
	APR_PROFILE_4444,
	APR_PROFILE_4444_XQ,
	APR_PROFILES,
};

/* Descriptor command word knobs whose right values are not settled. */
struct apr_cmd_knobs {
	u8 enc_mode;	/* cmd [11:8] for encode: 7 [M1N1], 6 [AURORA T8140] */
	u8 enc_passes;	/* cmd [5:4] "nPass": 3 in both */
	u8 dec_mode;	/* cmd [11:8] for decode: unknown, plugin-supplied */
	u8 crc_ctl;	/* desc 0x150 [1:0] "ControlCRC": 3 in both */
};

struct apr_frame {
	u32 width;
	u32 height;
	enum apr_input input;
	enum apr_profile profile;
	u32 luma_stride;	/* bytes, multiple of 64 */
	u32 chroma_stride;
	u32 alpha_stride;
	u64 luma;
	u64 chroma;
	u64 alpha;		/* 0: no alpha */
	u64 output;
	u32 output_size;
	u32 target_bytes;	/* 0: the profile's budget */
	u32 max_bytes;		/* 0: 9/8 of the target */
	u8 quant_index;		/* 0: the profile's */
	u16 frame_id;
	u8 primaries;
	u8 transfer;
	u8 matrix;
};

struct apr_dec_frame {
	u32 width;
	u32 height;
	bool is444;
	bool deep;		/* 16-bit samples, MSB aligned */
	u32 luma_stride;
	u32 chroma_stride;
	u64 input;
	u32 input_size;
	u64 luma;
	u64 chroma;
	u16 frame_id;
};

/* What a ProRes frame header says (decoder side). */
struct apr_frame_info {
	u32 frame_size;
	u16 width;
	u16 height;
	u8 chroma_format;	/* 2 = 4:2:2, 3 = 4:4:4 */
	u8 interlace;		/* 0 = progressive */
	u8 alpha_type;
	u8 version;
};

void apr_qmat_build(u32 luma[APR_QTABLES][32], u32 chroma[APR_QTABLES][32]);
u32 apr_dc_scale_reg(unsigned int index);
bool apr_profile_is_444(enum apr_profile profile);
bool apr_input_is_444(enum apr_input input);
bool apr_input_has_alpha(enum apr_input input);
bool apr_input_is_deep(enum apr_input input);
enum apr_qtable apr_profile_qtable(enum apr_profile profile);
void apr_frame_budget(enum apr_profile profile, u32 width, u32 height,
		      u32 *target, u32 *max);
u32 apr_slice_count(u32 width, u32 height, u32 log2_slice);
int apr_build_enc_desc(const struct apr_frame *f, const struct apr_cmd_knobs *k, u8 *desc);
int apr_build_dec_desc(const struct apr_dec_frame *f, const struct apr_cmd_knobs *k, u8 *desc);
int apr_check_output(const u8 *out, size_t capacity, u32 *frame_bytes);
int apr_parse_frame_header(const u8 *buf, size_t len, struct apr_frame_info *fi);

#endif

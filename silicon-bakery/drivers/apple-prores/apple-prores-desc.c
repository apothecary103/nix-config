// SPDX-License-Identifier: GPL-2.0-only
/*
 * Apple ProRes engine (APR): quantisation tables, DC scale, rate control and
 * the version 0 job descriptors. Nothing here touches hardware.
 *
 * Forked from aurora-silicon/linux aurora-wip
 * drivers/media/platform/apple/prores/apple-prores-desc.c (GPL-2.0-only):
 * the per-profile frame budget and the macroblock budget are aurora's; the
 * descriptor layout is version 0 ([KEXT13.5] ProgramEncodeYCbCrDescriptor
 * <ProRes_EncodeYCbCrDescriptor_v0_s> and DecodeFrame, field names from
 * [KEXT27]'s log strings), the matrices are computed from the public ProRes
 * tables with the [KEXT13.5] register packing.
 */
#include <linux/bitops.h>
#include <linux/errno.h>
#include <linux/kernel.h>
#include <linux/minmax.h>
#include <linux/sizes.h>
#include <linux/string.h>
#include <linux/unaligned.h>

#include "apple-prores.h"

/*
 * ProRes weight matrices, raster order, as SMPTE RDD 36 decoders and
 * ffmpeg's prores encoders carry them [SPEC]. The engine's five tables use
 * them as [KEXT13.5] ProgramCustomQuantizationAndRoundingMatrices does:
 *
 *   table   luma        chroma      dead-zone rounding
 *   0 XQ    xq_luma     hq          32
 *   1 HQ    hq          hq          32
 *   2 422   standard    standard    32
 *   3 LT    lt          lt          32
 *   4 Proxy proxy       proxy       32, 63 from the 7th anti-diagonal on
 *
 * The kext's own copies of these tables are byte-identical to the public
 * ones (checked against AppleProResHW 13.5); the dead-zone values are the
 * kext's, and equal the field values m1n1 traced on M1 Max [M1N1].
 */
static const u8 apr_qm_xq_luma[64] = {
	2, 2, 2, 2, 2, 2, 2, 2,
	2, 2, 2, 2, 2, 2, 2, 2,
	2, 2, 2, 2, 2, 2, 2, 2,
	2, 2, 2, 2, 2, 2, 2, 3,
	2, 2, 2, 2, 2, 2, 3, 3,
	2, 2, 2, 2, 2, 3, 3, 3,
	2, 2, 2, 2, 3, 3, 3, 4,
	2, 2, 2, 2, 3, 3, 4, 4,
};

static const u8 apr_qm_hq[64] = {
	4, 4, 4, 4, 4, 4, 4, 4,
	4, 4, 4, 4, 4, 4, 4, 4,
	4, 4, 4, 4, 4, 4, 4, 4,
	4, 4, 4, 4, 4, 4, 4, 5,
	4, 4, 4, 4, 4, 4, 5, 5,
	4, 4, 4, 4, 4, 5, 5, 6,
	4, 4, 4, 4, 5, 5, 6, 7,
	4, 4, 4, 4, 5, 6, 7, 7,
};

static const u8 apr_qm_standard[64] = {
	4, 4, 5, 5, 6, 7, 7, 9,
	4, 4, 5, 6, 7, 7, 9, 9,
	5, 5, 6, 7, 7, 9, 9, 10,
	5, 5, 6, 7, 7, 9, 9, 10,
	5, 6, 7, 7, 8, 9, 10, 12,
	6, 7, 7, 8, 9, 10, 12, 15,
	6, 7, 7, 9, 10, 11, 14, 17,
	7, 7, 9, 10, 11, 14, 17, 21,
};

static const u8 apr_qm_lt[64] = {
	4, 5, 6, 7, 9, 11, 13, 15,
	5, 5, 7, 8, 11, 13, 15, 17,
	6, 7, 9, 11, 13, 15, 15, 17,
	7, 7, 9, 11, 13, 15, 17, 19,
	7, 9, 11, 13, 14, 16, 19, 23,
	9, 11, 13, 14, 16, 19, 23, 29,
	9, 11, 13, 15, 17, 21, 28, 35,
	11, 13, 16, 17, 21, 28, 35, 41,
};

static const u8 apr_qm_proxy[64] = {
	4, 7, 9, 11, 13, 14, 63, 63,
	7, 7, 11, 12, 14, 63, 63, 63,
	9, 11, 13, 14, 63, 63, 63, 63,
	11, 11, 13, 14, 63, 63, 63, 63,
	11, 13, 14, 63, 63, 63, 63, 63,
	13, 14, 63, 63, 63, 63, 63, 63,
	13, 63, 63, 63, 63, 63, 63, 63,
	63, 63, 63, 63, 63, 63, 63, 63,
};

#define APR_DZ_DEFAULT	32	/* half a quantiser step, in 1/64 */
#define APR_DZ_DROP	63

static u8 apr_dz(enum apr_qtable t, unsigned int i)
{
	if (t == APR_QTABLE_PROXY && (i / 8 + i % 8) >= 7)
		return APR_DZ_DROP;
	return APR_DZ_DEFAULT;
}

/*
 * One register holds two neighbouring coefficients: weight in [5:0] and
 * dead-zone rounding in [11:6] for the even one, the same in [23:12] for the
 * odd one [KEXT13.5]. (A field of 0x802 is weight 2, rounding 32: the "bit 11
 * set" reading of the m1n1 values.)
 */
static u32 apr_qm_word(const u8 *w, enum apr_qtable t, unsigned int pair)
{
	unsigned int i = 2 * pair;

	return (w[i] & 0x3f) | (apr_dz(t, i) & 0x3f) << 6 |
	       (w[i + 1] & 0x3f) << 12 | (apr_dz(t, i + 1) & 0x3f) << 18;
}

void apr_qmat_build(u32 luma[APR_QTABLES][32], u32 chroma[APR_QTABLES][32])
{
	static const u8 *const l[APR_QTABLES] = {
		apr_qm_xq_luma, apr_qm_hq, apr_qm_standard, apr_qm_lt, apr_qm_proxy,
	};
	static const u8 *const c[APR_QTABLES] = {
		apr_qm_hq, apr_qm_hq, apr_qm_standard, apr_qm_lt, apr_qm_proxy,
	};
	unsigned int t, i;

	for (t = 0; t < APR_QTABLES; t++) {
		for (i = 0; i < 32; i++) {
			luma[t][i] = apr_qm_word(l[t], t, i);
			chroma[t][i] = apr_qm_word(c[t], t, i);
		}
	}
}

/*
 * DC quantiser scale, 112 entries: [KEXT13.5] ProgramDCQuantizationScale.
 * Entry i covers quantiser 2i+1 and 2i+2 up to 128, then steps of eight;
 * low 9 bits for the first, high 9 bits for the second, both wrapping at
 * 512. The values equal m1n1's traced table.
 */
u32 apr_dc_scale_reg(unsigned int index)
{
	u32 q = 2 * index + 1, s = 0x84 + 8 * index, lo, hi;

	if (index >= APR_DC_SCALE_ENTRIES)
		return 0;
	lo = q > 0x80 ? s : q;
	hi = q < 0x80 ? q + 1 : s - 0x1fc;
	return (lo & 0x1ff) | (hi & 0x1ff) << 9;
}

bool apr_profile_is_444(enum apr_profile profile)
{
	return profile == APR_PROFILE_4444 || profile == APR_PROFILE_4444_XQ;
}

bool apr_input_is_444(enum apr_input input)
{
	return input != APR_INPUT_422_8 && input != APR_INPUT_422_16;
}

bool apr_input_has_alpha(enum apr_input input)
{
	return input == APR_INPUT_444A_8 || input == APR_INPUT_444A_16;
}

bool apr_input_is_deep(enum apr_input input)
{
	return input == APR_INPUT_422_16 || input == APR_INPUT_444_16 ||
	       input == APR_INPUT_444A_16;
}

enum apr_qtable apr_profile_qtable(enum apr_profile profile)
{
	switch (profile) {
	case APR_PROFILE_PROXY:
		return APR_QTABLE_PROXY;
	case APR_PROFILE_LT:
		return APR_QTABLE_LT;
	case APR_PROFILE_STANDARD:
		return APR_QTABLE_STANDARD;
	case APR_PROFILE_4444_XQ:
		return APR_QTABLE_XQ;
	case APR_PROFILE_HQ:
	case APR_PROFILE_4444:
	default:
		return APR_QTABLE_HQ;
	}
}

/* ---- rate control [AURORA] --------------------------------------------- */

/*
 * Per profile: frame size relative to 422 HQ (a fraction) and the starting
 * quantiser. The engine refines the slice quantisers around the starting
 * one to meet the byte budget. Sizes agree with Apple's published target
 * data rates (Proxy ~ 0.21, LT ~ 0.46, 422 ~ 0.67, 4444 1.5, XQ 2.25 x HQ).
 */
static const struct {
	u8 num, den;
	u8 quant_index;
} apr_profile_policy[APR_PROFILES] = {
	[APR_PROFILE_PROXY] = { 13, 63, 8 },
	[APR_PROFILE_LT] = { 13, 28, 3 },
	[APR_PROFILE_STANDARD] = { 2, 3, 2 },
	[APR_PROFILE_HQ] = { 1, 1, 1 },
	[APR_PROFILE_4444] = { 3, 2, 1 },
	[APR_PROFILE_4444_XQ] = { 9, 4, 1 },
};

/*
 * Fixed rate-control settings, in [KEXT27]'s names: mbCategoryThr0..5
 * (7 bits each) with disQuantRefin in bit 63, alpha/alpha0/gamma0, four
 * betas and sixteen corrRatio_quantThr words. The same values are in
 * AppleProResHWEncoder's __const, m1n1's trace and aurora's driver; they do
 * not depend on profile, size or input.
 */
#define APR_RC_THRESHOLDS	0x8000402015100c0cULL
#define APR_RC_ALPHA		0x80
#define APR_RC_ALPHA0		0x80
#define APR_RC_GAMMA0		0x2c
static const u32 apr_rc_beta[4] = { 0x880080, 0x4e00c5, 0x9000d0, 0x200122 };
#define APR_RC_QUANT		0x400200

/* 422 HQ frame size for a picture of @pixels luma samples. */
static u64 apr_hq_budget(u64 pixels)
{
	static const struct { u32 pixels, bytes; } steps[] = {
		{ 349920, 294912 }, { 414720, 344064 }, { 691200, 442368 },
		{ 921600, 516096 }, { 1555200, 884736 }, { 2073600, 1032192 },
		{ 2359297, 1179648 },
	};

	for (unsigned int i = 0; i < ARRAY_SIZE(steps); i++)
		if (pixels <= steps[i].pixels)
			return steps[i].bytes;
	return pixels / 2;
}

/* Round n / 8 to a single-precision float, then down to an integer. */
static u64 apr_eighths_f32_floor(u64 n)
{
	int shift;
	u64 unit, q, r;

	if (!n)
		return 0;
	shift = fls64(n) - 24;
	if (shift <= 0)
		return n / 8;
	unit = 1ULL << shift;
	q = n >> shift;
	r = n & (unit - 1);
	if (r > unit / 2 || (r == unit / 2 && (q & 1)))
		q++;
	return (q << shift) / 8;
}

void apr_frame_budget(enum apr_profile profile, u32 width, u32 height,
		      u32 *target, u32 *max)
{
	u64 m = apr_hq_budget((u64)width * height) * apr_profile_policy[profile].num /
		apr_profile_policy[profile].den;

	m = round_down(max_t(u64, m, SZ_4K), SZ_4K);
	*target = 8 * m / 9;
	*max = apr_eighths_f32_floor(9ULL * *target);
}

/* A frame budget as Q3 bytes per macroblock, after header and slice table. */
static u16 apr_mb_budget(u32 bytes, u32 slices, u32 mbs)
{
	u32 overhead = 164 + 8 * slices;
	u32 left = bytes > overhead ? bytes - overhead : 1;

	return min(16383U, 8 * (left / mbs));
}

/*
 * Slices per picture: full slices per row, then the remainder in powers of
 * two ([KEXT13.5] computes the same for desc 0xec).
 */
u32 apr_slice_count(u32 width, u32 height, u32 log2_slice)
{
	u32 mbw = DIV_ROUND_UP(width, 16), mbh = DIV_ROUND_UP(height, 16);

	return (hweight32(mbw & (BIT(log2_slice) - 1)) + (mbw >> log2_slice)) * mbh;
}

/* ---- descriptors -------------------------------------------------------- */

/*
 * Command word, encode and decode alike ([KEXT27] "fid fstpss Int enc a cmp
 * nPass cfmt bd", positions from [KEXT13.5]):
 */
#define D_CMD_FRAME_ID(x)	((u32)(x) << 16)	/* [31:16] */
#define D_CMD_FAST_PASS		BIT(13)
#define D_CMD_INT_EN		BIT(12)			/* interrupt on completion */
#define D_CMD_MODE(x)		(((x) & 0xf) << 8)	/* encMode / decode mode */
#define D_CMD_ALPHA		BIT(7)
#define D_CMD_COMPRESSED	BIT(6)			/* tiled/compressed surfaces: never here */
#define D_CMD_PASSES(x)		(((x) & 3) << 4)
#define D_CMD_CFMT(x)		(((x) & 3) << 2)	/* 2 = 4:2:2, 3 = 4:4:4 */
#define D_CMD_BD(x)		((x) & 3)		/* 0 = 8 bit, 3 = 16 bit MSB */
#define D_CMDX			0x004	/* LCY [1:0], LCC [3:2], LCA [5:4]: per-plane
					 * compression of a compressed surface; 0 */
#define APR_CFMT_422		2
#define APR_CFMT_444		3
#define APR_BD_16		3	/* [AURORA]; 1 and 2 also give 16-bit reads [M1N1] */

/* Encode, 0x180 bytes. Little-endian unless noted. */
#define E_CMD			0x000
#define E_OUTPUT		0x008
#define E_OUTPUT_SIZE		0x010
#define E_OFFSET_X		0x014
#define E_OFFSET_Y		0x016
#define E_SIZE_H		0x018
#define E_SIZE_V		0x01a
#define E_WIDTH			0x01c
#define E_HEIGHT		0x01e
#define E_LUMA_STRIDE		0x020	/* bytes / 64 */
#define E_CHROMA_STRIDE		0x022
#define E_ALPHA_STRIDE		0x024
#define E_LUMA			0x028	/* 0x030: luma tile header (compressed only) */
#define E_CHROMA		0x038
#define E_ALPHA			0x048
/* The ProRes frame header the engine writes, 0x58..0xeb, big-endian. */
#define E_FH_SIZE		0x058
#define E_FH_VERSION		0x05b
#define E_FH_VENDOR		0x05c
#define E_FH_WIDTH		0x060
#define E_FH_HEIGHT		0x062
#define E_FH_FORMAT		0x064	/* chroma_format [7:6], interlace_mode [3:2] */
#define E_FH_ASPECT_RATE	0x065
#define E_FH_PRIMARIES		0x066
#define E_FH_TRANSFER		0x067
#define E_FH_MATRIX		0x068
#define E_FH_ALPHA		0x069	/* source format [7:4], alpha_channel_type [3:0] */
#define E_FH_FLAGS		0x06b	/* load_luma_qmat bit 1, load_chroma_qmat bit 0 */
/* 0x06c-0x0eb: the two 64-byte matrices. The engine fills them. */
#define E_FH_BYTES		0x94
#define E_SLICES		0x0ec	/* big-endian */
#define E_SLICE_LOG2		0x0ee	/* high nibble */
#define E_QUANT_INDEX		0x0ef
#define E_RC_TARGET		0x0f0	/* TargetSize: Q3 bytes per macroblock */
#define E_RC_MAX		0x0f2	/* MaxSize */
#define E_RC_THRESHOLDS		0x0f4
#define E_RC_ALPHA		0x0fc
#define E_RC_ALPHA0		0x0fd
#define E_RC_GAMMA0		0x0fe	/* 6 bits */
#define E_RC_BETA		0x100
#define E_RC_QUANT		0x110
#define E_QTABLE_SEL		0x150	/* QuantMatrixIndex [7:4], ControlCRC [1:0] */

#define APR_SLICE_LOG2		3
#define APR_VENDOR		"bkry"	/* the frame header's encoder identifier */

int apr_build_enc_desc(const struct apr_frame *f, const struct apr_cmd_knobs *k, u8 *desc)
{
	bool is444 = apr_input_is_444(f->input);
	bool deep = apr_input_is_deep(f->input);
	bool alpha = apr_input_has_alpha(f->input);
	enum apr_qtable table = apr_profile_qtable(f->profile);
	u32 min_luma, cmd, slices, mbs, target, max;
	u8 qi, fh_alpha;
	unsigned int i;

	if (f->profile >= APR_PROFILES || is444 != apr_profile_is_444(f->profile))
		return -EINVAL;
	if (f->width < 16 || f->height < 16 || f->width > 8192 || f->height > 8192 ||
	    f->width & 1)
		return -EINVAL;
	min_luma = f->width * (deep ? 2 : 1);
	if (f->luma_stride % 64 || f->chroma_stride % 64 ||
	    f->luma_stride < min_luma || f->chroma_stride < min_luma * (is444 ? 2 : 1) ||
	    f->luma_stride / 64 > U16_MAX || f->chroma_stride / 64 > U16_MAX)
		return -EINVAL;
	if (alpha && (f->alpha_stride % 64 || f->alpha_stride < min_luma ||
		      f->alpha_stride / 64 > U16_MAX || !f->alpha))
		return -EINVAL;
	if (!f->luma || !f->chroma || !f->output || f->output_size < SZ_4K)
		return -EINVAL;
	slices = apr_slice_count(f->width, f->height, APR_SLICE_LOG2);
	if (slices > U16_MAX)
		return -EINVAL;
	mbs = DIV_ROUND_UP(f->width, 16) * DIV_ROUND_UP(f->height, 16);

	apr_frame_budget(f->profile, f->width, f->height, &target, &max);
	if (f->target_bytes) {
		target = clamp(f->target_bytes, (u32)SZ_4K, f->output_size);
		max = apr_eighths_f32_floor(9ULL * target);
	}
	if (f->max_bytes)
		max = max(f->max_bytes, target);
	max = min(max, f->output_size);
	qi = f->quant_index ?: apr_profile_policy[f->profile].quant_index;

	memset(desc, 0, APR_ENC_DESC_BYTES);

	cmd = D_CMD_FRAME_ID(f->frame_id) | D_CMD_FAST_PASS | D_CMD_INT_EN |
	      D_CMD_MODE(k->enc_mode) | D_CMD_PASSES(k->enc_passes) |
	      D_CMD_CFMT(is444 ? APR_CFMT_444 : APR_CFMT_422) |
	      D_CMD_BD(deep ? APR_BD_16 : 0);
	if (alpha)
		cmd |= D_CMD_ALPHA;
	put_unaligned_le32(cmd, desc + E_CMD);
	put_unaligned_le32(0, desc + D_CMDX);
	put_unaligned_le64(f->output, desc + E_OUTPUT);
	put_unaligned_le32(f->output_size, desc + E_OUTPUT_SIZE);
	put_unaligned_le16(f->width, desc + E_SIZE_H);
	put_unaligned_le16(f->height, desc + E_SIZE_V);
	put_unaligned_le16(f->width, desc + E_WIDTH);
	put_unaligned_le16(f->height, desc + E_HEIGHT);
	put_unaligned_le16(f->luma_stride / 64, desc + E_LUMA_STRIDE);
	put_unaligned_le16(f->chroma_stride / 64, desc + E_CHROMA_STRIDE);
	/* m1n1 gives the luma plane as a dummy alpha plane; do the same. */
	put_unaligned_le16((alpha ? f->alpha_stride : f->luma_stride) / 64,
			   desc + E_ALPHA_STRIDE);
	put_unaligned_le64(f->luma, desc + E_LUMA);
	put_unaligned_le64(f->chroma, desc + E_CHROMA);
	put_unaligned_le64(alpha ? f->alpha : f->luma, desc + E_ALPHA);

	/* Frame header, as [KEXT13.5] fills it. */
	put_unaligned_be16(E_FH_BYTES, desc + E_FH_SIZE);
	desc[E_FH_VERSION] = (!is444 && !alpha) ? 0 : 1;
	memcpy(desc + E_FH_VENDOR, APR_VENDOR, 4);
	put_unaligned_be16(f->width, desc + E_FH_WIDTH);
	put_unaligned_be16(f->height, desc + E_FH_HEIGHT);
	desc[E_FH_FORMAT] = (is444 ? APR_CFMT_444 : APR_CFMT_422) << 6;	/* progressive */
	desc[E_FH_ASPECT_RATE] = 0;					/* unknown/unknown */
	desc[E_FH_PRIMARIES] = f->primaries;
	desc[E_FH_TRANSFER] = f->transfer;
	desc[E_FH_MATRIX] = f->matrix;
	if (is444)
		fh_alpha = deep ? 0xe0 : 0xd0;
	else
		fh_alpha = deep ? 0x30 : 0x10;
	/* alpha_channel_type: 1 = 8-bit, 2 = 16-bit alpha [SPEC] */
	if (alpha)
		fh_alpha |= deep ? 2 : 1;
	desc[E_FH_ALPHA] = fh_alpha;
	desc[E_FH_FLAGS] = 0x03;

	put_unaligned_be16(slices, desc + E_SLICES);
	desc[E_SLICE_LOG2] = APR_SLICE_LOG2 << 4;
	desc[E_QUANT_INDEX] = qi;

	put_unaligned_le16(apr_mb_budget(target, slices, mbs), desc + E_RC_TARGET);
	put_unaligned_le16(apr_mb_budget(max, slices, mbs), desc + E_RC_MAX);
	put_unaligned_le64(APR_RC_THRESHOLDS, desc + E_RC_THRESHOLDS);
	desc[E_RC_ALPHA] = APR_RC_ALPHA;
	desc[E_RC_ALPHA0] = APR_RC_ALPHA0;
	desc[E_RC_GAMMA0] = APR_RC_GAMMA0;
	for (i = 0; i < ARRAY_SIZE(apr_rc_beta); i++)
		put_unaligned_le32(apr_rc_beta[i], desc + E_RC_BETA + 4 * i);
	for (i = 0; i < 16; i++)
		put_unaligned_le32(APR_RC_QUANT, desc + E_RC_QUANT + 4 * i);
	put_unaligned_le32(table << 4 | (k->crc_ctl & 3), desc + E_QTABLE_SEL);
	return 0;
}

/*
 * Decode (YCbCr), 0x100 bytes: [KEXT13.5] DecodeFrame, client type 0.
 * 0x10..0x1a are six 16-bit fields from the plugin; the kext derives the
 * macroblock count from 0x14/0x16, so those are the coded width and height.
 * 0x10/0x12 and 0x18/0x1a are taken to be offsets and left 0 [INF].
 */
#define DD_CMD			0x000
#define DD_INPUT		0x008
#define DD_OFFSET_X		0x010
#define DD_OFFSET_Y		0x012
#define DD_CODED_W		0x014
#define DD_CODED_H		0x016
#define DD_UNK_18		0x018
#define DD_UNK_1A		0x01a
#define DD_WIDTH		0x01c
#define DD_HEIGHT		0x01e
#define DD_LUMA_STRIDE		0x020	/* (bytes + 63) / 64 */
#define DD_CHROMA_STRIDE	0x022
#define DD_ALPHA_STRIDE		0x024
#define DD_LUMA			0x028
#define DD_CHROMA		0x038
#define DD_ALPHA		0x048
#define DD_INPUT_SIZE		0x090

int apr_build_dec_desc(const struct apr_dec_frame *f, const struct apr_cmd_knobs *k, u8 *desc)
{
	u32 cmd, min_luma;

	if (f->width < 16 || f->height < 16 || f->width > 8192 || f->height > 8192)
		return -EINVAL;
	min_luma = f->width * (f->deep ? 2 : 1);
	if (f->luma_stride % 64 || f->chroma_stride % 64 || f->luma_stride < min_luma ||
	    f->chroma_stride < min_luma * (f->is444 ? 2 : 1) ||
	    f->luma_stride / 64 > U16_MAX || f->chroma_stride / 64 > U16_MAX)
		return -EINVAL;
	if (!f->input || f->input_size < 8 + E_FH_BYTES || !f->luma || !f->chroma)
		return -EINVAL;

	memset(desc, 0, APR_DEC_DESC_BYTES);
	cmd = D_CMD_FRAME_ID(f->frame_id) | D_CMD_INT_EN | D_CMD_MODE(k->dec_mode) |
	      D_CMD_CFMT(f->is444 ? APR_CFMT_444 : APR_CFMT_422) |
	      D_CMD_BD(f->deep ? APR_BD_16 : 0);
	put_unaligned_le32(cmd, desc + DD_CMD);
	put_unaligned_le32(0, desc + D_CMDX);
	put_unaligned_le64(f->input, desc + DD_INPUT);
	put_unaligned_le16(0, desc + DD_OFFSET_X);
	put_unaligned_le16(0, desc + DD_OFFSET_Y);
	put_unaligned_le16(f->width, desc + DD_CODED_W);
	put_unaligned_le16(f->height, desc + DD_CODED_H);
	put_unaligned_le16(0, desc + DD_UNK_18);
	put_unaligned_le16(0, desc + DD_UNK_1A);
	put_unaligned_le16(f->width, desc + DD_WIDTH);
	put_unaligned_le16(f->height, desc + DD_HEIGHT);
	put_unaligned_le16(f->luma_stride / 64, desc + DD_LUMA_STRIDE);
	put_unaligned_le16(f->chroma_stride / 64, desc + DD_CHROMA_STRIDE);
	put_unaligned_le16(f->luma_stride / 64, desc + DD_ALPHA_STRIDE);
	put_unaligned_le64(f->luma, desc + DD_LUMA);
	put_unaligned_le64(f->chroma, desc + DD_CHROMA);
	put_unaligned_le64(f->luma, desc + DD_ALPHA);	/* no alpha output */
	put_unaligned_le32(f->input_size, desc + DD_INPUT_SIZE);
	return 0;
}

/*
 * A finished frame starts with its big-endian length, which counts the whole
 * frame, then the 'icpf' frame identifier [SPEC].
 */
int apr_check_output(const u8 *out, size_t capacity, u32 *frame_bytes)
{
	u32 size;

	if (capacity < 8)
		return -EINVAL;
	size = get_unaligned_be32(out);
	if (memcmp(out + 4, "icpf", 4) || size < 8 + E_FH_BYTES || size > capacity)
		return -EIO;
	*frame_bytes = size;
	return 0;
}

int apr_parse_frame_header(const u8 *buf, size_t len, struct apr_frame_info *fi)
{
	const u8 *h = buf + 8;
	u16 hsize;

	if (len < 8 + 20 || memcmp(buf + 4, "icpf", 4))
		return -EINVAL;
	fi->frame_size = get_unaligned_be32(buf);
	hsize = get_unaligned_be16(h);
	if (hsize < 20 || 8 + (size_t)hsize > len || fi->frame_size > len ||
	    fi->frame_size < 8u + hsize)
		return -EINVAL;
	fi->version = h[3];
	fi->width = get_unaligned_be16(h + 8);
	fi->height = get_unaligned_be16(h + 10);
	fi->chroma_format = h[12] >> 6;
	fi->interlace = (h[12] >> 2) & 3;
	fi->alpha_type = h[17] & 0xf;
	if (fi->version > 1 || (fi->chroma_format != 2 && fi->chroma_format != 3))
		return -EINVAL;
	return 0;
}

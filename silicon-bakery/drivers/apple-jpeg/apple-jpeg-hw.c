// SPDX-License-Identifier: GPL-2.0-only
/*
 * Apple M2 Pro (t6020) JPEG codec: job programming without hardware
 * access, so it can be checked away from the machine.
 *
 * Forked from aurora-silicon's apple-jpeg-hw.c (aurora-wip 27c8c52a, Ryan
 * Murray, GPL-2.0-only): the IJG quality scaling and the write-list shape
 * are theirs. Defaults, tunables, the per-format tiling and the decoder are
 * from the macOS AppleJPEGHalV11 [KEXT13.5]; see apple-jpeg-hw.h for labels.
 *
 * Quantisation tables are computed: ITU-T T.81 Annex K tables K.1/K.2
 * scaled with the libjpeg (IJG) quality formula. No Apple table is used.
 */
#include <linux/errno.h>
#include <linux/kernel.h>
#include <linux/minmax.h>
#include <linux/string.h>
#include <linux/wordpart.h>

#include "apple-jpeg-hw.h"

/*
 * Per-core tunables, mask 0xff, applied by reset_jpeg_block between the
 * defaults and MODE 0x17f [KEXT13.5]; equal in 27.2 [KEXT27]. 0x098..0x0d8
 * sit in the high half of the 64-bit DMA pointer slots, 0x294..0x2b8 in the
 * DMA engine block [INF: AXI stream IDs / QoS].
 */
const struct apple_jpeg_tunable apple_jpeg_tunables[2][APPLE_JPEG_NUM_TUNABLES] = {
	{	/* jpeg0, 0x3_8d00_0000 */
		{ 0x098, 0x01 }, { 0x0a8, 0x02 }, { 0x0c8, 0x03 }, { 0x0d8, 0x04 },
		{ 0x298, 0x05 }, { 0x29c, 0x06 }, { 0x2b4, 0x07 }, { 0x2b8, 0x08 },
		{ 0x294, 0x07 }, { 0x2b0, 0x07 },
	},
	{	/* jpeg1, 0x3_8d00_8000 */
		{ 0x098, 0x09 }, { 0x0a8, 0x0a }, { 0x0c8, 0x0b }, { 0x0d8, 0x0c },
		{ 0x298, 0x0d }, { 0x29c, 0x0e }, { 0x2b4, 0x0f }, { 0x2b8, 0x10 },
		{ 0x294, 0x07 }, { 0x2b0, 0x07 },
	},
};

/* T.81 Annex K, tables K.1 and K.2, natural (row-major) order [AURORA] */
static const u8 aj_annex_k_luma[64] = {
	16, 11, 10, 16, 24, 40, 51, 61,
	12, 12, 14, 19, 26, 58, 60, 55,
	14, 13, 16, 24, 40, 57, 69, 56,
	14, 17, 22, 29, 51, 87, 80, 62,
	18, 22, 37, 56, 68, 109, 103, 77,
	24, 35, 55, 64, 81, 104, 113, 92,
	49, 64, 78, 87, 103, 121, 120, 101,
	72, 92, 95, 98, 112, 100, 103, 99,
};

static const u8 aj_annex_k_chroma[64] = {
	17, 18, 24, 47, 99, 99, 99, 99,
	18, 21, 26, 66, 99, 99, 99, 99,
	24, 26, 56, 99, 99, 99, 99, 99,
	47, 66, 99, 99, 99, 99, 99, 99,
	99, 99, 99, 99, 99, 99, 99, 99,
	99, 99, 99, 99, 99, 99, 99, 99,
	99, 99, 99, 99, 99, 99, 99, 99,
	99, 99, 99, 99, 99, 99, 99, 99,
};

/* libjpeg jpeg_quality_scaling() + jpeg_add_quant_table(force_baseline) */
void apple_jpeg_quant_tables(u32 quality, u8 luma[64], u8 chroma[64])
{
	u32 q = clamp_t(u32, quality, 1, 100);
	u32 scale = q < 50 ? 5000 / q : 200 - 2 * q;

	for (unsigned int i = 0; i < 64; i++) {
		luma[i] = clamp_t(u32, (aj_annex_k_luma[i] * scale + 50) / 100, 1, 255);
		chroma[i] = clamp_t(u32, (aj_annex_k_chroma[i] * scale + 50) / 100, 1, 255);
	}
}

/*
 * ajpeg_driver_check_setup_encode plus startEncoderGated, which forces
 * 4:2:2 for packed 4:2:2 input [KEXT13.5]. 4:1:1 encode is refused there.
 */
bool apple_jpeg_enc_supported(enum aj_codec codec, enum aj_pixfmt fmt)
{
	switch (codec) {
	case AJ_CODEC_444:
		return fmt == AJ_PIX_YUV444_2P;
	case AJ_CODEC_422:
		return fmt == AJ_PIX_YUV444_2P || fmt == AJ_PIX_YUV422_2P ||
		       fmt == AJ_PIX_YUV422_1P;
	case AJ_CODEC_420:
	case AJ_CODEC_400:
		return fmt == AJ_PIX_YUV444_2P || fmt == AJ_PIX_YUV422_2P ||
		       fmt == AJ_PIX_YUV420_2P;
	default:
		return false;
	}
}

/* ajpeg_driver_check_setup_decode: no 4:4:4 2P output from subsampled JPEGs */
bool apple_jpeg_dec_supported(enum aj_codec codec, enum aj_pixfmt fmt)
{
	if (codec > AJ_CODEC_400 || fmt > AJ_PIX_YUV422_1P)
		return false;
	if (fmt == AJ_PIX_YUV444_2P)
		return codec == AJ_CODEC_444 || codec == AJ_CODEC_400;
	return true;
}

/*
 * ajpeg_drv_set_image_boundary at scale 1: bytes per row of plane 0 and 1,
 * rows of plane 1 (0 = no plane 1) for a w x h image [KEXT13.5].
 */
void apple_jpeg_plane_sizes(enum aj_pixfmt fmt, u32 w, u32 h, u32 *w0, u32 *w1, u32 *h1)
{
	switch (fmt) {
	case AJ_PIX_YUV444_2P:
		*w0 = w;
		*w1 = 2 * w;
		*h1 = h;
		break;
	case AJ_PIX_YUV422_2P:
		*w0 = w;
		*w1 = (w + 1) & ~1u;
		*h1 = h;
		break;
	case AJ_PIX_YUV420_2P:
		*w0 = w;
		*w1 = (w + 1) & ~1u;
		*h1 = (h + 1) >> 1;
		break;
	default:	/* packed 4:2:2 */
		*w0 = (2 * w + 2) & ~3u;
		*w1 = 0;
		*h1 = 0;
		break;
	}
}

/* Engine cycles allowed: 6 per output sample + 66.5M, at least 266M [KEXT13.5] */
static u32 aj_timeout(u64 samples)
{
	u64 t = samples * 6 + 66500000;

	return clamp_t(u64, t, 266000000, U32_MAX);
}

struct aj_list {
	struct apple_jpeg_write *w;
	unsigned int n, max;
};

static void aj_put(struct aj_list *l, u32 offset, u32 value)
{
	if (l->n < l->max)
		l->w[l->n] = (struct apple_jpeg_write){ offset, value };
	l->n++;
}

static void aj_put64(struct aj_list *l, u32 offset, u64 value)
{
	aj_put(l, offset, lower_32_bits(value));
	aj_put(l, offset + 4, upper_32_bits(value));
}

static void aj_put_range(struct aj_list *l, u32 from, u32 to, u32 value)
{
	for (u32 off = from; off <= to; off += 4)
		aj_put(l, off, value);
}

/* ajpeg_driver_set_default_regs, in its order [KEXT13.5] */
static void aj_defaults(struct aj_list *l, bool tiled)
{
	aj_put(l, 0x000, 0);
	aj_put(l, 0x004, 0);
	aj_put(l, 0x028, 0);
	aj_put(l, 0x02c, 0);
	aj_put(l, 0x030, 0);
	aj_put(l, AJ_DECODE_ENABLE, 1);
	aj_put(l, AJ_ENCODE_ENABLE, 1);
	aj_put_range(l, 0x03c, 0x054, 0);
	aj_put(l, AJ_PLANAR_CHROMA_HALVE, 0);
	aj_put(l, AJ_PX_USE_PLANE1, 0);
	aj_put_range(l, 0x05c, 0x088, 1);
	aj_put(l, 0x090, 0);
	aj_put(l, 0x0a0, 0);
	aj_put(l, AJ_PIPE_LIMIT0, 1);
	aj_put(l, AJ_PIPE_LIMIT1, 1);
	aj_put(l, 0x0b0, 0xffffffff);
	aj_put(l, 0x0c0, 0);
	aj_put(l, 0x0d0, 0);
	aj_put(l, 0x0e0, 0xffffffff);
	aj_put(l, 0x094, 0);
	aj_put(l, 0x0a4, 0);
	aj_put(l, 0x0b4, 0xf);
	aj_put(l, 0x0c4, 0);
	aj_put(l, 0x0d4, 0);
	aj_put(l, 0x0e4, 0xf);
	aj_put_range(l, 0x0e8, 0x110, 0);	/* matrix */
	aj_put_range(l, 0x114, 0x138, 0xff);	/* dither */
	aj_put_range(l, 0x13c, 0x170, 0);
	aj_put_range(l, 0x184, 0x194, 0);
	aj_put_range(l, 0x174, 0x180, 0);
	aj_put_range(l, 0x238, 0x254, 0);
	aj_put_range(l, 0x260, 0x278, 0);
	aj_put(l, 0x27c, 0);
	aj_put(l, 0x280, 8000);
	aj_put(l, 0x290, 0);
	aj_put(l, 0x294, 7);
	aj_put(l, 0x2ac, 0);
	aj_put(l, 0x2b0, 7);
	aj_put(l, 0x288, 0);
	aj_put(l, 0x28c, 0);
	aj_put(l, 0x2a4, 0);
	aj_put(l, 0x2a8, 0);
	aj_put_range(l, 0x218, 0x234, 0);
	/*
	 * 0 for linear surfaces as macOS's reset does [KEXT13.5]. aurora writes
	 * 1 when encoding on T8140 [AURORA]; which is right here is [HW].
	 */
	aj_put(l, AJ_TILING_ENABLE, tiled);
	aj_put(l, AJ_TIMEOUT, 0);
	aj_put(l, AJ_IRQ_MASK, 0xff);
}

int apple_jpeg_defaults(bool tiled, struct apple_jpeg_write *w, unsigned int max)
{
	struct aj_list l = { w, 0, max };

	aj_defaults(&l, tiled);
	return l.n <= max ? l.n : -ENOSPC;
}

/* Plane geometry, MCU-independent part (set_image_boundary) */
static void aj_boundary(struct aj_list *l, enum aj_pixfmt fmt, u32 w, u32 h,
			u32 scale, u32 *w0, u32 *w1, u32 *h1)
{
	apple_jpeg_plane_sizes(fmt, w, h, w0, w1, h1);
	aj_put(l, AJ_PX_USE_PLANE1, *h1 ? 1 : 0);
	aj_put(l, AJ_PX_PLANE0_WIDTH_M1, *w0 - 1);
	aj_put(l, AJ_PX_PLANE0_HEIGHT_M1, h - 1);
	/* 0 - 1 for packed formats, as the kext writes [KEXT13.5] */
	aj_put(l, AJ_PX_PLANE1_WIDTH_M1, *w1 - 1);
	aj_put(l, AJ_PX_PLANE1_HEIGHT_M1, *h1 - 1);
	aj_put(l, AJ_TIMEOUT, aj_timeout((u64)scale * scale *
					 ((u64)*w0 * h + (u64)*w1 * *h1)));
}

static void aj_qtable(struct aj_list *l, unsigned int t, const u8 q[64])
{
	for (unsigned int i = 0; i < 16; i++)
		aj_put(l, AJ_QTBL(t) + 4 * i, q[4 * i] << 24 | q[4 * i + 1] << 16 |
		       q[4 * i + 2] << 8 | q[4 * i + 3]);
}

/* ajpeg_drv_setx_encode_CMP_YUV_*: tile sizes, pipe limits [KEXT13.5] */
static void aj_enc_tiles(struct aj_list *l, enum aj_codec codec, enum aj_pixfmt fmt)
{
	static const u8 tile400[] = { 1, 1, 1, 2 };	/* by fmt */
	u32 p0h = 2, p0v = 8, p1h = 0, p1v = 0, lim0, lim1;

	switch (codec) {
	case AJ_CODEC_444:
		p0h = 1; p1h = 2; p1v = 8;
		lim0 = 0xc; lim1 = 2;
		break;
	case AJ_CODEC_422:
		if (fmt == AJ_PIX_YUV422_1P) {
			p0h = 4;
		} else {
			p1h = fmt == AJ_PIX_YUV444_2P ? 4 : 2;
			p1v = 8;
		}
		lim0 = 8; lim1 = 2;
		break;
	case AJ_CODEC_420:
		p0v = 16;
		if (fmt == AJ_PIX_YUV422_1P) {
			p0h = 4;
		} else {
			p1h = fmt == AJ_PIX_YUV444_2P ? 4 : 2;
			p1v = fmt == AJ_PIX_YUV420_2P ? 8 : 16;
		}
		lim0 = 3; lim1 = 1;
		break;
	default:	/* 400 */
		p0h = tile400[fmt];
		lim0 = 0xb; lim1 = 2;
		break;
	}
	aj_put(l, AJ_PX_PLANE0_TILE_H, p0h);
	aj_put(l, AJ_PX_PLANE0_TILE_V, p0v);
	if (p1h) {
		aj_put(l, AJ_PX_PLANE1_TILE_H, p1h);
		aj_put(l, AJ_PX_PLANE1_TILE_V, p1v);
	}
	aj_put(l, AJ_PIPE_LIMIT0, lim0);
	aj_put(l, AJ_PIPE_LIMIT1, lim1);
}

/*
 * Every register write of one baseline encode, in macOS's order
 * (startEncoderGated -> ajpeg_drv_set_encode), ending with the start.
 * The engine has been reset (apple_jpeg_reset in the driver) before.
 */
int apple_jpeg_build_encode(const struct apple_jpeg_enc_job *job,
			    struct apple_jpeg_write *w, unsigned int max)
{
	static const u8 mcu_w[] = { 8, 16, 0, 16, 8 }, mcu_h[] = { 8, 8, 0, 16, 8 };
	static const u8 io_ss[] = { 0, 1, 0, 2, 3 };	/* 0x1000 low bits [KEXT13.5] */
	u32 width = job->width, height = job->height, w0, w1, h1;
	struct aj_list l = { w, 0, max };
	u8 luma[64], chroma[64];

	if (!width || !height || width > U16_MAX || height > U16_MAX)
		return -EINVAL;
	if (!apple_jpeg_enc_supported(job->codec, job->fmt))
		return -EINVAL;
	if ((job->plane0 | job->plane1 | job->output) & 127 || !job->output_size)
		return -EINVAL;
	if (job->input_end < job->plane0 || job->restart_interval > U16_MAX)
		return -EINVAL;

	aj_put(&l, AJ_MODE, AJ_MODE_SETUP);
	aj_put(&l, AJ_RUN, 0);
	aj_defaults(&l, false);
	aj_put(&l, AJ_MODE, AJ_MODE_OPEN);

	/* ajpeg_drv_set_encode */
	aj_put(&l, AJ_ENCODE_ENABLE, 1);
	aj_put(&l, AJ_CODEC_MODE, 1);
	aj_put(&l, AJ_DECODE_ENABLE, 0);
	aj_put(&l, AJ_CODEC, job->codec);
	aj_boundary(&l, job->fmt, width, height, 1, &w0, &w1, &h1);
	if (job->stride0 < w0 || (h1 && job->stride1 < w1))
		return -EINVAL;

	/* set_encode_mbcounts */
	aj_put(&l, AJ_PX_MCUS_W, DIV_ROUND_UP(width, mcu_w[job->codec]));
	aj_put(&l, AJ_PX_MCUS_H, DIV_ROUND_UP(height, mcu_h[job->codec]));
	aj_enc_tiles(&l, job->codec, job->fmt);
	aj_put(&l, AJ_DMA_IMAGE_WIDTH, width);
	aj_put(&l, AJ_DMA_IMAGE_HEIGHT, height);

	/* set_encode_submode: no colour conversion, component order */
	if (job->fmt == AJ_PIX_YUV422_1P) {
		aj_put(&l, AJ_ENC_PIXFMT, AJ_ENC_PIXFMT_YUV_LINEAR);
		/* order flag 1 = {0,1,3,2} = YUYV [KEXT13.5] + [M1N1]'s YUV-linear; [INF] */
		aj_put(&l, AJ_ENC_COMP_POS(0), job->yuyv ? 0 : 1);
		aj_put(&l, AJ_ENC_COMP_POS(1), job->yuyv ? 1 : 0);
		aj_put(&l, AJ_ENC_COMP_POS(2), job->yuyv ? 3 : 2);
		aj_put(&l, AJ_ENC_COMP_POS(3), job->yuyv ? 2 : 3);
	} else {
		aj_put(&l, AJ_ENC_PIXFMT, AJ_ENC_PIXFMT_YUV_PLANES);
		aj_put(&l, AJ_ENC_COMP_POS(0), 0);
		aj_put(&l, AJ_ENC_COMP_POS(1), 0);
		aj_put(&l, AJ_ENC_COMP_POS(2), 1);
	}

	/* set_encode_uv_subsample, chroma siting flag 0 as macOS [KEXT13.5] */
	if (job->codec == AJ_CODEC_420 && job->fmt != AJ_PIX_YUV420_2P) {
		if (job->fmt == AJ_PIX_YUV444_2P)
			aj_put(&l, AJ_CHROMA_HALVE_H2, 1);
		aj_put(&l, AJ_CHROMA_HALVE_V2, 1);
	} else if (job->codec == AJ_CODEC_422 && job->fmt == AJ_PIX_YUV444_2P) {
		aj_put(&l, AJ_CHROMA_HALVE_H2, 1);
	}

	/* set_pointers; the input end is ORed with 7 when encoding */
	aj_put64(&l, AJ_INPUT_PLANE0, job->plane0);
	aj_put64(&l, AJ_INPUT_PLANE1, h1 ? job->plane1 : 0);
	aj_put64(&l, AJ_INPUT_END, job->input_end | 7);
	aj_put64(&l, AJ_OUTPUT_PLANE0, job->output);
	aj_put64(&l, AJ_OUTPUT_PLANE1, job->output);	/* as [AURORA] */
	aj_put64(&l, AJ_OUTPUT_END, job->output + job->output_size - 1);
	aj_put(&l, AJ_PX_PLANE0_STRIDE, job->stride0);
	aj_put(&l, AJ_PX_PLANE1_STRIDE, h1 ? job->stride1 : 0);

	if (job->prefetch) {
		aj_put(&l, AJ_AXI_PREFETCH0, 1);
		aj_put(&l, AJ_AXI_PREFETCH1, 0);
	}
	aj_put(&l, AJ_RST_LOG_ENABLE, 0);
	aj_put(&l, AJ_MODE, AJ_MODE_ENCODE);
	aj_put(&l, AJ_JPEG_IO_FLAGS, 0x30 | io_ss[job->codec]);
	aj_put(&l, AJ_JPEG_WIDTH, width);
	aj_put(&l, AJ_JPEG_HEIGHT, height);
	aj_put(&l, AJ_RST_INTERVAL, job->restart_interval);
	aj_put(&l, AJ_OUTPUT_FLAGS, 0);

	/* jpeg_write_tables: slots 0/1 in use, 2/3 hold the quality-50 tables */
	apple_jpeg_quant_tables(job->quality, luma, chroma);
	aj_qtable(&l, 0, luma);
	aj_qtable(&l, 1, chroma);
	aj_qtable(&l, 2, aj_annex_k_luma);
	aj_qtable(&l, 3, aj_annex_k_chroma);
	aj_put(&l, AJ_HUFFMAN_TABLE, AJ_HUFFMAN_BASELINE);
	aj_put(&l, AJ_QTBL_SEL, AJ_QTBL_SEL_LUMA_CHROMA);

	aj_put(&l, AJ_RUN, 1);
	aj_put(&l, AJ_COMMAND, 1);
	return l.n <= max ? l.n : -ENOSPC;
}

/*
 * Decode tiling by codec and output layout: { MCU width divisor, plane 0
 * tile H, V, plane 1 tile H, V }, V before the scale division. The values
 * are m1n1's decode recipe [M1N1], equal to the kext's dcd_cmp_yuv_* rows
 * [KEXT13.5] (checked privately). 4:0:0 shares the 4:4:4 rows.
 */
static const u8 aj_dec_tiles[5][4][5] = {
	[AJ_CODEC_444] = {
		{ 8, 1, 8, 2, 8 }, { 16, 2, 8, 2, 8 }, { 16, 2, 8, 2, 4 }, { 16, 4, 8, 1, 1 },
	},
	[AJ_CODEC_422] = {
		{ 0 }, { 16, 2, 8, 2, 8 }, { 16, 2, 8, 2, 4 }, { 16, 4, 8, 1, 1 },
	},
	[AJ_CODEC_411] = {
		{ 0 }, { 32, 4, 8, 4, 8 }, { 32, 4, 8, 4, 4 }, { 32, 8, 8, 0, 0 },
	},
	[AJ_CODEC_420] = {
		{ 0 }, { 16, 2, 16, 2, 16 }, { 16, 2, 16, 2, 8 }, { 16, 4, 16, 0, 0 },
	},
	[AJ_CODEC_400] = {
		{ 8, 1, 8, 2, 8 }, { 16, 2, 8, 2, 8 }, { 16, 2, 8, 2, 4 }, { 16, 4, 8, 1, 1 },
	},
};

/* ajpeg_drv_setx_decode_CMP_YUV_*: chroma resampling to the output [KEXT13.5] */
static void aj_dec_chroma(struct aj_list *l, enum aj_codec codec, enum aj_pixfmt fmt,
			  u32 scale)
{
	u32 halve_v = scale == 8 ? AJ_PLANAR_CHROMA_HALVE : AJ_CHROMA_HALVE_V1;

	switch (codec) {
	case AJ_CODEC_444:
		if (fmt != AJ_PIX_YUV444_2P)
			aj_put(l, AJ_CHROMA_HALVE_H1, 1);
		if (fmt == AJ_PIX_YUV420_2P)
			aj_put(l, halve_v, 1);
		break;
	case AJ_CODEC_400:
		if (fmt == AJ_PIX_YUV422_2P)
			aj_put(l, AJ_CHROMA_HALVE_H1, 1);
		break;
	case AJ_CODEC_422:
		if (fmt == AJ_PIX_YUV420_2P)
			aj_put(l, halve_v, 1);
		break;
	case AJ_CODEC_411:
		aj_put(l, AJ_CHROMA_DOUBLE_H, 1);
		if (fmt == AJ_PIX_YUV420_2P)
			aj_put(l, halve_v, 1);
		break;
	case AJ_CODEC_420:
		if (fmt != AJ_PIX_YUV420_2P)
			aj_put(l, AJ_CHROMA_DOUBLE_V, 1);
		break;
	}
}

/*
 * Every register write of one baseline decode (startDecoderGated ->
 * ajpeg_drv_set_decode). The engine parses SOI..SOS (DQT, DHT included)
 * from the input itself [KEXT13.5].
 */
int apple_jpeg_build_decode(const struct apple_jpeg_dec_job *job,
			    struct apple_jpeg_write *w, unsigned int max)
{
	/* wrcnvset_w_h arguments by codec: MCU w, h, chroma rows halved, cols shift */
	static const u8 mcu[5][4] = {
		{ 8, 8, 0, 0 }, { 16, 8, 0, 1 }, { 32, 8, 0, 2 }, { 16, 16, 1, 1 }, { 8, 8, 0, 0 },
	};
	static const u8 scale_reg[9] = { [1] = 0, [2] = 1, [4] = 2, [8] = 3 };
	u32 W = job->width, H = job->height, s = job->scale;
	struct aj_list l = { w, 0, max };
	u32 ow, oh, w0, w1, h1, mw, mh, mcus_w, mcus_h, edge_w, edge_h, smp_w, smp_h;
	const u8 *t;

	if (!W || !H || W > U16_MAX || H > U16_MAX)
		return -EINVAL;
	if (s != 1 && s != 2 && s != 4 && s != 8)
		return -EINVAL;
	if (!apple_jpeg_dec_supported(job->codec, job->fmt))
		return -EINVAL;
	if ((job->input | job->plane0 | job->plane1) & 127 || job->input_end < job->input)
		return -EINVAL;
	ow = DIV_ROUND_UP(W, s);
	oh = DIV_ROUND_UP(H, s);
	t = aj_dec_tiles[job->codec][job->fmt];

	aj_put(&l, AJ_MODE, AJ_MODE_SETUP);
	aj_put(&l, AJ_RUN, 0);
	aj_defaults(&l, false);
	aj_put(&l, AJ_MODE, AJ_MODE_OPEN);

	aj_put(&l, AJ_DECODE_ENABLE, 1);
	aj_put(&l, AJ_CODEC_MODE, 0);
	aj_put(&l, AJ_ENCODE_ENABLE, 0);
	aj_put(&l, AJ_CODEC, job->codec);
	aj_put(&l, AJ_DEC_PIXFMT, job->fmt);
	aj_boundary(&l, job->fmt, ow, oh, s, &w0, &w1, &h1);
	if (job->stride0 < w0 || (h1 && job->stride1 < w1))
		return -EINVAL;
	aj_put(&l, AJ_PIPE_LIMIT0, 0x1f);
	aj_put(&l, AJ_PIPE_LIMIT1, 1);

	/* set_decode_mbcounts -> wrcnvset_w_h: MCUs and edge sizes of the JPEG */
	mw = mcu[job->codec][0];
	mh = mcu[job->codec][1];
	mcus_w = DIV_ROUND_UP(W, mw);
	mcus_h = DIV_ROUND_UP(H, mh);
	edge_w = W - mcus_w * mw + mw;
	edge_h = H - mcus_h * mh + mh;
	smp_h = mcu[job->codec][2] ? (edge_h + 1) >> 1 : edge_h;
	smp_w = mcu[job->codec][3] == 2 ? (edge_w + 3) >> 2 :
		mcu[job->codec][3] == 1 ? (edge_w + 1) >> 1 : edge_w;
	aj_put(&l, AJ_DEC_MCUS_W, mcus_w);
	aj_put(&l, AJ_DEC_MCUS_H, mcus_h);
	aj_put(&l, AJ_PX_MCUS_H, mcus_h);
	aj_put(&l, AJ_DEC_EDGE_PX_W, edge_w);
	aj_put(&l, AJ_DEC_EDGE_PX_H, edge_h);
	aj_put(&l, AJ_DEC_EDGE_SMP_W, smp_w);
	aj_put(&l, AJ_DEC_EDGE_SMP_H, smp_h);
	aj_dec_chroma(&l, job->codec, job->fmt, s);
	/* the output tiling, scaled */
	aj_put(&l, AJ_PX_MCUS_W, DIV_ROUND_UP(DIV_ROUND_UP(W, t[0]), s));
	aj_put(&l, AJ_PX_PLANE0_TILE_H, t[1]);
	aj_put(&l, AJ_PX_PLANE0_TILE_V, DIV_ROUND_UP(t[2], s));
	aj_put(&l, AJ_PX_PLANE1_TILE_H, t[3]);
	aj_put(&l, AJ_PX_PLANE1_TILE_V, DIV_ROUND_UP(t[4], s));

	/* set_decode_submode */
	if (job->fmt == AJ_PIX_YUV422_1P)
		aj_put(&l, AJ_YUV422_ORDER, job->yuyv);
	aj_put(&l, AJ_DCT_SCALE, scale_reg[s]);

	aj_put64(&l, AJ_INPUT_PLANE0, job->input);
	aj_put64(&l, AJ_INPUT_PLANE1, 0);
	aj_put64(&l, AJ_INPUT_END, job->input_end);
	aj_put64(&l, AJ_OUTPUT_PLANE0, job->plane0);
	aj_put64(&l, AJ_OUTPUT_PLANE1, h1 ? job->plane1 : 0);
	aj_put64(&l, AJ_OUTPUT_END, job->output_end);
	aj_put(&l, AJ_PX_PLANE0_STRIDE, job->stride0);
	aj_put(&l, AJ_PX_PLANE1_STRIDE, h1 ? job->stride1 : 0);

	if (job->prefetch) {
		aj_put(&l, AJ_AXI_PREFETCH0, 0);
		aj_put(&l, AJ_AXI_PREFETCH1, 1);
	}
	aj_put(&l, AJ_MODE, AJ_MODE_DECODE);
	aj_put(&l, AJ_EOI_INSERT, 1);		/* SupportsMissingEOI [LIVE] */
	aj_put(&l, AJ_DEC_INT_SETTING, 0);
	aj_put(&l, AJ_JPEG_IO_FLAGS, 0x3f);
	aj_put(&l, AJ_RUN, 1);
	aj_put(&l, AJ_COMMAND, 1);
	return l.n <= max ? l.n : -ENOSPC;
}

/*
 * The engine writes SOI DQT SOF0 DHT SOS and no DRI [KEXT13.5: VT output];
 * with restart markers in the scan a DRI segment must precede SOS
 * (T.81 B.2.4.4). Insert one in place unless the engine wrote it.
 * Returns the new length, or a negative error.
 */
ssize_t apple_jpeg_insert_dri(u8 *buf, size_t len, size_t cap, u16 interval)
{
	size_t p = 2;

	if (len < 4 || buf[0] != 0xff || buf[1] != 0xd8)
		return -EINVAL;
	while (p + 4 <= len) {
		u8 m;
		u16 seg;

		if (buf[p] != 0xff)
			return -EINVAL;
		m = buf[p + 1];
		if (m == 0xdd)
			return len;	/* already there */
		if (m == 0xda) {
			if (len + 6 > cap)
				return -ENOSPC;
			memmove(buf + p + 6, buf + p, len - p);
			buf[p] = 0xff;
			buf[p + 1] = 0xdd;
			buf[p + 2] = 0;
			buf[p + 3] = 4;
			buf[p + 4] = interval >> 8;
			buf[p + 5] = interval & 0xff;
			return len + 6;
		}
		seg = buf[p + 2] << 8 | buf[p + 3];
		if (seg < 2)
			return -EINVAL;
		p += 2 + seg;
	}
	return -EINVAL;
}

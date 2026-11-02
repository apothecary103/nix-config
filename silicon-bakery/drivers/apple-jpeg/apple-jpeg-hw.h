/* SPDX-License-Identifier: GPL-2.0-only */
/*
 * Apple M2 Pro (t6020) JPEG codec: register map and job programming.
 *
 * Forked from aurora-silicon/linux branch aurora-wip (27c8c52a),
 * drivers/media/platform/apple/jpeg/apple-jpeg-hw.h, the T8140 encoder by
 * Ryan Murray <ryan@aurorasilicon.org> (GPL-2.0-only). The T8140 layout
 * (64-bit DMA pointers, colour/format block moved up) is the t6020 one;
 * the MODE values, defaults, tunables, decoder and the AXI wrapper are
 * Silicon Bakery's, from the macOS AppleJPEGDriver (AppleJPEGHalV11).
 *
 * Provenance labels on values:
 *   [KEXT13.5] AppleJPEGDriver in the macOS 13.5 kernelcache (mac14j)
 *   [KEXT27]   the same in macOS 27.2; "13.5==27.2" where both agree
 *   [ADT]      macOS 13.5 j414sap device tree
 *   [LIVE]     IORegistry of the Mac14,9 under macOS 27.2
 *   [M1N1]     m1n1 proxyclient hw/jpeg.py, experiments/jpeg.py (M1 layout)
 *   [AURORA]   aurora-silicon's T8140 driver
 *   [INF]      inference, not verified on hardware
 * Nothing in this file has run on hardware.
 */
#ifndef APPLE_JPEG_HW_H
#define APPLE_JPEG_HW_H

#include <linux/bits.h>
#include <linux/types.h>

#define APPLE_JPEG_REG_SIZE		0x4000	/* [ADT] reg 0x8000 = codec + DART */

/* Control block, 0x000-0x2bc [KEXT13.5] (V8 == V11 offsets) */
#define AJ_RUN				0x000
#define AJ_MODE				0x008
#define  AJ_MODE_RESET			0x100	/* [KEXT13.5] reset_jpeg_block */
#define  AJ_MODE_SETUP			0x13e	/* [KEXT13.5] (T8140 same [AURORA]) */
#define  AJ_MODE_OPEN			0x17f	/* [KEXT13.5] */
#define  AJ_MODE_IDLE			0x143	/* [KEXT13.5] (T8140: 0x743) */
#define  AJ_MODE_IDENTIFY		0x147	/* [KEXT13.5] checkHardwareVersion */
/* job MODE = bits << 1 | 0x141; bits 3|4 encode, 3|8 decode, |0x10 RGB [KEXT13.5] */
#define  AJ_MODE_ENCODE			0x14f
#define  AJ_MODE_DECODE			0x157
#define AJ_DEBUG			0x00c
#define AJ_IRQ_MASK			0x020
#define AJ_STATUS			0x024
#define  AJ_STATUS_DONE			BIT(0)
#define  AJ_STATUS_TIMEOUT		BIT(1)
#define  AJ_STATUS_RDBUF		BIT(2)
#define  AJ_STATUS_WRBUF		BIT(3)
#define  AJ_STATUS_CODECBUF		BIT(4)
#define  AJ_STATUS_MB			BIT(5)
#define  AJ_STATUS_AXI			BIT(6)
#define  AJ_STATUS_OTHER		BIT(7)
#define  AJ_STATUS_ERRORS		GENMASK(7, 1)
#define AJ_CODEC			0x028	/* 0 444, 1 422, 2 411, 3 420, 4 400 */
#define AJ_CODEC_MODE			0x02c	/* 1 encode */
#define AJ_DECODE_ENABLE		0x034
#define AJ_ENCODE_ENABLE		0x038
#define AJ_CHROMA_HALVE_H1		0x03c	/* names [M1N1], offsets unchanged */
#define AJ_CHROMA_HALVE_H2		0x040
#define AJ_CHROMA_HALVE_V1		0x044
#define AJ_CHROMA_HALVE_V2		0x048
#define AJ_CHROMA_DOUBLE_H		0x04c
#define AJ_CHROMA_QUAD_H		0x050
#define AJ_CHROMA_DOUBLE_V		0x054
#define AJ_PX_USE_PLANE1		0x058
#define AJ_PX_MCUS_W			0x05c
#define AJ_PX_MCUS_H			0x060
#define AJ_PX_PLANE0_WIDTH_M1		0x064
#define AJ_PX_PLANE0_HEIGHT_M1		0x068
#define AJ_PX_PLANE0_TILE_H		0x06c
#define AJ_PX_PLANE0_TILE_V		0x070
#define AJ_PX_PLANE0_STRIDE		0x074
#define AJ_PX_PLANE1_WIDTH_M1		0x078
#define AJ_PX_PLANE1_HEIGHT_M1		0x07c
#define AJ_PX_PLANE1_TILE_H		0x080
#define AJ_PX_PLANE1_TILE_V		0x084
#define AJ_PX_PLANE1_STRIDE		0x088
#define AJ_INPUT_PLANE0			0x090	/* low, high; +8 per-core tunable */
#define AJ_INPUT_PLANE1			0x0a0
#define AJ_INPUT_END			0x0b0
#define AJ_PIPE_LIMIT0			0x0b8
#define AJ_PIPE_LIMIT1			0x0bc
#define AJ_OUTPUT_PLANE0		0x0c0
#define AJ_OUTPUT_PLANE1		0x0d0
#define AJ_OUTPUT_END			0x0e0
#define AJ_MATRIX(i)			(0x0e8 + 4 * (i))	/* 11 */
#define AJ_DITHER(i)			(0x114 + 4 * (i))	/* 10 */
#define AJ_ENC_PIXFMT			0x13c
#define  AJ_ENC_PIXFMT_YUV_PLANES	4
#define  AJ_ENC_PIXFMT_YUV_LINEAR	5
#define AJ_ENC_COMP_POS(i)		(0x140 + 4 * (i))
#define AJ_CSC_ENABLE			0x150
#define AJ_AXI_PREFETCH0		0x154
#define AJ_AXI_PREFETCH1		0x158
#define AJ_DEC_MCUS_W			0x16c
#define AJ_DEC_MCUS_H			0x170
#define AJ_DEC_EDGE_PX_W		0x174
#define AJ_DEC_EDGE_PX_H		0x178
#define AJ_DEC_EDGE_SMP_W		0x17c
#define AJ_DEC_EDGE_SMP_H		0x180
#define AJ_DCT_SCALE			0x184	/* 0 /1, 1 /2, 2 /4, 3 /8 */
#define AJ_DEC_PIXFMT			0x188
#define AJ_YUV422_ORDER			0x18c	/* 1 = Y0 Cb Y1 Cr [M1N1] */
#define AJ_PLANAR_CHROMA_HALVE		0x198
#define AJ_TILING_ENABLE		0x19c
#define AJ_TIMEOUT			0x1c0
#define AJ_HWREV			0x1c4
#define  AJ_HWREV_T6020			0x000e0010	/* [KEXT13.5][LIVE] hw-type e0010 [ADT] */
#define AJ_EOI_INSERT			0x1d8
#define AJ_RST_LOG_ENABLE		0x1dc
#define AJ_DMA_IMAGE_WIDTH		0x258
#define AJ_DMA_IMAGE_HEIGHT		0x25c

/* JPEG block, 0x1000 [KEXT13.5], names from [M1N1] */
#define AJ_JPEG_IO_FLAGS		0x1000	/* enc 0x30 | ss, dec 0x3f */
#define AJ_COMMAND			0x1004
#define AJ_QTBL_SEL			0x100c
#define  AJ_QTBL_SEL_LUMA_CHROMA	0x14	/* Y: 0, Cb and Cr: 1 */
#define AJ_HUFFMAN_TABLE		0x1010
#define  AJ_HUFFMAN_BASELINE		0x3c	/* standard (Annex K) tables */
#define AJ_RST_INTERVAL			0x1014
#define AJ_JPEG_HEIGHT			0x1018
#define AJ_JPEG_WIDTH			0x101c
#define AJ_COMPRESSED_BYTES		0x1020
#define AJ_OUTPUT_FLAGS			0x1024
#define AJ_DEC_INT_SETTING		0x1028
#define AJ_INT_STATUS			0x102c
#define  AJ_INT_STATUS_GOOD0		0x80000000	/* [KEXT13.5] either is success */
#define  AJ_INT_STATUS_GOOD1		0x40000000
#define AJ_DECOMP_ERROR			0x1030
#define AJ_QTBL(t)			(0x1100 + 0x40 * (t))	/* natural order, BE bytes */

/* The AXI wrapper outside the codec node, at die base 0x3_8c00_0000 [KEXT13.5] */
#define AJ_AXI_CTRL			0x0	/* jpeg0 +0xb38, jpeg1 +0xb98 */
#define AJ_AXI_STATUS			0x4	/* outstanding transactions */
#define  AJ_AXI_CTRL_RUN		0x0040000a	/* [KEXT13.5] written back after the drain */

/* Codec (subsampling of the JPEG) as the hardware numbers it */
enum aj_codec {
	AJ_CODEC_444 = 0,
	AJ_CODEC_422 = 1,
	AJ_CODEC_411 = 2,
	AJ_CODEC_420 = 3,
	AJ_CODEC_400 = 4,
};

/* Pixel layout ("IMG_*" in the kext), shared by ENC/DEC paths [KEXT13.5][M1N1] */
enum aj_pixfmt {
	AJ_PIX_YUV444_2P = 0,	/* NV24 */
	AJ_PIX_YUV422_2P = 1,	/* NV16 */
	AJ_PIX_YUV420_2P = 2,	/* NV12 */
	AJ_PIX_YUV422_1P = 3,	/* YUYV / UYVY */
};

struct apple_jpeg_write {
	u32 offset;
	u32 value;
};

struct apple_jpeg_tunable {
	u16 offset;
	u8 value;		/* written under mask 0xff [KEXT13.5] */
};

#define APPLE_JPEG_NUM_TUNABLES		10

/* Per-core tunables by core index; core = which ADT node [KEXT13.5] */
extern const struct apple_jpeg_tunable apple_jpeg_tunables[2][APPLE_JPEG_NUM_TUNABLES];

struct apple_jpeg_enc_job {
	u32 width, height;
	enum aj_codec codec;	/* 444, 422, 420 or 400 */
	enum aj_pixfmt fmt;
	bool yuyv;		/* packed 4:2:2: Y0 Cb Y1 Cr (else Cb Y0 Cr Y1) */
	u32 stride0, stride1;
	u64 plane0, plane1;
	u64 input_end;		/* inclusive */
	u64 output;
	u32 output_size;
	u32 quality;		/* 1 to 100 */
	u32 restart_interval;
	bool prefetch;
};

struct apple_jpeg_dec_job {
	u32 width, height;	/* from SOF0 */
	enum aj_codec codec;
	enum aj_pixfmt fmt;
	bool yuyv;
	u32 scale;		/* 1, 2, 4, 8 */
	u32 stride0, stride1;
	u64 input, input_end;	/* inclusive end */
	u64 plane0, plane1;
	u64 output_end;		/* inclusive */
	bool prefetch;
};

/* Enough for defaults (~170), the job and four quantisation tables */
#define APPLE_JPEG_MAX_WRITES		512

void apple_jpeg_quant_tables(u32 quality, u8 luma[64], u8 chroma[64]);
bool apple_jpeg_enc_supported(enum aj_codec codec, enum aj_pixfmt fmt);
bool apple_jpeg_dec_supported(enum aj_codec codec, enum aj_pixfmt fmt);
void apple_jpeg_plane_sizes(enum aj_pixfmt fmt, u32 w, u32 h, u32 *w0, u32 *w1, u32 *h1);
int apple_jpeg_defaults(bool tiled, struct apple_jpeg_write *w, unsigned int max);
int apple_jpeg_build_encode(const struct apple_jpeg_enc_job *job,
			    struct apple_jpeg_write *w, unsigned int max);
int apple_jpeg_build_decode(const struct apple_jpeg_dec_job *job,
			    struct apple_jpeg_write *w, unsigned int max);
ssize_t apple_jpeg_insert_dri(u8 *buf, size_t len, size_t cap, u16 interval);

#endif /* APPLE_JPEG_HW_H */

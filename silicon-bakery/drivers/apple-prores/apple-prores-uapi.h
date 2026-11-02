/* SPDX-License-Identifier: GPL-2.0-only WITH Linux-syscall-note */
/*
 * The user-space interface of the out-of-tree apple-prores driver, for
 * kernels without a ProRes V4L2 uAPI (asahi-7.2.14 has none).
 *
 * V4L2_PIX_FMT_PRORES and V4L2_CID_MPEG_VIDEO_PRORES_PROFILE (with its menu)
 * are the values aurora-silicon/linux proposes (aurora-wip,
 * include/uapi/linux/videodev2.h and v4l2-controls.h). If the kernel headers
 * define them, theirs are used and these are skipped; nothing here may
 * disagree with them.
 *
 * Everything below "driver private" is this driver's own: the 4:4:4 + alpha
 * raw formats and the rate-control controls. Applications must probe for
 * them (VIDIOC_ENUM_FMT, VIDIOC_QUERY_EXT_CTRL) and not assume them.
 */
#ifndef _APPLE_PRORES_UAPI_H
#define _APPLE_PRORES_UAPI_H

#include <linux/videodev2.h>
#include <linux/v4l2-controls.h>

/* One complete ProRes frame (frame_size .. last slice) per buffer. */
#ifndef V4L2_PIX_FMT_PRORES
#define V4L2_PIX_FMT_PRORES	v4l2_fourcc('P', 'R', 'E', 'S')
#endif

#ifndef V4L2_CID_MPEG_VIDEO_PRORES_PROFILE
#define V4L2_CID_MPEG_VIDEO_PRORES_PROFILE	(V4L2_CID_CODEC_BASE + 658)
enum v4l2_mpeg_video_prores_profile {
	V4L2_MPEG_VIDEO_PRORES_PROFILE_PROXY = 0,
	V4L2_MPEG_VIDEO_PRORES_PROFILE_LT = 1,
	V4L2_MPEG_VIDEO_PRORES_PROFILE_STANDARD = 2,
	V4L2_MPEG_VIDEO_PRORES_PROFILE_HQ = 3,
	V4L2_MPEG_VIDEO_PRORES_PROFILE_4444 = 4,
	V4L2_MPEG_VIDEO_PRORES_PROFILE_4444_XQ = 5,
};
#define APPLE_PRORES_PROFILE_CTRL_IS_PRIVATE	1
#endif

/* 16-bit semi-planar 4:2:2 / 4:4:4, data in the MSBs (aurora's proposal). */
#ifndef V4L2_PIX_FMT_P216
#define V4L2_PIX_FMT_P216	v4l2_fourcc('P', '2', '1', '6')
#endif
#ifndef V4L2_PIX_FMT_P416
#define V4L2_PIX_FMT_P416	v4l2_fourcc('P', '4', '1', '6')
#endif

/* ---- driver private ---------------------------------------------------- */

/*
 * 4:4:4 with alpha, one contiguous buffer: Y rows, then interleaved CbCr
 * rows (twice the Y stride), then alpha rows (the Y stride). Samples are
 * 8 bits (APA8) or 16 bits with the data in the MSBs (APA6). Encoder
 * only, profiles 4444 and 4444 XQ; the frame header then says alpha.
 */
#define V4L2_PIX_FMT_APPLE_NV24A	v4l2_fourcc('A', 'P', 'A', '8')
#define V4L2_PIX_FMT_APPLE_P416A	v4l2_fourcc('A', 'P', 'A', '6')

/*
 * Rate control. The engine refines the slice quantisers itself to meet a
 * frame size; the driver gives it a target and a maximum in bytes.
 * 0 (the default) means macOS's per-profile size for the frame's pixel
 * count. A non-zero target is clamped to 4 KiB .. the CAPTURE buffer size;
 * the maximum is 9/8 of the target unless set larger.
 */
#define V4L2_CID_APPLE_PRORES_BASE		(V4L2_CID_CODEC_BASE + 0x1980)
#define V4L2_CID_APPLE_PRORES_TARGET_BYTES	(V4L2_CID_APPLE_PRORES_BASE + 0)
#define V4L2_CID_APPLE_PRORES_MAX_BYTES		(V4L2_CID_APPLE_PRORES_BASE + 1)
/* Starting quantiser index 1..224; 0 = the profile's (8/3/2/1/1/1). */
#define V4L2_CID_APPLE_PRORES_QUANT_INDEX	(V4L2_CID_APPLE_PRORES_BASE + 2)

#endif

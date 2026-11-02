// SPDX-License-Identifier: GPL-2.0-only
/*
 * Apple M2Scaler: polyphase filters and colour matrices, computed here from
 * public formulas (Lanczos / Keys bicubic; ITU-R BT.601, BT.709, BT.2020 and
 * SMPTE 240M luma coefficients). No Apple filter bank or CSC table is used.
 *
 * Hardware formats [KEXT13.5, layout only]:
 *   filter coefficient  signed Q4.12, the taps of one phase sum to 4096;
 *   phase p in 0..31    sub-pixel offset +p/32 (p < 16) or (p-32)/32 from the
 *                       centre tap (V tap 4, H tap 7); weight moves to higher
 *                       taps as p rises [KEXT13.5 bank data, direction INF];
 *   3x3 coefficients    S3.12; offsets in normalised units (1.0 = full scale).
 */
#include <linux/kernel.h>
#include <linux/math64.h>
#include <linux/minmax.h>
#include <linux/videodev2.h>

#include "apple_scaler.h"

#define Q30		(1LL << 30)
#define Q24		(1LL << 24)
#define Q16		(1LL << 16)

/*
 * sin(pi * t), t and the result in Q30. Taylor series to t^9 on
 * [-1/2, 1/2]; worst error about 4e-6, far below one Q4.12 step.
 */
static s64 as_sinpi(s64 t)
{
	/* pi^(2k+1)/(2k+1)! in Q30 */
	static const s64 c[5] = {
		3373259426LL,	/* 3.14159265 */
		5548789346LL,	/* 5.16771278 */
		2738217788LL,	/* 2.55016403 */
		 643455389LL,	/* 0.59926453 */
		  88203474LL,	/* 0.08214589 */
	};
	s64 t2, acc;
	bool neg = false;

	/* reduce to [-1, 1) */
	t %= 2 * Q30;
	if (t >= Q30)
		t -= 2 * Q30;
	else if (t < -Q30)
		t += 2 * Q30;
	if (t < 0) {
		t = -t;
		neg = true;
	}
	if (t > Q30 / 2)
		t = Q30 - t;		/* sin(pi t) = sin(pi (1 - t)) */

	t2 = (t * t) >> 30;
	acc = c[4];
	acc = c[3] - ((t2 * acc) >> 30);
	acc = c[2] - ((t2 * acc) >> 30);
	acc = c[1] - ((t2 * acc) >> 30);
	acc = c[0] - ((t2 * acc) >> 30);
	acc = (t * acc) >> 30;
	return neg ? -acc : acc;
}

/* kernels, x >= 0 in Q16, result Q16 */
static s64 as_lanczos3(s64 x)
{
	s64 s1, s2, x2, den;

	if (x == 0)
		return Q16;
	if (x >= 3 * Q16)
		return 0;
	s1 = as_sinpi(x << 14);			/* Q16 -> Q30 */
	s2 = as_sinpi(div_s64(x << 14, 3));
	/* 3 sin(pi x) sin(pi x / 3) / (pi^2 x^2) */
	x2 = (x * x) >> 16;			/* Q16 */
	den = (646814LL * x2) >> 16;		/* pi^2 = 9.8696044 in Q16 */
	if (!den)
		return Q16;
	return div64_s64(((s1 * s2) >> 30) * 3 * 4, den);	/* Q30/Q16 = Q14, x4 */
}

static s64 as_bicubic(s64 x)
{
	/* Keys, a = -0.5 (Catmull-Rom) */
	s64 x2 = (x * x) >> 16, x3 = (x2 * x) >> 16;

	if (x < Q16)	/* 1.5x^3 - 2.5x^2 + 1 */
		return ((3 * x3) >> 1) - ((5 * x2) >> 1) + Q16;
	if (x < 2 * Q16) /* -0.5x^3 + 2.5x^2 - 4x + 2 */
		return -(x3 >> 1) + ((5 * x2) >> 1) - 4 * x + 2 * Q16;
	return 0;
}

static s64 as_linear(s64 x)
{
	return x < Q16 ? Q16 - x : 0;
}

/*
 * One filter: out[tap * 32 + phase], `taps` slots of which the `used` centred
 * ones are non-zero. ratio = src/dst in U4.22; for a downscale the kernel is
 * stretched by the ratio (and cut at the available taps, then normalised).
 */
void as_make_filter(s16 *out, unsigned int taps, unsigned int used,
		    u32 ratio_u422, unsigned int kernel, bool phase_neg)
{
	int c = taps / 2, k0, k1, p, k;
	s64 s = max_t(s64, Q16, ratio_u422 >> 6);	/* U4.22 -> Q16 */

	used = min(used, taps);
	k0 = c - (int)used / 2;
	k1 = k0 + used - 1;

	memset(out, 0, taps * AS_PHASES * sizeof(*out));
	for (p = 0; p < AS_PHASES; p++) {
		s64 w[AS_H_TAPS] = { 0 }, sum = 0, f, acc = 0;
		int best = c;

		f = (s64)(p < 16 ? p : p - 32) * (Q16 / AS_PHASES);
		if (phase_neg)
			f = -f;
		for (k = k0; k <= k1; k++) {
			s64 x = div64_s64((((s64)(k - c) << 16) - f) << 16, s);

			if (x < 0)
				x = -x;
			switch (kernel) {
			case 1:
				w[k] = as_bicubic(x);
				break;
			case 2:
				w[k] = as_linear(x);
				break;
			default:
				w[k] = as_lanczos3(x);
				break;
			}
			sum += w[k];
			if (w[k] > w[best])
				best = k;
		}
		if (sum <= 0) {
			out[c * AS_PHASES + p] = 4096;
			continue;
		}
		for (k = k0; k <= k1; k++) {
			s64 q = div64_s64(w[k] * 4096 + (w[k] >= 0 ? sum / 2 : -sum / 2), sum);

			q = clamp_t(s64, q, -32768, 32767);
			out[k * AS_PHASES + p] = q;
			acc += q;
		}
		/* exact unity gain: put the rounding residue on the largest tap */
		out[best * AS_PHASES + p] += 4096 - acc;
	}
}

/* ---------------------------------------------------------------- CSC */

static void as_kr_kb(enum v4l2_ycbcr_encoding enc, s64 *kr, s64 *kb)
{
	u32 r, b;	/* x 1e-4 */

	switch (enc) {
	case V4L2_YCBCR_ENC_601:
	case V4L2_YCBCR_ENC_XV601:
		r = 2990; b = 1140; break;
	case V4L2_YCBCR_ENC_BT2020:
	case V4L2_YCBCR_ENC_BT2020_CONST_LUM:	/* approximated by NCL */
		r = 2627; b = 593; break;
	case V4L2_YCBCR_ENC_SMPTE240M:
		r = 2120; b = 870; break;
	case V4L2_YCBCR_ENC_709:
	case V4L2_YCBCR_ENC_XV709:
	default:
		r = 2126; b = 722; break;
	}
	*kr = div_s64((s64)r * Q24, 10000);
	*kb = div_s64((s64)b * Q24, 10000);
}

static s64 qdiv(s64 a, s64 b)	/* Q24 / Q24 */
{
	return div64_s64(a * Q24, b);
}

static s64 qmul(s64 a, s64 b)
{
	return (a * b) >> 24;
}

/* range of one class at `bits`: offset/scale of Y (or R,G,B) and C, Q24 */
static void as_range(bool yuv, bool full, unsigned int bits,
		     s64 *yoff, s64 *ysc, s64 *coff, s64 *csc)
{
	s64 max = (1LL << bits) - 1;

	*coff = div64_s64((1LL << (bits - 1)) * Q24, max);
	if (full) {
		*yoff = 0;
		*ysc = Q24;
		*csc = Q24;
	} else {
		*yoff = div64_s64((16LL << (bits - 8)) * Q24, max);
		*ysc = div64_s64((219LL << (bits - 8)) * Q24, max);
		*csc = div64_s64((224LL << (bits - 8)) * Q24, max);
	}
	if (!yuv)
		*coff = *yoff;
}

static void mat_mul(s64 *o, const s64 *a, const s64 *b)
{
	int i, j, k;

	for (i = 0; i < 3; i++)
		for (j = 0; j < 3; j++) {
			s64 v = 0;

			for (k = 0; k < 3; k++)
				v += qmul(a[i * 3 + k], b[k * 3 + j]);
			o[i * 3 + j] = v;
		}
}

static bool as_full(const struct as_fmt *f, enum v4l2_quantization q)
{
	if (q == V4L2_QUANTIZATION_DEFAULT)
		return f->class == AS_RGB;
	return q == V4L2_QUANTIZATION_FULL_RANGE;
}

/*
 * out = C (in + pre) + post, C = B A. A/pre: input -> normalised R'G'B'
 * (full range, [0,1]); B/post: R'G'B' -> output. Columns/rows are in
 * (R,G,B) / (Y,Cb,Cr) order, the order of Apple's own matrices [KEXT13.5,
 * decoded 709Video2RGBFull], whatever the byte order in memory.
 * Gamut and transfer function are not converted (no CM LUTs yet).
 */
int as_build_csc(struct as_csc *csc,
		 const struct as_fmt *sf, enum v4l2_ycbcr_encoding senc,
		 enum v4l2_quantization squant,
		 const struct as_fmt *df, enum v4l2_ycbcr_encoding denc,
		 enum v4l2_quantization dquant)
{
	bool sfull = as_full(sf, squant), dfull = as_full(df, dquant);
	bool syuv = sf->class != AS_RGB, dyuv = df->class != AS_RGB;
	s64 A[9] = { 0 }, B[9] = { 0 }, C[9], pre[3], post[3];
	s64 yoff, ysc, coff, cs, kr, kb, kg;
	int i;

	memset(csc, 0, sizeof(*csc));

	/* nothing to do? */
	if (!syuv && !dyuv && sfull == dfull)
		return 0;
	if (syuv && dyuv && sfull == dfull &&
	    (senc == denc || df->class == AS_LUMA) &&
	    (sf->class == AS_YUV || df->class == AS_LUMA) &&
	    (sf->chroma_swap == df->chroma_swap || df->class == AS_LUMA))
		return 0;

	/* input -> R'G'B' */
	as_range(syuv, sfull, sf->bits, &yoff, &ysc, &coff, &cs);
	if (!syuv) {
		for (i = 0; i < 3; i++) {
			A[i * 4] = qdiv(Q24, ysc);
			pre[i] = -yoff;
		}
	} else {
		as_kr_kb(senc, &kr, &kb);
		kg = Q24 - kr - kb;
		/* columns Y, Cb, Cr */
		A[0] = A[3] = A[6] = qdiv(Q24, ysc);
		A[2] = qdiv(2 * (Q24 - kr), cs);
		A[4] = -qdiv(qdiv(2 * qmul(kb, Q24 - kb), kg), cs);
		A[5] = -qdiv(qdiv(2 * qmul(kr, Q24 - kr), kg), cs);
		A[7] = qdiv(2 * (Q24 - kb), cs);
		pre[0] = -yoff;
		pre[1] = pre[2] = -coff;
		if (sf->class == AS_LUMA) {
			A[1] = A[2] = A[4] = A[5] = A[7] = A[8] = 0;
			pre[1] = pre[2] = 0;
		} else if (sf->chroma_swap) {
			for (i = 0; i < 3; i++)
				swap(A[i * 3 + 1], A[i * 3 + 2]);
		}
	}

	/* R'G'B' -> output */
	as_range(dyuv, dfull, df->bits, &yoff, &ysc, &coff, &cs);
	if (!dyuv) {
		for (i = 0; i < 3; i++) {
			B[i * 4] = ysc;
			post[i] = yoff;
		}
	} else {
		as_kr_kb(denc, &kr, &kb);
		kg = Q24 - kr - kb;
		B[0] = qmul(kr, ysc);
		B[1] = qmul(kg, ysc);
		B[2] = qmul(kb, ysc);
		B[3] = qmul(qdiv(-kr, 2 * (Q24 - kb)), cs);
		B[4] = qmul(qdiv(-kg, 2 * (Q24 - kb)), cs);
		B[5] = qmul(qdiv(Q24 - kb, 2 * (Q24 - kb)), cs);
		B[6] = qmul(qdiv(Q24 - kr, 2 * (Q24 - kr)), cs);
		B[7] = qmul(qdiv(-kg, 2 * (Q24 - kr)), cs);
		B[8] = qmul(qdiv(-kb, 2 * (Q24 - kr)), cs);
		post[0] = yoff;
		post[1] = post[2] = coff;
		if (df->chroma_swap)
			for (i = 0; i < 3; i++)
				swap(B[3 + i], B[6 + i]);
	}

	mat_mul(C, B, A);
	for (i = 0; i < 9; i++)
		csc->coef[i] = clamp_t(s64, C[i], -8 * Q24, 8 * Q24 - 1);
	for (i = 0; i < 3; i++) {
		csc->pre[i] = clamp_t(s64, pre[i], -2 * Q24, 2 * Q24 - 1);
		csc->post[i] = clamp_t(s64, post[i], -2 * Q24, 2 * Q24 - 1);
	}
	csc->enable = true;
	return 0;
}

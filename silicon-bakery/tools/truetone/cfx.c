// SPDX-License-Identifier: MIT
/*
 * True Tone's colour engine, transliterated from macOS 27.2's CoreBrightness
 * (CFXInputAmbientColor, _CFXUpdateTarget, _CFXGetTarget, _CFXGetMatrix,
 * _CFXStickToPolygon, _CFXFindAdaptation, _CFXUpdateColorFadeInternal,
 * CFXUpdateColorFade and their helpers). Operation order, fused
 * multiply-adds and float/double conversions follow the arm64 code, so the
 * results match CoreBrightness's to the last bit or two (tools/truetone/
 * oracle.c checks this on macOS). Build with -ffp-contract=off.
 *
 * Left out, as macOS leaves them off on a Mac with one front sensor: Night
 * Shift (BLR) and twilight, the ALS mitigations, "Ammolite", the alternate
 * matrix output formats and the ANSI-bin snapping (harmony+0x136).
 */
#include <math.h>
#include <string.h>

#include "cfx.h"

/* Bradford, as CoreBrightness stores it */
static const float BF[9] = {
	0.895099998f, 0.266400009f, -0.161400005f,
	-0.750199974f, 1.71350002f, 0.0366999991f,
	0.0388999991f, -0.0684999973f, 1.02960002f,
};
/* Bradford x sRGB-to-XYZ, and its inverse (cfx+0x700, +0x724) */
static const float N[9] = {
	0.422657996f, 0.491356999f, 0.0273644999f,
	0.0556907989f, 0.961556017f, 0.0231893994f,
	0.0213792007f, 0.087643899f, 0.980742991f,
};
static const float NI[9] = {
	2.53845f, -1.29348004f, -0.040243201f,
	-0.145999998f, 1.11661994f, -0.0223286003f,
	-0.0422882996f, -0.0715901032f, 1.02251005f,
};
/* linear sRGB to XYZ (cfx+0x748) */
static const float S[9] = {
	0.412390798f, 0.357584327f, 0.180480793f,
	0.212639004f, 0.715168655f, 0.0721923187f,
	0.0193308182f, 0.119194783f, 0.950532138f,
};
/* Bradford LMS of D65 (cfx+0x6f0), and D65 (cfx+0x6e4) */
static const float LMS_D65[3] = { 0.941429019f, 1.04040003f, 1.08971202f };
static const float D65[2] = { 0.312715888f, 0.329001009f };

/*
 * The upper limit on the ambient chromaticity's y, by x (_CFXGetTarget's
 * "CCT RESTRICTION"): just above the Planckian locus.
 */
static const float LIM_X[9] = {
	0.0f, 0.263669193f, 0.303200006f, 0.342700005f, 0.382200003f,
	0.421799988f, 0.461299986f, 0.500799119f, 1.0f,
};
static const float LIM_Y[9] = {
	0.0f, 0.267171502f, 0.314200014f, 0.350300014f, 0.378500015f,
	0.398900002f, 0.411599994f, 0.415273696f, 0.415273696f,
};

/* CFXInitializeAmbientAdaptation's harmony parameters */
static const float UV_THR[2] = { 0.00300000003f, 0.0350000001f };
static const float RAMP_UP = 5.0f, RAMP_DOWN = 5.0f;		/* +0xa8, +0xac */
static const float SLOW_UP = 5.0f, SLOW_DOWN = 5.0f;		/* +0xb0, +0xb4 */
static const float RAMP_DIM = 20.0f, RAMP_DARK = 60.0f;	/* +0xb8, +0xbc */
static const float ENABLE_PERIOD = 2.0f;			/* +0xc4 */
static const float LUX_LOW = 10.0f, LUX_DARK = 15.0f;		/* +0xc8, +0xcc */
static const float LUX_DIM = 35.0f;				/* +0xd4 */
static const float LOW_XY[2] = { 0.382661015f, 0.384642988f };	/* +0xdc */
static const float MODE_STRENGTH[6] = { 0.0f, 0.2f, 0.2f, 0.1f, 0.1f, 0.1f };
static const double PI = 3.141592653589793;

static float fma3(float a, float b, float c) { return fmaf(a, b, c); }

static int mccamy(float x, float y)
{
	float n = (float)(((double)x + -0.332) / (0.1858 - (double)y));
	float a = (n * 449.0f) * n;
	float b = (n * 3525.0f) * n;
	double d;

	a = fma3(a, n, b);
	d = fma((double)n, 6823.3, (double)a);
	return (int)(d + 5520.33);
}

static float z_of(float x, float y)
{
	return (float)(((1.0 - (double)x) - (double)y) / (double)y);
}

static float max_row(const float m[9])
{
	float r0 = (m[0] + m[1]) + m[2];
	float r1 = (m[3] + m[4]) + m[5];
	float r2 = (m[6] + m[7]) + m[8];
	float mx = r0 > r1 ? r0 : r1;

	return mx > r2 ? mx : r2;
}

static void normalize(float m[9])
{
	float mx = max_row(m);

	for (int i = 0; i < 9; i++)
		m[i] /= mx;
}

static float lab_f(float t)
{
	if ((double)t > 0.0088565)
		return powf(t, 0.333333343f);
	return (float)fma((double)t, 7.787, 0.13793);
}

void cfx_lab(const float xyz[3], float lab[3])
{
	float fx = lab_f(xyz[0] / 95.0500031f);
	float fy = lab_f(xyz[1] / 100.0f);
	float fz = lab_f(xyz[2] / 108.900002f);

	lab[0] = fma3(fy, 116.0f, -16.0f);
	lab[1] = (fx - fy) * 500.0f;
	lab[2] = (fy - fz) * 200.0f;
}

static float lab_finv(double f)
{
	if (f > 0.2069)
		return powf((float)f, 3.0f);
	return (float)((f + -0.13793) * 0.12842);
}

void cfx_lab_inv(const float lab[3], float xyz[3])
{
	float fy = (lab[0] + 16.0f) / 116.0f;
	double dy = fy;
	float fx = (float)((double)lab[1] / 500.0 + dy);
	float fz = (float)((double)lab[2] / -200.0 + dy);

	xyz[0] = lab_finv(fx) * 95.0500031f;
	xyz[1] = (dy > 0.2069 ? powf(fy, 3.0f) :
		  (float)((dy + -0.13793) * 0.12842)) * 100.0f;
	xyz[2] = lab_finv(fz) * 108.900002f;
}

/* Clamp a*b* to the polygon along the ray from the origin. */
void cfx_stick(const float *p, int n, float ab[2])
{
	float a = ab[0], b = ab[1];

	if (a == 0.0f) {
		float x0, ab_abs;

		if (b == 0.0f || n < 2)
			return;
		ab_abs = fabsf(b);
		x0 = p[0];
		for (int i = 0; i < n - 1; i++) {
			float x1 = p[2 * (i + 1)];

			if ((x0 - a) * (a - x1) >= 0.0f) {
				float y0 = p[2 * i + 1];
				float m = (p[2 * (i + 1) + 1] - y0) / (x1 - x0);
				float yi = fma3(m, a - x0, y0);
				float d = yi - b;

				if (b * d > 0.0f)
					return;
				if (fabsf(d) < ab_abs) {
					ab[1] = yi;
					return;
				}
			}
			x0 = x1;
		}
		return;
	}

	if (n < 2)
		return;
	{
		float k = b / a;
		float c0 = fma3(-k, 0.0f, 0.0f);	/* the ray's intercept */
		float d0 = (0.0f - b) * (0.0f - b);
		float x1 = p[0];

		d0 = fma3(0.0f - a, 0.0f - a, d0);
		for (int i = 0; i < n - 1; i++) {
			float x0 = x1, xi, yi, d1, d2;
			float dx;

			x1 = p[2 * (i + 1)];
			dx = x1 - x0;
			if (dx == 0.0f) {
				xi = x1;
			} else {
				float m = (p[2 * (i + 1) + 1] - p[2 * i + 1]) / dx;
				float c = fma3(-m, x0, p[2 * i + 1]);

				xi = (c0 - c) / (m - k);
			}
			if ((x0 - xi) * (xi - x1) < 0.0f)
				continue;
			yi = fma3(k, xi, c0);
			if ((p[2 * i + 1] - yi) * (yi - p[2 * (i + 1) + 1]) < 0.0f)
				continue;
			d1 = fma3(0.0f - xi, 0.0f - xi, (0.0f - yi) * (0.0f - yi));
			d2 = fma3(a - xi, a - xi, (b - yi) * (b - yi));
			if (d1 >= d0 && d1 >= d2)
				return;
			if (d0 >= d1 && d0 >= d2) {
				ab[0] = xi;
				ab[1] = yi;
				return;
			}
		}
	}
}

static void lut_index(const float *axis, int n, float v, int *i0, int *i1)
{
	for (int i = 0; i < n; i++) {
		if (v <= axis[i]) {
			*i0 = i > 0 ? i - 1 : 0;
			*i1 = i;
			return;
		}
	}
	*i0 = *i1 = n - 1;
}

/* Bilinear lookup by a*b*. */
float cfx_find(const struct cfx_lut *l, const float ab[2])
{
	int i0, i1, j0, j1;
	float fa = 1.0f, fb = 1.0f, r0, r1;

	lut_index(l->x, l->nx, ab[0], &i0, &i1);
	lut_index(l->y, l->ny, ab[1], &j0, &j1);
	if (i0 != i1)
		fa = (ab[0] - l->x[i0]) / (l->x[i1] - l->x[i0]);
	if (j0 != j1)
		fb = (ab[1] - l->y[j0]) / (l->y[j1] - l->y[j0]);

	r0 = fma3(l->v[j0 * l->nx + i0], 1.0f - fa, fa * l->v[j0 * l->nx + i1]);
	r1 = fma3(l->v[j1 * l->nx + i0], 1.0f - fa, fa * l->v[j1 * l->nx + i1]);
	return fma3(r0, 1.0f - fb, fb * r1);
}

/*
 * The Bradford adaptation from lms_src to xyz's white, in linear sRGB, rows
 * scaled so the largest sums to 1. xyz is normalised to Y = 1 in place.
 */
void cfx_matrix(float xyz[3], const float src[3], float out[9])
{
	float inv = 1.0f / xyz[1];
	float X, Y, Z, d[3], A[9], B[9];

	xyz[0] *= inv;
	xyz[1] *= inv;
	xyz[2] *= inv;
	X = xyz[0];
	Y = xyz[1];
	Z = xyz[2];
	for (int i = 0; i < 3; i++) {
		float l = fma3(BF[3 * i + 2], Z,
			       fma3(BF[3 * i], X, BF[3 * i + 1] * Y));
		d[i] = l / src[i];
	}
	for (int i = 0; i < 3; i++) {
		float r0 = i == 0 ? d[0] : 0.0f;
		float r1 = i == 1 ? d[1] : 0.0f;
		float r2 = i == 2 ? d[2] : 0.0f;

		for (int j = 0; j < 3; j++)
			A[3 * i + j] = fma3(r2, N[6 + j],
					    fma3(r0, N[j], r1 * N[3 + j]));
	}
	for (int i = 0; i < 3; i++)
		for (int j = 0; j < 3; j++)
			B[3 * i + j] = fma3(NI[3 * i + 2], A[6 + j],
					    fma3(NI[3 * i], A[j],
						 NI[3 * i + 1] * A[3 + j]));
	memcpy(out, B, sizeof(B));
	normalize(out);
}

void cfx_white(const struct cfx *c, const float m[9], float xy[2], float *Y)
{
	float g0 = 1.0f, g1 = 1.0f, g2 = 1.0f, w[3], X, Yw, Z, sum;

	if (c && c->native) {
		g0 = c->native_gain[0];
		g1 = c->native_gain[1];
		g2 = c->native_gain[2];
	}
	for (int i = 0; i < 3; i++)
		w[i] = fma3(m[3 * i + 2], g2, fma3(m[3 * i], g0, g1 * m[3 * i + 1]));
	X = fma3(S[2], w[2], fma3(S[0], w[0], w[1] * S[1]));
	Yw = fma3(S[5], w[2], fma3(S[3], w[0], w[1] * S[4]));
	Z = fma3(S[8], w[2], fma3(S[6], w[0], w[1] * S[7]));
	sum = (X + Yw) + Z;
	xy[0] = X / sum;
	xy[1] = Yw / sum;
	if (Y)
		*Y = Yw;
}

static void xy_to_xyz100(float x, float y, float xyz[3])
{
	xyz[0] = (x / y) * 100.0f;
	xyz[1] = 100.0f;
	xyz[2] = (float)((((1.0 - (double)x) - (double)y) / (double)y) * 100.0);
}

static void restrict_step(float x0, float y, int j0, int j1, float *xo, float *yo)
{
	float dy = LIM_Y[j1] - LIM_Y[j0];
	float ox = x0 - LIM_X[j0];
	float dx = LIM_X[j1] - LIM_X[j0];
	float t = fma3(dy, ox, -((y - LIM_Y[j0]) * dx));

	t /= dx * dx + dy * dy;
	*yo = fma3(t, dx, y);
	*xo = fma3(-t, dy, x0);
}

/* _CFXGetTarget: the full-strength target for an ambient tristimulus. */
void cfx_target(const struct cfx *c, const float in[3], float out[9])
{
	float sum = (in[0] + in[1]) + in[2];
	float x = in[0] / sum, y = in[1] / sum, x0 = x;
	float xr = x, yr = y, xyz[3], lab[3];
	int i;

	if (!(x >= 0.0f && x <= 1.0f))
		x0 = fminf(fmaxf(x, 0.0f), 1.0f);

	for (i = 1; i < 9; i++)
		if (x0 <= LIM_X[i])
			break;
	if (i < 9) {
		float s3 = LIM_X[i - 1], s1 = LIM_Y[i - 1];
		float lim = fma3((LIM_Y[i] - s1) / (LIM_X[i] - s3), x0 - s3, s1);

		if (y < lim) {
			float dy = LIM_Y[i] - s1, dx = LIM_X[i] - s3;
			float t = fma3(dy, x0 - s3, -((y - s1) * dx));
			float xp;

			t /= dy * dy + dx * dx;
			xp = fma3(-t, dy, x0);
			if (i - 1 >= 1 && xp < s3)
				restrict_step(x0, y, i - 2, i - 1, &xr, &yr);
			else if (xp > LIM_X[i] && i < 8)
				restrict_step(x0, y, i, i + 1, &xr, &yr);
			else {
				xr = xp;
				yr = fma3(t, dx, y);
			}
		} else {
			xr = x0;
		}
	} else if (y < 0.0f) {
		xr = x0;
	} else {
		xr = x0;
	}

	xy_to_xyz100(xr, yr, xyz);
	cfx_lab(xyz, lab);
	if (c->t->polygon)
		cfx_stick(c->t->polygon, c->t->npolygon, lab + 1);
	lab[1] += 0.0f;
	lab[2] += 0.0f;
	cfx_lab_inv(lab, xyz);
	cfx_matrix(xyz, LMS_D65, out);
	normalize(out);
}

/* The harmony half of _CFXUpdateColorFadeInternal: strength and shift. */
void cfx_harmony(struct cfx *c, const float m[9], float out[9])
{
	float xy[2], xyz[3], lab[3], s = c->sfade.value, f = 0.0f;
	float f1, f2;

	cfx_white(c, m, xy, NULL);
	xy_to_xyz100(xy[0], xy[1], xyz);
	cfx_lab(xyz, lab);
	if (c->t->polygon)
		cfx_stick(c->t->polygon, c->t->npolygon, lab + 1);

	f1 = cfx_find(&c->t->lut[0], lab + 1);
	f2 = cfx_find(&c->t->lut[1], lab + 1);
	if ((double)s <= 0.35) {
		float r = (float)((0.35 - (double)s) / 0.35);

		f = (1.0f - r) * f2 + r;
	} else if ((double)s <= 0.7) {
		float r = (float)((0.7 - (double)s) / 0.35);

		f = fma3(r, f2, (1.0f - r) * f1);
	} else if ((double)s <= 0.85) {
		float r = (float)((0.85 - (double)s) / 0.15000000000000002);

		f = fma3(r, f1, (1.0f - r) * 0.0f);
	}

	for (int i = 0; i < 2; i++) {
		float v = (float)fma((double)lab[1 + i], 1.0 - (double)f,
				     (double)(f * 0.0f));

		lab[1 + i] = fma3(c->ab_shift[i], s, v);
	}
	cfx_lab_inv(lab, xyz);
	cfx_matrix(xyz, LMS_D65, out);
}

static bool fade_step(struct cfx_fade *f, double now)
{
	double e = now - f->start, t = e / f->period;
	bool active = f->period != 0.0 && e >= 0.0 && !(t >= 1.0);

	if (active) {
		f->value = (float)fma(t, (double)(f->target - f->from), (double)f->from);
	} else {
		f->value = f->target;
		f->period = 0.0;
		f->done = true;
	}
	return active;
}

static void fade_to(struct cfx_fade *f, float target, double period, double now)
{
	f->period = period;
	f->start = now;
	f->done = false;
	f->target = target;
	f->from = f->value;
}

void cfx_cct_to_xy(const struct cfx *c, float cct, float xy[2])
{
	const float *t = c->t->blackbody;
	int m = c->t->nblackbody, i;

	for (i = 0; i < m; i++)
		if (cct <= t[i])
			break;
	if (i == m) {
		xy[0] = t[2 * m - 1];
		xy[1] = t[3 * m - 1];
	} else if (i == 0) {
		xy[0] = t[m];
		xy[1] = t[2 * m];
	} else {
		float w = (cct - t[i]) / (t[i - 1] - t[i]);

		xy[0] = fma3(1.0f - w, t[m + i], w * t[m + i - 1]);
		xy[1] = fma3(1.0f - w, t[2 * m + i], w * t[2 * m + i - 1]);
	}
}

/* _CFXCheckStats: back off when the white point keeps changing direction */
static void stats_clear(struct cfx_stats *s)
{
	s->last = -1;
	s->count = 0;
	s->head = 0;
	s->idle = 5.0f;
}

static bool stats_check(struct cfx_stats *s, int dir, double now, float *out)
{
	const int cap = sizeof(s->times) / sizeof(s->times[0]);

	while (s->count && s->times[s->head] < now - 60.0) {
		s->head = (s->head + 1) % cap;
		s->count--;
	}
	if (s->count &&
	    now - s->times[(s->head + s->count - 1) % cap] > (double)s->idle)
		stats_clear(s);
	if (dir != 3 && dir != s->last) {
		if (s->count == cap) {
			s->head = (s->head + 1) % cap;
			s->count--;
		}
		s->times[(s->head + s->count) % cap] = now;
		s->count++;
		s->last = dir;
	}
	*out = 0.0f;
	if (s->count >= 5) {
		double span = s->times[(s->head + s->count - 1) % cap] -
			      s->times[s->head];
		float rate = (float)((double)((float)s->count + -1.0f) / span);

		s->idle = 3.0f / rate;
		*out = 10.0f / rate;
		return true;
	}
	return false;
}

/* _CFXSetTarget */
static void set_target(struct cfx *c, const float m[9], float period,
		       bool interruptible, double now)
{
	if (now < c->target_end && !interruptible && period != 0.0f &&
	    !c->target_hold)
		return;

	c->target_hold = !interruptible;
	c->target_end = now + (double)period;
	memcpy(c->ramp_from, c->ramp_now, sizeof(c->ramp_from));
	memcpy(c->ramp_target, m, sizeof(c->ramp_target));
	c->ramp_period = period;
	c->ramp_start = now;
	c->ramp_done = false;
}

/* _CFXUpdateTarget */
static void update_target(struct cfx *c, bool force, float period, double now)
{
	float m[9] = { 1, 0, 0, 0, 1, 0, 0, 0, 1 };
	float xy[2], u, v, den, du, dv, duv, p, extra;
	const float *xyz = c->sample;
	int cct, dir;
	bool small;

	if (c->enabled && c->strength >= 0.0f &&
	    (xyz[0] != 0.0f || xyz[1] != 0.0f || xyz[2] != 0.0f))
		cfx_target(c, xyz, m);

	cfx_white(c, m, xy, NULL);
	den = fma3(xy[0], -2.0f, 12.0f * xy[1]) + 3.0f;
	u = (xy[0] * 4.0f) / den;
	v = (xy[1] * 9.0f) / den;
	cct = mccamy(xy[0], xy[1]);
	du = u - c->uv[0];
	dv = v - c->uv[1];
	duv = sqrtf(fma3(du, du, dv * dv));
	small = duv < UV_THR[1];

	if (!force && small) {
		if (duv < UV_THR[0])
			return;
		if ((double)LUX_DARK / PI > (double)xyz[1])
			p = RAMP_DARK;
		else if ((double)LUX_DIM / PI > (double)xyz[1])
			p = RAMP_DIM;
		else
			p = (float)cct < (float)c->cct ? SLOW_DOWN : SLOW_UP;
		if (stats_check(&c->stats, 3, now, &extra))
			p = fmaxf(extra, p);
		set_target(c, m, p, false, now);
	} else {
		if (force) {
			p = period;
		} else {
			if ((double)LUX_DARK / PI > (double)xyz[1]) {
				dir = 2;
				p = RAMP_DARK;
			} else if ((double)LUX_DIM / PI > (double)xyz[1]) {
				dir = 2;
				p = RAMP_DIM;
			} else {
				dir = (float)cct < (float)c->cct;
				p = dir ? RAMP_DOWN : RAMP_UP;
			}
			if (stats_check(&c->stats, dir, now, &extra))
				p = fmaxf(extra, p);
		}
		set_target(c, m, p, true, now);
	}
	c->uv[0] = u;
	c->uv[1] = v;
	c->cct = (uint32_t)(float)cct;
}

void cfx_init(struct cfx *c, const struct cfx_tables *t, int mode,
	      const float ab_shift[2], const float native_xy[2])
{
	static const float id[9] = { 1, 0, 0, 0, 1, 0, 0, 0, 1 };

	memset(c, 0, sizeof(*c));
	c->t = t;
	c->mode = mode >= 0 && mode < 6 ? mode : 1;
	c->strength = 0.0f;
	c->sfade.done = true;
	c->nfade.done = true;
	c->ab_shift[0] = ab_shift[0];
	c->ab_shift[1] = ab_shift[1];
	c->sample[0] = 95.0500031f;
	c->sample[1] = 100.0f;
	c->sample[2] = 108.900002f;
	c->sample[3] = 6504.0f;
	c->fresh = true;
	c->target_hold = true;
	c->ramp_done = true;
	memcpy(c->ramp_target, id, sizeof(id));
	memcpy(c->ramp_from, id, sizeof(id));
	memcpy(c->ramp_now, id, sizeof(id));
	memcpy(c->harmony, id, sizeof(id));
	memcpy(c->current, id, sizeof(id));
	stats_clear(&c->stats);

	/* CFXSetNativeWhitePoint */
	if (native_xy && native_xy[0] > 0.0f && native_xy[1] > 0.0f) {
		float xr = native_xy[0] / native_xy[1];
		float zr = z_of(native_xy[0], native_xy[1]);
		float ref[3] = { D65[0] / D65[1], 1.0f, z_of(D65[0], D65[1]) };
		float lms[3];

		for (int i = 0; i < 3; i++)
			lms[i] = fma3(BF[3 * i + 2], zr,
				      fma3(BF[3 * i], xr, BF[3 * i + 1]));
		cfx_matrix(ref, lms, c->native_matrix);
		c->native_gain[0] = fma3(zr, -0.498610765f,
					 fma3(xr, 3.2409699f, -1.5373832f));
		c->native_gain[1] = fma3(0.0415550582f, zr,
					 fma3(-0.969243646f, xr, 1.8759675f));
		c->native_gain[2] = fma3(1.05697155f, zr,
					 fma3(0.0556300804f, xr, -0.203976959f));
		c->native = true;
	}
}

static void set_strength(struct cfx *c, float s, double now)
{
	if (s == c->strength)
		return;
	c->strength = s;
	fade_to(&c->sfade, s, 1.0f * ENABLE_PERIOD, now);
}

/* CFXEnableAmbientAdaptation */
void cfx_enable(struct cfx *c, bool enable, double now)
{
	if (c->enabled == enable)
		return;
	stats_clear(&c->stats);
	c->enabled = enable;
	if (enable) {
		if (c->native && c->nfade.value != 1.0f)
			fade_to(&c->nfade, 1.0f, ENABLE_PERIOD, now);
		set_strength(c, MODE_STRENGTH[c->mode], now);
		update_target(c, true, ENABLE_PERIOD, now);
	} else {
		update_target(c, true, ENABLE_PERIOD, now);
		set_strength(c, 0.0f, now);
		if (c->native && c->nfade.value != 0.0f)
			fade_to(&c->nfade, 0.0f, ENABLE_PERIOD, now);
	}
}

/* CFXInputAmbientColor, with _CFXRestrictLowAmbientColor */
void cfx_input(struct cfx *c, const float xyz_in[3], const float xy_in[2],
	       float cct_in, bool force, double now)
{
	float X = xyz_in[0], Y = xyz_in[1], Z = xyz_in[2];
	float x = xy_in[0], y = xy_in[1], cct = cct_in, lux;
	bool update = true;
	bool first = c->fresh;

	if ((double)Y >= 11140.846016432673) {
		x = D65[0];
		y = D65[1];
		X = Y * 0.950501323f;
		Z = (float)((double)Y * 1.0890030492483225);
		cct = 6500.0f;
	}
	if ((double)y >= 0.1958)
		cct = (float)mccamy(x, y);

	lux = (float)((double)Y * PI);
	if (LUX_DARK >= lux) {
		float tx, ty;
		bool far;

		if (lux > 2.0f && cct >= 6000.0f) {
			tx = D65[0];
			ty = D65[1];
			far = fabs((double)c->sample[3] + -6504.0) > 1000.0;
		} else {
			tx = LOW_XY[0];
			ty = LOW_XY[1];
			far = fabsf(c->sample[3] + -4000.0f) > 1000.0f;
		}
		if (LUX_LOW < lux) {
			float r = (LUX_DARK - lux) / (LUX_DARK - LUX_LOW);
			float k = 1.0f - r;
			float xs = k * x, ys = k * y;

			x = fma3(r, tx, xs);
			y = fma3(r, ty, ys);
		} else {
			x = tx;
			y = ty;
		}
		Y = fmaxf(Y, 1.0f);
		X = (x / y) * Y;
		Z = (float)(((1.0 - (double)x) - (double)y) / (double)y * (double)Y);
		cct = (float)mccamy(x, y);
		update = far || first;
	}

	if (update) {
		c->sample[0] = X;
		c->sample[1] = Y;
		c->sample[2] = Z;
		c->sample[3] = cct;
		if (c->enabled)
			update_target(c, force || first, first ? 2.0f : 0.0f, now);
	}
	c->fresh = false;
}

/* _CFXUpdateColorFadeInternal's interpolation */
static bool ramp_step(struct cfx *c, double now)
{
	double e = now - c->ramp_start, t = e / c->ramp_period;
	bool active = c->ramp_period != 0.0 && e >= 0.0 && !(t >= 1.0);

	if (active) {
		double k = t * (double)(float)(c->t->ncurve - 1);
		int i = (int)k;
		double fr = k - (double)i;
		double w = fma(fr, (double)c->t->curve[i + 1],
			       (1.0 - fr) * (double)c->t->curve[i]);

		for (int j = 0; j < 9; j++)
			c->ramp_now[j] = (float)fma(w, (double)(c->ramp_target[j] -
								c->ramp_from[j]),
						    (double)c->ramp_from[j]);
	} else {
		memcpy(c->ramp_now, c->ramp_target, sizeof(c->ramp_now));
		c->ramp_period = 0.0;
		c->ramp_done = true;
	}
	cfx_harmony(c, c->ramp_now, c->harmony);
	return active;
}

/*
 * _CFXMagic: scale each off-diagonal term by its gain and give the
 * difference to the diagonal, so the rows keep their sums.
 */
static void magic(const float *g, const float p[9], float o[9])
{
	float r0 = (p[0] + p[1]) + p[2];
	float r1 = (p[3] + p[4]) + p[5];
	float r2 = (p[6] + p[7]) + p[8];

	o[1] = g[0] * p[1];
	o[2] = g[1] * p[2];
	o[0] = (r0 - o[1]) - o[2];
	o[3] = g[2] * p[3];
	o[5] = g[3] * p[5];
	o[4] = (r1 - o[3]) - o[5];
	o[6] = g[4] * p[6];
	o[7] = g[5] * p[7];
	o[8] = (r2 - o[6]) - o[7];
}

/* CFXUpdateColorFade */
bool cfx_update(struct cfx *c, double now, float out[9], bool *busy)
{
	bool strength_done = c->sfade.done, active;
	float n[9], f[9], h[9], diff = 0.0f;
	bool near_id = true;

	active = fade_step(&c->sfade, now);
	if (!(c->ramp_done && strength_done))
		active |= ramp_step(c, now);

	if (c->native) {
		float k;

		if (!c->nfade.done)
			active |= fade_step(&c->nfade, now);
		k = fminf(fmaxf(c->nfade.value, 0.0f), 1.0f);
		for (int i = 0; i < 9; i++)
			n[i] = fma3(k, c->native_matrix[i],
				    (1.0f - k) * (i % 4 == 0 ? 1.0f : 0.0f));
	} else {
		static const float id[9] = { 1, 0, 0, 0, 1, 0, 0, 0, 1 };

		memcpy(n, id, sizeof(n));
	}
	if (c->t->magic)
		magic(c->t->magic, c->harmony, h);
	else
		memcpy(h, c->harmony, sizeof(h));
	for (int i = 0; i < 3; i++)
		for (int j = 0; j < 3; j++)
			f[3 * i + j] = fma3(n[3 * i + 2], h[6 + j],
					    fma3(n[3 * i], h[j], n[3 * i + 1] * h[3 + j]));
	normalize(f);

	for (int i = 0; i < 9; i++) {
		float d = fabsf(f[i] - c->current[i]);

		if (d > diff)
			diff = d;
		if (near_id && !active)
			near_id = fabs((double)(i % 4 == 0 ? f[i] + -1.0f : f[i])) <= 0.001;
	}
	if (!c->enabled && near_id && !active) {
		static const float id[9] = { 1, 0, 0, 0, 1, 0, 0, 0, 1 };

		memcpy(f, id, sizeof(f));
	}
	if (busy)
		*busy = active;
	if ((double)diff <= 0.001)
		return false;
	memcpy(c->current, f, sizeof(f));
	memcpy(out, f, sizeof(f));
	return true;
}

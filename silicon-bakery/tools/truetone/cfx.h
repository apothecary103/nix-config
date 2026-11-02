/* SPDX-License-Identifier: MIT */
/*
 * True Tone's colour engine, as macOS's CoreBrightness runs it (its "CFX"
 * ColorEffects code, ambient adaptation part), for an Apple panel under
 * Linux. See docs/truetone.md for where each step comes from.
 *
 * Everything works in linear sRGB-primary RGB with a D65 reference white,
 * like CoreBrightness: the output is the 3x3 matrix macOS hands DCP at
 * matrix location 9.
 */
#ifndef BAKERY_TRUETONE_CFX_H
#define BAKERY_TRUETONE_CFX_H

#include <stdbool.h>
#include <stdint.h>

/* The tables CoreBrightness carries, from tools/bakery-truetone-tables. */
struct cfx_lut {
	int nx, ny;		/* 29 a* columns, 55 b* rows */
	const float *x, *y;	/* axes */
	const float *v;		/* ny rows of nx */
};

struct cfx_tables {
	const float *polygon;	/* the a*b* gamut, npolygon (a, b) pairs */
	int npolygon;
	struct cfx_lut lut[2];	/* adaptation by a*b*, weak and strong */
	const float *curve;	/* ramp easing, ncurve samples over [0, 1] */
	int ncurve;
	const float *blackbody;	/* CCT ascending, then x, then y */
	int nblackbody;		/* entries per column */
	const float *magic;	/* _CFXMagic's off-diagonal gains, 6 */
};

struct cfx_fade {
	double period, start;
	bool done;
	float target, value, from;
};

struct cfx_stats {
	int last;
	int count;
	double times[64];	/* direction changes inside the window */
	int head;
	float idle;
};

struct cfx {
	const struct cfx_tables *t;

	/* harmony (ambient adaptation) */
	bool enabled;
	int mode;
	float strength;			/* the mode's target strength */
	struct cfx_fade sfade;		/* effective strength, to strength */
	float ab_shift[2];		/* HarmonyShiftA/B, a*b* at strength 1 */

	/* native white point correction */
	bool native;
	float native_gain[3];
	float native_matrix[9];
	struct cfx_fade nfade;

	/* the last sample CFXInputAmbientColor kept: X, Y, Z, CCT */
	float sample[4];
	bool fresh;			/* no sample yet: force a 2 s ramp */
	/* white point of the last target, u'v', and its CCT */
	float uv[2];
	uint32_t cct;
	struct cfx_stats stats;

	/* ramp: target-space matrices, then harmony applied */
	double ramp_period, ramp_start;
	bool ramp_done;
	float ramp_target[9], ramp_from[9], ramp_now[9], harmony[9];
	double target_end;
	bool target_hold;

	float current[9];
};

void cfx_init(struct cfx *c, const struct cfx_tables *t, int mode,
	      const float ab_shift[2], const float native_xy[2]);
void cfx_enable(struct cfx *c, bool enable, double now);
/* One ambient sample: XYZ in cd/m2 (the sensor's lux / pi), CCT in K. */
void cfx_input(struct cfx *c, const float xyz[3], const float xy[2],
	       float cct, bool force, double now);
/* Advance the ramps; true when out[] changed. *busy says a ramp runs. */
bool cfx_update(struct cfx *c, double now, float out[9], bool *busy);

/* Chromaticity of a correlated colour temperature, from the table. */
void cfx_cct_to_xy(const struct cfx *c, float cct, float xy[2]);

/* The steps, for the comparison against CoreBrightness. */
void cfx_lab(const float xyz[3], float lab[3]);
void cfx_lab_inv(const float lab[3], float xyz[3]);
void cfx_stick(const float *poly, int n, float ab[2]);
float cfx_find(const struct cfx_lut *l, const float ab[2]);
void cfx_matrix(float xyz[3], const float lms_src[3], float out[9]);
void cfx_white(const struct cfx *c, const float m[9], float xy[2], float *Y);
void cfx_target(const struct cfx *c, const float xyz[3], float out[9]);
void cfx_harmony(struct cfx *c, const float m[9], float out[9]);

#endif

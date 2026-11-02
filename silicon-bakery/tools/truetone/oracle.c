// SPDX-License-Identifier: MIT
/*
 * oracle: tools/truetone/cfx.c against macOS's own CoreBrightness, on macOS.
 * It loads CoreBrightness, finds its CFX functions by name and feeds both the
 * same inputs, step by step and end to end. macOS only, never shipped:
 *
 *   cc -O2 -ffp-contract=off -framework CoreFoundation \
 *      oracle.c cfx.c tables.c -o oracle
 *   ./oracle out/apple/truetone.bin     # from tools/bakery-truetone-tables
 */
#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "cfx.h"
#include "tables.h"

#define CB "/System/Library/PrivateFrameworks/CoreBrightness.framework/Versions/A/CoreBrightness"

static void *sym(const char *want)
{
	for (uint32_t i = 0; i < _dyld_image_count(); i++) {
		const struct mach_header_64 *h;
		const uint8_t *p, *q, *e;
		const struct linkedit_data_command *fs = NULL;
		uint64_t le_vm = 0, le_off = 0, text = 0, addr;
		intptr_t slide;

		if (strcmp(_dyld_get_image_name(i), CB))
			continue;
		h = (const void *)_dyld_get_image_header(i);
		slide = _dyld_get_image_vmaddr_slide(i);
		p = (const uint8_t *)(h + 1);
		for (uint32_t c = 0; c < h->ncmds; c++) {
			const struct load_command *lc = (const void *)p;

			if (lc->cmd == LC_SEGMENT_64) {
				const struct segment_command_64 *s = (const void *)lc;

				if (!strcmp(s->segname, "__LINKEDIT")) {
					le_vm = s->vmaddr;
					le_off = s->fileoff;
				} else if (!strcmp(s->segname, "__TEXT")) {
					text = s->vmaddr;
				}
			} else if (lc->cmd == LC_FUNCTION_STARTS) {
				fs = (const void *)lc;
			}
			p += lc->cmdsize;
		}
		if (!fs)
			break;
		q = (const uint8_t *)(le_vm + slide + fs->dataoff - le_off);
		e = q + fs->datasize;
		addr = text + slide;
		while (q < e) {
			uint64_t v = 0;
			int sh = 0;
			uint8_t b;
			Dl_info d;

			do {
				b = *q++;
				v |= (uint64_t)(b & 0x7f) << sh;
				sh += 7;
			} while (b & 0x80);
			if (!v)
				break;
			addr += v;
			if (dladdr((void *)addr, &d) && d.dli_sname &&
			    (uint64_t)d.dli_saddr == addr && !strcmp(d.dli_sname, want))
				return (void *)addr;
		}
	}
	fprintf(stderr, "oracle: no %s in CoreBrightness\n", want);
	exit(2);
}

static void *(*CFXCreate)(void);
static void (*CFXSetWhitePointType)(void *, int);
static int (*CFXInitializeAmbientAdaptation)(void *);
static void (*CFXSetNativeWhitePoint)(void *, const float *);
static int (*CFXSetABShift)(void *, const float *);
static void (*CFXEnableAmbientAdaptation)(void *, int);
static void (*CFXInstallCallback)(void *, void (*)(void *, void *), void *);
static void (*CFXInputAmbientColor)(void *, float *, int);
static int (*CFXUpdateColorFade)(void *, double);
static int (*CFXGetCurrentMatrix)(void *, float *);
static void (*Lab)(const float *, float *);
static void (*LabInv)(const float *, float *);
static void (*Stick)(const float *, int, const float *, float *);
static float (*Find)(const float *, const void *);
static void (*GetMatrix)(void *, float *, float *, const float *);
static void (*GetWP)(void *, const float *, float *, float *);
static void (*GetTarget)(void *, const float *, float *, const float *, int, int);
static int (*FadeInternal)(void *, void *, int, double);
static void (*BlackBody)(void *, float *, float);

static uint64_t rnd_state = 0x9e3779b97f4a7c15ull;

static double rnd(double lo, double hi)
{
	rnd_state ^= rnd_state << 13;
	rnd_state ^= rnd_state >> 7;
	rnd_state ^= rnd_state << 17;
	return lo + (hi - lo) * (double)(rnd_state >> 11) / 9007199254740992.0;
}

struct score {
	const char *what;
	long n, exact;
	double worst;
};

static void score(struct score *s, const float *a, const float *b, int n)
{
	bool same = true;

	for (int i = 0; i < n; i++) {
		double d = fabs((double)a[i] - (double)b[i]);

		if (memcmp(&a[i], &b[i], 4))
			same = false;
		if (d > s->worst || isnan(d))
			s->worst = isnan(d) ? INFINITY : d;
	}
	s->n++;
	s->exact += same;
}

static void report(const struct score *s)
{
	printf("%-12s %6ld cases, %6.2f %% bit-exact, worst |diff| %.3g\n",
	       s->what, s->n, 100.0 * s->exact / s->n, s->worst);
}

static void noop(void *ctx, void *arg)
{
	(void)ctx;
	(void)arg;
}

static uint8_t *apple(const float native[2], const float ab[2])
{
	uint8_t *c = CFXCreate();

	CFXSetWhitePointType(c, 1);
	CFXInitializeAmbientAdaptation(c);
	if (native)
		CFXSetNativeWhitePoint(c, native);
	CFXSetABShift(c, ab);
	CFXInstallCallback(c, noop, NULL);
	return c;
}

int main(int argc, char **argv)
{
	static const float ab[2] = { -4.5f, 2.1000061f };
	struct cfx_tables t;
	float *storage = NULL;
	struct cfx mine;
	uint8_t *c, *h;
	int err;

	if (argc < 2) {
		fprintf(stderr, "usage: oracle apple/truetone.bin\n");
		return 2;
	}
	err = cfx_tables_load(argv[1], &t, &storage);
	if (err) {
		fprintf(stderr, "oracle: %s: %s\n", argv[1], strerror(-err));
		return 2;
	}
	if (!dlopen(CB, RTLD_NOW))
		return 2;
	CFXCreate = sym("CFXCreate");
	CFXSetWhitePointType = sym("CFXSetWhitePointType");
	CFXInitializeAmbientAdaptation = sym("CFXInitializeAmbientAdaptation");
	CFXSetNativeWhitePoint = sym("CFXSetNativeWhitePoint");
	CFXSetABShift = sym("CFXSetABShift");
	CFXEnableAmbientAdaptation = sym("CFXEnableAmbientAdaptation");
	CFXInstallCallback = sym("CFXInstallCallback");
	CFXInputAmbientColor = sym("CFXInputAmbientColor");
	CFXUpdateColorFade = sym("CFXUpdateColorFade");
	CFXGetCurrentMatrix = sym("CFXGetCurrentMatrix");
	Lab = sym("CFXTristimulus2Lab");
	LabInv = sym("CFXLab2Tristimulus");
	Stick = sym("_CFXStickToPolygon");
	Find = sym("_CFXFindAdaptation");
	GetMatrix = sym("_CFXGetMatrix");
	GetWP = sym("_CFXGetWPFromMatrix");
	GetTarget = sym("_CFXGetTarget");
	FadeInternal = sym("_CFXUpdateColorFadeInternal");
	BlackBody = sym("CFXCCT2xy_BlackBody");

	c = apple(NULL, ab);
	CFXEnableAmbientAdaptation(c, 1);
	h = *(uint8_t **)(c + 0x38);
	cfx_init(&mine, &t, 1, ab, NULL);

	/* the tables Apple holds are the ones in the file */
	if (memcmp(*(float **)(h + 0x38), t.polygon, 36 * 4) ||
	    memcmp(*(float **)(c + 0x138), t.curve, 201 * 4)) {
		fprintf(stderr, "oracle: the table file is not this CoreBrightness's\n");
		return 1;
	}


	struct score sl = { "Lab", 0, 0, 0 }, sli = { "Lab^-1", 0, 0, 0 };
	struct score ss = { "polygon", 0, 0, 0 }, sf = { "LUT", 0, 0, 0 };
	struct score sm = { "matrix", 0, 0, 0 }, sw = { "white", 0, 0, 0 };
	struct score st = { "target", 0, 0, 0 }, sh = { "harmony", 0, 0, 0 };
	struct score sb = { "blackbody", 0, 0, 0 }, sn = { "native", 0, 0, 0 };
	struct score sr = { "ramp end", 0, 0, 0 }, sp = { "pipeline", 0, 0, 0 };

	for (int k = 0; k < 20000; k++) {
		float xyz[3] = { rnd(1, 120), rnd(1, 110), rnd(1, 130) };
		float a[3], b[3], la[3], lb[3];
		float ab2[2] = { rnd(-40, 40), rnd(-40, 60) }, o[2];
		float x[3], y[3], src[3] = { rnd(0.8, 1.2), rnd(0.8, 1.2), rnd(0.6, 1.3) };
		float m1[9], m2[9], xy1[2], xy2[2], Y1, Y2;

		Lab(xyz, a);
		cfx_lab(xyz, b);
		score(&sl, a, b, 3);
		la[0] = rnd(0, 100);
		la[1] = rnd(-60, 60);
		la[2] = rnd(-60, 60);
		LabInv(la, a);
		cfx_lab_inv(la, b);
		score(&sli, a, b, 3);

		memcpy(o, ab2, sizeof(o));
		Stick(t.polygon, 18, ab2, o);
		memcpy(lb, ab2, sizeof(ab2));
		cfx_stick(t.polygon, 18, lb);
		score(&ss, o, lb, 2);

		for (int l = 0; l < 2; l++) {
			float fa = Find(ab2, h + (l ? 0x68 : 0x40));
			float fb = cfx_find(&t.lut[l], ab2);

			score(&sf, &fa, &fb, 1);
		}

		memcpy(x, xyz, sizeof(x));
		memcpy(y, xyz, sizeof(y));
		GetMatrix(c, x, m1, src);
		cfx_matrix(y, src, m2);
		score(&sm, m1, m2, 9);

		GetWP(c, m1, xy1, &Y1);
		cfx_white(&mine, m1, xy2, &Y2);
		score(&sw, xy1, xy2, 2);

		/* ambient colours: around the locus, from candlelight to shade */
		{
			float cct = rnd(1800, 12000), bxy1[2], bxy2[2];
			float dx = rnd(-0.03, 0.03), dy = rnd(-0.03, 0.03);
			float lux = exp(rnd(log(0.5), log(50000)));
			float s[3];

			BlackBody(c, bxy1, cct);
			cfx_cct_to_xy(&mine, cct, bxy2);
			score(&sb, bxy1, bxy2, 2);

			s[1] = lux / M_PI;
			s[0] = (bxy2[0] + dx) / (bxy2[1] + dy) * s[1];
			s[2] = (1 - bxy2[0] - dx - bxy2[1] - dy) / (bxy2[1] + dy) * s[1];
			GetTarget(c, s, m1, *(float **)(h + 0x38), 18, 0);
			cfx_target(&mine, s, m2);
			score(&st, m1, m2, 9);

			/* the harmony step at a strength, through a zero-length fade */
			{
				uint8_t fb[0xc0] = { 0 };
				float str = rnd(0, 1);

				memcpy(fb + 0x14, m1, 36);
				*(float *)(h + 0x120) = str;
				mine.sfade.value = str;
				FadeInternal(c, fb, 1, CFAbsoluteTimeGetCurrent());
				cfx_harmony(&mine, m1, m2);
				score(&sh, (float *)(fb + 0x80), m2, 9);
			}
		}
	}

	/* native white point gains and matrix */
	for (int k = 0; k < 200; k++) {
		float nw[2] = { rnd(0.29, 0.34), rnd(0.30, 0.35) };
		uint8_t *a = apple(nw, ab);
		struct cfx b;

		cfx_init(&b, &t, 1, ab, nw);
		score(&sn, (float *)(a + 0x86c), b.native_gain, 3);
		score(&sn, (float *)(a + 0x848), b.native_matrix, 9);
	}

	/*
	 * End to end: enable, a run of ambient samples, each ramp run to its
	 * end. CoreBrightness takes its own clock for ramp starts, so this
	 * compares where the ramps end, not their middles.
	 */
	for (int run = 0; run < 300; run++) {
		uint8_t *a = apple(NULL, ab);
		struct cfx b;
		float ma[9], mb[9];
		double now = CFAbsoluteTimeGetCurrent();
		bool busy;

		cfx_init(&b, &t, 1, ab, NULL);
		CFXEnableAmbientAdaptation(a, 1);
		cfx_enable(&b, true, now);
		for (int k = 0; k < 6; k++) {
			float cct = rnd(1800, 12000), xy[2], s[6];
			float lux = exp(rnd(log(0.5), log(50000)));

			cfx_cct_to_xy(&b, cct, xy);
			xy[0] += rnd(-0.01, 0.01);
			xy[1] += rnd(-0.01, 0.01);
			s[1] = lux / M_PI;
			s[0] = xy[0] / xy[1] * s[1];
			s[2] = (1 - xy[0] - xy[1]) / xy[1] * s[1];
			s[3] = xy[0];
			s[4] = xy[1];
			s[5] = cct;
			now = CFAbsoluteTimeGetCurrent();
			CFXInputAmbientColor(a, s, 0);
			cfx_input(&b, s, s + 3, cct, false, now);
			for (double dt = 0; dt <= 400; dt += 0.5) {
				CFXUpdateColorFade(a, now + dt);
				cfx_update(&b, now + dt, mb, &busy);
			}
			CFXGetCurrentMatrix(a, ma);
			score(&sp, ma, b.current, 9);
			score(&sr, (float *)(a + 0x1c8), b.harmony, 9);
			if (getenv("ORACLE_DEBUG") && run < 2) {
				printf("run %d sample %d: %.1f lux, %.0f K\n", run, k, lux, cct);
				for (int i = 0; i < 9; i++)
					printf(" %.5f", ma[i]);
				printf("  CoreBrightness\n");
				for (int i = 0; i < 9; i++)
					printf(" %.5f", b.current[i]);
				printf("  port\n");
			}
		}
	}

	report(&sl);
	report(&sli);
	report(&ss);
	report(&sf);
	report(&sm);
	report(&sw);
	report(&sb);
	report(&st);
	report(&sh);
	report(&sn);
	report(&sr);
	report(&sp);
	free(storage);
	return 0;
}

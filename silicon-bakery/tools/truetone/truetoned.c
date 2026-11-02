// SPDX-License-Identifier: MIT
/*
 * bakery-truetoned: True Tone on the built-in panel, as macOS's
 * corebrightnessd does it.
 *
 * Every report interval it reads the ambient light sensor the AOP drives
 * (lux and the sensor's correlated colour temperature, from iio_aop_als),
 * gives the sample to CoreBrightness's colour engine (cfx.c) and, while a
 * ramp runs, writes the engine's matrix to the panel's DCP, which applies it
 * at the matrix location macOS's True Tone uses (appledrm's ambient_matrix,
 * patches/linux-truetone).
 */
#define _GNU_SOURCE
#include <errno.h>
#include <getopt.h>
#include <glob.h>
#include <math.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#include "cfx.h"
#include "tables.h"

static volatile sig_atomic_t stop;
static int verbose;
static const char *root = "";	/* --root: a stand-in for / in tests */

static void on_signal(int sig)
{
	(void)sig;
	stop = 1;
}

static double now_s(void)
{
	struct timespec ts;

	clock_gettime(CLOCK_MONOTONIC, &ts);
	return ts.tv_sec + ts.tv_nsec * 1e-9;
}

static void sleep_s(double s)
{
	struct timespec ts;

	if (s <= 0)
		return;
	ts.tv_sec = (time_t)s;
	ts.tv_nsec = (long)((s - ts.tv_sec) * 1e9);
	nanosleep(&ts, NULL);
}

/* The IIO device whose name is `name`, as a directory; NULL if none. */
static char *iio_device(const char *name)
{
	char pattern[512];
	glob_t g;
	char *dir = NULL;

	snprintf(pattern, sizeof(pattern), "%s/sys/bus/iio/devices/iio:device*/name", root);
	if (glob(pattern, 0, NULL, &g))
		return NULL;
	for (size_t i = 0; i < g.gl_pathc && !dir; i++) {
		char buf[64] = { 0 };
		FILE *f = fopen(g.gl_pathv[i], "r");

		if (!f)
			continue;
		if (fgets(buf, sizeof(buf), f)) {
			buf[strcspn(buf, "\n")] = 0;
			if (!strcmp(buf, name)) {
				dir = strdup(g.gl_pathv[i]);
				dir[strlen(dir) - strlen("/name")] = 0;
			}
		}
		fclose(f);
	}
	globfree(&g);
	return dir;
}

static int read_int(const char *dir, const char *attr, long *v)
{
	char path[512];
	FILE *f;
	int ok;

	snprintf(path, sizeof(path), "%s/%s", dir, attr);
	f = fopen(path, "r");
	if (!f)
		return -errno;
	ok = fscanf(f, "%ld", v) == 1;
	fclose(f);
	return ok ? 0 : -EIO;
}

static char *matrix_attr(void)
{
	char pattern[512];
	glob_t g;
	char *path = NULL;

	snprintf(pattern, sizeof(pattern), "%s/sys/bus/platform/drivers/apple-dcp/*/ambient_matrix",
		 root);
	if (!glob(pattern, 0, NULL, &g)) {
		if (g.gl_pathc)
			path = strdup(g.gl_pathv[0]);
		globfree(&g);
	}
	return path;
}

static int write_matrix(const char *path, const float m[9])
{
	char buf[256];
	int n = 0;
	FILE *f;

	if (!m) {
		snprintf(buf, sizeof(buf), "0\n");
	} else {
		for (int i = 0; i < 9; i++)
			n += snprintf(buf + n, sizeof(buf) - n, "%s%lld", i ? " " : "",
				      (long long)llround((double)m[i] * 4294967296.0));
		snprintf(buf + n, sizeof(buf) - n, "\n");
	}
	if (verbose > 1 || !path)
		fprintf(stderr, "matrix %s", buf);
	if (!path)
		return 0;
	f = fopen(path, "w");
	if (!f)
		return -errno;
	if (fputs(buf, f) < 0 || fclose(f)) {
		int err = -errno;

		return err ? err : -EIO;
	}
	return 0;
}

static int parse_pair(const char *s, float v[2])
{
	return sscanf(s, "%f,%f", &v[0], &v[1]) == 2 ? 0 : -1;
}

static void usage(void)
{
	fprintf(stderr,
		"usage: bakery-truetoned --tables apple/truetone.bin [options]\n"
		"  --mode N          CoreBrightness's ColorAdaptationMode (1)\n"
		"  --harmony-shift A,B  the panel's a*b* shift as DCP publishes it,\n"
		"                    HarmonyShiftA/B in 16.16 (-294912,137626)\n"
		"  --native-white X,Y  the panel's native white point (unset: none)\n"
		"  --interval MS     sensor reading interval (200)\n"
		"  --rate HZ         matrix updates per second during a ramp (60)\n"
		"  --dry-run         print matrices instead of writing them\n"
		"  -v                log samples; twice, matrices too\n");
}

int main(int argc, char **argv)
{
	static const struct option opts[] = {
		{ "tables", required_argument, NULL, 't' },
		{ "mode", required_argument, NULL, 'm' },
		{ "harmony-shift", required_argument, NULL, 's' },
		{ "native-white", required_argument, NULL, 'n' },
		{ "interval", required_argument, NULL, 'i' },
		{ "rate", required_argument, NULL, 'r' },
		{ "dry-run", no_argument, NULL, 'd' },
		{ "root", required_argument, NULL, 'R' },
		{ "verbose", no_argument, NULL, 'v' },
		{ NULL, 0, NULL, 0 },
	};
	const char *tables = NULL;
	float shift[2] = { -4.5f, 2.1000061f }, native[2] = { 0, 0 };
	int mode = 1, interval_ms = 200, rate = 60, dry = 0, o, err;
	char *als, *cctdev, *attr = NULL;
	struct cfx_tables t;
	float *storage = NULL, m[9];
	struct cfx c;
	double next_read;
	bool busy = false, pending = false;

	while ((o = getopt_long(argc, argv, "v", opts, NULL)) != -1) {
		switch (o) {
		case 't': tables = optarg; break;
		case 'm': mode = atoi(optarg); break;
		case 's': {
			int a, b;

			if (sscanf(optarg, "%d,%d", &a, &b) != 2)
				return usage(), 2;
			/* as CoreBrightness's setLabShift converts them */
			shift[0] = (float)a * 0x1p-16f;
			shift[1] = (float)b * 0x1p-16f;
			break;
		}
		case 'n':
			if (parse_pair(optarg, native))
				return usage(), 2;
			break;
		case 'i': interval_ms = atoi(optarg); break;
		case 'r': rate = atoi(optarg); break;
		case 'd': dry = 1; break;
		case 'R': root = optarg; break;
		case 'v': verbose++; break;
		default: return usage(), 2;
		}
	}
	if (!tables || mode < 0 || mode > 5 || interval_ms < 10 || rate < 1)
		return usage(), 2;

	err = cfx_tables_load(tables, &t, &storage);
	if (err) {
		fprintf(stderr, "bakery-truetoned: %s: %s\n", tables, strerror(-err));
		return 1;
	}
	als = iio_device("aop-sensors-als");
	cctdev = iio_device("aop-sensors-als-cct");
	if (!als || !cctdev) {
		fprintf(stderr, "bakery-truetoned: no %s: needs iio_aop_als with "
			"patches/linux-truetone\n", als ? "colour temperature" : "ambient light sensor");
		return 1;
	}
	if (!dry) {
		attr = matrix_attr();
		if (!attr) {
			fprintf(stderr, "bakery-truetoned: no ambient_matrix: needs appledrm "
				"with patches/linux-truetone\n");
			return 1;
		}
	}

	signal(SIGTERM, on_signal);
	signal(SIGINT, on_signal);

	cfx_init(&c, &t, mode, shift, native[0] > 0 ? native : NULL);
	cfx_enable(&c, true, now_s());
	next_read = now_s();

	while (!stop) {
		double now = now_s();
		bool tick = now >= next_read;

		if (tick) {
			long lux, cct;

			next_read = now + interval_ms / 1000.0;
			if (!read_int(als, "in_illuminance_input", &lux) &&
			    !read_int(cctdev, "in_colortemp_input", &cct) && cct > 0) {
				float xy[2], xyz[3];

				cfx_cct_to_xy(&c, (float)cct, xy);
				xyz[1] = (float)((double)lux / M_PI);
				xyz[0] = xy[0] / xy[1] * xyz[1];
				xyz[2] = (1.0f - xy[0] - xy[1]) / xy[1] * xyz[1];
				if (verbose)
					fprintf(stderr, "lux %ld cct %ld xy %.4f %.4f\n",
						lux, cct, xy[0], xy[1]);
				cfx_input(&c, xyz, xy, (float)cct, false, now);
				busy = true;
			}
		}
		/* a write the panel refused (off, mid-modeset) is retried */
		if (cfx_update(&c, now, m, &busy) || (pending && tick)) {
			err = write_matrix(attr, m);
			pending = err != 0;
			if (err && verbose)
				fprintf(stderr, "bakery-truetoned: ambient_matrix: %s\n",
					strerror(-err));
		}
		if (busy)
			sleep_s(fmin(1.0 / rate, next_read - now_s()));
		else
			sleep_s(next_read - now_s());
	}

	write_matrix(attr, NULL);
	free(storage);
	return 0;
}

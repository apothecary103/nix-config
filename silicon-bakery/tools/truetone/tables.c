// SPDX-License-Identifier: MIT
/* Loads apple/truetone.bin, as tools/bakery-truetone-tables writes it. */
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "tables.h"

static const struct {
	const char *name;
	int count;
} sections[] = {
	{ "polygon", 36 }, { "lut0_x", 29 }, { "lut0_y", 55 }, { "lut0", 29 * 55 },
	{ "lut1_x", 29 }, { "lut1_y", 55 }, { "lut1", 29 * 55 }, { "curve", 201 },
	{ "blackbody", 813 }, { "magic", 6 },
};
#define NSECTIONS (sizeof(sections) / sizeof(sections[0]))

static int le32(const unsigned char *p)
{
	return p[0] | p[1] << 8 | p[2] << 16 | (unsigned)p[3] << 24;
}

int cfx_tables_load(const char *path, struct cfx_tables *t, float **storage)
{
	const float *at[NSECTIONS] = { 0 };
	unsigned char *buf = NULL, *p, *end;
	long size;
	float *data;
	FILE *f;
	int n, err = -EINVAL;

	f = fopen(path, "rb");
	if (!f)
		return -errno;
	if (fseek(f, 0, SEEK_END) || (size = ftell(f)) < 12 || fseek(f, 0, SEEK_SET))
		goto out;
	buf = malloc(size);
	if (!buf || fread(buf, 1, size, f) != (size_t)size)
		goto out;
	if (memcmp(buf, "BKTT0001", 8))
		goto out;
	n = le32(buf + 8);
	p = buf + 12;
	end = buf + size;

	data = malloc(size);
	if (!data)
		goto out;
	*storage = data;
	for (int s = 0; s < n; s++) {
		char name[17] = { 0 };
		int count;

		if (end - p < 20)
			goto out;
		memcpy(name, p, 16);
		count = le32(p + 16);
		p += 20;
		if (count < 0 || end - p < 4L * count)
			goto out;
		for (int i = 0; i < count; i++) {
			unsigned v = le32(p + 4 * i);

			memcpy(&data[i], &v, 4);
		}
		for (size_t k = 0; k < NSECTIONS; k++)
			if (!strcmp(name, sections[k].name) && count == sections[k].count)
				at[k] = data;
		data += count;
		p += 4L * count;
	}
	for (size_t k = 0; k < NSECTIONS; k++)
		if (!at[k])
			goto out;

	t->polygon = at[0];
	t->npolygon = 18;
	for (int l = 0; l < 2; l++) {
		t->lut[l].nx = 29;
		t->lut[l].ny = 55;
		t->lut[l].x = at[1 + 3 * l];
		t->lut[l].y = at[2 + 3 * l];
		t->lut[l].v = at[3 + 3 * l];
	}
	t->curve = at[7];
	t->ncurve = 201;
	t->blackbody = at[8];
	t->nblackbody = 813 / 3;
	t->magic = at[9];
	err = 0;
out:
	free(buf);
	fclose(f);
	return err;
}

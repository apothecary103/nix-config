/* SPDX-License-Identifier: MIT */
#ifndef BAKERY_TRUETONE_TABLES_H
#define BAKERY_TRUETONE_TABLES_H

#include "cfx.h"

/* 0 or -errno; *storage holds the floats t points into (free it last). */
int cfx_tables_load(const char *path, struct cfx_tables *t, float **storage);

#endif

// SPDX-License-Identifier: MIT
/*
 * dcp-matrix: print the main display's DCP colour matrices under macOS
 * (IOMobileFramebufferGetMatrix), as two's complement 32.32 decoded.
 * Location 9 is True Tone's; 7 and 8 the factory calibration.
 *
 *   cc dcp-matrix.c -o dcp-matrix && ./dcp-matrix [location]
 */
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#define IOMFB "/System/Library/PrivateFrameworks/IOMobileFramebuffer.framework/IOMobileFramebuffer"

int main(int argc, char **argv)
{
	void *h = dlopen(IOMFB, RTLD_NOW);
	int (*get_main)(void **), (*get)(void *, int, uint64_t *);
	void *fb = NULL;
	int lo = 0, hi = 15;

	if (!h)
		return 1;
	get_main = (int (*)(void **))dlsym(h, "IOMobileFramebufferGetMainDisplay");
	get = (int (*)(void *, int, uint64_t *))dlsym(h, "IOMobileFramebufferGetMatrix");
	if (!get_main || !get || get_main(&fb))
		return 1;
	if (argc > 1)
		lo = hi = atoi(argv[1]);
	for (int loc = lo; loc <= hi; loc++) {
		uint64_t m[9];

		if (get(fb, loc, m))
			continue;
		printf("%2d:", loc);
		for (int i = 0; i < 9; i++)
			printf(" %9.6f", (double)(int64_t)m[i] / 4294967296.0);
		printf("\n");
	}
	return 0;
}

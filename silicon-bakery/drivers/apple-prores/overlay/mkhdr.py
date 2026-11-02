#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Embed a .dtbo as a C array (xxd -i replacement).

Copied from aquarat/apple-m-series-ave-driver test/mkhdr.py (GPL-2.0-only,
commit 9ab14e45281e8f61fb499b760408028171a5f2b5).
"""
import sys
data = open(sys.argv[1], "rb").read()
name = sys.argv[2]
out = [f"static const unsigned char {name}[] __aligned(8) = {{"]
for i in range(0, len(data), 12):
    out.append("  " + ", ".join(f"0x{b:02x}" for b in data[i:i+12]) + ",")
out.append("};")
out.append(f"static const unsigned int {name}_len = {len(data)};")
open(sys.argv[3], "w").write("\n".join(out) + "\n")

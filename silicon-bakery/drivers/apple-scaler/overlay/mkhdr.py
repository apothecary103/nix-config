#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Write a .dtbo as a C byte array: mkhdr.py in.dtbo name out.h"""
import sys

data = open(sys.argv[1], "rb").read()
name = sys.argv[2]
lines = [f"static const unsigned char {name}[] __aligned(8) = {{"]
for i in range(0, len(data), 12):
    lines.append("\t" + ", ".join(f"0x{b:02x}" for b in data[i:i + 12]) + ",")
lines.append("};")
lines.append(f"static const unsigned int {name}_len = {len(data)};")
open(sys.argv[3], "w").write("\n".join(lines) + "\n")

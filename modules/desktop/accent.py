"""The Catppuccin accent nearest in hue to a colour.

Usage: accent.py SOURCE CANDIDATES, where SOURCE is a hex colour (matugen's
source colour for a wallpaper) and CANDIDATES a file of "name hex" lines.
Prints the name of the candidate whose OKLCH hue is closest, so the picture
picks the colour and the theme keeps its own.
"""
import math
import sys


def hue(hex):
    r, g, b = (int(hex.lstrip("#")[i:i + 2], 16) / 255 for i in (0, 2, 4))
    r, g, b = (c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in (r, g, b))
    l = (0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b) ** (1 / 3)
    m = (0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b) ** (1 / 3)
    s = (0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b) ** (1 / 3)
    a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
    b = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
    return math.atan2(b, a)


def distance(x, y):
    d = abs(x - y) % (2 * math.pi)
    return min(d, 2 * math.pi - d)


source = hue(sys.argv[1])
names = [line.split() for line in open(sys.argv[2]) if line.strip()]
print(min(names, key=lambda n: distance(hue(n[1]), source))[0], end="")

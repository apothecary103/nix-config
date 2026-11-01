"""A Wi-Fi symbol drawn as azuki draws: one round-ended pen about 70 units
wide on its 1024 em, wavering a little as a hand does, sized to sit with its
music note and seashell.

Usage: azuki-wifi.py OUT.ttf. U+E000 is the dot alone, U+E001 to U+E003 the dot
with one to three arcs: the bar lays the level it has over the full symbol
drawn faint, as macOS shows its unlit arcs.
"""
import math
import sys

from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen

UPM = 1024
ADVANCE = 1024
CENTRE = (512, 70)  # where the arcs would meet, just above the baseline
SPAN = math.radians(42)  # each arc runs this far either side of upright
RADII = (220, 415, 610)
PEN = 70
DOT = 66


def wobble(t, seed, amount):
    """A slow waver along a stroke, the same every build."""
    return amount * (math.sin(2.1 * t + seed) * 0.6 + math.sin(5.3 * t + 2 * seed) * 0.4)


def arc(radius, seed, steps=48):
    """One arc as a closed outline: its outer edge, a round end, its inner
    edge back, and a round start."""
    cx, cy = CENTRE
    outer, inner = [], []
    for i in range(steps + 1):
        t = i / steps
        a = math.pi / 2 + SPAN - 2 * SPAN * t  # left to right over the top
        r = radius * (1 + wobble(t, seed, 0.03))
        half = PEN / 2 * (1 + wobble(t, seed + 1.7, 0.14))
        outer.append((cx + (r + half) * math.cos(a), cy + (r + half) * math.sin(a), a, r, half))
        inner.append((cx + (r - half) * math.cos(a), cy + (r - half) * math.sin(a)))

    def cap(a, r, half, ahead):
        # Half a circle round the stroke's end, from its outer edge to its
        # inner, bulging the way the stroke was going (ahead).
        ex, ey = cx + r * math.cos(a), cy + r * math.sin(a)
        nx, ny = math.cos(a), math.sin(a)
        tx, ty = ahead
        return [
            (ex + half * (math.cos(phi) * nx + math.sin(phi) * tx),
             ey + half * (math.cos(phi) * ny + math.sin(phi) * ty))
            for phi in (math.pi * j / 12 for j in range(1, 12))
        ]

    _, _, a_end, r_end, h_end = outer[-1]
    _, _, a_start, r_start, h_start = outer[0]
    points = [(x, y) for x, y, *_ in outer]
    # The pen runs left to right, so it ends heading clockwise and began
    # heading the other way; the start's cap is walked inner edge to outer.
    points += cap(a_end, r_end, h_end, (math.sin(a_end), -math.cos(a_end)))
    points += list(reversed(inner))
    points += list(reversed(cap(a_start, r_start, h_start, (-math.sin(a_start), math.cos(a_start)))))
    return points


def dot():
    cx, cy = CENTRE
    cy += DOT * 0.55
    return [
        (cx + DOT * (1 + wobble(i / 32, 0.4, 0.05)) * math.cos(2 * math.pi * i / 32),
         cy + DOT * (1 + wobble(i / 32, 0.4, 0.05)) * math.sin(2 * math.pi * i / 32))
        for i in range(32)
    ]


def clockwise(points):
    """TrueType fills clockwise outlines."""
    area = sum(x0 * y1 - x1 * y0 for (x0, y0), (x1, y1) in zip(points, points[1:] + points[:1]))
    return points if area < 0 else list(reversed(points))


def glyph(arcs):
    pen = TTGlyphPen(None)
    for contour in [dot()] + [arc(RADII[i], seed=1.3 + i * 2.2) for i in range(arcs)]:
        contour = clockwise([(round(x), round(y)) for x, y in contour])
        pen.moveTo(contour[0])
        for point in contour[1:]:
            pen.lineTo(point)
        pen.closePath()
    return pen.glyph()


names = [".notdef", "space"] + [f"wifi{n}" for n in range(4)]
glyphs = {".notdef": TTGlyphPen(None).glyph(), "space": TTGlyphPen(None).glyph()}
glyphs.update({f"wifi{n}": glyph(n) for n in range(4)})

fb = FontBuilder(UPM, isTTF=True)
fb.setupGlyphOrder(names)
fb.setupCharacterMap({0x20: "space", **{0xE000 + n: f"wifi{n}" for n in range(4)}})
fb.setupGlyf(glyphs)
# Each glyph's left side bearing is its own left edge, or renderers shift it.
glyf = fb.font["glyf"]
for name in names:
    glyf[name].recalcBounds(glyf)
fb.setupHorizontalMetrics({name: (ADVANCE, getattr(glyf[name], "xMin", 0)) for name in names})
fb.setupHorizontalHeader(ascent=880, descent=-144)
fb.setupOS2(sTypoAscender=880, sTypoDescender=-144, usWinAscent=880, usWinDescent=144)
fb.setupNameTable({"familyName": "azuki_wifi", "styleName": "Regular"})
fb.setupPost()
fb.save(sys.argv[1])

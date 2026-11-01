"""A Wi-Fi symbol made of azuki's own pen strokes.

Usage: azuki-wifi.py AZUKI.ttf OUT.ttf. The arcs are azuki's ⌒ (U+2312): its
centre line and the width of its stroke along it are traced from the font,
then the line is drawn again at three sizes about one centre, each with
azuki's own stroke, so the small arcs keep the pen's weight rather than
shrinking with it. The dot is azuki's ・ (U+30FB) as it stands.

U+E000 is the dot alone, U+E001 to U+E003 the dot with one to three arcs: the
bar lays the level it has over the full symbol drawn faint, as macOS shows its
unlit arcs.
"""
import math
import sys

import numpy as np
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.recordingPen import DecomposingRecordingPen
from fontTools.pens.transformPen import TransformPen
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib import TTFont
from PIL import Image, ImageDraw, ImageFont

AZUKI, OUT = sys.argv[1], sys.argv[2]
UPM = 1024
SCALES = (1.0, 0.63, 0.28)  # the arcs, outermost first, with room between
PEN = 0.8  # the arcs' stroke against ⌒'s, light enough to leave the gaps open
DOT = 0.7  # the dot against ・
BOX = (85, 940)  # the drawing's width on the em, about the note's
BASE = 0  # where the dot's foot would sit before centring

azuki = TTFont(AZUKI)
cmap = azuki.getBestCmap()
glyphs = azuki.getGlyphSet()


def trace(char, size=2000):
    """The centre line of a single-stroke glyph and its stroke's width, in
    font units: the middle of the ink down each column, and the ink's depth
    there turned across the stroke by its slope."""
    font = ImageFont.truetype(AZUKI, size)
    left, top, right, bottom = font.getbbox(char)
    image = Image.new("L", (right - left + 4, bottom - top + 4), 0)
    ImageDraw.Draw(image).text((2 - left, 2 - top), char, font=font, fill=255)
    ink = np.asarray(image) > 127
    xs, ys, depth = [], [], []
    for x in range(ink.shape[1]):
        rows = np.nonzero(ink[:, x])[0]
        if len(rows):
            xs.append(x)
            ys.append((rows[0] + rows[-1]) / 2)
            depth.append(rows[-1] - rows[0] + 1)
    xs, ys, depth = map(np.array, (xs, ys, depth))
    ys = np.convolve(np.pad(ys, 4, mode="edge"), np.ones(9) / 9, mode="valid")
    width = depth * np.cos(np.arctan(np.gradient(ys, xs)))
    # The outermost columns catch the round ends, not the stroke.
    trim = max(1, int(len(xs) * 0.05))
    xs, ys, width = xs[trim:-trim], ys[trim:-trim], width[trim:-trim]
    width = np.convolve(np.pad(width, 6, mode="edge"), np.ones(13) / 13, mode="valid")
    unit = UPM / size
    return xs * unit, -ys * unit, width * unit


def centre_of(xs, ys):
    """The centre of the circle nearest the line, which the arcs share."""
    a = np.column_stack([xs, ys, np.ones_like(xs)])
    d, e, _ = np.linalg.lstsq(a, -(xs ** 2 + ys ** 2), rcond=None)[0]
    return -d / 2, -e / 2


def stroke(xs, ys, width):
    """A round-ended pen stroke along the line, as one clockwise outline."""
    dx, dy = np.gradient(xs), np.gradient(ys)
    length = np.hypot(dx, dy)
    nx, ny = -dy / length, dx / length
    half = width / 2

    def cap(i, ahead):
        tx, ty = ahead * dx[i] / length[i], ahead * dy[i] / length[i]
        sx, sy = ahead * nx[i], ahead * ny[i]
        return [
            (xs[i] + half[i] * (math.cos(p) * sx + math.sin(p) * tx),
             ys[i] + half[i] * (math.cos(p) * sy + math.sin(p) * ty))
            for p in (math.pi * j / 10 for j in range(1, 10))
        ]

    left = list(zip(xs + nx * half, ys + ny * half))
    right = list(zip(xs - nx * half, ys - ny * half))
    contour = left + cap(-1, 1) + right[::-1] + cap(0, -1)
    area = sum(x0 * y1 - x1 * y0 for (x0, y0), (x1, y1) in zip(contour, contour[1:] + contour[:1]))
    return contour if area < 0 else contour[::-1]


xs, ys, width = trace("⌒")
cx, cy = centre_of(xs, ys)

# Lay the drawing out on the em: the outer arc spans the box, the shared
# centre sits on the dot.
fit = (BOX[1] - BOX[0]) / (xs.max() - xs.min())
bounds = BoundsPen(glyphs)
glyphs[cmap[0x30FB]].draw(bounds)
dot_left, dot_bottom, dot_right, dot_top = bounds.bounds
dot_height = dot_top - dot_bottom
centre_y = BASE + dot_height / 2


def place(x, y):
    return BOX[0] + (x - xs.min()) * fit, centre_y + (y - cy) * fit


def outline(arcs, lift=0.0):
    pen = TTGlyphPen(None)
    for scale in SCALES[len(SCALES) - arcs:]:
        px, py = np.array([place(cx + (x - cx) * scale, cy + (y - cy) * scale) for x, y in zip(xs, ys)]).T
        # Smaller about the shared centre, still with azuki's pen.
        contour = stroke(px, py + lift, width * PEN)
        pen.moveTo(tuple(map(round, contour[0])))
        for point in contour[1:]:
            pen.lineTo(tuple(map(round, point)))
        pen.closePath()
    dot = DecomposingRecordingPen(glyphs)
    glyphs[cmap[0x30FB]].draw(dot)
    shift_x = place(cx, cy)[0] - (dot_left + dot_right) / 2
    # Scaled about its own centre, which stays where the full-size dot's was.
    mid_x, mid_y = (dot_left + dot_right) / 2, (dot_bottom + dot_top) / 2
    to_x, to_y = mid_x + shift_x, mid_y + BASE - dot_bottom + lift
    dot.replay(TransformPen(pen, (DOT, 0, 0, DOT, to_x - DOT * mid_x, to_y - DOT * mid_y)))
    return pen.glyph()


# Centred on the same height as azuki's note, so the bar's icons line up.
note = BoundsPen(glyphs)
glyphs[cmap[0x252F]].draw(note)
full = outline(3)
full.recalcBounds(None)
lift = (note.bounds[1] + note.bounds[3]) / 2 - (full.yMin + full.yMax) / 2

names = [".notdef", "space"] + [f"wifi{n}" for n in range(4)]
built = {".notdef": TTGlyphPen(None).glyph(), "space": TTGlyphPen(None).glyph()}
built.update({f"wifi{n}": outline(n, lift) for n in range(4)})

fb = FontBuilder(UPM, isTTF=True)
fb.setupGlyphOrder(names)
fb.setupCharacterMap({0x20: "space", **{0xE000 + n: f"wifi{n}" for n in range(4)}})
fb.setupGlyf(built)
glyf = fb.font["glyf"]
for name in names:
    glyf[name].recalcBounds(glyf)
# Each glyph's left side bearing is its own left edge, or renderers shift it.
fb.setupHorizontalMetrics({name: (UPM, getattr(glyf[name], "xMin", 0)) for name in names})
fb.setupHorizontalHeader(ascent=880, descent=-144)
fb.setupOS2(sTypoAscender=880, sTypoDescender=-144, usWinAscent=880, usWinDescent=144)
fb.setupNameTable({"familyName": "azuki_wifi", "styleName": "Regular"})
fb.setupPost()
fb.save(OUT)

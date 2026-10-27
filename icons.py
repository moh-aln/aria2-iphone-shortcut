#!/usr/bin/env python3
"""Draws the pictures in aria2's menus: the photos of the vCard rows the shortcut shows.

Each picture is a coloured disc with a white symbol on it, like the photo of a contact, plus
progress rings for downloads (blue) and their preparation (orange), every 10%. They're drawn
here from circles, rings, rounded boxes, thick lines and polygons, so the build needs nothing
outside Python's standard library. Run on its own, it writes them all into icons/ to look at.
"""
import math
import struct
import zlib
from pathlib import Path

SIZE = 96   # pixels, each way
SAMPLES = 3  # samples per pixel, each way, for smooth edges

WHITE = (255, 255, 255)
# iOS's system colours.
BLUE, GREEN, ORANGE, RED = (10, 132, 255), (48, 209, 88), (255, 159, 10), (255, 69, 58)
GRAY, INDIGO, PURPLE, PINK = (142, 142, 147), (94, 92, 230), (191, 90, 242), (255, 55, 95)
TEAL, SLATE, DARK, BROWN = (48, 176, 199), (99, 110, 130), (44, 44, 46), (172, 142, 104)
TRACK_BG, TRACK = (242, 242, 247), (209, 209, 214)

# Shapes are tests of a point (x, y), with the picture spanning -1 to 1 and y pointing down.


def disc(cx, cy, r):
    return lambda x, y: (x - cx) ** 2 + (y - cy) ** 2 <= r * r


def box(x0, y0, x1, y1, r=0.0):
    def inside(x, y):
        dx = max(x0 + r - x, 0, x - (x1 - r))
        dy = max(y0 + r - y, 0, y - (y1 - r))
        return x0 <= x <= x1 and y0 <= y <= y1 and dx * dx + dy * dy <= r * r
    return inside


def line(x0, y0, x1, y1, width):
    """A thick line with round ends."""
    vx, vy = x1 - x0, y1 - y0
    length2 = vx * vx + vy * vy
    half2 = (width / 2) ** 2

    def inside(x, y):
        t = max(0.0, min(1.0, ((x - x0) * vx + (y - y0) * vy) / length2))
        px, py = x0 + t * vx - x, y0 + t * vy - y
        return px * px + py * py <= half2
    return inside


def polygon(*points):
    def inside(x, y):
        hit = False
        for (ax, ay), (bx, by) in zip(points, points[1:] + points[:1]):
            if (ay > y) != (by > y) and x < ax + (y - ay) * (bx - ax) / (by - ay):
                hit = not hit
        return hit
    return inside


def angle(x, y):
    """Degrees clockwise from 12 o'clock."""
    return math.degrees(math.atan2(x, -y)) % 360


def arc(r0, r1, start=0.0, end=360.0):
    """A ring around the centre between radii r0 and r1, from angle start to end."""
    def inside(x, y):
        d2 = x * x + y * y
        return r0 * r0 <= d2 <= r1 * r1 and (end - start >= 360 or start <= angle(x, y) <= end)
    return inside


def round_arc(r0, r1, start, end):
    """An arc with round ends."""
    mid, half = (r0 + r1) / 2, (r1 - r0) / 2
    ends = [disc(mid * math.sin(math.radians(a)), -mid * math.cos(math.radians(a)), half)
            for a in (start, end)]
    return union(arc(r0, r1, start, end), *ends)


def union(*shapes):
    return lambda x, y: any(s(x, y) for s in shapes)


def minus(shape, *holes):
    return lambda x, y: shape(x, y) and not any(h(x, y) for h in holes)


def draw(layers):
    """layers: (colour, shape) pairs, bottom first. Returns PNG bytes."""
    top_first = list(reversed(layers))
    offsets = [((i + 0.5) / SAMPLES, (j + 0.5) / SAMPLES) for i in range(SAMPLES) for j in range(SAMPLES)]
    raw = bytearray()
    for py in range(SIZE):
        raw.append(0)  # PNG filter: none
        for px in range(SIZE):
            r = g = b = hits = 0
            for ox, oy in offsets:
                x, y = (px + ox) / SIZE * 2 - 1, (py + oy) / SIZE * 2 - 1
                for colour, shape in top_first:
                    if shape(x, y):
                        r, g, b, hits = r + colour[0], g + colour[1], b + colour[2], hits + 1
                        break
            if hits:
                raw += bytes((r // hits, g // hits, b // hits, 255 * hits // len(offsets)))
            else:
                raw += b"\0\0\0\0"

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
    header = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0)  # 8-bit RGBA
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) +
            chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b""))


BACKGROUND = disc(0, 0, 1)


def symbol(colour, *shapes):
    return draw([(colour, BACKGROUND), (WHITE, union(*shapes))])


def ring(colour, percent, centre):
    layers = [(TRACK_BG, BACKGROUND), (TRACK, arc(0.62, 0.84))]
    if percent:
        layers.append((colour, round_arc(0.62, 0.84, 0, 360 * percent / 100) if percent < 100 else arc(0.62, 0.84)))
    layers.append((colour, union(*centre)))
    return draw(layers)


def arrow_down(top=-0.42, bottom=0.36, width=0.16, head=0.26):
    return [line(0, top, 0, bottom - head / 2, width),
            polygon((-head, bottom - head), (head, bottom - head), (0, bottom))]


def arrow_up(top=-0.42, bottom=0.42, width=0.16, head=0.28):
    return [line(0, bottom, 0, top + head / 2, width),
            polygon((-head, top + head), (head, top + head), (0, top))]


def circle_arrow(r=0.36, width=0.13):
    # A ring open at the top right, with an arrowhead at its end.
    tip = math.radians(40)
    cx, cy = r * math.sin(tip), -r * math.cos(tip)
    return [round_arc(r - width / 2, r + width / 2, 60, 330),
            polygon((cx - 0.2, cy - 0.05), (cx + 0.12, cy - 0.22), (cx + 0.1, cy + 0.16))]


def outline(x0, y0, x1, y1, r, width):
    return minus(box(x0, y0, x1, y1, r), box(x0 + width, y0 + width, x1 - width, y1 - width, max(r - width, 0)))


FOLDER = [box(-0.52, -0.28, 0.52, 0.42, 0.08), box(-0.52, -0.4, -0.08, -0.16, 0.06)]
PAUSE = [box(-0.28, -0.36, -0.08, 0.36, 0.05), box(0.08, -0.36, 0.28, 0.36, 0.05)]
PLAY = [polygon((-0.2, -0.4), (-0.2, 0.4), (0.42, 0))]
BELL = [disc(0, -0.06, 0.32), polygon((-0.32, -0.06), (0.32, -0.06), (0.4, 0.28), (-0.4, 0.28)),
        line(-0.44, 0.28, 0.44, 0.28, 0.1), disc(0, 0.4, 0.1), disc(0, -0.42, 0.07)]


def gear():
    teeth = [line(0.3 * math.sin(a), -0.3 * math.cos(a), 0.52 * math.sin(a), -0.52 * math.cos(a), 0.2)
             for a in (math.radians(45 * i) for i in range(8))]
    return [minus(union(disc(0, 0, 0.38), *teeth), disc(0, 0, 0.16))]


def icons():
    """{name: PNG bytes} for every picture the menus use."""
    found = {
        "back": symbol(GRAY, line(0.12, -0.36, -0.22, 0, 0.16), line(-0.22, 0, 0.12, 0.36, 0.16)),
        "more": symbol(GRAY, line(-0.12, -0.36, 0.22, 0, 0.16), line(0.22, 0, -0.12, 0.36, 0.16)),
        "downloads": symbol(BLUE, *arrow_down(-0.46, 0.22), line(-0.42, 0.44, 0.42, 0.44, 0.13)),
        "add": symbol(GREEN, line(0, -0.42, 0, 0.42, 0.16), line(-0.42, 0, 0.42, 0, 0.16)),
        "folder": symbol(TEAL, *FOLDER),
        "settings": symbol(GRAY, *gear()),
        "new": symbol(PINK, polygon(*[(r * math.sin(math.radians(45 * i)), -r * math.cos(math.radians(45 * i)))
                                      for i, r in zip(range(8), [0.55, 0.2] * 4)])),
        "bell": symbol(ORANGE, *BELL),
        "belloff": draw([(GRAY, BACKGROUND), (WHITE, union(*BELL)),
                         (GRAY, line(-0.5, -0.5, 0.5, 0.5, 0.24)), (WHITE, line(-0.45, -0.45, 0.45, 0.45, 0.1))]),
        "update": symbol(INDIGO, *arrow_up()),
        "tools": symbol(SLATE, line(-0.36, 0.36, 0.12, -0.12, 0.18),
                        minus(disc(0.2, -0.2, 0.26), line(0.22, -0.22, 0.5, -0.5, 0.17))),
        "app": symbol(DARK, line(-0.4, -0.24, -0.12, 0, 0.12), line(-0.12, 0, -0.4, 0.24, 0.12),
                      line(0.04, 0.28, 0.4, 0.28, 0.12)),
        "pause": symbol(ORANGE, *PAUSE),
        "play": symbol(GREEN, *PLAY),
        "stop": symbol(RED, box(-0.3, -0.3, 0.3, 0.3, 0.06)),
        "retry": symbol(BLUE, *circle_arrow()),
        "refresh": symbol(GRAY, *circle_arrow()),
        "auto": symbol(INDIGO, *circle_arrow()),
        "trash": symbol(RED, polygon((-0.3, -0.18), (0.3, -0.18), (0.24, 0.46), (-0.24, 0.46)),
                        line(-0.42, -0.3, 0.42, -0.3, 0.1), box(-0.12, -0.46, 0.12, -0.3, 0.04)),
        "info": symbol(BLUE, disc(0, -0.32, 0.1), line(0, -0.06, 0, 0.38, 0.16)),
        "done": symbol(GREEN, line(-0.34, 0.02, -0.1, 0.26, 0.16), line(-0.1, 0.26, 0.36, -0.24, 0.16)),
        "failed": symbol(RED, line(0, -0.4, 0, 0.1, 0.17), disc(0, 0.36, 0.1)),
        "paused": symbol(GRAY, *PAUSE),
        "clear": symbol(SLATE, line(0.38, -0.46, 0.06, 0.0, 0.11),
                        polygon((-0.08, -0.06), (0.2, 0.1), (0.02, 0.5), (-0.46, 0.26))),
        "pictures": symbol(PURPLE, outline(-0.46, -0.36, 0.46, 0.36, 0.08, 0.09),
                           polygon((-0.3, 0.2), (-0.06, -0.08), (0.1, 0.1), (0.2, 0.0), (0.32, 0.2)),
                           disc(0.18, -0.14, 0.07)),
        "appstore": symbol(BLUE, line(0.0, -0.4, -0.3, 0.36, 0.12), line(0.0, -0.4, 0.3, 0.36, 0.12),
                           line(-0.2, 0.12, 0.2, 0.12, 0.1)),
        "copy": symbol(SLATE, outline(-0.38, -0.44, 0.14, 0.16, 0.06, 0.08), box(-0.14, -0.16, 0.38, 0.44, 0.06)),
        "paste": symbol(BROWN, outline(-0.32, -0.34, 0.32, 0.46, 0.06, 0.08), box(-0.16, -0.46, 0.16, -0.26, 0.05),
                        line(-0.16, 0.06, 0.16, 0.06, 0.08), line(-0.16, 0.24, 0.1, 0.24, 0.08)),
        "playlist": symbol(PINK, line(-0.4, -0.3, 0.3, -0.3, 0.1), line(-0.4, -0.06, 0.3, -0.06, 0.1),
                           line(-0.4, 0.18, -0.06, 0.18, 0.1), polygon((0.06, 0.06), (0.06, 0.46), (0.42, 0.26))),
        "live": symbol(TEAL, line(-0.3, 0.36, -0.3, 0.06, 0.16), line(0, 0.36, 0, -0.36, 0.16),
                       line(0.3, 0.36, 0.3, -0.1, 0.16)),
        "share": symbol(BLUE, minus(box(-0.36, -0.12, 0.36, 0.46, 0.08), box(-0.26, -0.02, 0.26, 0.36, 0.03),
                                    box(-0.12, -0.2, 0.12, 0.0)),
                        *arrow_up(-0.46, 0.16, 0.12, 0.2)),
        "remove": symbol(GRAY, line(-0.36, 0, 0.36, 0, 0.16)),
        "video": symbol(PURPLE, box(-0.48, -0.26, 0.14, 0.26, 0.08), polygon((0.1, 0.0), (0.46, -0.24), (0.46, 0.24))),
        "music": symbol(PINK, disc(-0.14, 0.26, 0.16), line(0.0, 0.26, 0.0, -0.4, 0.09),
                        polygon((-0.04, -0.46), (0.34, -0.32), (0.34, -0.16), (-0.04, -0.28))),
        "unchecked": draw([(TRACK_BG, BACKGROUND), (TRACK, arc(0.46, 0.6))]),
        "bolt": symbol(ORANGE, polygon((0.1, -0.5), (-0.3, 0.08), (-0.02, 0.08), (-0.1, 0.5), (0.3, -0.08), (0.02, -0.08))),
        "sliders": symbol(INDIGO, *[line(x, -0.42, x, 0.42, 0.08) for x in (-0.28, 0, 0.28)],
                          *[disc(x, y, 0.12) for x, y in ((-0.28, 0.16), (0, -0.18), (0.28, 0.06))]),
        "mute": draw([(GRAY, BACKGROUND),
                      (WHITE, union(box(-0.44, -0.14, -0.2, 0.14, 0.03), polygon((-0.24, -0.14), (0.08, -0.4), (0.08, 0.4), (-0.24, 0.14)))),
                      (WHITE, union(line(0.2, -0.16, 0.44, 0.16, 0.08), line(0.2, 0.16, 0.44, -0.16, 0.08)))]),
        "bug": draw([((52, 199, 89), BACKGROUND),
                     (WHITE, union(box(-0.24, -0.14, 0.24, 0.46, 0.24), disc(0, -0.24, 0.16),
                                   *[line(side * 0.2, y, side * 0.44, y + tilt, 0.08)
                                     for side in (-1, 1) for y, tilt in ((0.0, -0.1), (0.16, 0.0), (0.32, 0.1))],
                                   line(-0.08, -0.36, -0.2, -0.5, 0.07), line(0.08, -0.36, 0.2, -0.5, 0.07))),
                     ((52, 199, 89), line(0, -0.06, 0, 0.44, 0.05))]),
    }
    dots = [disc(-0.24, 0, 0.08), disc(0, 0, 0.08), disc(0.24, 0, 0.08)]
    for percent in range(0, 101, 10):
        found[f"ring{percent}"] = ring(BLUE, percent, arrow_down(-0.3, 0.28, 0.12, 0.18))
        found[f"prep{percent}"] = ring(ORANGE, percent, dots)
    return found


if __name__ == "__main__":
    out = Path(__file__).resolve().parent / "icons"
    out.mkdir(exist_ok=True)
    for name, data in icons().items():
        (out / f"{name}.png").write_bytes(data)
    print(out)

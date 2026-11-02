#!/usr/bin/env python3
"""Turn an mt-probe recording into macOS's measured trackpad transfer
functions, and compare them with what IOHIDFamily's code predicts from the
Mac's profile.

    python3 -I analyse.py recording.jsonl ../../profiles/Mac14,9/macos.json [--write]

It answers the two things the open source leaves open:

- pointer: does the gesture engine send whole or fractional counts? (the
  "exact" and "floor" quantisations in lib/macos-accel.nix)
- scroll: how many points WindowServer makes of a scroll-wheel line, i.e. the
  absolute scroll speed (scroll.pixelsPerLine in lib/macos-accel.nix)

With --write the answers go into the profile under trackpad.measured, which
lib/macos-accel.nix then uses by default.
"""

import bisect
import json
import math
import os
import statistics
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "tests", "reference"))
import iohid  # noqa: E402

TOUCHING = 4  # MultitouchSupport touch state while a finger is down


def load(path):
    header, frames, moves, scrolls, buttons, keys = {}, [], [], [], [], []
    for line in open(path):
        e = json.loads(line)
        k = e["kind"]
        if k == "header":
            header = e
        elif k == "frame":
            frames.append(e)
        elif k in ("move", "drag"):
            moves.append(e)
        elif k == "scroll":
            scrolls.append(e)
        elif k in ("down", "up"):
            buttons.append(e)
        elif k == "key":
            keys.append(e)
    frames.sort(key=lambda f: f["t"])
    return header, frames, moves, scrolls, buttons, keys


def touch_tracks(frames, size):
    """Every touch from first contact to lift, with what it looked like and
    what macOS's frame data says about it: the firmware's finger and hand
    identity, which is macOS's palm verdict."""
    w, h = size
    live, done = {}, []
    for f in frames:
        seen = set()
        for i, t in enumerate(f["touches"]):
            if t["state"] != TOUCHING:
                continue
            tid = t.get("id", i)
            seen.add(tid)
            x, y = t["x"] * w, t["y"] * h
            tr = live.get(tid)
            if tr is None:
                tr = live[tid] = {"start": f["t"], "x0": t["x"], "y0": t["y"], "mx0": x, "my0": y,
                                      "travel": 0.0, "major": 0.0, "minor": 0.0, "z": 0.0, "density": 0.0, "force": 0.0,
                                      "fields": {}}
            tr["travel"] = max(tr["travel"], math.hypot(x - tr["mx0"], y - tr["my0"]))
            for k in ("major", "minor", "z", "density", "force"):
                tr[k] = max(tr[k], t.get(k, 0.0))
            for k in ("finger", "hand", "f14"):
                if k in t:
                    tr["fields"].setdefault(k, {}).setdefault(t[k], 0)
                    tr["fields"][k][t[k]] += 1
            tr["end"] = f["t"]
        for i in [i for i in live if i not in seen]:
            done.append(live.pop(i))
    done.extend(live.values())
    for tr in done:
        tr["fields"] = {k: max(v, key=v.get) for k, v in tr["fields"].items()}
    return done


def macos_verdict(tr):
    """macOS's own: a contact the trackpad's firmware does not identify as a
    finger (1 thumb to 5 little finger) is rejected (_mthid_pathWasRejected)."""
    finger = tr["fields"].get("finger")
    if finger is None:
        return ""
    return "finger" if 1 <= finger <= 5 else "rejected"


def bakery_verdict(tr, key_downs):
    """What patches/libinput 0001-typing-palms decides for a touch, from where
    it lands (assuming MultitouchSupport's normalised y runs up from the edge
    nearest the user): resting if it starts in the bottom 4 %, or in the outer
    5 % either side within 2.5 s of a key press; released after 4 mm."""
    typing = any(0 <= tr["start"] - k <= 2.5 for k in key_downs)
    resting = tr["y0"] < 0.04 or (typing and (tr["x0"] < 0.05 or tr["x0"] > 0.95))
    return "rest" if resting and tr["travel"] <= 4.0 else ("released" if resting else "finger")


def three_finger_drag_release(frames, buttons):
    """For each button release, the time since three fingers last left the pad,
    when the press began with three fingers down (a three-finger drag)."""
    times = [f["t"] for f in frames]
    count = lambda f: sum(1 for t in f["touches"] if t["state"] == TOUCHING)
    delays = []
    for down, up in zip(buttons, buttons[1:]):
        if down["kind"] != "down" or up["kind"] != "up":
            continue
        i = bisect.bisect_right(times, down["t"]) - 1
        if i < 0 or count(frames[i]) != 3:
            continue
        j = bisect.bisect_right(times, up["t"]) - 1
        # Walk back to the last frame with three fingers before the release.
        while j > i and count(frames[j]) < 3:
            j -= 1
        if j + 1 < len(frames) and count(frames[j + 1]) < 3:
            delays.append(up["t"] - frames[j + 1]["t"])
    return delays


def finger_tracks(frames, fingers, size):
    """(t, x_mm, y_mm) of the centroid while exactly `fingers` touch."""
    w, h = size
    out = []
    for f in frames:
        down = [t for t in f["touches"] if t["state"] == TOUCHING]
        if len(down) != fingers:
            out.append((f["t"], None, None))
            continue
        out.append((f["t"], sum(t["x"] for t in down) / fingers * w, sum(t["y"] for t in down) / fingers * h))
    return out


def position_at(track, times, t):
    i = bisect.bisect_right(times, t) - 1
    if i < 0 or i + 1 >= len(track):
        return None
    t0, x0, y0 = track[i]
    t1, x1, y1 = track[i + 1]
    if x0 is None or x1 is None or t1 - t0 > 0.03:
        return None
    a = (t - t0) / (t1 - t0) if t1 > t0 else 0
    return x0 + a * (x1 - x0), y0 + a * (y1 - y0)


def best_lag(track, events, value):
    """The latency (s) between finger motion and the events it causes, found by
    matching speeds; WindowServer delivers events some milliseconds later."""
    times = [p[0] for p in track]
    best = (0.0, -1.0)
    for lag_ms in range(0, 61, 2):
        lag = lag_ms / 1000
        xs, ys = [], []
        for a, b in zip(events, events[1:]):
            dt = b["t"] - a["t"]
            if not 0.004 <= dt <= 0.03:
                continue
            pa, pb = position_at(track, times, a["t"] - lag), position_at(track, times, b["t"] - lag)
            if pa is None or pb is None:
                continue
            xs.append(math.hypot(pb[0] - pa[0], pb[1] - pa[1]) / dt)
            ys.append(value(b) / dt)
        if len(xs) > 20:
            r = correlation(xs, ys)
            if r > best[1]:
                best = (lag, r)
    return best


def correlation(xs, ys):
    mx, my = statistics.fmean(xs), statistics.fmean(ys)
    sx = math.sqrt(sum((x - mx) ** 2 for x in xs))
    sy = math.sqrt(sum((y - my) ** 2 for y in ys))
    return sum((x - mx) * (y - my) for x, y in zip(xs, ys)) / (sx * sy) if sx and sy else 0


def pairs(track, events, value, lag):
    """(finger speed in in/s, output per ms) for consecutive events."""
    times = [p[0] for p in track]
    out = []
    for a, b in zip(events, events[1:]):
        dt = b["t"] - a["t"]
        if not 0.004 <= dt <= 0.03:
            continue
        pa, pb = position_at(track, times, a["t"] - lag), position_at(track, times, b["t"] - lag)
        if pa is None or pb is None:
            continue
        mm = math.hypot(pb[0] - pa[0], pb[1] - pa[1])
        out.append((mm / 25.4 / dt, value(b) / (dt * 1000)))
    return out


def binned(samples, edges):
    rows = []
    for lo, hi in zip(edges, edges[1:]):
        inside = [s for s in samples if lo <= s[0] < hi]
        if len(inside) >= 8:
            rows.append((statistics.median(s[0] for s in inside), statistics.median(s[1] for s in inside), len(inside)))
    return rows


def main():
    rec, profile_path = sys.argv[1], sys.argv[2]
    write = "--write" in sys.argv
    profile = json.load(open(profile_path))
    header, frames, moves, scrolls, buttons, keys = load(rec)
    tp = profile["trackpad"]
    s = tp["sensor"]
    size = (s["widthHundredthsMM"] / 100, s["heightHundredthsMM"] / 100)
    interval = tp["reportIntervalMicroseconds"] / 1000
    F = iohid.FIXED_TO_DOUBLE
    print(f"{len(frames)} multitouch frames, {len(moves)} pointer and {len(scrolls)} scroll events")
    if frames and not any(t["state"] == TOUCHING for f in frames for t in f["touches"]):
        sys.exit("no touching fingers recorded: the MTTouch layout may have changed")
    measured = {}

    # Pointer: one finger, cursor deltas in points.
    one = finger_tracks(frames, 1, size)
    lag, r = best_lag(one, moves, lambda e: math.hypot(e["dx"], e["dy"]))
    samples = pairs(one, moves, lambda e: math.hypot(e["dx"], e["dy"]), lag)
    p = tp["pointer"]
    res = F(p["resolution"])
    curve = iohid.ParametricAcceleration(p["curves"], F(p["acceleration"]), res, iohid.FRAME_RATE)

    def model(v, quant):
        c = v * res * interval / 1000
        whole = math.floor(c) if quant == "floor" else c
        vel = max(whole, F(1))
        return c * curve.multiplier(vel) / vel / interval

    rows = binned(samples, [x / 10 for x in range(1, 30)] + [3 + x / 2 for x in range(0, 35)])
    if rows:
        print(f"\npointer (latency {lag * 1000:.0f} ms, speed correlation {r:.3f})")
        print("  finger in/s   macOS pt/ms   exact model   floor model   n")
        err = {"exact": [], "floor": []}
        for v, out, n in rows:
            e, f = model(v, "exact"), model(v, "floor")
            err["exact"].append(math.log(out / e) ** 2)
            err["floor"].append(math.log(out / f) ** 2)
            print(f"  {v:10.2f}   {out:11.4f}   {e:11.4f}   {f:11.4f}   {n}")
        rms = {k: math.sqrt(statistics.fmean(v)) for k, v in err.items()}
        quant = min(rms, key=rms.get)
        print(f"  rms log error: exact {rms['exact']:.3f}, floor {rms['floor']:.3f} -> {quant}")
        measured["pointerQuantisation"] = quant
        measured["pointerRmsLogError"] = round(rms[quant], 4)

    # Scroll: two fingers, contact phase only (momentum is analysed apart).
    two = finger_tracks(frames, 2, size)
    contact = [e for e in scrolls if e["momentum"] == 0 and e["phase"] in (2, 4)]
    lag, r = best_lag(two, contact, lambda e: math.hypot(e["dx"], e["dy"]))
    samples = pairs(two, contact, lambda e: math.hypot(e["dx"], e["dy"]), lag)
    sc = tp["scroll"]
    sres = F(sc["resolution"])
    srate = F(sc["reportRate"]) if sc["reportRate"] else iohid.FRAME_RATE
    scurve = iohid.ParametricAcceleration(sc["curves"], F(sc["acceleration"]), sres, srate)
    timing = (2 * interval**2 - 955 * interval + 98369) / 65536

    def lines(v):
        c = v * sres * interval / 1000
        vel = max(timing * c, F(1))
        return c * scurve.multiplier(vel) / vel * iohid.SCROLL_PIXEL_TO_WHEEL_SCALE / interval

    rows = binned(samples, [x / 10 for x in range(1, 30)] + [3 + x / 2 for x in range(0, 35)])
    if rows:
        print(f"\nscroll (latency {lag * 1000:.0f} ms, speed correlation {r:.3f})")
        print("  finger in/s   macOS pt/ms   points per line   n")
        ratios = []
        for v, out, n in rows:
            ppl = out / lines(v)
            ratios += [ppl] * n
            print(f"  {v:10.2f}   {out:11.4f}   {ppl:15.3f}   {n}")
        ppl = statistics.median(ratios)
        spread = statistics.pstdev(ratios) / ppl
        slow = [o / (v * 25.4 / 1000) for v, o, _ in rows if v < 1.0]
        print(f"  points per line {ppl:.3f} (spread {spread * 100:.1f} %)")
        if slow:
            print(f"  slow scrolling moves content {statistics.median(slow):.3f} pt per mm of finger travel")
        measured["scrollPixelsPerLine"] = round(ppl, 4)
        measured["scrollShapeSpread"] = round(spread, 4)

    # Momentum: how fast the glide after lift-off decays.
    glide = [e for e in scrolls if e["momentum"] in (1, 4)]
    decay = []
    for a, b in zip(glide, glide[1:]):
        dt = b["t"] - a["t"]
        va, vb = abs(a["dy"]) + abs(a["dx"]), abs(b["dy"]) + abs(b["dx"])
        if 0.004 <= dt <= 0.05 and va > 0.5 and vb > 0.5 and vb < va:
            decay.append(math.log(vb / va) / dt)
    if decay:
        k = statistics.median(decay)
        print(f"\nmomentum: velocity decays as exp({k:.2f} t), half-life {math.log(2) / -k * 1000:.0f} ms")
        measured["momentumDecayPerSecond"] = round(k, 3)

    # Three-finger drag: how long the drag outlives the fingers.
    delays = three_finger_drag_release(frames, buttons)
    if len(delays) >= 3:
        ms = statistics.median(delays) * 1000
        print(f"\nthree-finger drag ends {ms:.0f} ms after the fingers lift ({len(delays)} drags)")
        measured["threeFingerDragReleaseMs"] = round(ms)

    # Palms: every touch's shape and place, macOS's fields for it, and what the
    # bakery's rules make of it, for tuning them against macOS's own verdict.
    tracks = touch_tracks(frames, size)
    key_downs = [k["t"] for k in keys if k.get("down")]
    if tracks:
        out = os.path.splitext(rec)[0] + ".touches.csv"
        cols = ["start", "end", "x0", "y0", "travel", "major", "minor", "z", "density", "force",
                "finger", "hand", "f14", "typing", "bakery", "macos"]
        with open(out, "w") as f:
            f.write(",".join(cols) + "\n")
            for tr in tracks:
                row = dict(tr, **tr["fields"])
                row["typing"] = int(any(0 <= tr["start"] - k <= 2.5 for k in key_downs))
                row["bakery"] = bakery_verdict(tr, key_downs)
                row["macos"] = macos_verdict(tr)
                f.write(",".join(str(row.get(c, "")) for c in cols) + "\n")
        print(f"\n{len(tracks)} touches ({len(key_downs)} key presses) written to {out}")
        groups = {}
        for tr in tracks:
            key = (tr["fields"].get("finger"), tr["fields"].get("hand"))
            groups.setdefault(key, []).append(tr)
        agreement = {}
        for tr in tracks:
            key = (macos_verdict(tr), bakery_verdict(tr, key_downs))
            agreement[key] = agreement.get(key, 0) + 1
        print("  macOS verdict vs the bakery's rest zones (before firmware palms):")
        for (mac, ours), n in sorted(agreement.items()):
            print(f"    macOS {mac or '?':8}  bakery {ours:8}  {n}")
        print("  finger hand   n   major  minor      z   travel mm  bakery rest")
        for (finger, hand), trs in sorted(groups.items(), key=lambda g: -len(g[1])):
            med = lambda k: statistics.median(t[k] for t in trs)
            rest = sum(bakery_verdict(t, key_downs) == "rest" for t in trs)
            print(f"  {finger!s:>6} {hand!s:>4} {len(trs):3d} {med('major'):7.2f} {med('minor'):6.2f}"
                  f" {med('z'):6.2f} {med('travel'):10.1f} {rest:6d}")

    if write and measured:
        measured["recording"] = os.path.basename(rec)
        tp["measured"] = measured
        with open(profile_path, "w") as f:
            json.dump(profile, f, indent=2, sort_keys=True)
            f.write("\n")
        print(f"\nwrote trackpad.measured to {profile_path}")


if __name__ == "__main__":
    main()

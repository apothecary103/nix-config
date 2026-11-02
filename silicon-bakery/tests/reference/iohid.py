#!/usr/bin/env python3
"""IOHIDFamily's trackpad acceleration, transliterated line by line from
apple-oss-distributions/IOHIDFamily (tag IOHIDFamily-2238.100.59,
IOHIDEventSystemPlugIns/IOHIDAccelerationAlgorithm.cpp and IOHIDAcceleration.cpp),
as a second implementation the Nix curves are checked against.

    python3 -I iohid.py ../../profiles/Mac14,9/macos.json > Mac14,9.json

It writes the same JSON as ./run-oracle, which compiles Apple's sources
themselves; run that on macOS to replace this file's output with Apple's own.
Names and order follow the C++ so the two can be read side by side.
"""

import json
import math
import sys

FRAME_RATE = 67.0
kCursorScale = 96.0 / 67.0
SCROLL_EVENT_AVARAGE_LENGHT = 9
SCROLL_CLEAR_THRESHOLD_MS = 500.0
SCROLL_EVENT_THRESHOLD_MS = 150.0
SCROLL_MULTIPLIER_A = 0x00000002 / 65536.0
SCROLL_MULTIPLIER_B = 0x000003BB / 65536.0
SCROLL_MULTIPLIER_C = 0x00018041 / 65536.0
SCROLL_PIXEL_TO_WHEEL_SCALE = 0x0000199A / 65536.0
DBL_MAX = sys.float_info.max


def FIXED_TO_DOUBLE(x):
    return x / 65536.0


class ParametricAcceleration:
    """IOHIDParametricAcceleration::CreateWithParameters and ::multiplier."""

    KEYS = ["index", "gainLinear", "gainParabolic", "gainCubic", "gainQuartic",
            "tangentSpeedLinear", "tangentSpeedParabolicRoot"]

    def __init__(self, curves, acceleration, resolution, rate):
        accelIndex = acceleration
        accelCurves = []
        currentIndex = 0
        for index, raw in enumerate(curves):
            curve = {k: FIXED_TO_DOUBLE(raw.get(k, 0)) for k in self.KEYS}
            # ACCELL_CURVE::isValid: any gain is set. Like Apple's code,
            # currentIndex counts every curve, valid or not.
            if (curve["gainLinear"] or curve["gainParabolic"]
                    or curve["gainCubic"] or curve["gainQuartic"]):
                accelCurves.append(curve)
                if accelIndex >= curve["index"]:
                    currentIndex = index
        self.resolution_ = resolution
        self.rate_ = rate
        lo = accelCurves[currentIndex]
        if lo["index"] < accelIndex and currentIndex + 1 < len(accelCurves):
            hi = accelCurves[currentIndex + 1]
            ratio = (accelIndex - lo["index"]) / (hi["index"] - lo["index"])
            accel = {k: lo[k] + ratio * (hi[k] - lo[k]) for k in self.KEYS}
        else:
            accel = dict(lo)
        self.accel = accel

        self.tangent = [DBL_MAX, DBL_MAX]
        self.m = [0.0, 0.0]
        self.b = [0.0, 0.0]
        a = accel
        if a["tangentSpeedLinear"] != 0:
            t = a["tangentSpeedLinear"]
            y0 = (a["gainLinear"] * t + pow(a["gainParabolic"] * t, 2)
                  + pow(a["gainCubic"] * t, 3) + pow(a["gainQuartic"] * t, 4))
            self.m[0] = (a["gainLinear"] + 2 * t * pow(a["gainParabolic"], 2)
                         + 3 * pow(t, 2) * pow(a["gainCubic"], 3)
                         + 4 * pow(t, 3) * pow(a["gainQuartic"], 4))
            self.b[0] = y0 - self.m[0] * t
            self.tangent[0] = t
            if a["tangentSpeedParabolicRoot"] != 0:
                r = a["tangentSpeedParabolicRoot"]
                y1 = self.m[0] * r + self.b[0]
                self.m[1] = 2 * y1 * self.m[0]
                self.b[1] = pow(y1, 2) - self.m[1] * r
                self.tangent[1] = r
        elif a["tangentSpeedParabolicRoot"] != 0:
            r = a["tangentSpeedParabolicRoot"]
            y0 = (a["gainLinear"] * r + pow(a["gainParabolic"] * r, 2)
                  + pow(a["gainCubic"] * r, 3) + pow(a["gainQuartic"] * r, 4))
            self.m[1] = (a["gainLinear"] + 2 * r * pow(a["gainParabolic"], 2)
                         + 3 * pow(r, 2) * pow(a["gainCubic"], 3)
                         + 4 * pow(r, 3) * pow(a["gainQuartic"], 4))
            self.b[1] = pow(y0, 2) - self.m[1] * r
            self.tangent[0] = r

    def multiplier(self, value):
        a = self.accel
        deviceScale = self.resolution_ / self.rate_
        value /= deviceScale
        if value <= self.tangent[0]:
            multiplier = (a["gainLinear"] * value + pow(a["gainParabolic"] * value, 2)
                          + pow(a["gainCubic"] * value, 3) + pow(a["gainQuartic"] * value, 4))
        elif value <= self.tangent[1] and self.tangent[0] == a["tangentSpeedLinear"]:
            multiplier = self.m[0] * value + self.b[0]
        else:
            multiplier = math.sqrt(self.m[1] * value + self.b[1])
        return multiplier * kCursorScale


class PointerAccelerator:
    """IOHIDPointerAccelerator::accelerate, times in milliseconds."""

    def __init__(self, algorithm, resolution, rate, fixedMultiplier):
        self._algorithm = algorithm
        self._resolution = resolution
        self._rate = rate
        self._fixedMultiplier = fixedMultiplier
        self._lastTimeStamp = None

    def accelerate(self, dx, dy, timestamp):
        rateMultiplier = 1
        if self._rate != 0 and self._lastTimeStamp is not None:
            deltaT = timestamp - self._lastTimeStamp
            if deltaT != 0:
                period_ms = 1000 / self._rate
                if deltaT < period_ms:
                    deltaT = period_ms
                rateMultiplier = period_ms / deltaT
        self._lastTimeStamp = timestamp
        velocity = math.floor(math.sqrt(pow(dx, 2) + pow(dy, 2)))
        velocity *= rateMultiplier if self._fixedMultiplier == 1 else self._fixedMultiplier
        if velocity < FIXED_TO_DOUBLE(0x1):
            velocity = FIXED_TO_DOUBLE(0x1)
        mult = self._algorithm.multiplier(velocity) / velocity
        return dx * mult, dy * mult


class ScrollAccelerator:
    """IOHIDScrollAccelerator::accelerate (parametric branch), times in ms."""

    def __init__(self, algorithm, resolution, rate):
        self._algorithm = algorithm
        self._resolution = resolution
        self._rate = rate
        self._tail = 0
        self._head = 0
        self._direction = False
        self._lastTimeStamp = 0.0
        self.events = [[0.0, 0.0] for _ in range(SCROLL_EVENT_AVARAGE_LENGHT)]

    def accelerate(self, scroll, timestamp):
        deltaT = timestamp - self._lastTimeStamp
        self._lastTimeStamp = timestamp
        head = self._head
        self.events[head] = [deltaT, abs(scroll)]
        self._head = (self._head + 1) % SCROLL_EVENT_AVARAGE_LENGHT
        if self._head == self._tail:
            self._tail = (self._tail + 1) % SCROLL_EVENT_AVARAGE_LENGHT
        direction = scroll > 0
        if self._direction != direction or deltaT > SCROLL_CLEAR_THRESHOLD_MS:
            self._tail = head
            self._direction = direction
        sumDeltaT = 0.0
        sumScroll = 0.0
        eventCount = 0
        i = self._head
        while True:
            i = (i if i else SCROLL_EVENT_AVARAGE_LENGHT) - 1
            sumScroll += self.events[i][1]
            eventCount += 1
            if self.events[i][0] > SCROLL_EVENT_THRESHOLD_MS:
                sumDeltaT += SCROLL_EVENT_THRESHOLD_MS
                break
            sumDeltaT += self.events[i][0]
            if sumDeltaT >= SCROLL_CLEAR_THRESHOLD_MS:
                break
            if i == self._tail:
                break
        rateMultiplier = self._rate / FRAME_RATE
        avargeDeltaTime = (sumDeltaT / eventCount) * rateMultiplier
        if avargeDeltaTime > SCROLL_EVENT_THRESHOLD_MS:
            avargeDeltaTime = SCROLL_EVENT_THRESHOLD_MS
        elif avargeDeltaTime < 1:
            avargeDeltaTime = 1
        avargeScroll = sumScroll / eventCount
        velocity = (SCROLL_MULTIPLIER_A * avargeDeltaTime * avargeDeltaTime
                    - SCROLL_MULTIPLIER_B * avargeDeltaTime + SCROLL_MULTIPLIER_C) * avargeScroll * rateMultiplier
        if velocity < FIXED_TO_DOUBLE(0x1):
            velocity = FIXED_TO_DOUBLE(0x1)
        mult = self._algorithm.multiplier(velocity) / velocity
        return scroll * mult * SCROLL_PIXEL_TO_WHEEL_SCALE


def main():
    profile = json.load(open(sys.argv[1]))
    tp = profile["trackpad"]
    interval = tp["reportIntervalMicroseconds"] / 1000.0
    speeds = [round(i * 0.05, 2) for i in range(1, 801)]

    p = tp["pointer"]
    p_res = FIXED_TO_DOUBLE(p["resolution"])
    p_acc = FIXED_TO_DOUBLE(p["acceleration"])
    pointer = []
    for v in speeds:
        counts = v * p_res * interval / 1000.0
        # Fractional deltas, as accelerate() floors them.
        acc = PointerAccelerator(ParametricAcceleration(p["curves"], p_acc, p_res, FRAME_RATE), p_res, p["reportRate"], 1.0)
        t = 1000.0
        for _ in range(8):
            t += interval
            out, _ = acc.accelerate(counts, 0.0, t)
        floor_out = out / interval
        # Integer deltas carrying the remainder, averaged.
        acc = PointerAccelerator(ParametricAcceleration(p["curves"], p_acc, p_res, FRAME_RATE), p_res, p["reportRate"], 1.0)
        carry = total = 0.0
        reports = 4000
        for _ in range(reports):
            t += interval
            want = counts + carry
            whole = math.floor(want)
            carry = want - whole
            if whole != 0:
                out, _ = acc.accelerate(whole, 0.0, t)
                total += out
        integer_out = total / (reports * interval)
        exact = ParametricAcceleration(p["curves"], p_acc, p_res, FRAME_RATE).multiplier(counts) / interval
        pointer.append({"speed": v, "counts": counts, "floor": floor_out, "integer": integer_out, "exact": exact})

    s = tp["scroll"]
    s_res = FIXED_TO_DOUBLE(s["resolution"])
    s_acc = FIXED_TO_DOUBLE(s["acceleration"])
    s_rate = FIXED_TO_DOUBLE(s["reportRate"]) if s["reportRate"] else FRAME_RATE
    scroll = []
    for v in speeds:
        counts = v * s_res * interval / 1000.0
        acc = ScrollAccelerator(ParametricAcceleration(s["curves"], s_acc, s_res, s_rate), s_res, s_rate)
        t = 1000.0
        for _ in range(20):
            t += interval
            out = acc.accelerate(counts, t)
        scroll.append({"speed": v, "counts": counts, "lines": out / interval})

    json.dump({
        "model": profile["model"],
        "iohidfamily": "IOHIDFamily-2238.100.59 (transliterated, tests/reference/iohid.py)",
        "units": {
            "speed": "finger speed, inches per second",
            "counts": "counts per report at the profile's resolution",
            "floor/integer/exact": "pointer output, points per millisecond",
            "lines": "scroll output, wheel lines per millisecond",
        },
        "pointer": pointer,
        "scroll": scroll,
    }, sys.stdout, indent=1)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()

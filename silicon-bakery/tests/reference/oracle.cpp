// Runs Apple's own trackpad acceleration (IOHIDFamily's IOHIDPointerAccelerator,
// IOHIDScrollAccelerator and IOHIDParametricAcceleration, compiled unchanged
// from apple-oss-distributions/IOHIDFamily) on steady finger motion, and prints
// what macOS makes of it as JSON. tests/default.nix holds the Nix curves to it.
//
//   oracle <profile.json values on argv, see run-oracle>
//
// Built and run on macOS by ./run-oracle, which pins the IOHIDFamily sources.

#include "IOHIDAcceleration.hpp"
#include "IOHIDAccelerationAlgorithm.hpp"

#include <CoreFoundation/CoreFoundation.h>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <mach/mach_time.h>
#include <string>
#include <vector>

// One curve as published in the IORegistry (16.16 fixed point).
struct Curve {
  long index, gainLinear, gainParabolic, gainCubic, gainQuartic, tangentLinear, tangentRoot;
};

static CFNumberRef number(long v) {
  SInt64 x = v;
  return CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt64Type, &x);
}

static CFArrayRef curveArray(const std::vector<Curve> &curves) {
  CFMutableArrayRef array = CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks);
  for (const Curve &c : curves) {
    CFMutableDictionaryRef d = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks,
                                                         &kCFTypeDictionaryValueCallBacks);
    auto put = [&](const char *key, long v) {
      if (v == 0) return;  // unpublished fields read back as 0, as in the IORegistry
      CFStringRef k = CFStringCreateWithCString(kCFAllocatorDefault, key, kCFStringEncodingUTF8);
      CFNumberRef n = number(v);
      CFDictionarySetValue(d, k, n);
      CFRelease(k);
      CFRelease(n);
    };
    put("HIDAccelIndex", c.index);
    if (c.index == 0) {
      // Index 0 is a real value; GetCurve treats a missing key as 0 anyway.
    }
    put("HIDAccelGainLinear", c.gainLinear);
    put("HIDAccelGainParabolic", c.gainParabolic);
    put("HIDAccelGainCubic", c.gainCubic);
    put("HIDAccelGainQuartic", c.gainQuartic);
    put("HIDAccelTangentSpeedLinear", c.tangentLinear);
    put("HIDAccelTangentSpeedParabolicRoot", c.tangentRoot);
    CFArrayAppendValue(array, d);
    CFRelease(d);
  }
  return array;
}

// argv: <kind> <acceleration 16.16> <resolution 16.16> <rate> <report interval us>
//       <n curves> then 7 integers per curve, then speeds in inches per second.
int main(int argc, char **argv) {
  if (argc < 7) {
    fprintf(stderr, "usage: oracle pointer|scroll accel resolution rate interval n curves... speeds...\n");
    return 2;
  }
  std::string kind = argv[1];
  double accel = atol(argv[2]) / 65536.0;
  double resolution = atol(argv[3]) / 65536.0;
  double rate = atof(argv[4]);  // pointer: integer reports/s; scroll: 16.16 already divided
  double intervalMs = atof(argv[5]) / 1000.0;
  int n = atoi(argv[6]);
  int a = 7;
  std::vector<Curve> curves;
  for (int i = 0; i < n; i++, a += 7) {
    curves.push_back({atol(argv[a]), atol(argv[a + 1]), atol(argv[a + 2]), atol(argv[a + 3]), atol(argv[a + 4]),
                      atol(argv[a + 5]), atol(argv[a + 6])});
  }
  std::vector<double> speeds;
  for (; a < argc; a++) speeds.push_back(atof(argv[a]));

  CFArrayRef cfCurves = curveArray(curves);
  mach_timebase_info_data_t tb;
  mach_timebase_info(&tb);
  auto ticks = [&](double ms) { return (uint64_t)llround(ms * 1e6 * tb.denom / tb.numer); };

  // IOHIDPointerScrollFilter builds the algorithm with FRAME_RATE (67) and the
  // service's resolution for both pointer and scroll.
  const double frameRate = kind == "pointer" ? 67.0 : rate;

  printf("[\n");
  for (size_t s = 0; s < speeds.size(); s++) {
    double v = speeds[s];
    // Counts per report at the published resolution (dots per inch).
    double counts = v * resolution * intervalMs / 1000.0;
    double out = 0, outInteger = 0;
    if (kind == "pointer") {
      // Fractional deltas: velocity = floor(|delta|), as accelerate() does.
      auto *alg = IOHIDParametricAcceleration::CreateWithParameters(cfCurves, accel, resolution, frameRate);
      IOHIDPointerAccelerator acc(alg, resolution, rate, 1.0);
      double xy[2];
      uint64_t t = ticks(1000.0);
      for (int i = 0; i < 8; i++) {
        xy[0] = counts;
        xy[1] = 0;
        t += ticks(intervalMs);
        acc.accelerate(xy, 2, t);
      }
      out = xy[0] / intervalMs;
      // Integer deltas carrying the remainder: average over many reports.
      auto *alg2 = IOHIDParametricAcceleration::CreateWithParameters(cfCurves, accel, resolution, frameRate);
      IOHIDPointerAccelerator acc2(alg2, resolution, rate, 1.0);
      double carry = 0, total = 0;
      const int reports = 4000;
      for (int i = 0; i < reports; i++) {
        double want = counts + carry;
        double whole = std::floor(want);
        carry = want - whole;
        xy[0] = whole;
        xy[1] = 0;
        t += ticks(intervalMs);
        if (whole != 0) {
          acc2.accelerate(xy, 2, t);
          total += xy[0];
        }
      }
      outInteger = total / (reports * intervalMs);
      // The curve itself, without the floor: multiplier() of the exact speed.
      auto *alg3 = IOHIDParametricAcceleration::CreateWithParameters(cfCurves, accel, resolution, frameRate);
      double exact = counts > 0 ? alg3->multiplier(counts) / intervalMs : 0;
      delete alg3;
      printf("  {\"speed\": %.17g, \"counts\": %.17g, \"floor\": %.17g, \"integer\": %.17g, \"exact\": %.17g}%s\n", v,
             counts, out, outInteger, exact, s + 1 < speeds.size() ? "," : "");
    } else {
      auto *alg = IOHIDParametricAcceleration::CreateWithParameters(cfCurves, accel, resolution, frameRate);
      IOHIDScrollAccelerator acc(alg, resolution, rate, 1.0);
      double value = 0;
      uint64_t t = ticks(1000.0);
      // Steady scrolling: the average over the last nine reports settles.
      for (int i = 0; i < 20; i++) {
        value = counts;
        t += ticks(intervalMs);
        acc.accelerate(&value, 1, t);
      }
      // value is in scroll-wheel lines (SCROLL_PIXEL_TO_WHEEL_SCALE applied).
      out = value / intervalMs;
      printf("  {\"speed\": %.17g, \"counts\": %.17g, \"lines\": %.17g}%s\n", v, counts, out,
             s + 1 < speeds.size() ? "," : "");
    }
  }
  printf("]\n");
  CFRelease(cfCurves);
  return 0;
}

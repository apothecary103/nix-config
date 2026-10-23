# macOS trackpad acceleration as libinput custom curves (sway's
# pointer_accel_custom / scroll_accel_custom, see ./patches).
#
# The curves are IOHIDFamily's parametric acceleration (IOHIDEventSystemPlugIns/
# IOHIDAccelerationAlgorithm.cpp), fed with the HIDAccelCurves and
# HIDScrollAccelCurves this MacBook's trackpad publishes in the IORegistry
# (`ioreg -r -l -c AppleMultitouchDevice`), at the default speeds macOS reports
# there: HIDTrackpadAcceleration 0.6875 and HIDTrackpadScrollAcceleration 0.3125.
#
# Each curve is three pieces: a polynomial up to TangentSpeedLinear, its tangent
# line up to TangentSpeedParabolicRoot, then sqrt(m * x + b) continuing that line.
# Apple squares and cubes gain * x rather than the gain alone, which differs
# from its own comment; this follows the code.
#
# libinput's custom profile maps device units/ms to output px/ms, with no DPI
# normalisation, so the curves are built for the device's resolution. At scale 2
# a logical pixel is a macOS point (both lay this panel out as 1512x982).
{
  # Device units per mm along x (libinput scales y to match). hid-magicmouse
  # takes the span and size from the trackpad's sensor-dimensions report, which
  # is the IORegistry's "Sensor Surface Descriptor": x runs -5896..6416 over
  # 124.80 mm. The kernel advertises this truncated to 98; the deltas libinput
  # sees are in the real units.
  resolution ? (6416 + 5896) / 124.80,
  # Content speed for slow two-finger scrolling, in logical px per mm of finger
  # travel. 5 is 1:1 on this 254 ppi panel at scale 2 (1512 px across 302 mm).
  # Apple's own numbers suggest nearer 3.5 (0.925 * 96 pt per inch, if a
  # scroll count is 1/400 in and a point is ten of them), but how the closed
  # gesture engine and CGEvent scale it is unknown; measure before changing.
  scrollBaseline ? 5.0,
  # Reports per second: the IORegistry's ReportInterval is 8000 us.
  reportRate ? 125.0,
}:
let
  sqrt =
    x:
    let
      go = n: y: if n == 0 then y else go (n - 1) ((y + x / y) / 2);
    in
    if x <= 0 then 0.0 else go 40 (x + 1.0);

  parametric =
    {
      gainLinear,
      gainParabolic ? 0.0,
      gainCubic ? 0.0,
      gainQuartic ? 0.0,
      tangentLinear,
      tangentRoot,
    }:
    let
      pow2 = v: v * v;
      pow3 = v: v * v * v;
      pow4 = v: pow2 (pow2 v);
      f1 = x: gainLinear * x + pow2 (gainParabolic * x) + pow3 (gainCubic * x) + pow4 (gainQuartic * x);
      t1 = tangentLinear;
      m0 =
        gainLinear
        + 2 * t1 * pow2 gainParabolic
        + 3 * pow2 t1 * pow3 gainCubic
        + 4 * pow3 t1 * pow4 gainQuartic;
      b0 = f1 t1 - m0 * t1;
      y1 = m0 * tangentRoot + b0;
      m1 = 2 * y1 * m0;
      b1 = y1 * y1 - m1 * tangentRoot;
    in
    x:
    if x <= t1 then
      f1 x
    else if x <= tangentRoot then
      m0 * x + b0
    else
      sqrt (m1 * x + b1);

  # HIDAccelCurves entry at HIDAccelIndex 0.6875 (45056), used as is.
  pointerCurve = parametric {
    gainLinear = 62915 / 65536.0;
    gainParabolic = 54395 / 65536.0;
    gainCubic = 7864 / 65536.0;
    tangentLinear = 465306 / 65536.0;
    tangentRoot = 1179648 / 65536.0;
  };

  # HIDScrollAccelCurves at 0.3125: ratio (0.3125 - 0.125) / (0.5 - 0.125) = 0.5
  # between the 8192 and 32768 entries, every field interpolated.
  scrollCurve = parametric {
    gainLinear = (62259 + 58982) / 2 / 65536.0;
    gainParabolic = (39322 + 58982) / 2 / 65536.0;
    tangentLinear = (406323 + 419430) / 2 / 65536.0;
    tangentRoot = 786432 / 65536.0;
  };
  scrollGainLinear = (62259 + 58982) / 2 / 65536.0;

  # v is finger speed in in/s throughout.
  #
  # IOHIDPointerAccelerator: x = (counts per report) / (400 / FRAME_RATE), and the
  # report's delta is scaled to f(x) * 96/67. The trackpad reports every
  # ReportInterval = 8000 us (125 Hz); HIDPointerReportRate 120 only clamps dt.
  pointer = v: pointerCurve (v * 67 / reportRate) * (96.0 / 67) * reportRate / 1000;

  # IOHIDScrollAccelerator: velocity = P(t) * counts per report, P(t) =
  # 3.05e-5 t^2 - 0.01457 t + 1.501 with t the mean report interval in ms
  # (HIDScrollReportRate is unset, so its rate multiplier is 67/67 = 1).
  t = 1000.0 / reportRate;
  timing = 2 / 65536.0 * t * t - 955 / 65536.0 * t + 98369 / 65536.0;
  scroll =
    v:
    let
      x = v * timing * 67 / reportRate;
      gain = if x == 0 then 1.0 else scrollCurve x / (scrollGainLinear * x);
    in
    scrollBaseline * v * 25.4 / 1000 * gain;

  # 64 samples (libinput's maximum). The pointer's last two samples sit on
  # Apple's tangent line (13.2..33.6 in/s), so libinput's extrapolation follows it.
  unitsPerInch = resolution * 25.4;
  sample = stepInches: fn: {
    step = stepInches * unitsPerInch / 1000;
    points = builtins.genList (i: fn (i * stepInches)) 64;
  };

  render = c: builtins.concatStringsSep " " (map toString ([ c.step ] ++ c.points));
in
{
  pointer = render (sample 0.22 pointer);
  scroll = render (sample 0.4 scroll);
}

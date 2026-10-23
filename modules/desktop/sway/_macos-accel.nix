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
  scrollBaseline ? 5.0,
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
      f1 =
        x:
        gainLinear * x + pow2 (gainParabolic * x) + pow3 (gainCubic * x) + pow4 (gainQuartic * x);
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

  # HIDAccelCurves entry at HIDAccelIndex 0.6875.
  pointerCurve = parametric {
    gainLinear = 0.9600067138671875;
    gainParabolic = 0.8300018310546875;
    gainCubic = 0.1199951171875;
    tangentLinear = 7.100006103515625;
    tangentRoot = 18.0;
  };

  # HIDScrollAccelCurves at 0.3125: halfway between the 0.125 and 0.5 entries,
  # interpolated the way IOHIDParametricAcceleration does.
  scrollCurve = parametric {
    gainLinear = (0.9499969482421875 + 0.899993896484375) / 2;
    gainParabolic = (0.600006103515625 + 0.899993896484375) / 2;
    tangentLinear = (6.1999969482421875 + 6.399993896484375) / 2;
    tangentRoot = 12.0;
  };
  scrollGainLinear = (0.9499969482421875 + 0.899993896484375) / 2;

  # The trackpad reports 400 counts per inch at 120 Hz; IOHIDFamily divides
  # speed by resolution / FRAME_RATE (67) and scales output by 96 / 67.
  # Pointer: x = (in/s) * 67 / 120, out = f(x) * 96/67 points per report.
  pointer = inchesPerSecond: pointerCurve (inchesPerSecond * 67 / 120) * (96.0 / 67) * 120 / 1000;

  # Scroll: IOHIDScrollAccelerator weights the per-event delta by its
  # 1.501 - 0.01457 t + 3.05e-5 t^2 timing polynomial (t = 8.33 ms at 120 Hz)
  # before the same normalisation, giving x = 0.7714 * (in/s). Only the curve's
  # shape is kept; scrollBaseline sets the slow-speed rate.
  scrollX = inchesPerSecond: inchesPerSecond * 0.7714;
  scroll =
    inchesPerSecond:
    let
      x = scrollX inchesPerSecond;
      gain = if x == 0 then 1.0 else scrollCurve x / (scrollGainLinear * x);
    in
    scrollBaseline * inchesPerSecond * 25.4 / 1000 * gain;

  # 40 samples, 0.5 in/s apart, up to 19.5 in/s. libinput extrapolates past
  # that along the last segment, which for the pointer is still Apple's own
  # tangent line (its sqrt knee is at 32 in/s).
  samples = 40;
  stepInches = 0.5;
  unitsPerInch = resolution * 25.4;
  sample =
    fn:
    {
      step = stepInches * unitsPerInch / 1000;
      points = builtins.genList (i: fn (i * stepInches)) samples;
    };

  render = c: builtins.concatStringsSep " " (map toString ([ c.step ] ++ c.points));
in
{
  pointer = render (sample pointer);
  scroll = render (sample scroll);
}

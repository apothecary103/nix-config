# macOS trackpad acceleration as libinput custom curves.
#
# What macOS does with trackpad motion, rebuilt from the Mac's own numbers (a
# profile from tools/bakery-probe) and IOHIDFamily's code
# (IOHIDEventSystemPlugIns/IOHIDAccelerationAlgorithm.cpp, IOHIDAcceleration.cpp
# and IOHIDPointerScrollFilter.cpp in apple-oss-distributions/IOHIDFamily):
#
# - The trackpad reports every ReportInterval (8000 us here). Its motion reaches
#   IOHIDPointerAccelerator in counts at HIDPointerResolution (400 per inch).
# - Pointer: velocity = |delta| per report (floored, see `quantisation`), times
#   min(1, (1000 / HIDPointerReportRate) / dt). The delta is scaled by
#   multiplier(velocity) / velocity, where multiplier(v) = f(v / (resolution /
#   67)) * 96/67 and f is the parametric curve for the user's tracking speed:
#   gainLinear*x + (gainParabolic*x)^2 + (gainCubic*x)^3 + (gainQuartic*x)^4 up
#   to tangentSpeedLinear, its tangent line up to tangentSpeedParabolicRoot,
#   then sqrt(m1*x + b1). Curves between two published indices are
#   interpolated field by field, tangent speeds included.
# - Scroll: IOHIDScrollAccelerator averages |delta| and the report interval over
#   up to nine reports; velocity = P(t) * mean delta * rate/67 with P(t) =
#   (2t^2 - 955t + 98369) / 65536, t the mean interval in ms clamped to 1..150,
#   and the delta is scaled by multiplier(velocity) / velocity, then by 0.1
#   (SCROLL_PIXEL_TO_WHEEL_SCALE) into scroll-wheel lines.
#
# libinput's custom profile (filter-custom.c) maps the speed of each touchpad
# frame, in device units per ms (x-axis units, unnormalised), to an output
# speed in logical pixels per ms by linear interpolation between at most 64
# evenly spaced points, extrapolating the last segment. At scale 2 a logical
# pixel is a macOS point (both lay this panel out as 1512x982), so the pointer
# curve maps finger speed to the same points per ms macOS produces.
{ lib }:
{
  # A profile from tools/bakery-probe (profiles/<model>.json, parsed).
  profile,
  # How macOS turns a fractional delta into a velocity. IOHIDPointerAccelerator
  # floors |delta| before looking up the curve: with whole-count deltas (the
  # remainder carried to the next report) that only picks points on the curve
  # and the result follows it ("exact"); with fractional deltas every speed is
  # rounded down to a whole count per report first ("floor", 3-10 % slower
  # below 2 in/s). Which one the gesture engine sends is not in the open
  # source; tools/mt-probe measures it, and a profile with
  # trackpad.measured (tools/mt-probe/analyse.py --write) supplies it.
  quantisation ? profile.trackpad.measured.pointerQuantisation or "exact",
  # Scroll output scale. macOS ends in scroll-wheel lines, which WindowServer
  # turns into exactly 10 points each, rounding every event up to a whole
  # point: { pixelsPerLine = 10; roundUp = true; }, the default. The gesture
  # engine emits whole counts with the remainder carried, so at the slowest
  # every count is one point (15.75 per mm of finger travel), and the
  # rounding matters less as events grow. { pixelsPerLine = x; } without
  # roundUp is Apple's curve alone (3.5 px per mm at the slowest);
  # { slowPixelsPerMM = x; } keeps its shape at another slow-speed rate. A
  # profile with trackpad.measured.scrollPixelsPerLine (tools/mt-probe)
  # overrides the scale.
  scroll ? {
    pixelsPerLine = profile.trackpad.measured.scrollPixelsPerLine or 10.0;
    roundUp = true;
  },
  # Sample spacing of the libinput curves, in inches per second of finger speed.
  # libinput takes 64 points; past the last one it extrapolates the last
  # segment. The pointer's default puts the last two samples on Apple's
  # tangent line, so the extrapolation is exact up to the line's end at
  # tangentSpeedParabolicRoot (33.6 in/s here), with the finest spacing that
  # allows. Scrolling rounded per event is sampled at whole counts per report,
  # which libinput's interpolation then reproduces exactly; without rounding,
  # 0.4 in/s keeps slow scrolls within 8 % and flings to 40 in/s within 6 %
  # (tests/accel.nix holds both to that).
  pointerStep ? null,
  scrollStep ? null,
}:
let
  tp = profile.trackpad;
  fixed = x: x / 65536.0;

  sqrt =
    x:
    let
      go =
        n: y:
        let
          y' = (y + x / y) / 2;
        in
        if n == 0 || y' == y then y else go (n - 1) y';
    in
    if x <= 0 then 0.0 else go 100 (if x > 1 then x else 1.0);

  pow2 = v: v * v;
  pow3 = v: v * v * v;
  pow4 = v: pow2 (pow2 v);
  floor =
    x:
    let
      i = builtins.floor x;
    in
    i + 0.0;
  min = a: b: if a < b then a else b;

  keys = [
    "index"
    "gainLinear"
    "gainParabolic"
    "gainCubic"
    "gainQuartic"
    "tangentSpeedLinear"
    "tangentSpeedParabolicRoot"
  ];

  # IOHIDParametricAcceleration::CreateWithParameters, then ::multiplier.
  parametric =
    {
      curves,
      acceleration,
      resolution,
      rate,
    }:
    let
      parsed = map (c: lib.genAttrs keys (k: fixed (c.${k} or 0))) curves;
      valid = c: c.gainLinear != 0 || c.gainParabolic != 0 || c.gainCubic != 0 || c.gainQuartic != 0;
      # As in Apple's code, the index counts every published curve.
      currentIndex = lib.foldl (
        current: i:
        if valid (builtins.elemAt parsed i) && acceleration >= (builtins.elemAt parsed i).index then
          i
        else
          current
      ) 0 (lib.range 0 (builtins.length parsed - 1));
      validCurves = builtins.filter valid parsed;
      lo = builtins.elemAt validCurves currentIndex;
      hi = builtins.elemAt validCurves (currentIndex + 1);
      a =
        if lo.index < acceleration && currentIndex + 1 < builtins.length validCurves then
          let
            ratio = (acceleration - lo.index) / (hi.index - lo.index);
          in
          lib.genAttrs keys (k: lo.${k} + ratio * (hi.${k} - lo.${k}))
        else
          lo;

      f1 =
        x:
        a.gainLinear * x + pow2 (a.gainParabolic * x) + pow3 (a.gainCubic * x) + pow4 (a.gainQuartic * x);
      slope =
        t:
        a.gainLinear
        + 2 * t * pow2 a.gainParabolic
        + 3 * pow2 t * pow3 a.gainCubic
        + 4 * pow3 t * pow4 a.gainQuartic;

      big = 1.0e308;
      t1 = a.tangentSpeedLinear;
      t2 = a.tangentSpeedParabolicRoot;
      m0 = slope t1;
      b0 = f1 t1 - m0 * t1;
      y1 = m0 * t2 + b0;
      tangent0 =
        if t1 != 0 then
          t1
        else if t2 != 0 then
          t2
        else
          big;
      tangent1 = if t1 != 0 && t2 != 0 then t2 else big;
      m1 = if t1 != 0 then 2 * y1 * m0 else slope t2;
      b1 = if t1 != 0 then y1 * y1 - m1 * t2 else pow2 (f1 t2) - m1 * t2;
    in
    {
      inherit a;
      multiplier =
        value:
        let
          x = value / (resolution / rate);
          y =
            if x <= tangent0 then
              f1 x
            else if x <= tangent1 && tangent0 == t1 then
              m0 * x + b0
            else
              sqrt (m1 * x + b1);
        in
        y * (96.0 / 67.0);
    };

  frameRate = 67.0;
  # Milliseconds between trackpad reports. The IORegistry says 8000 us; the
  # firmware's clock runs 1.97 % slow, and frames really come 8.157 ms apart
  # (a profile's linux.json carries the measured value).
  intervalMs = tp.reportIntervalMicroseconds / 1000.0;

  # Finger speed (in/s) to counts per report at a resolution in dots per inch.
  counts = dpi: v: v * dpi * intervalMs / 1000;

  pointerDpi = fixed tp.pointer.resolution;
  pointerCurve = parametric {
    inherit (tp.pointer) curves;
    acceleration = fixed tp.pointer.acceleration;
    resolution = pointerDpi;
    rate = frameRate;
  };
  # IOHIDPointerAccelerator: the time since the last report, clamped below at
  # 1/HIDPointerReportRate, scales the velocity down when reports are late.
  rateMultiplier =
    if tp.pointer.reportRate == 0 then 1.0 else min 1.0 (1000.0 / tp.pointer.reportRate / intervalMs);

  # Points per ms for a finger speed in inches per second.
  pointer =
    v:
    let
      c = counts pointerDpi v;
      whole = if quantisation == "floor" then floor c else c;
      velocity0 = whole * rateMultiplier;
      velocity = if velocity0 < fixed 1 then fixed 1 else velocity0;
    in
    if v <= 0 then 0.0 else c * pointerCurve.multiplier velocity / velocity / intervalMs;

  scrollDpi = fixed tp.scroll.resolution;
  scrollRate = if tp.scroll.reportRate == null then frameRate else fixed tp.scroll.reportRate;
  scrollCurve = parametric {
    inherit (tp.scroll) curves;
    acceleration = fixed tp.scroll.acceleration;
    resolution = scrollDpi;
    rate = scrollRate;
  };
  scrollRateMultiplier = scrollRate / frameRate;
  # The mean report interval as IOHIDScrollAccelerator sees it while scrolling
  # steadily, and its timing polynomial.
  meanInterval =
    let
      t = intervalMs * scrollRateMultiplier;
    in
    if t > 150 then
      150.0
    else if t < 1 then
      1.0
    else
      t;
  timing = fixed 2 * meanInterval * meanInterval - fixed 955 * meanInterval + fixed 98369;
  wheelScale = fixed 6554; # SCROLL_PIXEL_TO_WHEEL_SCALE, 0x199a

  # Scroll-wheel lines per ms, as macOS hands them to the window server.
  scrollLines =
    v:
    let
      c = counts scrollDpi v;
      velocity0 = timing * c * scrollRateMultiplier;
      velocity = if velocity0 < fixed 1 then fixed 1 else velocity0;
    in
    if v <= 0 then 0.0 else c * scrollCurve.multiplier velocity / velocity * wheelScale / intervalMs;

  # Lines per mm of finger travel as the speed goes to zero.
  slowLinesPerMM =
    scrollCurve.a.gainLinear * (96.0 / 67.0) * scrollRate / scrollDpi * wheelScale * scrollDpi / 25.4;

  pixelsPerLine =
    if scroll ? pixelsPerLine then scroll.pixelsPerLine else scroll.slowPixelsPerMM / slowLinesPerMM;
  roundUp = scroll.roundUp or false;

  # Finger speed (in/s) of one whole count per report.
  countSpeed = 1000 / (scrollDpi * intervalMs);

  # Points WindowServer makes of an event of n whole counts, rounded up.
  pointsPerEvent =
    n: if n <= 0 then 0.0 else ceil (pixelsPerLine * scrollLines (n * countSpeed) * intervalMs);
  ceil =
    x:
    let
      i = builtins.ceil x;
    in
    i + 0.0;

  # Logical pixels per ms. Rounded per event, a steady finger speed between
  # whole counts per report alternates the two neighbouring event sizes, so
  # the output follows the straight line between them (below one count, one
  # event of a count every few reports).
  scrollPixels =
    v:
    if !roundUp then
      scrollLines v * pixelsPerLine
    else
      let
        c = counts scrollDpi v;
        n = builtins.floor c;
        frac = c - n;
      in
      (pointsPerEvent n * (1 - frac) + pointsPerEvent (n + 1) * frac) / intervalMs;

  # The trackpad's own units per mm, which libinput's speeds are in. The MTP
  # trackpads report hundredths of a millimetre (macOS's multitouch stack
  # divides positions by 100), which a profile records as
  # trackpad.positionUnitsPerMM; without it, the sensor's span over its
  # surface, a little short (the surface is wider than the sensed span).
  sensor = tp.sensor;
  unitsPerMM =
    tp.positionUnitsPerMM or ((sensor.maxX - sensor.minX) / (sensor.widthHundredthsMM / 100.0));
  unitsPerInch = unitsPerMM * 25.4;

  # libinput interpolates from 0 to the first sample, so below it the gain is
  # constant while Apple's rises from its slow-speed limit. Through the curve
  # that constant would be the gain at the first sample, too high near zero;
  # the harmonic mean of the two ends splits the error evenly either side
  # (halving it), and the second segment starts from the same point.
  sample =
    stepInches: fn:
    let
      tiny = 1.0e-6;
      slowGain = fn tiny / tiny;
      firstGain = fn stepInches / stepInches;
      first = stepInches * 2 * slowGain * firstGain / (slowGain + firstGain);
    in
    {
      step = stepInches * unitsPerInch / 1000;
      points = builtins.genList (
        i:
        if i == 0 then
          0.0
        else if i == 1 then
          first
        else
          fn (i * stepInches)
      ) 64;
    };

  # The finger speed at which Apple's pointer curve turns into its tangent line.
  pointerTangentSpeed =
    pointerCurve.a.tangentSpeedLinear * (pointerDpi / frameRate)
    / (pointerDpi * intervalMs / 1000 * rateMultiplier);
  pointerStep' =
    if pointerStep != null then
      pointerStep
    else if pointerCurve.a.tangentSpeedLinear > 0 then
      pointerTangentSpeed / 62
    else
      0.22;
in
{
  pointer = sample pointerStep' pointer;
  scroll = sample (
    if scrollStep != null then
      scrollStep
    else if roundUp then
      countSpeed
    else
      0.4
  ) scrollPixels;

  # The underlying functions (finger in/s to output per ms) and the numbers
  # they come from, for tests and for anyone building their own curves.
  functions = {
    inherit pointer scrollLines scrollPixels;
  };
  inherit
    unitsPerMM
    pixelsPerLine
    roundUp
    slowLinesPerMM
    pointerTangentSpeed
    ;
  curves = {
    pointer = pointerCurve.a;
    scroll = scrollCurve.a;
  };
}

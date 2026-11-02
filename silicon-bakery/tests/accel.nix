# The Nix curves against IOHIDFamily's own arithmetic (tests/reference/*.json,
# from ./reference/run-oracle or ./reference/iohid.py), for every profile that
# has a reference. Pure evaluation: { failures = [ ... ]; checked = n; }.
{ lib }:
let
  macosAccel = import ../lib/macos-accel.nix { inherit lib; };

  # Relative error, with an absolute floor for values near zero.
  close =
    tolerance: want: got:
    let
      diff = if want > got then want - got else got - want;
      scale = if want > 1.0e-6 || want < -1.0e-6 then (if want > 0 then want else -want) else 1.0e-6;
    in
    diff / scale <= tolerance;

  checkProfile =
    model:
    let
      profile = lib.importJSON ../profiles/${model}/macos.json;
      reference = lib.importJSON ./reference/${model}.json;
      exact = macosAccel { inherit profile; };
      floored = macosAccel {
        inherit profile;
        quantisation = "floor";
      };
      apple = macosAccel {
        inherit profile;
        scroll.pixelsPerLine = 10;
      };

      compare =
        name: tolerance: fn: field: rows:
        lib.concatMap (
          row:
          let
            got = fn row.speed;
          in
          lib.optional (!close tolerance row.${field} got)
            "${model} ${name} at ${toString row.speed} in/s: IOHIDFamily ${toString row.${field}}, Nix ${toString got}"
        ) rows;
    in
    compare "pointer (exact)" 1.0e-9 exact.functions.pointer "exact" reference.pointer
    ++ compare "pointer (floor)" 1.0e-9 floored.functions.pointer "floor" reference.pointer
    ++ compare "scroll" 1.0e-9 exact.functions.scrollLines "lines" reference.scroll
    # Whole-count deltas average out to the curve itself; the gap is the
    # chord between neighbouring whole counts (convex curve) and late reports.
    ++ compare "pointer (integer deltas)" 0.025 exact.functions.pointer "integer" reference.pointer
    # A sanity check on the units: Apple's slow-speed scroll rate at 10 px a line.
    ++
      lib.optional (!close 0.05 3.5 (apple.slowLinesPerMM * 10))
        "${model} slow scroll: ${toString (apple.slowLinesPerMM * 10)} px/mm"
    # What libinput makes of the 64 samples (its interpolation and
    # extrapolation), against the functions themselves.
    ++ interpolated "pointer" 0.045 exact exact.pointer exact.functions.pointer 33.5
    # Rounded per event (the default): exact while the samples last (63 whole
    # counts a report), within 7 % beyond.
    ++ interpolated "scroll" 1.0e-9 exact exact.scroll exact.functions.scrollPixels (
      62.5 * 1000 / (400 * 8)
    )
    ++
      interpolated "scroll beyond the samples" 0.07 exact exact.scroll exact.functions.scrollPixels
        40.0
    # Apple's curve alone, sampled every 0.4 in/s.
    ++ interpolated "scroll (unrounded)" 0.085 apple apple.scroll apple.functions.scrollPixels 40.0;

  # libinput's custom_accel_function_profile, for a finger speed in in/s.
  libinputSpeed =
    accel: curve: v:
    let
      speed = v * accel.unitsPerMM * 25.4 / 1000;
      i0 = builtins.floor (speed / curve.step);
      i = if i0 > 62 then 62 else i0;
      x0 = curve.step * i;
      x1 = curve.step * (i + 1);
      y0 = builtins.elemAt curve.points i;
      y1 = builtins.elemAt curve.points (i + 1);
    in
    (y0 * (x1 - speed) + y1 * (speed - x0)) / curve.step;

  interpolated =
    name: tolerance: accel: curve: fn: top:
    let
      speeds = builtins.genList (i: (i + 1) * top / 2000) 2000;
      bad = builtins.filter (v: !close tolerance (fn v) (libinputSpeed accel curve v)) speeds;
    in
    lib.optional (bad != [ ])
      "${name} as libinput interpolates it is more than ${toString (tolerance * 100)} % off at ${toString (builtins.length bad)} speeds, first ${toString (builtins.head bad)} in/s";

  models = builtins.filter (m: builtins.pathExists ./reference/${m}.json) (
    builtins.attrNames (builtins.readDir ../profiles)
  );
in
{
  failures = lib.concatMap checkProfile models;
  checked = builtins.length models;
}

# True Tone

How macOS moves the Mac14,9's white point with the room's light, what Linux
lacked, and what `display.trueTone` adds. Read on 2026-11-03 from macOS
27.2 (26B5101f): CoreBrightness run in-process, the live IORegistry and DCP
matrices, `corebrightnessdiag`, and AppleALSColorSensor in both the 27.2
kernelcache and the 13.5 one of the stub Linux boots; and from
asahi-7.2.14-1.

## How macOS does it

1. **Sensor.** The ambient light sensor is an ST VD6286 ("Redbird", class
   `AppleSPUVD6286`, `crgb` = 1) behind the AOP. Each report (0x7a bytes,
   about every 200 ms) carries lux (f32 at 0x28), five channel counts (i32
   at 0x14), the AOP's correlated colour temperature (f32 at 0x45), gain
   (0x43), integration time (0x4d) and report interval (0x49). Linux's
   `iio_aop_als` receives the same bytes (its lux offset is 0x28 too).
   - macOS 27.2's AOP firmware also computes XYZ, and the HID event carries
     it (colour space 1, components X, Y, Z, plus CCT). The 13.5 kext's
     VD6286 path, which matches the AOP firmware Linux runs, fills lux, the
     channels and CCT but leaves the XYZ fields and their "computed on the
     AOP" flag zero (only the VD6287 path copies XYZ from 0x6e).
2. **CoreBrightness** (`CBALSEvent`) divides XYZ by pi, takes x, y and the
   CCT, and hands the sample to its colour engine, "CFX"
   (`CFXInputAmbientColor`), on every event.
3. **Low light** (`_CFXRestrictLowAmbientColor`): at or below 15 lux the
   sample is pulled toward a fixed white, D65 if lux > 2 and CCT >= 6000 K,
   else (0.3827, 0.3846), about 4000 K; fully at 10 lux and below, linearly
   between 10 and 15. Above 11141 cd/m2 the sample becomes D65.
4. **Target** (`_CFXGetTarget`): x is clamped to [0, 1] and y held under a
   nine-point limit just above the Planckian locus; the white goes to CIELAB
   (D65), its a*b* is clamped to an 18-point gamut polygon
   (`_CFXStickToPolygon`), and the Bradford adaptation from D65 to it is
   built in linear sRGB primaries, rows scaled so the largest sums to 1.
5. **When to move** (`_CFXUpdateTarget`): the new white's distance from the
   last in CIE 1976 u'v': under 0.003 nothing happens; under 0.035 a slow,
   non-interrupting ramp; beyond, an interrupting one. Ramps take 5 s, 20 s
   under 35 lux and 60 s under 15 lux. Five or more direction changes inside
   60 s stretch the ramp to 10/rate (`_CFXCheckStats`).
6. **Ramp** (`_CFXUpdateColorFadeInternal`): the full-strength target
   matrices are interpolated along a 201-point easing curve. Each step's white
   goes back to a*b*, is clamped to the polygon again, and is pulled toward
   neutral by a factor read from two 29 x 55 tables indexed by a*b*, blended
   by the strength (0.2 for `ColorAdaptationMode` 1, macOS's default):
   below 0.35 the factor is (1 - r) f2 + r with r = (0.35 - s) / 0.35. The
   panel's shift, `HarmonyShiftA/B` from DCP (-4.5, 2.1 on this panel,
   16.16 in the capabilities), is added times the strength. The strength
   itself ramps from 0 over 2 s when True Tone turns on.
7. **`_CFXMagic`**: each off-diagonal term is scaled by its own gain
   (1.006, 1.322, 0.992, 0.576, 1.667, 1.798 here) and the difference given
   to the diagonal, so rows keep their sums. Then the native white point
   correction, a Bradford matrix from the panel's native white to D65
   (`CFXSetNativeWhitePoint`, ramped in over 2 s), and the rows scaled again.
   An update under 0.001 in every term is not sent.
8. **DCP.** The matrix goes to DCP matrix location 9 as two's complement
   32.32 (`IOMobileFramebufferGetMatrix(fb, 9, ...)` read back
   0.8875, 0.0617, 0.0132 / -0.0021, 0.8619, 0.0019 / -0.0068, -0.0274,
   0.7200 at 7 lux; -0.0021 is 0xffffffffff74c365). Locations 7 and 8 hold
   the factory calibration, 10 is identity.

Every table CFX uses is a constant in CoreBrightness: CFXCreate,
`CFXSetWhitePointType(1)` and `CFXInitializeAmbientAdaptation` take no
input. The only per-panel numbers are the shift and the native white point.

## What Linux had

- `iio_aop_als` reports lux only.
- appledrm gives the CRTC's CTM to DCP at location 9, but copies DRM's
  sign-magnitude S31.32 as is, so every negative coefficient became a huge
  positive one. Nothing set a matrix from the ambient light.

## What Silicon Bakery adds

- `patches/linux-truetone/0001`: the CTM converted to two's complement
  (`drm_color_ctm_s31_32_to_qm_n(v, 32, 32)`).
- `0002`: an `ambient_matrix` attribute on the panel's DCP
  (`/sys/bus/platform/drivers/apple-dcp/*.dcp/ambient_matrix`): nine signed
  integers in 2^-32 units, row major, or `0` to drop it. It is applied after
  the CTM at location 9 and pushed with an idle commit, as the backlight is.
  Its DCP hunk applies with and without `linux-hdr` and `linux-vrr`.
- `0003`: the report's CCT as a second IIO device, `aop-sensors-als-cct`
  (`in_colortemp_input`, K). VD6286 only; the CT720 report layout is not
  known.
- `tools/truetone`: CFX's ambient adaptation in C (`cfx.c`) and the daemon
  (`truetoned.c`, package `siliconBakery.truetone`). The sample is the
  sensor's lux and the blackbody point of its CCT, which is what the 13.5
  report offers; the tint off the locus (Duv) that 27.2's XYZ carries is not
  there.
- `tools/bakery-truetone-tables`: the polygon, the two tables, the easing
  curve, the blackbody table and the magic gains, read from CoreBrightness
  as corebrightnessd builds them, into `apple/truetone.bin` for the private
  firmware input. It refuses unless every constant `cfx.c` carries matches
  CFX's own and the tables hash to macOS 27.2's.
- `tools/bakery-probe` records `display.trueTone` (enabled, mode, shift)
  in the profile; the module takes mode and shift from there.

Left out, as macOS leaves them off for one front sensor: the ALS
mitigations (CE/occlusion strength look-ups), Night Shift and twilight in
the same pipeline, "Ammolite" and the alternate matrix formats.

## How it was checked

`tools/truetone/oracle.c` (macOS only) loads CoreBrightness, finds the CFX
functions by name and feeds them and the port the same inputs:

| Step | Cases | Bit-exact |
|---|---|---|
| Lab, Lab^-1 | 20000 each | 100 % |
| polygon clamp | 20000 | 100 % |
| a*b* tables | 40000 | 100 % |
| Bradford matrix, white point | 20000 each | 100 % |
| blackbody CCT to xy | 20000 | 100 % |
| `_CFXGetTarget` | 20000 | 100 % |
| harmony step at random strengths | 20000 | 100 % |
| native white point gains and matrix | 400 | 100 % |
| end of each ramp, 300 runs of 6 random samples from 0.5 to 50000 lux | 1800 | 100 % |
| matrix handed out at the end of those ramps | 1800 | 87 %, all within 0.001 |

The last row is the 0.001 deadband: which step was last sent depends on when
the ramp was sampled, and CoreBrightness takes its own clock for ramp starts.

The daemon, fed this room's reading (7 lux), settles on
0.91845, 0.06832, 0.01323 / -0.00323, 0.86184, 0.00187 / -0.00738, -0.02755,
0.72024; corebrightnessd's own `ColorRampTarget` was 0.91838, 0.06839,
0.01323 / -0.00323, 0.86171, 0.00187 / -0.00738, -0.02754, 0.72015.

## Open questions

- **What else macOS multiplies in.** Live location 9 was the ramp target
  times about diag(0.966, 1, 1) on probing (white (0.3352, 0.3521) against
  CFX's (0.3383, 0.3518)). The native white point correction would do that;
  WindowServer supplies the native white (`SLSDisplayController
  nativeWhitePoint`) and publishes it nowhere else. Unset, the daemon applies
  no correction; `display.trueTone.nativeWhitePoint` takes one.
- **XYZ from the 13.5 AOP.** The report's 0x6d flag and XYZ at 0x6e may be
  filled for the VD6286 too even though the 13.5 kext ignores them; reading
  the raw report on Linux would tell, and XYZ would give the tint as well.
- **ALS calibration.** The CCT needs the sensor's calibration loaded
  (`apple/aop-als-cal.bin`, from the installer's vendor firmware).

## On the machine

1. On macOS: `tools/bakery-truetone-tables -o out`, then copy `out/` to
   `truetone/` in the private firmware input and update its lock.
2. In `hardware.siliconBakery`:
   `display.trueTone = { enable = true; tables = inputs.asahi-firmware + "/truetone"; };`
   and rebuild (the kernel rebuilds).
3. `grep . /sys/bus/iio/devices/iio:device*/name` lists `aop-sensors-als`
   and `aop-sensors-als-cct`; `in_colortemp_input` should follow a lamp
   (about 2700 K) and daylight (5000-6500 K). Compare with macOS's HID event
   CCT under the same light if possible.
4. `journalctl -u bakery-truetoned`; with the service stopped,
   `bakery-truetoned --tables ... --dry-run -vv` prints the samples and
   matrices.
5. `cat /sys/bus/platform/drivers/apple-dcp/*/ambient_matrix` while the
   light changes; the panel should warm under a lamp within 5 s (20 s under
   35 lux, 60 s under 15) and the matrix should match what
   `tools/truetone/dcp-matrix 9` reads under macOS in the same room.
6. A compositor CTM (Night Light) now applies with its negative terms intact;
   check the colours look right with one on.

`echo 0 > .../ambient_matrix`, or stopping the service, returns the panel to
its calibrated white.

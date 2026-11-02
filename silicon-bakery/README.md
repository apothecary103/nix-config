# Silicon Bakery for NixOS

Asahi Linux, finished to behave like the Mac it runs on.

[nixos-apple-silicon](https://github.com/nix-community/nixos-apple-silicon)
gets NixOS booting on Apple Silicon. Silicon Bakery is the layer on top: the
patches, the Mac's own numbers read out of macOS, and the modules that apply
them, so the trackpad, the panel and the media engine behave the way they did
under macOS. One flake, one option to turn it on, one profile per Mac model.

```nix
{
  inputs.silicon-bakery.url = "github:<you>/silicon-bakery";

  outputs = { nixpkgs, silicon-bakery, ... }: {
    nixosConfigurations.mac = nixpkgs.lib.nixosSystem {
      modules = [
        silicon-bakery.nixosModules.default # brings nixos-apple-silicon too
        {
          hardware.asahi.peripheralFirmwareDirectory = ./firmware;
          hardware.siliconBakery = {
            enable = true;
            model = "Mac14,9";
          };
        }
      ];
    };
  };
}
```

`nixosModules.silicon-bakery` is the same without nixos-apple-silicon, for
systems that import it themselves.

## Profiles: the Mac's own numbers

Everything model-specific comes from `profiles/<model>/`:

- `macos.json`, written by `tools/bakery-probe` under macOS on that Mac. It
  reads the IORegistry, `defaults` and `sysctl`, and changes nothing: the
  trackpad's sensor surface and report interval, the pointer and scroll
  acceleration curves exactly as macOS publishes them (16.16 fixed point), the
  tracking and scrolling speeds currently set, the trackpad preferences, key
  repeat and double-click time, and the SoC.
- `linux.json`, for what can only be measured on Linux (touch sizes in evdev
  units for palm rejection, connector names).

```sh
m=$(sysctl -n hw.model); mkdir -p "profiles/$m"
./tools/bakery-probe > "profiles/$m/macos.json"
```

Run it before installing Linux, or from macOS whenever a setting changes.
`hardware.siliconBakery.profile` holds the result.

## What it does

`docs/support.md` is the support table for the Mac14,9: what works, what
Silicon Bakery adds, and what the hardware does under macOS that Linux does
not yet.

### Trackpad (`modules/input.nix`, `lib/macos-accel.nix`)

macOS's pointer and scroll acceleration, rebuilt from the profile and from
IOHIDFamily's own code (`IOHIDAccelerationAlgorithm.cpp`,
`IOHIDAcceleration.cpp`, `IOHIDPointerScrollFilter.cpp` in
apple-oss-distributions/IOHIDFamily): the parametric curves interpolated to
the user's speed, the tangent and square-root segments, the report-rate clamp,
the scroll accelerator's timing polynomial and wheel scale. The result is a
pair of libinput custom curves in `hardware.siliconBakery.trackpad.curves`,
for a compositor to apply (Silicon Bakery's kwim does). In detail:

- The curves follow IOHIDFamily to 1e-9 at 800 finger speeds
  (`tests/accel.nix` against `tests/reference`).
- libinput interpolates 64 evenly spaced samples and must pass through zero,
  so below the first sample its gain is constant while Apple's rises. The
  first sample is set to the harmonic mean of the gains at its two ends, which
  halves the worst case; the pointer's spacing puts its last samples on
  Apple's tangent line, so libinput's extrapolation is exact up to 33.6 in/s.
  As libinput applies them, the pointer stays within 4.5 % of macOS and
  scrolling within 8.5 % at every speed, most of it in the first few mm/s
  (also tested).
- Speeds are in the trackpad's own units, hundredths of a millimetre.

`patches/libinput`, read from macOS's gesture engine (HSTouchHIDService):

- `0001-typing-palms`: typing no longer freezes the pointer, and, for kernels
  that don't pass on the firmware's palms, hands at rest are told apart by
  where they land (measured over 945 touches on a Mac14,9).
- `0002-apple-no-wobble-hysteresis`: libinput's wobble detector never turns
  its quarter-millimetre ellipse on for good.
- `0003-apple-macos-deadband`: macOS's own deadband instead, 0.169 mm per
  axis from the first touch.
- `0004-macos-tap-timings`: taps lift within 250 ms, tap-and-drag waits
  200 ms and survives 500 ms, and no tap counts within 250 ms of a click.
- `0005-macos-three-finger-drag`: the drag outlives the fingers by 625 ms
  only if it moved in the last 750 ms, and three fingers always drag.
- `0006-macos-resting-finger`: macOS's one resting finger, nearest the
  front edge (`docs/palm-rejection.md`).

`patches/libinput-1.32` is the same set for libinput 1.32.

Scrolling as WindowServer finishes it: 10 points a line, every event rounded
up to a whole point, so the slowest scroll moves a point per count of finger
travel (15.75 per mm). Momentum is the compositor's or toolkit's on Linux;
macOS's (0.975 per 8 ms when fast, down to 0.91, at most 2.2 s) is in the
findings for when one wants it.

`patches/linux` for the trackpad itself:

- `hid-magicmouse-mtp-palms-from-firmware`: the trackpad's firmware
  identifies every contact as one of five fingers or not, and macOS rejects
  whatever is not a finger; Linux dropped those bytes. Contacts the firmware
  calls something else are now reported as palms (`trackpad.firmwarePalms`).
  `docs/palm-rejection.md` has how macOS does it.

- `hid-magicmouse-mtp-hundredths`: positions are hundredths of a millimetre
  (macOS's multitouch stack divides by 100); the kernel advertised 98 and 97
  units/mm, so libinput's distances were 1.4-2 % off and vertical motion 1 %
  faster than horizontal.
- `hid-magicmouse-mtp-click-feel` (with `hid-dockchannel-set-report-type`,
  AsahiLinux/linux#573's fix): the haptic waveforms macOS gives the
  firmware's own clicks for Light, Medium or Firm (feature reports 0x22 and
  0x23, decoded from MultitouchSupport's actuator table; the medium press is
  byte for byte what #573 captured from macOS), per `trackpad.click`. Where
  a click triggers stays the firmware's: macOS decides that in userspace from
  the force in grams (125 g x 0.8, 1 or 1.2; Force Click at 300 g), which
  needs host click control Linux does not have yet.

The profile's palm sizes become libinput quirks, and `bakery-trackpad`
prints the curves in finger units or runs `libinput debug-events` with them.

What the open source does not settle, `tools/mt-probe` measures (below):
whether the gesture engine hands IOHIDFamily whole or fractional counts
(`trackpad.quantisation`), the absolute scroll scale (`trackpad.scroll`;
until measured, slow scrolling moves content 1:1 with the finger, 5 px/mm,
where Apple's code with CGEventSource's documented 10 px a line gives 3.5),
and how long a three-finger drag outlives the fingers (libinput: 700 ms).
Measurements written into the profile are picked up automatically.

### Display (`modules/display.nix`)

- `patches/linux/appledrm-xrgb2101010-premultiplied`: XRGB2101010, which 10-bit
  clients scan out in, blended as premultiplied so its X bits are not read as
  alpha.
- `patches/linux/dcp-*`: open upstream fixes carried until they merge
  (AsahiLinux/linux #582: a power-off swap timeout no longer marks DCP
  crashed, which blocked every later display change until reboot; #654: a
  disconnected monitor's EDID is dropped; #655: HDMI audio's period count is
  bounded). See `docs/upstream.md`.
- Display P3: macOS profiles the built-in panels as P3 primaries, D65 and the
  sRGB curve with an identity vcgt, DCP applying the factory calibration. The
  kernel leaves RGB planes NATIVE on the internal panel, so the compositor
  composites in P3 (`patches/river/0001-colour`, enabled for
  `display.p3Outputs`) and clients that tag wider content keep it.
- HDR on outputs that advertise BT.2020 and PQ (`patches/river/0002-hdr`,
  `display.hdrOutputs`), and an EDID-less internal panel allowed to advertise
  them when its driver offers the properties (`patches/wlroots/0003`).
- `display.experimentalVrr`: ProMotion as adaptive sync
  (`patches/linux-vrr`, `appledrm.experimental_vrr=1`). In its 120 Hz timing
  DCP already hands every swap to the panel's timing controller, which
  refreshes between 120 and 24 Hz (bounds read from the 13.5 firmware and
  macOS's `IOMFBDisplayRefresh`); the patch gives eDP-1 `vrr_capable` and
  holds 120 Hz through the firmware's `APTFixedRR` property when a
  compositor turns adaptive sync off. Untested on hardware.
- `display.experimentalHdr`: appledrm with the standard Colorspace and
  HDR_OUTPUT_METADATA properties, PQ link modes on external displays where
  DCP reports them, and BT.2020 PQ surface tags
  (`patches/linux-hdr`, booted with `appledrm.experimental_hdr=1`). Off by
  default and untested on hardware: the internal panel has no PQ link mode,
  and macOS's HDR there is EDR (a backlight boost inside DCP), so whether DCP
  converts PQ surfaces for it is the open question. See `docs/hdr.md` for the
  evidence and an on-device test plan.
- `display.trueTone`: True Tone as macOS's CoreBrightness does it.
  `bakery-truetoned` (`tools/truetone`) runs CoreBrightness's colour engine,
  transliterated to C and bit-exact against macOS's own, on the ambient light
  sensor's lux and colour temperature, and sets the panel's white point at
  DCP matrix location 9, where macOS sets it (`patches/linux-truetone`: the
  sensor's CCT, an `ambient_matrix` attribute, and the CTM's sign fixed).
  The engine's tables come from this Mac's macOS through
  `tools/bakery-truetone-tables` into the private firmware input. Untested on
  hardware; see `docs/truetone.md`.

### Graphics (`modules/graphics.nix`)

- `patches/mesa`, applied to `hardware.graphics.package` only, so nothing
  linking Mesa rebuilds:
  - `mesa-hk-no-compressed-input-attachments`: Honeykrisp leaves input
    attachments uncompressed; without it wlroots' 10-bit Vulkan scanout
    flickers the panel's edges on G14S.
  - `mesa-agx-g14x-metal-cdm-barrier`: the barrier after each compute launch
    is the one AGXMetalG14X writes on the M2 Pro/Max (5 bits) instead of
    every known bit.
  - `mesa-hk-cdm-barrier-on-demand`: `vkCmdDispatch` leaves its barrier
    pending until something must be ordered after it, so independent
    dispatches overlap as in Metal's concurrent mode. Untested on hardware:
    `hk-dispatch-bench` and the CTS groups in `docs/gpu.md` check it.
  - `mesa-hk-memory-budget`: advertises the `VK_EXT_memory_budget` support
    Honeykrisp already has (Mesa !40238).
- `patches/linux/drm-asahi-flush-stamps-last-command`: the last render and
  compute command of a submission flush their stamps again, as before the
  UAPI rework (AsahiLinux/linux#633).
- `docs/gpu.md`: the driver checked against macOS's device tree, kext and
  Metal driver, what matches, what was fixed and what is open, and
  Honeykrisp feature by feature against Metal. `tools/metal-probe` measures
  the Metal side.
- `WLR_RENDER_DRM_DEVICE` set to the GPU's render node for the profile's SoC:
  appledrm has no render node, and wlroots would otherwise hand the display
  node to the Vulkan renderer.

### Media engine (`modules/media.nix`)

AVD hardware decode (H.264, HEVC, VP9 on the M2 Pro) through VA-API
(nixos-apple-silicon's `hardware.asahi.avd`, asahi-va-driver), with `vainfo`
and `v4l2-ctl` to see what it offers, and `media.decodeCodecs` keeping H.264
and HEVC once the firmware defaults to patent-free codecs only.

`media.encode`: the AVE hardware encoder, through Silicon Bakery's t6020 port
of the community driver (`patches/apple-ave`, `pkgs/apple-ave.nix`), its
firmware made by `tools/bakery-ave-fw` from this Mac's own macOS 13.5 into a
private input. Experimental and untested on the M2 Pro; `docs/ave-port.txt`
is the staged bring-up. `docs/media-engine.md` has the hardware facts and
the CPU encoding settings for meanwhile.

### Power (`modules/power.nix`)

`power.experimentalPmp`: the Power Management Processor, which macOS always
runs and Linux leaves idle (`patches/linux-pmp`). The device tree defines
`APPLE_USE_PMP`, so m1n1 hands the PMP its board tunables and the displays,
decoder and camera report their power states to it, and enables the ISP's
report entry that t602x leaves off, without which the camera would not
probe. Asahi measured about 0.5 W less at idle on an M1 Pro. Mac14,9 only,
untested on hardware; `docs/pmp.md` has the test plan.

### Packages

Under `pkgs.siliconBakery` (and `packages.aarch64-linux`), so nothing else in
nixpkgs rebuilds against them: `libinput`, `wlroots` (backdrop blur, 8-bit
capture formats from 10-bit outputs, EDID-less HDR), `river` (P3, HDR, blur
by layer namespace), `kwim` (custom acceleration curves), `mesa`, and
`kernelPatches` / `kernelPatchesHdr`.

## Measuring macOS: `tools/mt-probe`

A small AppKit app that records raw finger positions from the private
MultitouchSupport framework next to the pointer, scroll and button events
WindowServer delivers to its window. No permissions, nothing sent anywhere.

```sh
tools/mt-probe/build
tools/mt-probe/mt-probe recording.jsonl     # follow the window's instructions
python3 -I tools/mt-probe/analyse.py recording.jsonl profiles/Mac14,9/macos.json --write
```

The analysis tests both readings of the pointer quantisation against the
recording, fits the points WindowServer makes of a scroll-wheel line, the
momentum decay and the three-finger-drag release, and with `--write` stores
them under `trackpad.measured`.

## Verification

```sh
nix flake check   # on Linux or macOS
```

- `accel`: the curves against IOHIDFamily's arithmetic and libinput's
  interpolation bounds.
- `patches-*`: every patch set applies in order, without fuzz, to the exact
  sources an aarch64-linux system builds (nixpkgs' own patches first), the
  opt-in kernel sets stacked on the default one, plus the AVE driver's port,
  ffmpeg's and libinput 1.32's ahead of nixpkgs. The sources are fetched
  again on the machine running the check and pinned by hash, so a Mac can
  check them without a Linux builder.

`tests/reference/<model>.json` comes from `tests/reference/iohid.py`, a
line-by-line transliteration of IOHIDFamily's acceleration code. On macOS,
`tests/reference/run-oracle` builds Apple's sources themselves (with a stub for
one private logging header) and writes the same file from them.

## On the machine

- `bakery-trackpad curves`, `bakery-trackpad pointer`, `bakery-trackpad scroll`
- `vainfo` for the decoder; `mpv --hwdec=vaapi` to use it
- `journalctl -t river` for the colour and HDR decisions river logs at start

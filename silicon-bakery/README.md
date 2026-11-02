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
- Speeds are in the trackpad's own units (the sensor's span over its width),
  not the whole number the kernel advertises.

`patches/libinput`:

- `0001-typing-palms`: palm rejection as macOS does it, by where a hand rests
  (the outer 5 % either side shortly after typing, the bottom 4 % always),
  not by whether a key is held; fingers keep moving, scrolling and gesturing
  while typing. Measured over 945 touches on a Mac14,9.
- `0002-apple-no-wobble-hysteresis`: libinput switches on a quarter-millimetre
  hysteresis for good the first time a resting finger reads as a left-right-left
  wobble, swallowing fine movements macOS keeps. Apple's trackpads filter in
  firmware; for them it stays off.

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

### Graphics (`modules/graphics.nix`)

- `patches/mesa`: Honeykrisp leaves input attachments uncompressed; without it
  wlroots' 10-bit Vulkan scanout flickers the panel's edges on G14S. Applied
  to `hardware.graphics.package` only, so nothing linking Mesa rebuilds.
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

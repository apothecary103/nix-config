# The media engine

What the Mac14,9 (M2 Pro, t6020) media engine can do under Linux, read on
2026-11-02 from macOS 27.2's IORegistry, the Asahi stub's macOS 13.5 firmware
set (which iBoot loads for Linux), asahi-7.2.14-1 and the public state of the
art. No Apple firmware or kernel binaries are kept here.

## Blocks

| block | macOS node | firmware | Linux today |
|---|---|---|---|
| AVD, decoder | `avd0`, `avd,t6020` | Cortex-M3; Linux loads Asahi's open `avd-fw` | `apple-avd` V4L2 stateless decoder, device tree node present; Silicon Bakery's fixes in `media.decodeFixes` (docs/avd-port.txt) |
| AVE, encoder | `ave0`, `ave2`, one instance | ARM64 RTKit "Chinook" core, preloaded by iBoot (`AppleAVE2FW_H14S`, build 6070.11.1 on the 13.5 stub), symbols not stripped | upstream nothing; Silicon Bakery's t6020 port of the community driver (`media.encode`, below) |
| ProRes | `apr0` | none, register-driven (macOS 27's "SCodec" RTKit core is a separate display/camera streaming codec that can borrow it) | upstream nothing; Silicon Bakery's `apple-prores` encoder (`media.prores`, docs/prores-port.txt) |
| JPEG ×2 | `jpeg0`, `jpeg1` | none, register-driven | upstream nothing; Silicon Bakery's `apple-jpeg` encoder and decoder (`media.jpeg`, docs/jpeg-port.txt) |
| M2Scaler | `scaler0` | none, register-driven | upstream nothing; Silicon Bakery's `apple-scaler` converter (`media.scaler`, docs/scaler-port.txt) |

macOS advertises AVE encode for H.264 up to 4096×4096 at 2160p30 pixel rate
and HEVC at 2160p60, 4:0:0 to 4:4:4. The AVE sits behind a `dart,t8110`
IOMMU (DART, CPUDART, SMMU and CPU_APF instances, `vm-base`
0x100_0000_0000) and fetches its firmware through the CPUDART.

## Decode (what Silicon Bakery enables)

`hardware.siliconBakery.media.decode` turns on nixos-apple-silicon's AVD
support with VA-API (asahi-va-driver 2.0, `LIBVA_DRIVER_NAME=asahi`):
H.264, HEVC and VP9 on t6020, NV12/P010/NV16 out. No AV1 on the M2 Pro.

- avd-fw 0.2 (nixpkgs#581622) and nixos-apple-silicon#575 default the firmware
  to `all_free`, VP9 and AV1 only, which on t6020 would leave VP9 alone.
  `media.decodeCodecs` (default `[ "all" ]`, H.264 and HEVC kept, as today)
  applies as soon as either lands. The patented codecs are a licensing choice.
  (As of asahi-7.2.14-1 the kernel looks for the codec mask in the last 0x20
  bytes of the firmware while avd-fw 0.2 writes it at 0x400, so for now every
  codec stays on whatever the setting.)
- mpv zero-copy (`hwdec=vaapi`) with `vo=gpu-next` shows wrong colours: Honeykrisp
  imports the frames without error but ignores the plane offset (Mesa #16429),
  so mpv never falls back. The same report has `--vo=gpu --gpu-api=opengl`
  (EGL import) zero-copy and correct; otherwise `hwdec=vaapi-copy`, still
  decoded on AVD.
- VA-API offers less than the V4L2 decoder: H.264 Constrained Baseline, Main
  and High, HEVC Main and Main10, VP9 profiles 0 and 2. H.264 10-bit and 4:2:2
  are V4L2 only, and HEVC 4:2:2 10-bit comes out labelled P010 (the kernel has
  no P210 yet). The driver lists VP9 profiles 1 and 3, which the hardware
  cannot decode. 4:4:4 (H.264 and HEVC, 8/10-bit) decodes on macOS but the
  driver has no path for it; interlaced H.264 is refused on macOS too.
- asahi-va-driver#6: `vaDestroyContext` frees surfaces still in use, so
  ffmpeg's `hwdownload` path can corrupt or crash on the last frames.
- One frame in flight on the whole decoder; a second player waits its turn.
  That is the driver, not the hardware: macOS runs several streams at once
  (four HEVC 1080p streams, 2593 fps together, against 715 for one), queues
  work in the coprocessor and votes the decoder's clock and voltage up.
- Firefox needs `MOZ_DISABLE_RDD_SANDBOX=1` for VA-API, a sandbox trade-off.
- GStreamer can use the V4L2 decoders directly (`v4l2slh264dec` and friends
  in gst-plugins-bad), without libva.

On the machine:

```sh
v4l2-ctl --list-devices          # an avd entry and a /dev/mediaN
vainfo                           # H264/HEVC/VP9 profiles, VAEntrypointVLD only
ffmpeg -benchmark -hwaccel vaapi -hwaccel_output_format vaapi -i in.mp4 -f null -
mpv -v --hwdec=vaapi,vaapi-copy in.mkv 2>&1 | grep -iE 'hwdec|Using hardware'
```

If `vainfo` lists only VP9, the firmware lost H.264 and HEVC (see above).

## Encode

Upstream has no encoder for the M2 Pro: `aquarat/apple-m-series-ave-driver`
(commit 9ab14e45, GPL-2.0, out of tree, a V4L2 stateful H.264/HEVC encoder)
covers t8103, t8112 and t6000-t6002 on the 13.5 stub firmware, and calls
itself beta, "almost entirely AI-generated" and able to hang or reset the
machine; `aurora-silicon/linux` encodes on T8140 and T6041 (M4 Pro), not t602x. Honeykrisp has no
`VK_KHR_video_*`, and the VA-API driver decodes only.

Silicon Bakery ports that driver to t6020 (`patches/apple-ave`, read from
the 13.5 kext, firmware and device tree on this Mac; `docs/ave-port.txt` has
every value's source and the staged bring-up), with feature patches
beyond the community driver: VUI colour, CBR with filler, slices, realtime
and throughput controls, suspend replay, and 4:2:2/4:4:4/mono input (all off
by default, ave-port.txt §10). Compiled with clang against 7.2.14's headers;
never run on the M2 Pro yet.

```nix
hardware.siliconBakery.media.encode = {
  enable = true;
  firmware = inputs.asahi-firmware + "/ave"; # tools/bakery-ave-fw, private
};
```

`tools/bakery-ave-fw` writes the firmware and tunables the driver needs from
this Mac's own Asahi stub (macOS 13.5), refusing anything that does not
match what the port was written for; they are Apple's and belong in the
private firmware input. Bring it up by hand first (`modprobe ave_overlay`,
then `modprobe apple_ave`, one stage a boot as the document says, with SSH
from another machine), and only then `autoload` and `deviceTree`. Encoders:
`h264_v4l2m2m` and `hevc_v4l2m2m` (`pkgs.siliconBakery.ffmpeg-ave` adds the
community fixes, B-frames and MP4/MKV), `v4l2h264enc` / `v4l2h265enc`.

Until then, or on other Macs, the CPU: x264 for live capture, x265 or SVT-AV1
for archives (decode on AVD with `-hwaccel vaapi` to leave the cores to the
encoder).

```sh
# screen capture at the panel's half resolution, 60 fps
wf-recorder -a -r 60 -c libx264 -x yuv420p -p preset=veryfast -p crf=20 -F scale=1512:-2 -f capture.mkv
# archive
ffmpeg -hwaccel vaapi -i in.mp4 -c:v libsvtav1 -preset 6 -crf 30 -pix_fmt yuv420p10le -c:a libopus -b:a 128k out.mkv
ffmpeg -i in.mp4 -c:v libx265 -preset slow -crf 22 -pix_fmt yuv420p10le -tag:v hvc1 -c:a copy out.mp4
```

In OBS: x264, CRF 18-20, keyframes every 2 s, preset veryfast.

## What the t6020 port settled, and what it could not

Read from macOS (the port carries them; `docs/ave-port.txt` for the rest):

- Register banks identical to t6001's except the power-state window
  (pmgr east, 0x2_9028_03e0 + 0x7c44, Asahi's `ps_venc_sys` ... `ps_venc_me1`).
- AVE interrupt 1110 (also 1104, 1103, 1106, 1105), DART interrupt 1107.
- The 13.5 device row for t6020: chip type 11, device type 16, device ID 19,
  one encoder (read from both the H14S firmware and the 13.5 AppleAVE2 kext).
- `dart,t8110` with translated firmware fetch, as on t8112, but with a
  populated `dapf-instance-1` t8112 lacks; how DAPF must be handled is unknown.
- The firmware image (H14S, `__TEXT` 0xF0000, `__DATA` 0x134000) is new to the
  driver: it needs its pristine `__DATA` copy, and a symbol diff against H14G
  to find the source-size fields t8112 needed.
- Its placement under Linux comes from iBoot and must be read from the live
  ADT that m1n1 publishes.
- The PMP performance vote: needed on t6001, not on t8112; measure.
- A device tree node: through a kernel patch, since nixos-apple-silicon's m1n1
  stage bakes the device trees in and `hardware.deviceTree.overlays` does not
  reach them.
- Firmware and tables are generated from the user's own 13.5 kernelcache and
  firmware, so they belong in the private `asahi-firmware` input, never in a
  public flake or cache.

# Media engine: what to do on Linux

Written 2026-11-02 on the Mac14,9 under macOS, for an agent running on frieren
(NixOS on the same Mac). `ON-LINUX.md` is the overall runbook (rebuild, GPU,
trackpad, display); this file is the media engine part of its section 4. Everything below was written and statically checked on
macOS; nothing has run on Linux. Work top to bottom. Each block has its own
runbook in `silicon-bakery/docs/<block>-port.txt` with exact commands, expected
`dmesg` lines and what each failure means: read it before touching that block.

## Rules

- This Mac is the only machine. No netconsole, no SSH from elsewhere, no m1n1
  hypervisor. After a hang: hold the power button ~10 s, boot, read
  `journalctl -k -b -1`. Check the journal is persistent first
  (`ls /var/log/journal`). pstore is not available on this Mac.
- One risky stage per boot (`stop_after=N`, `step_ms=` so markers reach disk,
  `sync` before each `modprobe`). Never `rmmod` a driver whose probe stopped
  early; reboot instead.
- Nothing autoloads: keep `autoload` and `deviceTree` off until the overlay
  path has passed. Before any `deviceTree = true` switch, copy
  `/boot/m1n1/boot.bin` to `/boot/m1n1/boot.bin.pre-media`; recovery from
  macOS is in `ave-port.txt` §5.
- Don't suspend while an experimental media driver is loaded.
- Apple data (firmware, tunables) lives only in the private `asahi-firmware`
  input; never commit it to nix-config (it is mirrored to GitHub).
- Commits: small conventional commits, subject line only, no body, no
  Co-Authored-By. Record what you learn in the block's `*-port.txt`.
- Configuration lives in `modules/hosts/frieren/configuration.nix` under
  `hardware.siliconBakery`; options are in `silicon-bakery/modules/media.nix`.

## 0. Before the first build

1. **Private firmware.** The encoder and ProRes files are committed in the
   Mac's `~/asahi-firmware` (two commits, `ave/` and `prores/`) but Codeberg
   refused every push on 2026-11-02 from about 16:40 ("pre-receive hook
   declined / Internal Server Connection Error"), for asahi-firmware and
   nix-config alike, with SSH auth fine: a Codeberg-side incident. nix-config's
   GitHub mirror has every commit; Codeberg's lambda-river may lag. A bundle of the two commits is at
   `~/asahi-firmware-2026-11-02.bundle` on macOS.
   - Retry from Linux: clone `git@codeberg.org:frieren/asahi-firmware.git`; if
     it still lacks `ave/` and `prores/`, get the bundle across (Maomao HDD,
     exFAT) and `git pull <bundle> main`, then `git push`. If Codeberg still
     refuses, build with
     `--override-input asahi-firmware git+file:///path/to/asahi-firmware`.
   - Then `nix flake update asahi-firmware` and commit the lock.
   - Expected hashes are in `ave/SHA256SUMS` and `prores/SHA256SUMS`
     (ProRes file `34c15a7b…1e51`, AVE firmware `b5f928ac…8c1c`).
2. **Benchmark clips.** 56 clips plus the macOS baselines are on the Maomao
   HDD in `avd-clips/` (`results_*.txt` are the macOS numbers).
3. **Kernel facts to record** (they decide some code paths):
   `zcat /proc/config.gz | grep -E 'OF_OVERLAY|V4L2_JPEG_HELPER|PSTORE_RAM|VIDEO_APPLE_AVD|DEBUG_FS'`
   and `tr -d '\0' < /proc/device-tree/chosen/asahi,os-fw-version` (must be 13.5).

## 1. Decoder (AVD) — lowest risk, do first (`avd-port.txt`)

1. With the stock driver: `tools/avd-bench -d <clips> check` (must report
   mismatched 0), then `… all > stock.txt`.
2. Set `media.decodeFixes = true;`, rebuild, reboot, check `lsmod` shows
   `apple_avd_bakery` and not `apple_avd`, then `… all > bakery.txt` and the
   corrupted-clip test in §6.
3. Compare both with macOS (one stream: H.264 1080p 471 fps, HEVC 1080p 759,
   HEVC10 2160p 286, VP9 2160p 148; four HEVC 1080p streams 2593). The gap
   decides whether multi-stream (§5) or clock voting (§4) comes next.
4. Optional: `hevc_level_6=1` with an HEVC stream above 4K; `macos_init=1`;
   `media.decodeP210 = true` (kernel rebuild) for HEVC 4:2:2 10-bit.

## 2. Encoder (AVE) (`ave-port.txt` §8, then §10)

1. `media.encode = { enable = true; firmware = inputs.asahi-firmware + "/ave"; };`
2. Staged bring-up, one boot each: overlay + DARTs (record both DARTs' AS
   width and lock state; stop if they differ, either is < 41 or locked),
   `stop_after=8`, `stop_after=10`, full load, encode, compliance.
3. Save the cold DATA capture at once
   (`/sys/kernel/debug/apple_ave_iboot_data`); turning it into the pristine
   blob needs `tools/bakery-ave-fw --capture` on macOS later.
4. Default streams must be byte-identical to the community driver's; then
   test each feature in §10 (VUI, CBR filler, slices, throughput mode,
   `pm_replay`, `enc_chroma_formats` — riskiest last).

## 3. JPEG (`jpeg-port.txt`)

`media.jpeg.enable = true;` then the staged probe (`apple_jpeg_overlay
cores=1` first, `stop_after=1..5`). Open: register 0x19c value, whether
reading the AXI wrapper (`axi_init=1`) is safe, YUYV/UYVY order. Test with
`v4l2-ctl`, `gst-launch-1.0 … v4l2jpegenc / v4l2jpegdec`, PSNR via ffmpeg.

## 4. Scaler (`scaler-port.txt`)

`media.scaler.enable = true;` then `stop_after=1..7` (stage 5 is a polled
64x64 self-test). Then `scaler-test` (28 v4l2-ctl cases against ffmpeg
swscale, plus a GStreamer `v4l2convert` case). Open: DPE needed (`dpe=0`),
`ps_msr0_ase_core`, DDA centre/phase (`dda_center=`, `phase_neg=`), flip and
rotation directions, `uyvy_swizzle=`, IRQ 1188, `hang_recovery` level
(default 1).

## 5. ProRes — riskiest, do last (`prores-port.txt`)

1. `media.prores = { enable = true; firmware = inputs.asahi-firmware + "/prores"; };`
2. `stop_after=1..8`, one per boot. Stage 5 writes the DMA tunables: a wrong
   table can hang the whole machine. Stage markers are KERN_CRIT so the
   journal keeps them.
3. `selftest=1` (one 64x64 encode), then real encodes of all six profiles,
   checked with ffprobe and ffmpeg's ProRes decoder (PSNR). Open: ID
   register value, encMode 7 vs 6. Decoder only after encode works
   (`decoder=1`). An ffmpeg v4l2m2m ProRes patch (~80 lines) is worth
   writing only once an encode works.

## 6. After hardware runs

- Only once a block's overlay path passes: try its `deviceTree = true`
  (kernel rebuild; back up boot.bin). All four DT patches apply together in
  any order on asahi-7.2.14-1, but dtc has not been run on the full stack:
  build it and check with `fdtget`.
- Write results into each `*-port.txt` (replace [HW] items with findings) and
  `docs/media-engine.md`.
- Known gaps needing more reverse engineering on macOS, not Linux: the AVD
  clock/voltage vote mechanism (pmgr kext), the AVE QP-map address field,
  the scaler's colour-manager LUTs.

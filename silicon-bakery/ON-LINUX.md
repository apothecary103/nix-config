# On Linux: what to do after booting frieren

A runbook for an agent working on frieren (NixOS on the Mac14,9) after a
stretch of work done from macOS. Everything below was written and checked
statically from macOS. Nothing has been built or run on Linux yet. Work
through it in order and record what you find under **Results** at the end.

## Rules

- **The repo** is `~/nix-config` on branch `lambda-river`; Silicon Bakery is
  `silicon-bakery/` inside it. `docs/upstream.md` says where each patch
  stands upstream.
- **Commits** are small conventional commits with a subject line only: no
  body, no Co-Authored-By. Use the scopes in `git log` (`bakery`, `desktop`,
  `shell`, ...). Never commit or push `~/.password-store`.
- **frieren mirrors macOS.** Settings follow what the user's macOS does
  (read from the profile), not better defaults.
- **You run on the machine you are testing.** Several steps can hang or
  reset it. Before each risky step:
  - write your results so far into this file and commit;
  - run `sync`;
  - say what you're about to do.

  After a hang and forced reboot, `journalctl -k -b -1` has the previous
  boot.
- **The experimental features in section 4 need the user's go-ahead**, one
  per boot. They are off by default for a reason.
- **To go back:** boot the previous generation from the limine menu, or
  turn the option off and rebuild.

## 1. Before rebuilding

1. Bring the checkout up to date:
   ```sh
   cd ~/nix-config && git pull && git log --oneline -15
   ```
   The macOS commits from 2026-11-02 include
   `docs(bakery): plan the gpu dispatch tests on frieren`. If that's
   missing, they haven't been pushed from macOS yet: ask the user.
2. **Connect the Maomao HDD.** `modules/hosts/frieren/build-cache.nix` puts
   the kernel build's scratch space (about 30 GB) and its ccache on it.
   Without it the kernel still builds, but on the internal disk and from
   scratch.
3. **Record baselines on the current system,** for comparison after the
   rebuild:
   - GPU: `nix run ./silicon-bakery#hk-dispatch-bench > /tmp/bench-before.txt`.
     It uses whatever Mesa is installed now, and also checks ordering.
   - Idle power on battery, screen on, nothing running, one minute:
     ```sh
     for i in $(seq 60); do cat /sys/class/power_supply/macsmc-battery/power_now; sleep 1; done | awk '{s+=$1} END {print s/NR/1e6 " W"}'
     ```
   - AVD decode: step 0 of section 6 of `docs/avd-port.txt` (stock
     `apple_avd`, `tools/avd-bench` over its clips, saved as `stock.txt`).

## 2. Rebuild with the defaults

```sh
cd ~/nix-config && nh os switch && reboot
```

This builds the kernel and Mesa. frieren sets only
`hardware.siliconBakery = { enable = true; model = "Mac14,9"; }`, so what
changes is the always-on patch sets:

- **Kernel (`patches/linux`):**
  - `drm-asahi-flush-stamps-last-command`: the GPU driver sets
    `flush_stamps` on the last render and compute command again, as it did
    up to asahi-6.12.
  - The DCP fixes (`dcp-*`) and appledrm's XRGB2101010.
  - The trackpad patches (`hid-*`).
- **Mesa (`patches/mesa`), runtime driver only:**
  - `mesa-agx-g14x-metal-cdm-barrier`: the compute barrier bits
    AGXMetalG14X uses.
  - `mesa-hk-cdm-barrier-on-demand`: `vkCmdDispatch` leaves its barrier
    pending, so independent dispatches overlap. This is the riskiest
    default change.
  - `mesa-hk-memory-budget`: advertises `VK_EXT_memory_budget`.
  - `mesa-hk-no-compressed-input-attachments`.

If the build fails, the Mesa patches were never compiled: I couldn't build
the Vulkan driver on macOS. Fix the patch in `patches/mesa`, test it, and
commit.

## 3. Check the default build

### 3.1 Boot and GPU basics

```sh
journalctl -k -b -p err
journalctl -k -b | grep -i -E 'asahi|agx' | head -40
vulkaninfo --summary
vulkaninfo | grep -i memory_budget          # VK_EXT_memory_budget listed
```

River should come up as before. Check the 10-bit output (no flickering
border round the panel), a video in mpv, and a browser tab with WebGL.

### 3.2 GPU dispatch: benchmark and conformance

`docs/gpu.md`, "Testing on frieren", has the full commands.

```sh
nix run ./silicon-bakery#hk-dispatch-bench | tee /tmp/bench-after.txt
diff /tmp/bench-before.txt /tmp/bench-after.txt
```

- **Pass:** all three ordering checks print `ok` and the exit status is 0.
- **Expect:** independent dispatches fall towards Metal's 0.14-0.15 µs and
  dependent ones towards 1.3-1.5 µs. The Metal numbers were measured on this
  Mac with `tools/metal-probe`.
- **Then the CTS groups listed in `docs/gpu.md`** (`nix shell
  nixpkgs#vulkan-cts`, `deqp-vk --deqp-case=...`): compute, synchronization,
  memory_model, query_pool, api.copy_and_blit, tessellation, geometry.

If a check or a CTS group fails, find the culprit. Remove
`patches/mesa/mesa-hk-cdm-barrier-on-demand.patch` locally first (don't
commit that), rebuild and rerun. Then try the same with the Metal-barrier
patch. `hardware.siliconBakery.graphics.mesaPatches = false` turns off all
of them. Report which patch and which test, with output.

### 3.3 Trackpad

- **The test plan:** `docs/trackpad-driver-tests.txt`, steps 0-4. It reads
  only, except where a step says SET.
- **Palms:** `bakery-trackpad palms` shows libinput's palm decisions live; a
  firmware palm shows as `tool-palm`.
- **Resting fingers:** check the resting-finger rule against how macOS
  behaves (`docs/palm-rejection.md`, the part not yet checked on the
  machine).
- **Click feel:** `trackpad.click` sets Light, Medium or Firm. Check it
  matches the macOS setting in the profile.
- **Curves:** `bakery-trackpad curves`, `pointer` and `scroll` print them.

### 3.4 Media decode

Run the commands in `docs/media-engine.md`, "On the machine": `v4l2-ctl
--list-devices`, `vainfo` (H.264, HEVC and VP9 profiles), an
`ffmpeg -hwaccel vaapi` benchmark and `mpv --hwdec=vaapi`. If `vainfo`
lists only VP9, see that doc.

### 3.5 Display

- `journalctl -t river -b` for the colour (Display P3) decisions.
- **HDMI:** unplug and replug a monitor. The DCP patches should keep later
  display changes working, and the old monitor's EDID should be gone.
- **Suspend:** suspend and resume once, then repeat 3.1.

## 4. Experimental features, one per boot, with the user's go-ahead

Lowest risk first. For each one:
1. Set the option in `modules/hosts/frieren/configuration.nix` under
   `hardware.siliconBakery`.
2. Follow the doc's on-machine plan.
3. Record the results.
4. Set the option back to off unless the user wants to keep it.

| # | Option | Plan | Risk |
|---|---|---|---|
| a | `media.decodeFixes = true` | `docs/avd-port.txt` section 6, steps 1+ (diff against `stock.txt`) | low: a module, no kernel rebuild |
| b | `display.experimentalVrr = true` | `docs/vrr.md`, "On the machine" (boot with `appledrm.enable_verbose_logging=1`) | medium: DCP errors, screen blanking |
| c | `display.experimentalHdr = true` | `docs/hdr.md`, "On the machine" | medium: a DCP crash needs a reboot |
| d | `power.experimentalPmp = true` | `docs/pmp.md`, "On the machine" (idle power before and after) | medium: no display or camera; keep SSH |
| e | `media.scaler.enable = true` | `docs/scaler-port.txt` section 4 | high: staged, `step_ms=2000` |
| f | `media.jpeg.enable = true` | `docs/jpeg-port.txt` section 6 | high |
| g | `media.prores.enable = true` | `docs/prores-port.txt` section 5 | high: a wrong DMA table can hang |
| h | `media.encode.enable = true` (AVE) | `docs/ave-port.txt` section 8: Boot A, then B, then C, one per boot | high: Boot B is the risky one; needs the private firmware input |

Several of these have `autoload` and `deviceTree` sub-options; the docs say
when to turn those on (generally only after the runtime overlay works).

## 5. Unconfirmed hardware

From `docs/support.md`. Try each and note whether it works:

- 6 GHz Wi-Fi
- HDMI modes above 4K60
- UHS-II SD cards
- LE Audio
- hibernate
- **Ambient light:** whether `asahi-firmware` holds the sensor's calibration;
  with iio-sensor-proxy, auto-brightness follows.

## 6. When done

Update the docs the results settle:
- `docs/gpu.md`: the benchmark numbers;
- `docs/support.md`: the status column;
- the port docs: "untested" becomes what was seen.

Then commit, one change per commit, and summarise for the user: what works,
what failed with logs, and which experimental options are now on.

## Results

<!-- One entry per step: date, what ran, the result, log excerpts. -->

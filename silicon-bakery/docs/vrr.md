# ProMotion (variable refresh)

How the Mac14,9's internal panel varies its refresh, what Linux lacks, and
what `display.experimentalVrr` adds. Read on 2026-11-02 from macOS 27.2's
IORegistry, the DCP firmware of the macOS 13.5 stub (the one Linux boots),
IOMobileFramebuffer and QuartzCore, and asahi-7.2.12-2.

## How the panel works

- The timing list has no VRR range: min/max refresh are 0 on every mode.
  The limits are in `IOMFBDisplayRefresh` instead: frame intervals of 8.33 to
  41.67 ms in steps of 4.167 ms, so 120 down to 24 Hz on a 240 Hz subframe
  grid.
- macOS runs the 120 Hz timing (ID 2) with `NormalModeActive` and
  `APTFixedRR = 0`, and CoreAnimation gives every swap a target time (ts1).
- The 13.5 firmware hands each swap's ts1 to the panel's timing controller,
  which shows the frame on the next subframe at least 2 subframes after the
  last refresh and repeats it after 10. A swap with ts1 = 0 is held at a
  fixed 60 Hz. The promoted 60/59.94/50/48/47.95 Hz timings are fixed.
- `APTFixedRR` (runtime property 74, set with `applyProperty`, method A352)
  pins the refresh to N subframes; 0 lets it follow the swaps.
- The Adaptive-Sync parameter (minRR) is read only on the external DP/HDMI
  path, never for the internal panel.

## What Linux has

asahi-7.2.12-2 and 7.2.14-1 already send non-zero timestamps in the 120 Hz
timing, so the panel most likely already varies 24 to 120 Hz. What is
missing is control and visibility: no `vrr_capable`, so wlroots never offers
adaptive sync. AsahiLinux/linux#477 (open) uses minRR and a modeset, the
right lever for external displays but, per the firmware, not for the
internal panel. wlroots 0.20.2 and river 0.5.0 pass `adaptive_sync` through
already.

## What Silicon Bakery adds

`patches/linux-vrr/appledrm-experimental-vrr`, with
`display.experimentalVrr = true` (boots with `appledrm.experimental_vrr=1`
and asks kanshi for `adaptive_sync on`):

- eDP-1 gets `vrr_capable` (13.5 firmware, while the 120 Hz timing is
  offered).
- Adaptive sync on: nothing new is sent; the firmware's own behaviour.
- Adaptive sync off: `APTFixedRR = 2` (fixed 120 Hz) ahead of the next swap,
  without a modeset. That draws more power than today's default, so leave
  adaptive sync on.
- Without the parameter the driver is unchanged.

## On the machine

Boot with `appledrm.enable_verbose_logging=1` too, so DCP's own log reaches
dmesg. Keep SSH available.

1. `drm_info | grep -i -E 'eDP-1|vrr_capable|VRR_ENABLED'`: `vrr_capable = 1`.
2. `wlr-randr --output eDP-1 --adaptive-sync disabled`, then `enabled`, while
   `journalctl -k -f | grep -E 'APTFixedRR|forcing refresh'` shows "APTFixedRR
   2 (fixed refresh)" with DCP's "forcing refresh rate: 2 subframes", then
   "APTFixedRR 0" and "disabled". The screen must not blank. A DCP error here
   means A352 is wrong: boot without the parameter and keep the log.
3. Frame timing: play a 48 fps source fullscreen
   (`mpv --fs --no-audio --vo=gpu-next 'av://lavfi:testsrc2=rate=48:size=3024x1964'`)
   and record `sudo trace-cmd record -e dcp:iomfb_swap_complete -- sleep 10`.
   Adaptive sync on: completions every 20.8 ms. Off: alternating 16.7 and
   25 ms. 48 and 80 fps tell the two apart; 24, 30, 40 and 60 fps look the
   same either way.
4. Idle power on battery, a minute each way:
   `for i in $(seq 60); do cat /sys/class/power_supply/macsmc-battery/power_now; sleep 1; done | awk '{s+=$1} END {print s/NR/1e6 " W"}'`.
   On should be at or below the unpatched kernel, off higher.

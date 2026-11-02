# HDR on Apple Silicon panels

Where HDR stands for the Mac14,9 (MacBook Pro 14", M2 Pro, Liquid Retina XDR)
under asahi-7.2.12-2, what Silicon Bakery adds, and how to find out the rest
on the machine. Read on 2026-11-02 from macOS 27.2's IORegistry, the Asahi
kernel, wlroots 0.20.2 and river 0.5.0.

## How macOS does it

The internal panel has one link colour mode. Its `ColorElements` hold a
single entry: 8-bit RGB, EOTF 0 (SDR gamma), colorimetry 16 ("Default RGB"),
shared by every timing from 47.95 to 120 Hz. There is no PQ signal to the
panel. HDR on these Macs is EDR: SDR white sits at up to 500 nits
(`BLNitsCap`, `user-accessible-max-nits`), the mini-LEDs go to 1600
(`limit_max_physical_brightness`, `LmaxProduct`), and `EDRPotentialHeadroom`
is 16. Brighter-than-white pixels come from raising the backlight inside DCP
and dimming SDR content to match (`IOMFBDigitalDimmingLevel`,
`IOMFBSecureIndicatorSDRFactor`, `GCPBypassesEDRPixels`, 2D local dimming).
How macOS asks DCP for that has not been traced; m1n1's DCP tracer names
`display_edr_factor_changed(float)` and a `double` in `swap_submit_dcp` that
Linux always sends as 0, either a likely channel.

## What Linux does today

- appledrm offers no Colorspace, HDR_OUTPUT_METADATA or "max bpc" property,
  avoids PQ link modes on every display, and tags RGB surfaces NATIVE with
  the SDR transfer function. `DCP_XFER_FUNC_HDR` (16) is defined, never sent.
- The backlight maps 2 to 510 nits and the device tree caps it at 500.
- wlroots learns BT.2020 and PQ only from an EDID, and only if the connector
  has those properties. The internal panel has no EDID.

So river's `RIVER_HDR_OUTPUTS` (patches/river/0002-hdr) cannot take effect
on this machine with a stock kernel; it logs that the output does not
advertise BT.2020 and PQ and stays SDR.

## What Silicon Bakery adds

- `patches/river/0002-hdr`: HDR for outputs that advertise it, tried on a copy
  of the state so a refusal changes nothing (fixed: a refused output was left
  in an untested 10-bit format, and a null image description was committed,
  which the legacy DRM interface rejects). The first frame of a modeset now
  gets the P3 transform too.
- `patches/wlroots/0003-edid-less-hdr`: an eDP connector without an EDID that
  has HDR_OUTPUT_METADATA and a Colorspace offering BT2020_RGB advertises
  BT.2020 and PQ. Inert unless the kernel offers those properties.
- `patches/linux-hdr/appledrm-experimental-hdr`, with
  `hardware.siliconBakery.display.experimentalHdr = true` (which also boots
  with `appledrm.experimental_hdr=1` and lists the internal panel in
  `RIVER_HDR_OUTPUTS`): the standard properties on every connector; BT2020_RGB
  with PQ static metadata is HDR, the default colorspace is SDR, anything else
  is refused; external displays switch to a PQ colour mode where DCP reports
  one; in HDR, RGB surfaces are tagged `DCP_COLORSPACE_BG_BT2020` with
  `DCP_XFER_FUNC_HDR`. Without the parameter nothing changes.

The open question is DCP's: whether it converts BT.2020 PQ surfaces onto the
internal panel's 8-bit SDR link correctly, and whether it lifts the backlight
for highlights. The likely outcomes are correct colour without extra
brightness, or wrong colour. Real EDR probably needs a trace of macOS under
the m1n1 hypervisor (surface formats, the `swap_submit_dcp` double, any
EDR-factor calls, backlight values above 510 nits), or emulating it in the
compositor as KWin does on SDR laptops, which the 500-nit cap limits.

Watch on kernel bumps: river's P3 design relies on appledrm tagging internal
RGB surfaces NATIVE. If it starts tagging them sRGB, DCP would map sRGB to P3
on top of river's own transform and colours would oversaturate.

## On the machine

Keep SSH available; a DCP crash needs a reboot. To go back, set
`experimentalHdr = false` (or boot the previous generation).

1. The kernel offers the properties:
   ```sh
   cat /sys/module/appledrm/parameters/experimental_hdr
   drm_info | grep -B1 -A4 -E 'Colorspace|HDR_OUTPUT_METADATA'
   journalctl -k -b | grep -E 'set_digital_out_mode|color mode|HDR on'
   ```
   On eDP-1 expect `depth:8 eotf:0` every time: the link stays SDR.
2. wlroots and river take HDR: `journalctl -t river -b | grep -E 'EDID-less|is HDR|refused'`,
   then `sudo grep -A15 eDP-1 /sys/kernel/debug/dri/*/state | grep colorspace`
   (expect BT2020_RGB).
3. Does DCP decode PQ? Compare the desktop in HDR and SDR. Matching hues and
   normal white: DCP converts. Grey, dim and desaturated (PQ's 203 nits is
   about 58 % code value, shown raw): it ignores the tags.
   `mpv --vo=gpu-next --target-colorspace-hint=yes hdr10.mkv` for HDR video.
4. Any EDR boost? `echo 'file systemep.c +p' | sudo tee /sys/kernel/debug/dynamic_debug/control`,
   then `journalctl -kf | grep mNits` and `watch cat /sys/class/backlight/apple-panel-bl/actual_brightness`
   while showing a 1000-nit PQ patch. Expect none.
5. External HDR monitor: look for `eotf:2` in the colour mode line once HDR is on.

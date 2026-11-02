# Upstream

Where Silicon Bakery stands against Asahi upstream, surveyed 2026-11-02.

## Pinned

- nixos-apple-silicon f88fb8087b3f (2026-11-01): linux-asahi `asahi-7.2.14-1`,
  asahi-va-driver 2.0 (`LIBVA_DRIVER_NAME=asahi`), `boot.m1n1Package`.
- Mesa from nixpkgs (26.2.5), libinput 1.31.3, wlroots 0.20.2, river 0.5.0.
- m1n1 2.0.0 (nixpkgs). Do not point `boot.m1n1Package` at m1n1 main: its
  new HDMI-controller check (cb42485b067e) looks inverted and would leave the
  t6020's HDMI port disabled.

## Carried patches and their upstream status

| patch | upstream |
|---|---|
| linux/appledrm-xrgb2101010-premultiplied | not upstream; still needed in 7.2.14-1 |
| linux/dcp-poweroff-timeout-not-a-crash | AsahiLinux/linux#582, open |
| linux/dcp-drop-edid-on-disconnect | AsahiLinux/linux#654, open |
| linux/dcp-hdmi-audio-64-periods | AsahiLinux/linux#655, open (only matters with `appledrm.hdmi_audio=1`) |
| linux-hdr | none; chadmed's unmerged `dcp/scanout` 5fa3d22649eb touches the same functions |
| linux-vrr | none; #477 (open, minRR) edits neighbouring code: rebase when it lands |
| linux-ave | none |
| linux-pmp | none; Asahi keeps `APPLE_USE_PMP` opt-in until the PMP driver is upstream |
| mesa/mesa-hk-no-compressed-input-attachments | not reported upstream; compression code unchanged through 26.3.0-rc3 and main |
| mesa/mesa-agx-g14x-metal-cdm-barrier | ours, from AGXMetalG14X; Mesa !44041 (open) drops the same bits but also unk_10/12 |
| mesa/mesa-hk-memory-budget | Mesa !40238, open since 2026-03-05 (a duplicate, !41293, was closed) |
| linux/drm-asahi-flush-stamps-last-command | AsahiLinux/linux#633, open, no fix posted |
| libinput, libinput-1.32 | ours; 1.32 (nixpkgs#564171, open) needs the -1.32 set, picked by version |
| wlroots | ours; 0001-backdrop-blur no longer applies to wlroots master (0.21) |

Left out on purpose: #657 (HDMI 2.1 EDID) and #631 (AVD allocations), closed
under Asahi's AI-assistance policy and unreviewed.

## Watch

- AsahiLinux/linux#573: MTP haptics; marks the trackpad a pressure pad
  (libinput MR !1508 is the other half). Re-measure palm sizes if it lands.
- avd-fw 0.2 (nixpkgs#581622) and nixos-apple-silicon#575: the codec option,
  which `media.decodeCodecs` already answers.
- Mesa !39755 (draft) edits `hk_image.c`, the file the Mesa patch touches.
- AsahiLinux/linux#625: HDMI freezes on M2 Pro/Max.
- `nix flake check` re-applies every patch to the pinned sources; run it
  after each bump.

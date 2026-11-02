# Support: MacBook Pro 14" M2 Pro (Mac14,9)

What works on the Mac14,9 (j414s, t6020) with Silicon Bakery, what Asahi
upstream gives it, and what the hardware does under macOS that Linux does not
do yet. Surveyed 2026-11-02 against the pins in `docs/upstream.md`
(linux-asahi `asahi-7.2.14-1`, m1n1 2.0.0, Mesa 26.2.5) and Asahi's M2
feature table (AsahiLinux/docs, `feature-support/m2.md`, 2026-08-02). The
hardware column was read from this Mac under macOS 27.2 (IORegistry,
`system_profiler`) and Apple's tech specs (support.apple.com/kb/SP889).

The 14" and 16" M2 Pro and M2 Max (Mac14,5, 14,6, 14,9, 14,10) share a
device tree (`t602x-j414-j416.dtsi`), firmware and drivers. Only the
Mac14,9 has been checked here.

| status | meaning |
|---|---|
| works | upstream or linux-asahi, nothing to add |
| bakery | works, and Silicon Bakery brings it closer to macOS |
| partial | works with a real gap against macOS |
| experimental | Silicon Bakery has an opt-in patch, untested on hardware |
| WIP | upstream work in a branch or an open PR, not in our kernel |
| missing | the hardware can do it; nothing on Linux does |
| no | not expected to work on Linux |

"Upstream" below means `asahi-7.2.14-1`. A kernel version means the release
where the driver reached mainline Linux.

## Summary

| area | status | the gap against macOS |
|---|---|---|
| CPU, cpufreq | works | deep idle is downstream-only; PMP power savings are opt-in and untested here |
| Suspend | partial | about 2 %/h asleep against macOS's near 0; no hibernate |
| GPU | bakery | no compute preemption; no ray tracing or mesh shaders in hardware |
| Internal panel | bakery | no EDR/HDR, no adaptive refresh exposed, 500-nit SDR ceiling |
| HDMI | partial | hotplug freezes; no modes above 4K60, HDR or VRR confirmed |
| USB-C display out | WIP | one port, `fairydust` branch only |
| Thunderbolt / USB4 | WIP | USB 2/3 only; no PCIe or DP tunnelling |
| Trackpad | bakery | no host click control: no Force Click, no click pressure setting |
| Keyboard, backlight | works | |
| Audio: speakers, jack, mics | works | no Spatial Audio, no high-impedance headphone mode |
| Camera | works | no Studio Light, Portrait or other ISP effects |
| Wi-Fi | partial | 6 GHz (Wi-Fi 6E) unconfirmed; firmware timeouts under load |
| Bluetooth | partial | no LE Audio |
| SD card | partial | UHS-II unconfirmed; a card inserted before boot is missed |
| Battery, charging | works | no adaptive (Optimized) charging; the charge limit resets at boot |
| Ambient light | partial | needs calibration firmware; no True Tone |
| Motion and lid-angle sensors | missing | the accelerometer, gyroscope and lid angle have no driver |
| Video decode (AVD) | bakery | VA-API covers less than V4L2; one stream at a time |
| Video encode (AVE) | experimental | Silicon Bakery's t6020 port, never run |
| ProRes, JPEG, scaler | missing | no drivers |
| Neural Engine | missing | out of tree only, t6020 not stated |
| Touch ID | no | the Secure Enclave owns the sensor (`docs/touch-id.md`) |

## CPU and power

| feature | status | upstream | Silicon Bakery | macOS has, Linux lacks |
|---|---|---|---|---|
| cpufreq (6 P + 4 E cores) | works | mainline 6.2 | | Low Power Mode as a platform profile; Linux has governors only, and no platform_profile for power-profiles-daemon (unverified) |
| cpuidle | partial | deep WFI in linux-asahi, never upstreamable; the PSCI-through-UEFI replacement is an RFC (`efi-psci`) | | macOS's full idle residency |
| PMP (power management coprocessor) | experimental | driver in linux-asahi since 7.0, idle unless the device tree defines `APPLE_USE_PMP`; about 0.5 W (20 %) less at idle, measured on an M1 Pro | `power.experimentalPmp`: the define plus the ISP report entry t602x leaves off (`docs/pmp.md`) | measured savings on the M2 Pro |
| s2idle suspend | partial | linux-asahi | | sleep drains about 2 %/h (AsahiLinux/linux#262; macOS is near 0); some long sleeps fail to resume; Power Nap and dark wakes have no equivalent |
| Hibernate | no | not supported (unverified) | | |
| Battery life | partial | | | Apple claims 18 h video, 12 h web. Users report roughly half to two thirds of macOS's on M1/M2 Pro/Max (anecdotal; none measured on this Mac) |
| CPU PMU / perf | works | mainline 6.4; #614 adds the macOS 27 event name | | |
| TSO for x86 emulation | works | linux-asahi only (`bits/220-tso`) | | |
| 16K pages, x86 apps | works | FEX in muvm (4K-page VM); WoW64 FEX without muvm for most Windows apps | | Rosetta 2, without a VM for 4K-page apps |
| AMX matrix coprocessor | missing | not exposed (unverified) | | Accelerate and Core ML use it |

## Graphics (G14S, 16 cores)

| feature | status | upstream | Silicon Bakery | macOS has, Linux lacks |
|---|---|---|---|---|
| OpenGL 4.6, GLES 3.2 | works | Mesa `asahi`, conformant | | |
| Vulkan 1.4 | bakery | Honeykrisp, conformant | input attachments uncompressed (10-bit scanout flicker) | |
| OpenCL 3.0 | works | rusticl | | CPU reads of GPU memory are slow (Mesa #16553) |
| Compute barriers | bakery | Mesa sets all 21 known bits after every launch | the 5-bit barrier AGXMetalG14X writes (`patches/mesa`) | dependent dispatches cost ~4 µs against Metal's 2.3 µs (llama.cpp #10982) |
| Stamp flushes | bakery | none flushed since the UAPI rework (AsahiLinux/linux#633) | `drm-asahi-flush-stamps-last-command` | |
| DVFS, thermal tables | works | match macOS's ADT to the value (`docs/gpu.md`) | checked | two values open: t6020's temperature sensor address, the fast-die release temperature |
| Geometry, tessellation | partial | emulated with compute | | native on Metal |
| DirectX through Proton | works | FEX + Wine/Proton | | |
| Compute preemption | missing | none (AsahiLinux/linux#417): a long compute job stalls the desktop | | |
| Mesh shaders, cooperative matrix | missing | not in Honeykrisp | | Metal 3 mesh shaders |
| Ray tracing | no | no RT hardware on M2 | | |
| GPU load and pstate in sysfs | missing | AsahiLinux/linux#340 | | Activity Monitor's GPU history |
| Direct scanout of compressed buffers | WIP | Interchange format work, blocked on compositors | | |

## Internal display (Liquid Retina XDR, 3024x1964)

| feature | status | upstream | Silicon Bakery | macOS has, Linux lacks |
|---|---|---|---|---|
| Panel, DCP | works | linux-asahi | XRGB2101010 blended as premultiplied; DCP power-off timeout and EDID fixes (#582, #654) | |
| 120 Hz | works | since asahi-6.18.4 | | |
| ProMotion 24-120 Hz | experimental | the panel likely already varies (non-zero swap timestamps) but nothing exposes it; #477 (open) uses minRR and a modeset, behind `appledrm.force_vrr` | `display.experimentalVrr`: `vrr_capable`, `APTFixedRR` for fixed 120 Hz (`docs/vrr.md`) | compositor-visible VRR, verified on hardware |
| Colour: Display P3 | bakery | DCP applies the factory calibration; planes left NATIVE | river composites in P3 (`display.p3Outputs`) | ColorSync for every app; Linux needs colour-managed clients |
| HDR / EDR | experimental | no Colorspace or HDR_OUTPUT_METADATA | `display.experimentalHdr` (`docs/hdr.md`) | EDR: 1000 nits sustained, 1600 peak, headroom 16; Linux stops at 500 nits |
| Brightness | works | 2-500 nits | | the 1600-nit range for highlights |
| Local dimming (mini-LED) | works | inside DCP, as on macOS | | |
| Notch | works | `appledrm.show_notch=1` gives the full panel | frieren sets it | |
| True Tone | missing | | | white point following the room's light |
| Night Shift | works | Night Light through the CTM | | |

## External displays and ports

| feature | status | upstream | Silicon Bakery | macOS has, Linux lacks |
|---|---|---|---|---|
| HDMI port | partial | linux-asahi; hotplug can freeze the desktop for ~30 s on Mac14,9 (#456; plug in before boot); #625 freezes on some monitors | `dcp-hdmi-audio-64-periods` (#655) | HDMI 2.1: 8K60 or 4K240; nothing above 4K60 is confirmed on Linux, and no HDR or VRR |
| HDMI audio | partial | `appledrm.hdmi_audio=1`, preview | | |
| DisplayPort over USB-C | WIP | `fairydust` branch, one port (dcpext1/atcphy1) | | two 6K60 displays over Thunderbolt, or 6K60 + 4K144 HDMI |
| USB 2 / USB 3 over USB-C | works | mainline 7.0 (atcphy) | | |
| Thunderbolt 4 / USB4 | WIP | 19-patch series posted 2026-08 (`bits/270-thunderbolt`), no PCIe or DP tunnelling | | 40 Gb/s, PCIe devices and docks, Thunderbolt networking |
| USB-PD | works | tipd, mainline 5.16 | | |
| MagSafe 3 | works | charges; LED control unverified | | |
| SDXC slot | partial | GL9755 on PCIe, mainline 5.17; a card present at boot is not seen (#461, on NixOS) | | UHS-II (about 250 MB/s); Linux UHS-II on this reader is unconfirmed |

## Input

| feature | status | upstream | Silicon Bakery | macOS has, Linux lacks |
|---|---|---|---|---|
| Keyboard | works | DockChannel/MTP, linux-asahi only | key repeat and delay from the profile | |
| Keyboard backlight | works | mainline 6.18 | | automatic backlight from the ambient light |
| Trackpad tracking | bakery | | units in hundredths of a mm; macOS's acceleration curves, deadband, tap and drag timings, three-finger drag, resting finger, firmware palms | gesture engine momentum (left to toolkits) |
| Trackpad click feel | bakery | haptics in #573 (open) | firmware clicks get macOS's Light/Medium/Firm waveforms | |
| Force Click, click pressure | missing | #573 adds `INPUT_PROP_PRESSUREPAD` and host click control; libinput !1508 the other half | | where a click triggers (125 g x 0.8/1/1.2), Force Click at 300 g, pressure-sensitive input |
| Lid switch, power key | works | SMC input, linux-asahi | | |
| Touch ID | no | the Secure Enclave owns the sensor | `docs/touch-id.md`: FIDO2 key with `pam_u2f` instead | |

## Audio

| feature | status | upstream | Silicon Bakery | macOS has, Linux lacks |
|---|---|---|---|---|
| Six speakers | works | asahi-audio (j314 profile) with speakersafetyd | | macOS's psychoacoustic bass and spatial processing; asahi-audio aims for flat |
| Spatial Audio, Dolby Atmos | missing | | | Atmos rendering and head tracking |
| Headphone jack | partial | cs42l84 mainline; 44.1-192 kHz | | high-impedance detection and drive; HD650-class headphones distort at high volume (#247) |
| Three-mic array | works | fixed for M2 Pro/Max in 6.18; beamforming through asahi-audio's triforce | | |
| Voice processing | missing | | | macOS's Voice Isolation and Wide Spectrum modes |

## Camera

| feature | status | upstream | Silicon Bakery | macOS has, Linux lacks |
|---|---|---|---|---|
| 1080p FaceTime HD (IMX558, ISP) | works | linux-asahi; PipeWire and GNOME Camera fixed in 6.19 | | Studio Light, Portrait, Center Stage-style framing (ISP and ANE effects) |

## Wireless

| feature | status | upstream | Silicon Bakery | macOS has, Linux lacks |
|---|---|---|---|---|
| Wi-Fi (BCM4388) | partial | brcmfmac in linux-asahi; mainline series posted 2026-09, station mode, 6 GHz deferred; firmware timeouts under load (#453, #603) | | Wi-Fi 6E's 6 GHz band (unconfirmed on linux-asahi); WPA3 through brcmfmac is unconfirmed |
| Bluetooth 5.3 | partial | hci_bcm4377; coexistence fixed in 7.0 | | LE Audio (LC3), which macOS lists; `CONFIG_BT_ISO` and firmware support unconfirmed |
| Continuity, AirDrop, Handoff, Sidecar | no | Apple software, not hardware | | KDE Connect is the nearest |

## Sensors and coprocessors

| feature | status | upstream | Silicon Bakery | macOS has, Linux lacks |
|---|---|---|---|---|
| Battery, charge limit | works | macsmc-power, mainline 7.1; `charge_control_end_threshold` 80 or 100 | | Optimized Charging; the threshold resets at boot (persist with udev) |
| Fans, temperatures | works | SMC hwmon, mainline 6.19 | | |
| Ambient light (`als`, AOP) | partial | AOP ALS in linux-asahi 6.19+, needs calibration firmware from the installer's "rebuild vendor firmware" (not checked in frieren's firmware) | | auto-brightness out of the box, True Tone |
| Accelerometer, gyroscope (`accel`, `gyro`, SPU) | missing | none | | present on this Mac (SPU HID devices, 8 ms report interval); Linux has no SPU sensor driver |
| Lid angle (`las`, SPU) | missing | none | | present on this Mac (HID usage page 0x20, usage 0x8a) |
| Neural Engine (`ane0`, H11ANE) | missing | out of tree (eiln/ane); device tree bindings refused without a driver (#584) | | Core ML, Live Text, on-device ML |
| Video decode (`avd0`) | bakery | V4L2 stateless, asahi-va-driver | `media.decode`, `media.decodeCodecs` (`docs/media-engine.md`) | VA-API lacks H.264 10-bit, 4:2:2 and VP9 profiles 1/3; one stream at a time; mpv zero-copy with gpu-next is wrong (Mesa #16429) |
| Video encode (`ave0`) | experimental | none | `media.encode`: t6020 port, never run (`docs/ave-port.txt`) | H.264 to 2160p30, HEVC to 2160p60 |
| ProRes (`apr0`) | missing | none | | ProRes encode and decode |
| JPEG x2, M2Scaler | missing | none | | hardware JPEG and scaling/colour conversion |
| Secure Enclave | no | put to sleep before Linux | | FileVault keys, Touch ID, Apple Pay |
| AES engine (`aes`) | missing | none | | the CPU's AES instructions cover it on Linux |

## Boot

| feature | status | upstream | Silicon Bakery | macOS has, Linux lacks |
|---|---|---|---|---|
| m1n1, U-Boot, boot picker | works | m1n1 2.0.0; stays on 2.0.0 (`docs/upstream.md`: main's HDMI check would disable the port) | | |
| macOS 27 alongside | works | the boot picker needs the APFS bootable flag (installer option) | | |
| Firmware | partial | Linux runs the macOS 13.5 stub's firmware (GPU, DCP, AVE) | | newer firmware means new kernel ABIs no one has started for M2 |

## Where to go next

The gaps nearest to hand, with what would close them:

- **PMP power savings**: `power.experimentalPmp` is written; the test plan
  in `docs/pmp.md` (does everything still probe, idle `power_now` before and
  after).
- **Charge limit at boot**: a udev rule writing `charge_control_end_threshold`
  from an option, for macOS's 80 %.
- **Ambient light**: check whether frieren's `asahi-firmware` holds the ALS
  calibration; with iio-sensor-proxy, auto-brightness follows.
- **ProMotion and HDR**: the on-device test plans in `docs/vrr.md` and
  `docs/hdr.md`.
- **Force Click**: #573 plus libinput !1508, then macOS's force thresholds
  from the profile.
- **Motion and lid-angle sensors**: the SPU's HID devices sit behind the
  AOP, as the ALS does; the ALS driver is the model for a driver.
- **AVE**: the staged bring-up in `docs/ave-port.txt`.

Unconfirmed and worth a test on the machine: 6 GHz Wi-Fi, HDMI modes above
4K60, UHS-II, LE Audio, and whether hibernate works.

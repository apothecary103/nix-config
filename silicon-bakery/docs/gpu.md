# GPU (AGX G14S, M2 Pro)

What the Asahi GPU stack does against what macOS does on a Mac14,9 (t6020,
16 cores of 20 across 2 clusters: `core_mask_list` 0x1ef per cluster in
`GPUConfigurationVariable`). Checked 2026-11-02 against linux-asahi
`asahi-7.2.14-1`, m1n1 2.0.0 and Mesa 26.2.5.

Sources on the Mac:

- macOS 27.2's IORegistry (`AGXAcceleratorG14X`, the ADT's `arm-io/sgx`).
- The ADT of the 13.5 stub that boots Linux: `DeviceTree.j414sap.im4p` in
  the NixOS container's Preboot volume. Linux runs the 13.5 GPU firmware, so
  this is the macOS that firmware was built for.
- The 13.5 kernelcache in the same Preboot (`kernelcache.release.mac14j`),
  whose `com.apple.AGXG14X` is the kext that drives the 13.5 firmware.
- macOS 27.2's `AGXMetalG14X` from the dyld shared cache. The command
  encoding it writes is the hardware's, so the firmware version does not
  matter there.

Nothing from Apple is in this repository; only numbers and conclusions.

## Matches macOS

- **DVFS and power control.** m1n1 fills the OPP tables (9 states, up to
  1398 MHz), voltages, leakage and memory regions from the ADT at boot. Every
  other constant is in `t602x-die0.dtsi` and `t6020.dtsi`, and every
  `apple,*` value equals the 13.5 ADT's `gpu-*` property: the perf, power,
  PPM (`ppm-ki` 28.0, filter 32 ms, both t6020 overrides) and SE loops, and
  the fast-die0 gains. macOS 27.2's ADT has the same values.
- **Thermal sensor masks.** The kext's G14X table lists the fast-die sensor
  masks per chip; t6020's `0xc000d00` and t6021/t6022's equal
  `hw/t602x.rs`. So do `shared2_tab` (0x800, 0x1555, -1...), `shared3_tab`
  (125..., 7500) and `unk_87c` (500), all in the same table.
- **Tiler heap (parameter buffer).** The kernel's limits are macOS's to the
  byte: 862,322,688 (`AGXParameterBufferMaxSize`) and 287,440,896 without
  memoryless (`...NeverMemless`), growing to 3x the used size after an
  overflow, as macOS does.
- **Firmware ABI.** Only 13.5 exists for G14X in the driver; m1n1 maps
  13.5B4 and 13.6.1 to it. Moving to a newer firmware means a new ABI in the
  kernel, which no one has started for M1/M2.

## Fixed here

- `patches/linux/drm-asahi-flush-stamps-last-command`: since the UAPI rework
  `submit()` swaps its last-render and last-compute indices, so no command
  gets `flush_stamps`. Up to asahi-6.12 the last command of each kind did,
  as traced from macOS (AsahiLinux/linux#633, confirmed in the source).
- `patches/mesa/mesa-agx-g14x-metal-cdm-barrier`: Mesa puts a CDM barrier
  with all 21 known bits after every compute launch, a guess its comment
  says to revisit. On the M2 Pro, `ComputeContext::encodeBarrier` in
  AGXMetalG14X writes one of two words:
  - `0x60000160` (unk_5, unk_6, unk_8) between dispatches;
  - `0x60001560` (adding unk_10, unk_12) after a CDM blit that wrote a
    texture.

  The second is chosen by a flag only the texture-writing blits set
  (`blitCDMTextureToTexture`, `blitCDMBufferToTexture`). The multi-word path
  is taken only when `DeviceConstants::hasMultipleAGCs` is set, which only
  `AGXG14DDevice` (M2 Ultra) does. Mesa can't tell an image-writing launch
  apart where it flushes, so single-die G14X gets `0x60001560` every time.
  Vulkan compute, Vulkan's geometry and tessellation emulation, queries and
  GL compute all go through it. Mesa !44041 (unmerged) measured the
  per-dispatch cost halving on M1 with unk_5/6/8 alone; not yet measured
  here.

## Open

- **AnalogTempSensorController address.** `hw/t602x.rs` maps 0x28e460000 for
  t6020 and 0x28e478000 for t6021/t6022. The 13.5 kext's G14X table has only
  0x28e478000 (and 0x228e478000 for the second die), and nothing in the kext
  reads that table directly, so whether t6020 is chosen elsewhere is not
  settled. Check on the machine before changing it: the firmware reads its
  temperatures there.
- **fast-die0 release temperature.** The kernel defaults it to 80 °C. The
  ADT gives `gpu-fast-die0-target` and `-alarm-threshold` as 94 and
  `gpu-sochot-temp` as 111, which the kernel doesn't read. How macOS turns
  them into the firmware's fields needs the kext's initdata builder.
- **Known gaps, from upstream** (not fixed here):
  - No compute preemption (AsahiLinux/linux#417): a long compute job stalls
    the desktop.
  - No cooperative matrix, mesh shaders or ray tracing in Honeykrisp.
  - Geometry and tessellation are emulated with compute.
  - Dependent dispatches cost about 4 µs against Metal's 2.3 µs (llama.cpp
    #10982); the barrier patch addresses part of that.
  - CPU reads of GPU memory are slow in rusticl (Mesa #16553).
  - No GPU pstate or utilisation in sysfs (AsahiLinux/linux#340).

## Reproducing

From macOS, with the NixOS stub's Preboot mounted read-only:

```sh
ioreg -p IODeviceTree -l -a -d 40      # the live ADT
ioreg -rc AGXAccelerator -d1 -l         # GPUConfigurationVariable, PB sizes
```

The 13.5 ADT and kernelcache are IM4P files holding LZFSE; libcompression
(`compression_decode_buffer`, algorithm 0x801) unpacks them. The kext is the
`com.apple.AGXG14X` fileset entry. `AGXMetalG14X` comes out of the dyld
shared cache through `/usr/lib/dsc_extractor.bundle`.

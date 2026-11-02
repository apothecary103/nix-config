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
- **AnalogTempSensorController address.** The kext's firmware mapping setup
  derives it from AICSWInt's base, 0x28e106000, by GPU variant: 0x10 (G14S)
  adds 0x35a000, giving 0x28e460000; 0x11 (G14C) adds 0x372000, giving
  0x28e478000; 0x12 (G14D) maps two, 0x28e478000 and 0x228e478000, from its
  constant table. `hw/t602x.rs` has the same three. m1n1's Python
  `agx/initdata.py` gives t6020 0x28e478000, which is wrong but only used by
  its hypervisor tooling.
- **Fast-die thermal loop.** macOS reads `gpu-fast-die0-target`,
  `-release-temp`, `-prop-tgt-delta` and the gains from the ADT, defaulting
  to 80 °C release, a delta of 0 and a ki of 400 (j414s has no
  `release-temp`, so 80, as in the kernel). It then overwrites the target
  with 110.0 °C and the next field with 5.0 whenever the chip has fast-die
  sensor masks, as t6020 does, so the ADT's 94 never reaches the firmware.
  Times 100, these are the kernel's `unk_8cc` (11000) and `unk_87c` (500).
  The same routine sets t6020's sensor mask (0xc000d00) and the 8.2 and 6.9
  coefficients of `unk_coef_a`.
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

- `patches/mesa/mesa-hk-memory-budget`: Honeykrisp has implemented
  `VK_EXT_memory_budget` since its first commit but never advertised it
  (Mesa !40238, open). DXVK and vkd3d-proton size themselves from it.

## Honeykrisp against Metal

What Metal does with this GPU and what Honeykrisp (Mesa 26.2.5, and main
on 2026-11-02 where it differs) does. Metal's side is from AGXMetalG14X's
symbols and encoders and from running Metal on this Mac
(`MTLDevice` queries plus test kernels).

| | Metal, M2 Pro | Honeykrisp |
|---|---|---|
| Clocks, power, thermals | firmware | same firmware, same constants (above) |
| Tessellation | hardware tessellator (`HWTessellationContextA/B`, the VDM Tessellate block) | compute: count, prefix sum, tessellate, draw |
| Geometry shaders, transform feedback | none | yes, in compute |
| Isolines, point-mode tessellation | none | yes |
| 64-bit atomics | min/max only, native | none |
| Barycentrics | yes | off |
| Raster order groups / fragment shader interlock | yes | not exposed |
| Mesh shaders | yes | no |
| Ray tracing | yes, in compute (no RT hardware before M3) | no |
| Variable rate shading (rasterization rate maps) | yes | no |
| Cooperative / simdgroup matrix | yes | no |
| FP64 | none (no hardware) | none |
| Memory budget | n/a | implemented, never advertised (fixed here) |
| Per dispatch, dependent | 1.3-1.5 µs (measured here) | about 4 µs (llama.cpp #10982, M2 Ultra) |
| Per dispatch, independent | 0.14-0.15 µs (measured here) | same as dependent: a barrier after every launch |
| Hardware counters | AGXGPURawCounterBundle | no performance queries |

So Honeykrisp does not use every part of the GPU, but the gaps are smaller
than the table looks:

- **Hardware tessellation was tried and dropped.** Alyssa Rosenzweig wrote a
  VDM tessellation path and removed it on 2024-10-26 (Mesa a7843643c6c):
  a couple of percent on terraintess, slower than the compute path on
  Sascha Willems' other tessellation demo. It can't do isolines, point mode,
  transform feedback or geometry shaders, all of which Vulkan needs and
  Metal lacks.
- **64-bit atomics are min and max only.** Under 64-way contention, 64-bit
  `atomic_max` runs at 16.6 G/s, the same as 32-bit, so it is native. Metal
  rejects 64-bit add, exchange, compare-exchange and or.
  `VK_KHR_shader_atomic_int64` and `VK_EXT_shader_image_atomic_int64` need
  all of them, so Vulkan can't expose what the hardware has. That is why
  Nanite's 64-bit image atomics work under Metal on M2 and not here.
- **Most missing features have no dedicated hardware on G14.** Mesh shaders,
  ray tracing and simdgroup matrices are compiler and compute work in Metal
  too, so Mesa could match them in software.
- **Pixel-ordered sync is in the hardware.** Mesa already emits `wait_pix` and
  `signal_pix` for blending, so fragment shader interlock is a missing
  feature, not missing silicon. Barycentrics likewise: the compiler already
  interpolates pull-model.

## Where Linux can beat Metal

- **API reach.** Geometry shaders, transform feedback, isolines, logic ops,
  wide lines and BC/ETC2/ASTC together run under Vulkan and GL here. Metal
  has none of the first five.
- **Independent dispatches.** Honeykrisp ends every compute launch with a
  CDM barrier. Vulkan only orders dispatches across a pipeline barrier or
  event, and Honeykrisp already ends the control stream for both.
  `patches/mesa/mesa-hk-cdm-barrier-on-demand` therefore leaves the barrier
  after `vkCmdDispatch` pending. The next launch that must be ordered, or
  the end of the stream, emits it. Every internal launch is still ordered:
  meta operations, queries, the geometry and tessellation stages. Metal's
  concurrent mode shows what the hardware then costs: about 0.15 µs a
  dispatch instead of 1.3-1.5 µs. Untested on hardware; see "Testing on
  frieren".
- **The barrier itself.** `patches/mesa/mesa-agx-g14x-metal-cdm-barrier`
  already uses Metal's own bits.
- **Not measured yet:** CPU overhead per draw, shader code quality and frame
  pacing. These need the same workload timed under both systems;
  `tools/metal-probe` gives the Metal half of the dispatch and atomics
  numbers above.

## Testing on frieren

`hk-dispatch-bench` (`tools/hk-dispatch-bench`) runs the same shape as
`tools/metal-probe/dispatch`: 4096 dispatches of 4096 threads, independent
and with a barrier between each. It then checks ordering:

- **dependent:** increments through barriers add up exactly;
- **distinct:** unordered writes to separate slots all land;
- **chain:** each dispatch reads the last one's result across a barrier.

It exits non-zero on a wrong result. Under MoltenVK on macOS it passes all
three, at 1.66 µs independent and 23.75 µs dependent. MoltenVK splits its
Metal encoders at barriers, so those are not Metal's own numbers.

On frieren, after rebuilding with the patched Mesa:

```sh
nix run ./silicon-bakery#hk-dispatch-bench
# the same against nixpkgs' Mesa, for the before
VK_ICD_FILENAMES=$(echo $(nix build --no-link --print-out-paths nixpkgs#mesa)/share/vulkan/icd.d/asahi_icd.*.json) \
  nix run ./silicon-bakery#hk-dispatch-bench
```

Expect independent dispatches to fall towards Metal's 0.15 µs and dependent
ones towards 1.3-1.5 µs. A failed check means a missing barrier. Then
run the Vulkan CTS groups the patches touch (`nix shell nixpkgs#vulkan-cts`):

```sh
deqp-vk --deqp-case='dEQP-VK.compute.*'
deqp-vk --deqp-case='dEQP-VK.synchronization*'
deqp-vk --deqp-case='dEQP-VK.memory_model.*'
deqp-vk --deqp-case='dEQP-VK.query_pool.*'
deqp-vk --deqp-case='dEQP-VK.api.copy_and_blit.*'
deqp-vk --deqp-case='dEQP-VK.tessellation.*'
deqp-vk --deqp-case='dEQP-VK.geometry.*'
```

`hardware.siliconBakery.graphics.mesaPatches = false` goes back to stock
Mesa if anything regresses.

## Open

- **Lifetime servo.** `LifetimeServoFastDieTemperatureTarget` and its setter
  are `setProperties` keys, so userspace on macOS can retarget the fast-die
  loop at run time. Linux has no equivalent. Whether anything on macOS sets
  it is not known.
- **Known gaps, from upstream** (not fixed here; see also above):
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

# The Power Management Processor

The PMP is an RTKit coprocessor that macOS always runs: it manages the
fabric, memory controller and uncore power states, voting bandwidth for the
GPU, ANE and displays (its ADT node carries `agx-*`, `ane0-*`, `dcs-bw-*`
and `afi-*` thresholds). Linux leaves it idle by default. Read on 2026-11-02
from asahi-7.2.14-1, m1n1 2.0.0 and this Mac's IORegistry under macOS 27.2.

## What Linux has

- `apple_pmp` (drivers/soc/apple/pmp.rs, built in) and the PMP report power
  domains (drivers/pmdomain/apple/pmp-report.c) are in the kernel.
- The device tree only uses them when it defines `APPLE_USE_PMP`, which no
  board does. The define adds the `pmp` alias, and that alias is what m1n1's
  `dt_set_pmp` looks for: it copies the board ID, DRAM vendor and capacity
  and every property of the ADT's `/arm-io/pmp/iop-pmp-nub` (the tunables)
  into the node and enables it.
- The define also moves DCP, both external DCPs, AVD and the ISP's DART
  from their pmgr power domains onto PMP report entries, so the PMP is told
  when each block powers up or down.
- Asahi (progress report 7.0): about 0.5 W less at idle on a 14" M1 Pro,
  roughly 20 %; "not yet been validated on every machine"; opt-in until
  upstream.

## What Silicon Bakery adds

`patches/linux-pmp/dts-j414s-use-pmp`, with
`hardware.siliconBakery.power.experimentalPmp = true` (Mac14,9 only):

- `APPLE_USE_PMP` in `t6020-j414s.dts`.
- `pmp_report_isp_sys` enabled. t602x leaves it disabled and no t602x board
  turns it on, unlike the M1 Pro/Max and M2 Air boards, so with the define
  alone the ISP's DART (enabled on j414s) would wait for a power domain
  that never registers and the camera would not probe.

Compiled against the pinned tree, the device tree differs from the stock
one in exactly the alias, the five power domains and that entry.

Open on t602x:

- The PMP node has no `apple,pio-ranges` (t600x's do; t8112's do not; the
  macOS ADT has no such property), so the driver answers the firmware's
  IOVA table request empty. Whether the t6020 firmware needs MMIO ranges
  mapped is unknown.
- AVE (Silicon Bakery's `media.encode`) still uses `ps_venc_sys` directly;
  with PMP on it should report through `pmp_report_venc_sys` as AVD does.

## On the machine

Keep SSH available; a failure most likely shows as no display, or no
camera. Go back by booting the previous generation.

1. The coprocessor is up:
   ```sh
   journalctl -k -b | grep -iE 'apple.pmp|pmp-report|pmp@'
   cat /proc/device-tree/soc/pmp@28e700000/status        # okay
   ls /proc/device-tree/soc/pmp@28e700000/ | grep -c tunable
   ```
   "unknown property" lines name tunables the firmware asked for that m1n1
   did not copy.
2. Everything that moved still probes: the panel lights, `ls /dev/video*`
   lists the camera, `vainfo` lists AVD's profiles, HDMI still hotplugs.
   `cat /sys/kernel/debug/pm_genpd/pm_genpd_summary | grep pmp` shows the
   report domains switching on and off.
3. Idle power on battery, a minute each way, with and without the option:
   `for i in $(seq 60); do cat /sys/class/power_supply/macsmc-battery/power_now; sleep 1; done | awk '{s+=$1} END {print s/NR/1e6 " W"}'`.
   Asahi's M1 Pro figure was about 0.5 W lower.
4. Suspend and resume once, then repeat 2.

# Palm rejection

How macOS keeps palms off the Mac14,9's trackpad, and how Silicon Bakery
gets Linux to do the same. Read on 2026-11-02 from MultitouchSupport and the
multitouch kexts of macOS 27.2 (symbols and disassembly; no Apple code is
reproduced here).

## How macOS does it

Mostly in the trackpad. Every 30-byte contact record the trackpad's
firmware sends begins with four bytes: the contact's id, its state
(hovering, touching, lifting), **which finger it is** (1 thumb, 2 index,
3 middle, 4 ring, 5 little) and which hand. MultitouchSupport copies them
into each contact as it parses a frame (`mt_FillMTContactDirectFromBinary`),
and the gesture layer rejects every contact whose identity is not a finger
(`_mthid_pathWasRejected`: identity below 1 or above 5). The firmware sees
the whole 24 x 18 capacitance image and identifies fingers from it, which is
why a resting palm never moves the pointer however it lands.

The identities, as HSTouchHIDService (the built-in trackpad's gesture
engine) reads them: 0 not yet identified, 1 thumb, 2 to 5 fingers, 6 to 11
palm, 12 to 14 a contact along the edge (14 a thumb there), 15 ignored. Only
1 to 5 point, tap, scroll, gesture or count for a click; edge contacts may
still press the button.

The host adds no palm rules of its own: no zones, size limits or typing
timers, and no keyboard input reaches the engine at all. It adds two things:

- **Resting**: at most one finger a frame, the one nearest the front edge,
  is marked resting (bit 9 of the digitizer event mask,
  `_mthid_pathIsResting`) while it lies in a strip along the front edge
  (12 to 20 mm deep, growing with its size and how long after the other
  finger it landed), unless the other finger is beside it or it landed high
  on the pad; or while the button is held. It stops resting when it moves
  along with the other finger. A resting finger moves nothing and counts for
  nothing, so a thumb on the click area while the index finger points is
  ignored.
- **A lonely thumb** rule for a thumb on its own.

Linux never had any of this: hid-magicmouse kept those four bytes as
`unknown1` and `unknown2` and dropped them, so libinput had to guess palms
from size and position alone.

## What Silicon Bakery does

1. `patches/linux/hid-magicmouse-mtp-palms-from-firmware`: contacts the
   firmware identifies as something other than a finger are reported as
   `MT_TOOL_PALM`, which libinput ignores as palms (and takes back if the
   firmware changes its mind). `hardware.siliconBakery.trackpad.firmwarePalms`:
   "identified" (default), "macos" (also contacts the firmware has not
   identified, exactly as macOS, once a recording shows it identifies every
   finger under Linux), or "off".
2. `patches/linux/hid-magicmouse-mtp-hundredths`: distances in the units the
   firmware means, so libinput's mm thresholds are right.
3. `patches/libinput/0006-macos-resting-finger`: macOS's resting finger, as
   above. With a kernel that reports the firmware's palms (the default), the
   strips of `0001-typing-palms` (side strips after typing, the bottom strip)
   stand down, since macOS has none; `0001` still keeps typing from freezing
   the pointer.
4. The measured palm sizes as libinput quirks (`profiles/<model>/linux.json`).

## Checking it against macOS

`tools/mt-probe` records the firmware's identity for every contact
(`finger` and `hand`) with its shape, place and travel, and when keys go
down; `analyse.py` writes one row per contact
(`<recording>.touches.csv`) with macOS's verdict and what the bakery's rest
zones would decide, and tables where they disagree.

On frieren, `bakery-trackpad palms` shows libinput's palm decisions live
(a firmware palm shows as "tool-palm"), and `bakery-trackpad record` keeps
a session that went wrong for `libinput replay`.

Recorded under macOS from the same firmware, identity 0 never came with a
touching contact (0 of 9308 frames), only with contacts coming into range,
so `firmwarePalms = "macos"` (the default) is macOS exactly. Identities do
change during a touch (thumb and index, palm and edge), which libinput
follows. Not yet checked on the machine: the resting rules against macOS's
`NSTouch.isResting`.

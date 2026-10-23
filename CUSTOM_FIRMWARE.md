# PGB-1 custom firmware

Experimental custom firmware based on upstream commit
`ad0fc62` of [WNM-PGB1-firmware](https://github.com/wee-noise-makers/WNM-PGB1-firmware).
The upstream GPL-3.0 license applies.

## What is implemented

Tracks **1–8** have the same capabilities and default configuration.
Each starts as a Lead synth with normal fixed-note steps. In **Track settings →
Track mode**, select an internal synth family, sample playback or external MIDI.
The eight choices are MIDI, Sample, Kick, Snare, Hi-hat, Bass, Lead and Chord.
FX track modes are unavailable on tracks 1–8. **Track Mode is page 2** for every
track mode.
Synth/sample tracks show Engine first; MIDI/FX tracks show default parameters
first. Then select the engine and its parameters.
The instrument numbers 1–8 no longer determine the instrument. Tracks **9–16**
retain their original roles: 9 Reverb/MIDI, 10 Overdrive/MIDI, 11 Bitcrusher/MIDI,
and 12–16 MIDI only. Their original default FX parameters and MIDI channel
defaults are retained. Earlier custom projects that assigned synth/sample modes
to tracks 9–16 load with these reserved roles restored. Earlier FX assignments
on tracks 1–8 load as Lead; other settings and step data are retained.

Tracks have independent engine, sample, volume, pan, LFO and arpeggiator settings.
The internal audio engine has **eight track voices**, allocated when notes play.
Each of the eight instrument tracks can use a voice. MIDI tracks and FX control
tracks do not consume internal voices. A chord-engine voice retains its existing
four-note polyphony.
CPU capacity also depends on engine selection and still needs hardware testing.

The existing Bass/Lead choices remain available. Older Sample 1/Sample 2
assignments both load as the single **Sample** mode. FX remain global buses
controlled by tracks 9–11; instrument tracks can use their existing FX sends.

### Eight independent sample tracks

Select any instrument track (1–8), set **Track mode → Sample**, then choose its sample
using the **Sample** parameter (CC default A) with Up/Down. Repeat for up to
eight tracks. Each has its own sample selection, playback position, pitch,
start, release, volume and pan. All eight can play different samples at once.
The sample library still holds 64 samples; eight is the simultaneous internal
track-voice limit, shared with synth tracks.

Switching a synth/MIDI track to Sample selects the first populated sample and
sets Start and Drive to zero. Existing step parameter locks still override track
defaults. The instrument mixer displays track numbers 1–8. FX and MIDI settings
on tracks 9–16 remain available through their existing controls.

### Custom chord progressions

1. Enter Song mode and select one of the four chord progressions (13–16).
2. On the chord's own settings page, highlight its preset/scale name between
   the tonic and duration.
3. Select **Custom** with Up/Down (after the final preset, or Down from the first
   preset) and press **A** to edit that chord's notes. The touch strip can also
   select Custom at its upper end.
4. Inside the editor, Left/Right selects one of the four notes; Up/Down and the
   touch strip edit its pitch. **A** advances to the next chord and wraps around.
5. Press **B** to return to that chord's preset/scale selector. Edits are kept.
   Add/remove chord slots and set durations using the existing progression
   controls. The Magic Hat scale selector also offers Custom for editing the
   whole progression.

Each chord can contain four explicit MIDI pitches, including different octaves,
inversions and repeated notes. Pitches are not constrained to a scale. Switching
to Custom and opening the editor copies each preset chord as an editable
starting point, preserving notes that are already custom. The custom-note pages
are separate from the main Left/Right sequence. Selecting a preset name returns
that chord to preset playback; generating a preset progression replaces the
custom progression.

Chord steps, Note-in-chord steps and chord-following arpeggios use these explicit
notes. The four-note limit comes from the existing chord data and voice design.

### Custom arpeggiator notes

In Track settings:

1. Set **Arpeggiator notes** to **Custom notes**.
2. Set **Custom arp length** to 1–16.
3. On **Custom arp note**, A selects the next note and B the previous note.
   Up/Down and the touch strip edit its MIDI pitch.
4. Enable Arpeggiator note mode on the desired sequencer steps.

Up plays the list in entry order; Down reverses it. Up/Down and Random use the
whole list. The three original fixed patterns retain their four index positions,
wrapped into the configured list when it has fewer than four notes.
Selecting **Notes of chord** restores progression-following behavior, including
custom chord notes. Track and step octave offsets still apply.

### Live note recording

1. Select the destination track in Track or Step mode.
2. Set **Live record quantize** in Track settings.
3. Start playback with Play.
4. Start with the Rec LED off, then hold Rec until the chromatic keyboard
   appears. Rec press arms recording; the long press exposes the keyboard.
5. Play the keyboard while holding Rec. Release Rec to leave the keyboard;
   tap Rec to disarm recording afterward.

Recording writes into the selected track's **playing pattern and step**, including
linked patterns, rather than the previous edit cursor. Notes are monitored
immediately. While stopped, recording writes to the selected step.

With quantize **On**, notes snap to the start of the currently playing sixteenth
note cell (downward quantization). With quantize **Off**, onset offsets are saved
at 1/128 of a cell and replayed through the existing short-term scheduler.
At 120 BPM that stored resolution is about 0.98 ms; actual playback timing also
depends on the sequencer and audio buffers.

The step architecture stores **one pitch per track per cell**. A second note in
the same cell replaces the first. The cell's existing gate length and parameter
locks remain editable in Step settings. Key-release timing and arbitrary
polyphonic performances are not recorded. Shuffle is applied in addition to a
recorded onset offset.

## Project files

Custom projects use format version 2. The loader accepts stock version 1 files
and migrates their old fixed track assignments. Custom modes, chord notes,
arpeggiator lists, recording quantization and step onset offsets are saved.
Stock firmware cannot read version 2 projects. Keep copies of stock projects
before saving them with this firmware.

## Building on Windows

For a fresh checkout, install Git and Python 3, then run:

```powershell
./scripts/setup-windows.ps1
./scripts/build.ps1 -Target all -Python python
```

You can pass the full path to an existing Python executable. The setup script
installs Alire 2.1.1, native GNAT 16.1.0, GPRbuild 26.0.1, the ARM GNAT 14.2.1
toolchain required by the SDK, MSYS2 audio/MIDI libraries and CSFML 2.6.1.
Downloaded tools are stored locally under `.tools` and are excluded from Git.
Synth, SDK and ROM-tool source revisions are pinned in the Alire manifests.

Build targets are `device`, `simulator`, `tests` and `all`. Generated files:

| File | Purpose |
| --- | --- |
| `artifacts/pgb1-cfw.uf2` | Code-only RP2040 firmware image |
| `artifacts/pgb1-cfw.elf` | Linked firmware with symbols |
| `artifacts/pgb1-cfw.bin` | Raw flash code image |
| `simulator/bin/wnm-pgb1-simulator.exe` | Windows simulator |
| `simulator/bin/wnm-pgb1-rom-tool.exe` | Factory ROM/filesystem tool |
| `simulator/bin/cfw-tests.exe` | Regression test executable |

The device script normally uses `alr build --release`. If Windows rejects the
compiler's `collect2` helper, it uses the compiler-generated link plan with GNU
`ld` directly. It does not change Windows security settings. UF2 conversion
checks that the code image stays within the existing 1 MiB code partition.

Double-click **Run Simulator.cmd** in the repository folder. It sets the working
directory and starts the simulator with its own custom ROM file. The Windows
build script bundles all seven required non-system DLLs beside the executable
in `simulator/bin`; no PATH changes or system-wide DLL installation are needed.

Alternatively, start it from PowerShell:

```powershell
./scripts/run-simulator.ps1
```

This launcher uses `artifacts/pgb1-cfw-simulator.rom`. The ROM is separate from any
stock simulator project storage. The existing simulator keyboard layout and
controls are unchanged.

For an older build that does not have DLLs in `simulator/bin`, run
`./scripts/copy-simulator-dlls.ps1` once. Keep the repository's `simulator/share`
folder alongside `simulator/bin`, since it contains the interface resources and
factory samples. Copying just the EXE to another folder is insufficient.
The double-click launcher and regression executable were also verified with
only Windows directories on PATH, using the bundled DLLs.

Build and run regression tests:

```powershell
./scripts/build.ps1 -Target tests -RunTests -Python python
```

Tests create a fresh in-memory filesystem. They cover bounded allocation,
audio rendering across tracks 1–8, track routing, reserved FX/MIDI roles,
eight distinct simultaneous samples on tracks 1–8, Custom-scale editor
navigation, arbitrary chord notes, arpeggiator lengths and directions,
recording position and timing, v2 persistence, and legacy mode migration. A Linux CI
workflow is included to build and run them under Xvfb.

## Validation status

Firmware and simulator compilation/linking were completed in this workspace.
The firmware fits the RP2040 RAM and existing code partition. Build metadata,
memory use and artifact hashes are recorded in `artifacts/build-report.json`.

After Windows application control was unblocked, the native regression suite
passed with exit code 0. All internal instrument families rendered successfully.
Eight nonempty sample fixtures played simultaneously with independent output
on tracks 1–8; their assignments also survived saving/loading. Tests verify that
tracks 1–8 cannot select FX modes and tracks 9–16 retain their original FX/MIDI
roles, including legacy project loading.
Menu event tests verified Custom in the chord's own preset list, A to open the
selected chord's editor, note edits, advancing chords and B to return, plus
Track Mode on page 2 in all 11 modes and access to all eight mixer tracks.
The simulator loaded the factory sample/project ROM, opened its window and
initialized audio without exceptions. No physical MIDI devices were connected.

Listening tests, manual UI interaction, external MIDI and physical device
operation still need validation. The Linux CI workflow has not been run here.
The supplied UF2 remains an experimental build until hardware testing is done.

The UF2 contains firmware code only. It does not include factory filesystem or
sample images. Use the existing PGB-1 firmware update procedure after validating
the build and keeping a copy of your projects. This work did not flash a device.

# brWave — Project Memory

State file for session continuity. Update at end of each session. This is the quick-start reference for a fresh conversation.

---

## Current State (2026-04-11)

**Phase**: Session 9 handoff state. Full patch format ecosystem import is running. We successfully closed out the vintage PPG Wavetable ROM extraction—ensuring perfect 128-sample AIFF exports utilizing the authentic "back-to-front phase inverted" mirroring logic. The task now shifts toward closing the *export* loop, making brWave the ultimate Universal Bridge.

**New since Session 8 (this session):**
- `docs/ppg_wavetable_rom_mechanics.md` — NEW: Architectural archive detailing the 64-byte half-cycle compression, the phase-inverted mirroring interpolation, and the authentic hardcoded 8-bit integer overflows found in the real PPG ROMs.
- `make_aiffs.py` / `PPG_AIFFs/` — Successfully generated perfect baseline AIFF files from the 30 extracted ROM arrays for Hibiki testing.
- `V8Importer.swift` — PPG Wave V8x SysEx bank importer (F0 29 01 0D, nibble-encoded), wired into import menu (done out-of-band by Claude, integrated fully here).

**What exists:**
- `CLAUDE.md` at project root — full technical briefing, read first
- `brWave_bible.md` at project root — dev journal
- `docs/memory.md` — this file
- `docs/EDITOR_STARTER_KIT.md` — architectural guide from OBsixer project
- `docs/ppg_wavetable_rom_mechanics.md` — Detailed breakdown of PPG wavetable architecture and EPROM interpolation tricks
- `docs/FXB_ANALYSIS.md` — THE Rosetta Stone for FXB/V8 conversion. Contains the 1:1 Float Index -> Behringer byte map. (READ THIS before building importers)
- `docs/w23_fact.wav` — Original PPG 2.3 factory cassette dump.
- `docs/PPG SYSEX__but not really.html` — Narkive thread discussing the "editor vs librarian" challenge for PPG SysEx.
- CoreData `Patch`, `PatchSet`, and `PatchCategory` models functionality ported.
- `WaveSysExParser.swift` and `WaveSysExImporter.swift` implemented for 121-byte `.syx` files.
- `V8Importer.swift` — imports PPG Wave V8x `.syx` bank files (F0 29 01 0D format, nibble-encoded)
- `WaldorfImporter.swift` — imports Waldorf PPG Wave 3.V `.fxb` bank files AND `.fxp` single presets
- `WaldorfExporter.swift` — exports patches as Waldorf PPG Wave 3.V `.fxb` bank files
- `WaveTables.swift` contains the factory wavetable set as 64 waves × 128 samples per table for editor/display use.
- `Patch+Generation.swift` available to instantly populate test `.syx` patches by Category.
- `PatchNamesSheet.swift` — "Apply Names from Clipboard" sheet (fuzzy paste parser for manual/web patch lists)
- `Theme.gridBackground` — dark navy for bank grid (separate from PPG blue panelBackground)
- `SampleMapperModels.swift` — sample-zone data model, notes, loop points, and auto-mapper
- `SampleMapperState.swift` — file/folder import, root-note detection, waveform cache, zone editing state
- `SampleMapperView.swift` — new `Samples` workspace UI
- `ContentView.swift` — new top-level `Samples` mode in the app mode picker
- Waveform strip above the keyboard for the selected sample
- Inspector payload for sample/session metadata in Samples mode
- Mapper state now survives switching away from Samples and back
- Waveform zoom and pan both exist; pan is usable but still slightly jittery
- Root conflict prompt exists when filename note and analyzed pitch disagree
- Zone bars can select samples directly
- Keyboard/zone layout has been substantially improved from the first pass
- Loop handles are in decent shape for a first pass
- There is active local work in `SampleMapperView.swift` from the interrupted Antigravity session; do not overwrite it blindly

**What's next from here:**
1. **Playback path**:
   - implement keyboard-triggered sample playback from the on-screen keybed
   - sample playback is anchored to the root key
   - non-root keys transpose playback from the root
   - add mini-toolbar control for play-through behavior
   - try Core Audio/Core AV path first; if insufficient, build a dedicated playback engine
2. **Waveform redraw**:
   - current filled waveform style is not right for editing use
   - redesign drawing to be more informative and better suited to loop/sample editing
3. **Waveform interaction pass**:
   - keep pan smooth with zoom
   - stop pointer interaction from getting trapped when crossing loop points
   - keep zoom centered around the pointer where possible
4. **HUD cleanup**:
   - keep heads-up values from colliding
   - keep label/value pills on one line with reserved width
5. **Auto-map cleanup**:
   - validate duplicate-root handling
   - eliminate remaining visible/playable overlap in crowded groups
6. **Keyboard polish**:
   - continue black-key proportion tuning
   - later add keyboard viewport shifting across broader MIDI range
7. **Hibiki integration path**:
   - port the internal sample/wave model from Hibiki
   - port parsers and writers from Hibiki where not already moved
   - assume some of this may already be partially present; verify before redoing
8. **Project/layout persistence**:
   - create a proper mapper layout/project file similar to the Nord project-file pattern
   - autosave should be near-transparent and happen continuously in the background
   - explicit Save should promote to a user-named file
   - new saves should create new files rather than overwriting prior ones
   - catastrophic-loss protection matters more than full undo initially
9. **Then resume headline work**:
   - wavetable view remains the signature brWave feature after the mapper stabilizes

**V8 partial map (implemented in V8Importer.swift):**
See `docs/FXB_ANALYSIS.md` Session 6 for the full table. Summary:
- Confirmed (r≥0.9): V8[3]=VCF_CUT, V8[7]=ENV1_DEC, V8[9]=ENV2_SUS, V8[11]=LFO_DELAY, V8[17]=KL, V8[21]=SEMIT (all voices)
- Moderate (r 0.65–0.9): V8[2]=WAVES_OSC, V8[14]=WAVES_SUB, V8[15]=UW, V8[16]=TM
- Scale rule: Beh 0-63 params = V8÷4; Beh 0-127 params = V8÷2
- NOTE: VCF_CUTOFF is 0–63 range (Session 5 table had this wrong as 0–127)
- ~39 of 51 V8 positions still unmapped — needs waveprog.exe on Windows to complete

**FXB files available in docs:**
- `docs/PPGwave-ProSounds-DemoBank.fxb` — additional test bank
- `docs/PS_PPGWave_1984Demo/FXB Format/PS-PPGwave2v-1984Demo.fxb` — 2.V format (339 floats)
- `docs/PPG_Wave_3.V_Presets/PPG Wave 2.V Factory Soundsets/` — 8 banks × 137 patches each (~1096 patches)
- `docs/PPG_Wave_3.V_Presets/PPG Wave 2.3 Hardware Unit Soundset/PPG Wave 2.3 Hardware Unit Bank.fxb` — 128 patches, same as Behringer Bank 1 (anchor set for correlation)

---

## Key Technical Facts (quick ref)

- **Behringer Wave**: 8-voice, wavetable + analog VCF, 2 banks × 100 programs, 2 sounds per patch (Group A/B)
- **SysEx**: raw bytes, no MS-bit packing. Mfr=`00 20 32`, Model=`00 01 39`, DevID=`00`, PKT=`0x74`
- **Preset**: 120 bytes. Name at bytes 0–15. Group A: bytes 16–69. Group B: bytes 70–120. Checksum=(sum)&0x7F
- **NRPN**: 3-msg format: `Bn 63 00`, `Bn 62 ParNum`, `Bn 06 Value` (ParNum 0–46)
- **Wavetable SysEx**: already in `AudioMorph/AudioMorph/WaveTable/Synths/BehringerWave.swift`

---

## Product Vision: PPG/Wave Ecosystem Hub

brWave is not just a Behringer editor — it is the glue between:
- **Behringer Wave** hardware (MIDI control + SysEx patch management) ← primary
- **Waldorf PPG Wave 3.V plugin** (FXB import/export — share patches with plugin users)
- **Original PPG Wave 2.x hardware** (V8 firmware SysEx — patch, lib, and control real PPG hardware)

Full bidirectional format support is the goal:

| Direction | Behringer .syx | Waldorf .fxb | PPG V8x .syx | PPG live MIDI |
|-----------|---------------|-------------|-------------|---------------|
| Read | ✅ done | ✅ done | ✅ done | 🔲 planned |
| Write | ✅ done | ✅ done | 🔲 partial | 🔲 planned |

Key export tasks to build (priority order):
1. **V8 .syx export** — Behringer → nibble-encoded V8 bank (reverse Pearson scaling calculations).
2. **Waldorf FXB Export validation** - Ensure the WaldorfExporter maps Behringer back to the unscaled FPCh float indices identically.
3. **PPG live MIDI** — PPGMIDIController targeting mfr ID 0x29, using V8 SysEx transmission format.

---

## Decisions Made

- **Headline feature**: wavetable view — send custom WTs to hardware + visual display of current patch's WT
- **Group A/B**: A/B toggle (not side-by-side). Diff arc on knobs shows inactive group value as ghost arc.
- **Incoming A/B MIDI**: Group Select is plain `CC 31`, with `0 = A`, `1 = B`, and `2 = A+B`; in A+B mode incoming panel CCs should update both groups.
- **PPG blue**: approximate OK, will tune visually. Start with `Color(red: 0.08, green: 0.25, blue: 0.75)`
- **Wavetable scope**: send = yes. Pull from hardware = TBD. Generation tools = highly likely later (easy to add given sidebar/detail/inspector layout). Don't replicate Hibiki's full editor.
- **Patch import order**: Behringer SYX native first → PPG Wave 3.V (Waldorf virtual) second
- **FIRM for imports**: default to FIRM=0 (compatible), let user change
- **App layout**: sidebar / detail view / inspector — standard pattern across the series. Wavetable generators would slot into this layout easily when the time comes.
- **Samples workspace**: sample/transient mapping lives as a full workspace, not a patch-editor subpanel.
- **Waveform placement**: selected sample waveform belongs above the keyboard map.
- **Inspector usage**: the third panel should actively support the mapper, not sit mostly idle.
- **Playback split**: key playback should be straight-sample playback for now; loop playback belongs to the loop editor.
- **Playback model**: clicking a key should play the mapped sample; transposition is relative to the root key.
- **Zone philosophy**: clean butt-joint zones are preferred over forcing the root note to remain inside the playable span.
- **Terminology direction**: user-facing language will likely move from `Samples` toward `Transients` for brWave.
- **Shared-code direction**: the mapper is being incubated in brWave but is intended to port to Sledgitor, Hibiki, and later shared-library code.
- **Reference-doc priority**: prefer `*.llm.md` files over raw PDFs because MDRxp OCR/prepares them for model use.
- **Naming note**: older references to `AudioMorph` often now mean `Hibiki D`.
- **Arp/Seq direction**: plan for an Arp panel and a brWave-native 64-step sequencer with MIDI-note transposition. OBsixer can donate proven mechanics, but this should be its own design. Keep a native/raw Wave step-seq mode available because retrieved Wave sequences may not conform cleanly. Hardware sequence storage appears to be one sequence per patch, so model sequence data as patch-attached first.
- **Arp panel parameters**: include SynthTribe-style Mode A/B, clock source/rate, clock division, gate, tempo, metronome, overdub, and key transpose controls.

---

## Reference Paths

| What | Path |
|------|------|
| OBsixer (main reference) | `/Users/rob99/Development/Swift/swiftUI/OBsixer/OBsixer/` |
| Sledgitor | `/Users/rob99/Development/Swift/swiftUI/Sledgitor/Sledgitor/` |
| Wave wavetable SysEx | `/Users/rob99/Development/Swift/swiftUI/AudioMorph/AudioMorph/WaveTable/Synths/BehringerWave.swift` |
| Manual | `brWave/docs/Manual_BE_0722-ABD_WAVE.pdf` |
| Starter kit guide | `brWave/docs/EDITOR_STARTER_KIT.md` |

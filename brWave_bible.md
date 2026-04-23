# brWave — Dev Journal & Project Bible

**App name: brWave. Don't change it.**

This is the living development journal and source of truth for the brWave project. Update it at the end of every session.

---

## What This Is

brWave is a SwiftUI macOS patch editor for the Behringer WAVE synthesizer — a PPG Wave clone with 8-voice wavetable synthesis, analog VCF/VCA, 3 envelopes, arpeggiator, and sequencer. Third in a series after Sledgitor (Waldorf Sledge) and OBsixer (Sequential OB-6).

Reference projects:
- OBsixer (cleanest): `/Users/rob99/Development/Swift/swiftUI/OBsixer/`
- Sledgitor: `/Users/rob99/Development/Swift/swiftUI/Sledgitor/`
- AudioMorph/Hibiki (wavetable tools): `/Users/rob99/Development/Swift/swiftUI/AudioMorph/`

---

## Product Philosophy

Unlock what the hardware can do that players don't know about. Not a generic librarian. Features ship only if they'd get personal use. The Wave's personality is its wavetable system — that's what we build around.

---

## Current State

**Session 1 (2026-03-30): Project initialized, documentation created.**

Built this session:
- `CLAUDE.md` — full technical briefing
- `brWave_bible.md` — this file
- `docs/memory.md` — state memory

Nothing else yet. Bare Xcode template.

**Session 6 (2026-04-04): Sample Mapper first pass landed.**

Built this session:
- Added a new top-level `Samples` workspace in `ContentView.swift`
- Added `SampleMapperModels.swift` for sample formats, notes, zones, loop points, and auto-mapping
- Added `SampleMapperState.swift` for import, folder scan, root-note detection from filenames, auto-zoning, and waveform caching
- Added `SampleMapperView.swift` with:
  - import files / import folder actions
  - sample list
  - waveform strip above the keyboard
  - keyboard zoning preview
  - zone editor for root / low / high key
  - basic loop start / end editing
  - inspector content for session and selection details
- Confirmed the first visual pass is working in-app with real sample sets

Current quality:
- Good first-pass workflow and layout
- Filename-based root-note detection is working well for named samples
- Waveform display is live for AVFoundation-readable files
- Loop visualization exists, but handle interaction still needs refinement
- Broader format support should be pulled from Hibiki next

**Session 7 (2026-04-04): Sample Mapper interaction pass in progress.**

Built this session:
- Moved Sample Mapper state into the app workspace so switching away from the view no longer clears the imported sample set
- Added waveform zoom state, pan state, and a new native interaction capture layer for waveform gestures
- Reworked waveform drawing from simple vertical sticks toward a filled envelope display
- Added root-conflict detection between filename note and analyzed audio pitch, with a user-facing resolution prompt
- Added more active inspector support, including path privacy/display controls
- Reworked the keybed and zone display for better readability
- Made zone bars clickable so selecting a zone selects the matching sample
- Continued tightening zone geometry and lane assignment to reduce false visual overlap

Current quality:
- The mapper is clearly usable and now survives view switching
- Keyboard readability is much better than the first pass
- Waveform zoom is partly working, but pan and loop-handle interaction still need another pass
- Auto-map logic around duplicate or tightly packed roots still needs more validation
- Heads-up display is much closer, but still needs final collision/layout polish
- Hibiki remains the right next source for mature waveform interaction behavior

---

## Architecture Decisions

### Headline Feature: Wavetable View
The Wave's identity is its wavetable. The headline feature is a **wavetable view** that:
1. Sends custom wavetables from brWave to the hardware (already proven in Hibiki — port `BehringerWave.swift`)
2. Displays the current patch's wavetable visually (64 waves as waveform images)
   - If we can pull wavetables FROM the Wave: show them live
   - If not: record audio out of the Wave (as done for Sledgitor) to generate static images
3. May add wavetable generation tools (similar to Hibiki's NeuronGenerator, SuperWave, Vector) — highly likely, scope TBD

**Scope boundary**: don't replicate Hibiki's full wavetable editor — that would diminish Hibiki. brWave's wavetable view is patch-centric. Deep generation/editing stays in Hibiki.

**Adding generators later is low-risk**: All apps in the series use sidebar / detail / inspector layout. Hibiki's wavetable generators would slot naturally into this structure as a detail or inspector panel view. No need to pre-architect for it — add when scope is decided.

**Wavetable display**: If we can't pull wavetable data from the Wave (not documented in the manual — may be impossible), displaying the actual wavetable in use becomes difficult. Options:
1. Record audio out of the Wave for each factory wavetable and use those as static images (Sledgitor approach)
2. Display only the wavetable NAME and POSITION (numeric), no waveform image
3. Bundle static images of all 32 factory wavetables (record once, ship with app)
Decision deferred until we confirm whether pull is possible.

This is what makes brWave more than SynthTribe. It puts the wavetable system front and center.

### Group A / Group B Panel
Every Wave preset has two full sounds (Group A + Group B). **Decision: A/B tab toggle** — side-by-side ruled out as too visually dense.

**Diff arc concept**: knobs in Group A view show a secondary (dimmer) arc indicating the Group B value for that parameter. This gives an instant visual diff without switching views. Implement as an optional second arc in `WaveControls.swift` — primary arc = active group, ghost arc = inactive group. Color TBD (probably dimmer version of the highlight color, or a neutral grey).

**Incoming MIDI group select**: the hardware sends Group Select as plain Control Change `CC 31`, not NRPN and not a SysEx offset. Values observed and documented in the Wave manual:
- `CC 31 = 0`: edit Group A
- `CC 31 = 1`: edit Group B
- `CC 31 = 2`: edit Group A+B together

When `CC 31 = 2`, incoming panel-control CCs should update both stored group values. Do not infer A/B behavior from the panel UI toggle alone; the synth has its own live edit target.

### Bank/Program Layout
- 2 banks × 100 programs = 200 slots
- Bank 0 = Behringer sounds, Bank 1 = classic PPG Wave programs
- Position math: `position = bank * 100 + program` (0–199)
- BankMemoryView will be a 2-row × 100-column grid (or 10×10 per bank)

### SysEx: No MS-bit packing
The Wave uses raw bytes with a simple checksum — completely different from Sequential's 8-byte block packing. This makes the parser much simpler than OB6SysExParser.

### NRPN: 3-message format
```
Bn 63 00       (CC99, MSB always 0)
Bn 62 ParNum   (CC98, 0–46)
Bn 06 Value    (CC6, 0–127)
```
No CC38 (LSB data) unlike OB-6.

### Arp / Sequencer Plan
Plan for a dedicated Arp panel plus a fuller sequence editor.

- The Arp panel should cover the Wave's live arp/seq controls: state, mode, clock source/rate, gate, division, tempo, metronome, overdub, and key transpose.
- Match the SynthTribe parameter breakdown for the Arp panel:
  - Mode A: Sequencer, Arpeggiator 1, Arpeggiator 2
  - Mode B: Up, Down, Up & Down, Random, Moving
  - Clock Source: Internal, DIN MIDI, USB MIDI, Analog Trigger
  - Clock Rate: 1 ppqn, 2 ppqn, 24 ppqn, 48 ppqn
  - Clock Division: 1/4 Note, 1/8 Note, 1/16 Note, 1/32 Note, 1/4 Note Triplet, 1/8 Note Triplet, 1/16 Note Triplet
  - Gate, Tempo, Metronome, Overdub, and Key Transpose
- The brWave sequencer should be its own design: 64 steps, with transposition based on incoming MIDI note. OBsixer can donate proven interaction mechanics, but it is not the design target.
- Do not assume the Wave sequence payload conforms cleanly to the OBsixer model. Retrieved Wave sequences may need to be shown in a native/raw step-seq mode first.
- If we add an OBsixer-style editor, treat it as a conformed/editor mode with explicit conversion rules, not as the only representation.
- Preserve the raw Wave sequence data when possible so importing a sequence never silently loses hardware-specific behavior.
- Hardware sequence storage appears to be one sequence per patch. Model retrieved sequence data as patch-attached first; any larger sequence browser/library should be an app-side convenience that can write into the selected patch's sequence.

---

## Critical Layout Rules

*(None yet — will be populated as panel work begins)*

---

## Hard-Won Lessons (from OBsixer / Sledgitor)

1. **Section padding must be identical across all style variants** or controls shift when switching styles. Always verify before calling done.
2. **Prefer `fixedSize` over hardcoded heights** for content rows.
3. **Every struct using environment values needs its own `@Environment` declaration** — they don't inherit.
4. **Don't change enum rawValues** — they are `@AppStorage` keys.
5. **Ask before structural layout changes** — cascading effects everywhere.
6. **Knob width must be ≥ label width** or text clips.

---

## Session Log

### Session 7 — 2026-04-04

**What was done:**
- Persisted sample-mapper state across app mode changes by moving ownership of `SampleMapperState` up into `ContentView`
- Added waveform zoom and pan state to the mapper
- Replaced the simple stick-style waveform with a filled envelope display
- Added an AppKit-backed waveform interaction layer for zoom/pan experiments
- Added root-conflict detection between filename-derived pitch and analyzed pitch
- Added a settings preference for inspector path display plus an expandable path row
- Made zone bars clickable and selection-aware
- Reworked zone lanes so non-overlapping ranges can share a row instead of always alternating
- Continued tuning keyboard proportions and black-key geometry
- Began shifting zone geometry from rough width estimates toward note-boundary-based positioning

**What is working now:**
- Import files/folders
- Sample mapper state survives switching away from Samples and back
- Root conflict prompt appears when filename and analysis disagree
- Waveform can zoom
- Zone bars can select samples
- Inspector carries much more useful state than the first pass

**What still needs attention next:**
1. Waveform interaction polish:
   - pan is still unreliable / absent in practice
   - loop handles and zoom/pan hit targets still compete
   - zoom should continue to anchor cleanly around the pointer
2. Heads-up cleanup:
   - keep HUD elements from colliding
   - keep label/value readouts on one line with stable reserved width
3. Auto-map cleanup:
   - validate duplicate-root handling
   - eliminate remaining visual/playable overlap in crowded groups
4. Keyboard polish:
   - continue black-key proportion tuning toward a more realistic piano ratio
   - later add keyboard viewport shifting for wider MIDI range
5. Hibiki integration:
   - bring over the mature waveform zoom/pan/detail behavior rather than continuing to solve it piecemeal here

**Decisions clarified this session:**
- Key playback should be straight sample playback only for now
- Loop playback belongs to the loop editor, not the keybed audition path
- Clean butt-joint zones matter more than forcing the root note to stay inside the playable span
- The mapper architecture should stay universal so it can later move into Sledgitor and other sample-capable apps
- User-facing terminology in brWave will likely shift from `Samples` toward `Transients`, matching PPG/WAVE language

### Session 6 — 2026-04-04

**What was done:**
- Started the universal sample keymapper as a real top-level `Samples` view in brWave
- Implemented support scaffolding for `wav`, `aiff/aif`, `yaf`, `sdi`, and `sdii` as recognized target formats
- Built the first auto-map engine using filename-detected root notes plus configurable lower/upper reach
- Added a keyboard zoning view so sample ranges can be seen at a glance
- Added sample detail editing for root, low, and high key
- Added a waveform strip above the keyboard and selection-aware waveform switching
- Added a basic inspector payload so the right panel shows sample/session metadata instead of staying empty
- Verified the mapper is visually usable with a real imported sample set

**Decisions made:**
- The sample mapper should live as a dedicated workspace, not inside the patch editor
- Iterative design is expected; this feature will evolve in-place as real use reveals what matters
- The waveform strip belongs above the keyboard
- Inspector space should be used intentionally for sample/session metadata
- Hibiki is the long-term source for broader audio/file-format support and richer waveform handling

**What is working now:**
- Import sample files
- Import a whole folder recursively
- Auto-assign zones from detected note names
- Show current sample waveform
- Show keyboard map for current imported set
- Edit root / low / high values
- Basic loop start / end values

**Immediate next steps:**
1. Improve loop-handle drag behavior and visibility
2. Move more of the sample/session metadata into a stronger inspector layout
3. Pull waveform/file support from Hibiki instead of relying only on AVAudioFile
4. Add real pitch detection from audio, not just filename parsing
5. Add sample start/end support to the model, even if the synth doesn't use it yet
6. After the mapper stabilizes, begin the wavetable view work

### Session 1 — 2026-03-30

**What was done:**
- Read full hardware manual (MIDI CCs, NRPNs, SysEx format, preset data layout)
- Read Behringer Wave images — confirmed PPG blue aesthetic
- Found `BehringerWave.swift` in AudioMorph — already has wavetable SysEx encode/decode
- Read OBsixer CLAUDE.md, DEV_JOURNAL, EDITOR_STARTER_KIT
- Created CLAUDE.md, brWave_bible.md, docs/memory.md
- Set up Claude memory system

**Pending / Blockers:**
- PPG blue color needs visual tuning during panel work (approximate is fine to start)
- Wavetable pull FROM the Wave: not in manual — may be impossible. Record audio out as fallback for images.
- Wavetable generation tools: highly likely later, low effort to add (sidebar/detail/inspector fits them naturally)
- More patch files needed for Galaxy testing — user is sourcing

**Decisions made:**
- Headline feature = wavetable view (send + display)
- Group A/B panel: toggle (not side-by-side), with diff arc on knobs
- Patch import priority: Behringer SYX first → PPG Wave 3.V (Waldorf virtual) second
- FIRM=0 (compatible) for all imports by default
- Wavetable scope boundary: don't replicate Hibiki — patch-centric only
- Architecture follows OBsixer pattern closely
- 200 slot bank (2×100), not 1000 like OB-6
- Panel view: OBsixer's panel style system (profiles/styles) is more refined than Sledgitor's. Use OBsixer as the reference for the style system.
- Panel work is the hardest part of these apps. Tuning mode (wrench/grid) is dev-only — not shipped.
- Wave Sweeper (JS web tool) was the original source for the wavetable SysEx format. Hibiki's BehringerWave.swift is a port of that.

---
### Session 5: V8 Map Partial + Group B Confirmed (2026-04-02)

**What was done:**
- Extensive correlation analysis: factory23.syx ↔ Hardware Unit Bank.fxb (N=64 matched patches)
- Confirmed V8 scale: full 8-bit (0-254). Conversion: Beh = V8÷2 (0-127 params) or V8÷4 (0-63 params)
- Confirmed 6 V8 positions (see FXB_ANALYSIS.md Session 5 section for full table)
- **Group B FXB CONFIRMED**: FPCh record N+1 = Group B, SAME float index map as Group A
- Established blocker: remaining 44 V8 positions need Wine+waveprog.exe or PPG hardware
- V8 factory23 patches are in same order as Hardware Unit Bank FXB but DIFFERENT order from Behringer B1

**Key decision:** V8 importer needs `waveprog.exe` on Windows to complete. Move on.

**Pending:**
- V8 complete map: needs Wine/Windows + waveprog.exe to convert factory23.syx → WaveSim FXB
- FXB importer: Group B is now unblocked (same float map). Build next.

---

### Session 4: The Rosetta Stone Found (2026-04-01)

#### Breakthrough: FXB Float Mapping Solved
- Using targeted `.fxp` mod files (tweaking one knob at a time), we mapped the 340-float Waldorf 3.V array with 100% precision.
- **Critical Discovery**: Multitimbral FXB banks (like the PPG 2.3 Hardware set) do NOT store A and B sounds in a single float array. They store them as **separate sequential programs** in the VST bank (Program 0 = PPG 000 Sound A, Program 1 = PPG 000 Sound B).
- Behavior: Program N and N+1 represent a single Behringer Dual Patch.
- Scaling: Most continuous params (0–127) use `÷63` or `÷127` float logic. Binary toggles are `0.5 / 1.0`.
- Documented the results in `docs/FXB_ANALYSIS.md`.

#### Discovery: V8 SysEx Structure
- Analyzed `factory23.syx` (Hermann Seib V8.x dump).
- Bank size: 10,205 bytes => 5 byte header + (100 patches × 102 bytes).
- Patch encoding: 102 nibbles => **51 internal bytes**.
- **The Clue**: Behringer's standard Group A / Group B payload is also exactly 51 bytes! 
- Verdict: Behringer cloned the V8 hardware memory structure as their native 8-bit parameter block. 

#### New Forensic Assets
- `docs/w23_fact.wav`: Authentic PPG 2.3 factory cassette dump.
- `docs/PPG SYSEX__but not really.html`: Narkive thread confirms PPG SysEx was proprietary until V8.3 opened the floodgates.

#### Next Actions
- Build the `FXBImporter` using the 340-float map.
- Map the 51-byte V8 hardware order (via Hermann Seib's emulator if possible) to allow import of `.syx` legacy banks.
- Assemble the `WavePanelView` using the verified `WaveParameters.swift` offsets.

### Session 2 — 2026-03-30
**What was done:**
- Successfully completed infrastructure port from OBsixer.
- Verified Behringer Wave `.syx` patch import pipeline and `WaveSysExParser` correctness based on the 121-byte specification.
- Successfully extracted the original vintage PPG wavetables from ROM dumps (`docs/PPG Wave 2.3 version v6/w23_64.bin` through `w23_6e1.bin`)! Wrote a Python script that perfectly interpolates the "missing" wave slots logic found in the hardware.
- Exported the factory wavetable set into `WaveTables.swift` as a static `[30 tables][64 waves][128 samples]` `Int8` matrix. These entries are already complete 128-sample waves for editor/display use.
- Discovered that legacy Hermann Seib V8.x patches (`factory23.syx`) are 10,205 bytes and lack public parameter maps online. Decryption is blocked until the V8 manual is located.
- Avoided the block by writing `Patch+Generation.swift`, which outputs functionally valid 121-byte Behringer Wave patches categorized by keywords (Bass, Lead, Pad, etc.) so UI development can proceed immediately without vintage patches.

**Pending / Blockers:**
- Need the Hermann Seib V8.x SysEx extended manual from the user in order to properly translate 1980s 10KB `.syx` patch banks into the 121-byte native format.

**Decisions made:**
- Rather than waiting on legacy PPG patch documentation to build translators, we rely on the custom `.syx` Patch Generator to populate UI with test patches.

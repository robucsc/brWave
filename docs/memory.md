# brWave — Project Memory

State file for session continuity. Update at end of each session. This is the quick-start reference for a fresh conversation.

---

## Current State (2026-04-04)

**Phase**: Session 7 in progress. The Sample Mapper is now a durable top-level workspace with much stronger interaction, but waveform pan/loop interaction and crowded auto-map cases still need another pass.

**What exists:**
- `CLAUDE.md` at project root — full technical briefing, read first
- `brWave_bible.md` at project root — dev journal
- `docs/memory.md` — this file
- `docs/EDITOR_STARTER_KIT.md` — architectural guide from OBsixer project
- `docs/FXB_ANALYSIS.md` — THE Rosetta Stone for FXB/V8 conversion. Contains the 1:1 Float Index -> Behringer byte map. (READ THIS before building importers)
- `docs/w23_fact.wav` — Original PPG 2.3 factory cassette dump.
- `docs/PPG SYSEX__but not really.html` — Narkive thread discussing the "editor vs librarian" challenge for PPG SysEx.
- CoreData `Patch`, `PatchSet`, and `PatchCategory` models functionality ported.
- `WaveSysExParser.swift` and `WaveSysExImporter.swift` implemented for 121-byte `.syx` files.
- `PPGWavetables.swift` completely populated from authentic PPG Wave ROM firmware dumps.
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
- Waveform zoom path is in progress
- Root conflict prompt exists when filename note and analyzed pitch disagree
- Zone bars can select samples directly
- Keyboard/zone layout has been substantially improved from the first pass

**What's next from here:**
1. **Waveform interaction pass**:
   - get pan working reliably with zoom
   - stop loop handles and zoom/pan hit targets from fighting each other
   - keep zoom centered around the pointer
2. **HUD cleanup**:
   - keep heads-up values from colliding
   - keep label/value pills on one line with reserved width
3. **Auto-map cleanup**:
   - validate duplicate-root handling
   - eliminate remaining visible/playable overlap in crowded groups
4. **Keyboard polish**:
   - continue black-key proportion tuning
   - later add keyboard viewport shifting across broader MIDI range
5. **Hibiki integration path**:
   - pull the mature waveform zoom/pan/detail model from AudioMorph/Hibiki
   - stop solving waveform interaction piecemeal here
6. **Then resume headline work**:
   - wavetable view remains the signature brWave feature after the mapper stabilizes

**V8 partial map (confirmed positions):**
- V8[3] = VCF_CUT (A+20), Beh = V8÷2
- V8[7] = ENV1_DEC (A+17), Beh = V8÷4
- V8[9] = ENV2_SUS (A+29), Beh = V8÷4
- V8[11] = LFO_DELAY (A+13), Beh ≈ V8÷2
- V8[17] = KL (A+39), scale unclear
- V8[21] = SEMIT (all voices identical in factory), Beh = V8÷2
- Scale rule: V8 = 2×Beh (0-127 params) or 4×Beh (0-63 params)

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

## Decisions Made

- **Headline feature**: wavetable view — send custom WTs to hardware + visual display of current patch's WT
- **Group A/B**: A/B toggle (not side-by-side). Diff arc on knobs shows inactive group value as ghost arc.
- **PPG blue**: approximate OK, will tune visually. Start with `Color(red: 0.08, green: 0.25, blue: 0.75)`
- **Wavetable scope**: send = yes. Pull from hardware = TBD. Generation tools = highly likely later (easy to add given sidebar/detail/inspector layout). Don't replicate Hibiki's full editor.
- **Patch import order**: Behringer SYX native first → PPG Wave 3.V (Waldorf virtual) second
- **FIRM for imports**: default to FIRM=0 (compatible), let user change
- **App layout**: sidebar / detail view / inspector — standard pattern across the series. Wavetable generators would slot into this layout easily when the time comes.
- **Samples workspace**: sample/transient mapping lives as a full workspace, not a patch-editor subpanel.
- **Waveform placement**: selected sample waveform belongs above the keyboard map.
- **Inspector usage**: the third panel should actively support the mapper, not sit mostly idle.
- **Playback split**: key playback should be straight-sample playback for now; loop playback belongs to the loop editor.
- **Zone philosophy**: clean butt-joint zones are preferred over forcing the root note to remain inside the playable span.
- **Terminology direction**: user-facing language will likely move from `Samples` toward `Transients` for brWave.

---

## Reference Paths

| What | Path |
|------|------|
| OBsixer (main reference) | `/Users/rob99/Development/Swift/swiftUI/OBsixer/OBsixer/` |
| Sledgitor | `/Users/rob99/Development/Swift/swiftUI/Sledgitor/Sledgitor/` |
| Wave wavetable SysEx | `/Users/rob99/Development/Swift/swiftUI/AudioMorph/AudioMorph/WaveTable/Synths/BehringerWave.swift` |
| Manual | `brWave/docs/Manual_BE_0722-ABD_WAVE.pdf` |
| Starter kit guide | `brWave/docs/EDITOR_STARTER_KIT.md` |

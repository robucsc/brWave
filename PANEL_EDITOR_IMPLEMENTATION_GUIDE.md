# Panel Editor Implementation Guide

Last updated: 2026-04-26

This captures the brWave panel editor implementation for reuse in future synth editors. The core shift: from a static SwiftUI panel to a tunable editor surface where sections and controls can be selected, aligned, resized, and their positions automatically persist to a git-tracked plist — one file, one map, no competing sources.

---

## What This Editor Does

- `PatchEditorView` treats the editor as a shell with a floating toolbar and a persistent Panel/Table segmented control.
- `FloatingToolbar` owns the top editor commands: init, pattern generation, and display mode switching.
- `WavePanelView` is the real panel surface — a large coordinate-space canvas with independently placed section panels.
- The panel has an A/B group tab in the header. Group A and Group B share the same physical panel while reading/writing different per-group values.
- The tuning wrench enables developer layout mode without making layout tools part of the normal patch editing flow. **Edit mode is `#if DEBUG` only — strip completely from release builds.**
- Tab key selection advances the active control or panel for fast nudging during layout tuning.
- Control and section selection share one canonical selection model. Panels use `panel:<sectionID>` IDs; controls use their parameter/control IDs.
- Alignment tools work across controls and panels: left, center, right, top, middle, bottom.
- Distribution works for three or more selected controls.
- Size matching works for selected controls or panels.
- Panel gap tools apply a standard 20 px horizontal or vertical gap between two selected panels.
- Section panels can be dragged and resized in tuning mode.
- Gesture split fix: per-control tuning gestures use `onTapGesture` + `DragGesture(minimumDistance: 3)` — **not** `highPriorityGesture(DragGesture(minimumDistance: 0))`. The high-priority zero-distance gesture stole taps from panel headers and other controls, breaking normal interaction.
- The Performance section was split into "Performance" (260 × 547 px) and "Voice Tuning" (172 × 547 px). The V1–V8 per-voice semitone knobs live in Voice Tuning. Both panels seed adjacent in `defaultPanelFrame`.
- Layout positions (panel frames, control frames, knob sizes) persist automatically to `PanelLayout.plist` in the source directory — git-tracked, one map, no App Support.
- Export to clipboard generates Swift code for baking tuned positions back into source defaults after a real tuning pass.

---

## Files To Reuse

| File | Notes |
|---|---|
| `PatchEditorView.swift` | Editor shell, selected patch handling, save debounce, Panel/Table mode |
| `FloatingToolbar.swift` | Top toolbar pattern for app-wide editor commands |
| `WavePanelView.swift` | Canvas, section composition, A/B tabs, tuning controls, section drag/resize |
| `PanelLayoutService.swift` | Canonical layout storage, selection, keyboard nav, alignment, distribution, panel gap, persistence, export — **no synth prefix** |
| `AlignmentToolbar.swift` | Floating layout tools shown in tuning mode — **no synth prefix** |
| `NudgeableModifier.swift` | Per-control tuning overlay, inspector, drag gesture, environment keys — **no synth prefix** |
| `WaveControls.swift` | Reusable knobs, menus, toggles, inline numeric entry, Wave-specific value display |
| `PanelLayout.plist` | Pre-populated layout data — ship this with the project from day one |

**File naming rule:** Infrastructure files (`PanelLayoutService`, `AlignmentToolbar`, `NudgeableModifier`) use generic names with no synth prefix. These files port between editors. Only synth-specific files (`WavePanelView`, `WaveControls`, `WaveParameters`) keep a synth prefix.

---

## Layout Architecture

Use one canonical layout service per editor. It owns:

- section frames
- control frames
- knob/control sizes
- selected IDs
- key object ID
- live drag delta
- load/save/export behavior

Do not let individual views privately own layout state. The editor gets much easier to tune when the toolbar, selected overlays, keyboard commands, and section wrappers all talk to the same service.

---

## Persisting Layout — The One-Map Rule

**`PanelLayout.plist` is the single source of truth.** There is no second active map.

### How it works

- **App Support** is the live working copy: `~/Library/Application Support/brWave/PanelLayout.plist`
- **Bundle plist** (`PanelLayout.plist` as an app resource, git-tracked) is the factory seed
- On first launch, `load()` finds no App Support plist, reads from the bundle, writes immediately to App Support
- Every subsequent launch reads from App Support only — one active map
- Every mutation calls `saveSoon()` — 0.3 s debounced write to App Support
- On quit, `willTerminateNotification` triggers `saveNow()` — synchronous flush

### Dev workflow

1. Edit positions in tuning mode → App Support plist auto-saves
2. Quit and relaunch → picks up exactly where you left off
3. When layout is finished → Export → paste into `defaultPanelFrame` / `naturalFrame` in source → commit
4. Committing source updates the bundle plist for the next build, which becomes the new factory seed

### Why not source directory?

App Sandbox blocks reads/writes to the source directory. Disabling the sandbox redirects CoreData to a different container — the library disappears. App Support is the correct sandbox-accessible writable location.

### Shipping the plist

`PanelLayout.plist` ships in the app bundle as a resource (Xcode 16 `PBXFileSystemSynchronizedRootGroup` auto-discovers it). In release builds the edit UI is compiled out (`#if DEBUG`) but the bundle plist still provides the factory layout.

### Future: field-deliverable updates

The plist approach is ready to promote to App Support for field updates without a new app release. The migration: on first launch, copy the bundle plist to App Support; always read/write App Support thereafter. The bundle plist becomes the factory default. This is deferred — not needed while edit mode is developer-only.

### The wrong pattern (do not repeat)

An earlier version saved to three locations (App Support, UserDefaults, source JSON in `#if DEBUG` only), with App Support taking load priority. This made the source JSON a dead write target, UserDefaults a silent override, and git useless for layout work. The symptom was: edits in the app appeared to work, but every relaunch restored old positions.

A second wrong pattern: Swift default constants (`defaultPanelFrame`, `naturalFrame`) as a live fallback that competed with a JSON/plist override file. Any time the override file failed to load, positions silently reverted to Swift defaults, creating invisible layout drift. **Once the plist exists and is pre-populated, Swift default values must be dead code — never the active source.**

---

## Selection Rules

- Plain click selects one item.
- Shift-click toggles selection.
- Empty-space click clears selection.
- Tab advances to the next visible selectable item (sorted top-to-bottom, left-to-right).
- The first selected item, or explicit key object, is the alignment anchor.
- Use `panel:<sectionID>` prefix for section selections so panels and controls share one selection set.

---

## Alignment Rules

- Align selected items against the key object's displayed frame.
- Use displayed frames during active drags so toolbar operations see what the user sees.
- Distribution skips panels unless panel distribution is explicitly designed.
- Matching width/height preserves each selected item's origin.
- Panel gap is a separate command from distribution — it is for clean section spacing, not general layout solving. Default gap: 20 px.

---

## Section Panel Rules

- Treat each section as a movable, resizable panel with a real frame (origin + size).
- Store full frames, not just sizes. Size-only tuning is too limited once a panel is dense.
- Keep section content top-left aligned inside the panel.
- Keep resize handles active only in tuning mode.
- Keep the top-left corner fixed when resizing from the lower-right handle.
- Report live section frames so hit testing and selection work even before a stored frame exists.
- `removePanelFrame(_:)` removes the stored key; the panel re-seeds from `defaultPanelFrame` on next display. Never store zero-size as a "reset" signal — that creates a second implicit default path.

---

## Control Rules

- Register every tunable control with a stable ID.
- Use parameter IDs where possible so layout survives refactors.
- Give non-parameter controls explicit IDs (`wheel.pitch`, `waves.plot`, etc.).
- Keep knob size separate from frame size — it lets the panel tune visual weight without fighting the slot frame.
- Use inline numeric entry on knobs; it makes the panel usable as an editor, not just a remote surface.

---

## Knob Design — brWave Dual-Arc Model

The brWave knob shows two arcs — one for Group A (cyan) and one for Group B (white) — so the user can see how both sounds differ without switching views.

**Geometry rules (reference OBsixer for the single-arc baseline):**
- Cap diameter: `s - 12` — matches OBsixer exactly.
- Group A arc at diameter `s`, width 3.5 px.
- Group B arc at diameter `s + 10`, width 2.5 px — floats *outside* the A arc as a ghost ring.
- **Do not put the second arc inside the A arc.** Inside placement forces the cap to shrink to `s - 20` to clear the inner ring, making the knob feel smaller than OBsixer at the same nominal size.

**Opacity:**
- Active group: 1.0
- Inactive group: 0.30
- Earlier values of 0.88/0.96 made inactive arcs almost indistinguishable from active. Keep inactive clearly dim.

**Reference dot:**
- A 4.5 px dot on the active arc track marks the loaded value.
- Only visible when the current value differs from the loaded value by more than ~1.5% of full range.
- Captured in `@State private var loadedNorm: Double?` — set on `.onAppear`, refreshed on `patch.objectID` change.
- Group A viewing: dot sits on the A arc. Group B viewing: dot sits on the B ghost arc.

---

## Visual / UX Decisions

- The normal editor stays clean. Tuning tools are developer affordances, not user-facing.
- The panel should feel like the instrument: dark panel, PPG blue highlights, light knobs, minimal chrome.
- A/B should be a tab/toggle, not side-by-side panels. Side-by-side is too dense for the Wave.
- Group B values stay visible through secondary accents/diff indicators where useful, but the active group must be obvious.
- The panel needs enough whitespace that labels and controls breathe after alignment.

---

## Starter Checklist For The Next Editor

1. Ship `PanelLayout.plist` pre-populated with starting positions from day one.
2. Create `PatchEditorView` as the shell first.
3. Add a `FloatingToolbar` with display mode selection before building the full panel.
4. Build the parameter table view early — fallback editor while the panel is rough.
5. Port `PanelLayoutService.swift` (generic name, no synth prefix) before tuning any visual controls.
6. Add tuning mode, selection, and export before doing serious alignment work.
7. Make sections movable/resizable from the start.
8. Give every control a stable ID before it appears in the panel.
9. Add alignment and size-match tools as soon as there are enough controls to tune.
10. Wrap all edit-mode UI in `#if DEBUG`.
11. Commit `PanelLayout.plist` after each real tuning pass — that commit is the new factory default.
12. Keep generated build artifacts out of Git before the first big panel commit.

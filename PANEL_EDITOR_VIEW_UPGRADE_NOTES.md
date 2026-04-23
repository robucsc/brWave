# Panel Editor View Upgrade Notes

Date: 2026-04-23

This captures the brWave panel editor work that should be reused when building the next synth editor. The important shift was moving from a static SwiftUI panel to a tunable editor surface: sections and controls can be selected, aligned, resized, exported, and later committed as source defaults.

## What Changed

- `PatchEditorView` now treats the editor as a shell with a floating toolbar and a persistent Panel/Table segmented control.
- `FloatingToolbar` owns the top editor commands: init, pattern generation, and display mode switching.
- `WavePanelView` is the real panel surface, with a large coordinate-space canvas and independently placed section panels.
- The panel has an A/B group tab in the header. Group A and Group B share the same physical panel while reading/writing different per-group values.
- The tuning wrench enables developer layout mode without making layout tools part of the normal patch editing flow.
- Tab key selection was added for layout tuning, so the active control or panel can be advanced quickly while nudging.
- Control and section selection now share one canonical selection model. Panels use `panel:<sectionID>` IDs, while controls use their parameter/control IDs.
- Alignment tools now work across controls and panels: left, center, right, top, middle, bottom.
- Distribution works for three or more selected controls.
- Size matching works for selected controls or panels.
- Panel gap tools apply a standard 20 px horizontal or vertical gap between two selected panels.
- Section panels can be dragged and resized in tuning mode.
- Control frame overrides, panel frames, and knob sizes are persisted together in `WavePanelLayoutService`.
- Layout defaults can be exported to clipboard and promoted into source-controlled defaults.
- `.derived/` and `.deriveddata/` are ignored so Xcode build/index files do not flood commits.

## Files To Reuse

- `PatchEditorView.swift`: editor shell, selected patch handling, save debounce, Panel/Table mode.
- `FloatingToolbar.swift`: top toolbar pattern for app-wide editor commands.
- `WavePanelView.swift`: canvas, section composition, A/B tabs, tuning controls, section drag/resize.
- `WavePanelLayoutService.swift`: canonical layout storage, selection, keyboard navigation, alignment, distribution, panel gap, export.
- `AlignmentToolbar.swift`: floating layout tools shown in tuning mode.
- `NudgeableModifier.swift`: per-control tuning overlay, inspector, and environment keys.
- `LayoutDefaults.swift`: source-committed layout baseline.
- `WaveControls.swift`: reusable knobs, menus, toggles, inline numeric entry, and Wave-specific value display.

## Layout Architecture

Use one canonical layout service per editor. It should own:

- section frames
- control frames
- knob/control sizes
- selected IDs
- key object ID
- live drag delta
- load/save/export behavior

Do not let individual views privately own layout state. The editor gets much easier to tune when the toolbar, selected overlays, keyboard commands, and section wrappers all talk to the same service.

## Selection Rules

- Plain click selects one item.
- Shift click toggles selection.
- Empty-space click clears selection.
- Tab advances to the next visible selectable item.
- The first selected item, or explicit key object, is the alignment anchor.
- Use a prefix for section selections, such as `panel:LFO`, so panels and controls can live in the same selection set.

## Alignment Rules

- Align selected items against the key object's displayed frame.
- Use displayed frames during active drags so toolbar operations see what the user sees.
- Distribution should skip panels unless panel distribution is explicitly designed.
- Matching width/height should preserve each selected item's origin.
- Panel gap should be a separate command from distribution; it is for clean section spacing, not general layout solving.

## Section Panel Rules

- Treat each section as a movable, resizable panel with a real frame.
- Store the full frame, not just size. Earlier section-size-only tuning is too limited once a panel becomes dense.
- Keep section content top-left aligned inside the panel.
- Keep resize handles active only in tuning mode.
- Keep the top-left fixed when resizing from the lower-right corner.
- Report live section frames so hit testing and selection can work even before an override exists.

## Control Rules

- Register every tunable control with a stable ID.
- Use parameter IDs where possible so layout survives refactors.
- Give non-parameter controls explicit IDs, for example `wheel.pitch`.
- Keep knob size separate from frame size. It lets the panel tune visual weight without fighting the slot frame.
- Use inline numeric entry on knobs; it makes the panel usable as an editor, not just a remote surface.

## Persisting Layout

The current brWave flow is:

1. Tune in the app with the wrench enabled.
2. Use the export button to copy the canonical layout JSON.
3. Promote stable values into source defaults.
4. Commit the source defaults so a fresh install starts from the tuned panel.

Keep user overrides layered on top of source defaults. A user should be able to tune their local panel without changing the app baseline.

## Visual / UX Decisions

- The normal editor should stay clean. Tuning tools are developer affordances.
- The panel should feel like the instrument: dark panel, PPG blue highlights, light knobs, minimal chrome.
- A/B should be a tab/toggle, not side-by-side panels. Side-by-side is too dense for the Wave.
- Group B values should remain visible through secondary accents/diff indicators where useful, but the active group should be obvious.
- The panel needs enough whitespace that labels and controls breathe after alignment.

## Starter Checklist For The Next Editor

- Create `PatchEditorView` as the shell first.
- Add a `FloatingToolbar` with display mode selection before building the full panel.
- Build the parameter table view early so there is a fallback editor while the panel is still rough.
- Create a single layout service before tuning any visual controls.
- Add tuning mode, selection, and export before doing serious alignment work.
- Make sections movable/resizable from the start.
- Give every control a stable ID before it appears in the panel.
- Add alignment and size-match tools as soon as there are enough controls to tune.
- Commit source defaults after a real tuning pass.
- Keep generated build artifacts out of Git before the first big panel commit.


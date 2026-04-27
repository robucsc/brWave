# Bayesian Patch Generator — Implementation Guide

Last updated: 2026-04-26

Ported from Hexatronix. The engine is generic — the three-layer split (generic engine / synth adapter / UI sheet) makes it a 1–2 hour port to any editor that already has GalaxyEngine and SimilarityEngine.

---

## What It Does

Navigates the patch library by Bayesian inference rather than random sampling. Starting from any patch or category centroid, the user explores nearby sounds, incorporates ones they like as evidence, and the system generates a posterior that drifts toward their taste. A Schmitt-trigger accumulator prevents chattering — the posterior shifts steadily as evidence builds, not randomly on every step.

---

## File Structure

| File | Role |
|---|---|
| `BayesianVectorSampler.swift` | Generic engine — pure `[Double]` → `[Double]`. No synth refs. Copy verbatim to other editors. |
| `BayesianWavePatchSampler.swift` | Wave adapter — vectorize via `GalaxyEngine.vector(for:)`, materialize via `SimilarityEngine.vectorToPatchValues`. |
| `BayesianExplorerSheet.swift` | Sheet UI — navigation, regime breadcrumb, snap meter, commit to set. |
| `GalaxyEngine.swift` | Added `vector(for: Patch) → [Double]` — same normalized space as anchor vectors. |
| `Patch+Helpers.swift` | Added `rebuildRawSysex()` — packs current `patch.values` (JSON dict) back to `rawSysexPayload` for hardware send. |

---

## Architecture

```
BayesianVectorSampler          (pure [Double] → [Double], engine-agnostic)
  ↕
BayesianWavePatchSampler       (Wave adapter)
  vectorize:    GalaxyEngine.shared.vector(for: patch)   → [Double]
  materialize:  SimilarityEngine.vectorToPatchValues(v)  → Data (patch.values format)
  ↕
BayesianExplorerSheet          (UI)
  apply:        patch.values = data  →  patch.rebuildRawSysex()
  audition:     MIDIController.shared.sendToEditBuffer(payload: patch.rawBytes)
```

### Why `rebuildRawSysex()` exists

brWave stores patch state in two places:
- `patch.values` — JSON dict `[String: Int]`, used by the panel view and SimilarityEngine
- `patch.rawSysexPayload` — raw 120-byte SysEx, used for hardware send

The Bayesian generator writes to `patch.values`. To send the generated sound to hardware, `rawSysexPayload` must be kept in sync. `rebuildRawSysex()` reconstructs a `WaveParsedPatch` from the current `patchValues` and calls `WaveSysExParser.buildPayload(from:)`.

---

## User Flow

1. Select a patch in any view
2. **Patch → Explore from Here…** — sheet opens, seeds sampler from the selected patch
3. Arrow right → generates first patch (posterior starts at seed)
4. Arrow right again → incorporates current as evidence, generates next
5. Arrow left → revisit previous without incorporating
6. **Use This** → applies chosen patch, saves name, dismisses
7. **New Set from All** → creates a PatchSet with all generated patches as new Patch entities

---

## Entry Points

### Seeding

Two modes — the sheet always uses the patch-based seed:

```swift
// From selected patch (always used in the sheet)
sampler.seed(from: patch)

// From category centroid (requires anchors from GalaxyEngine.updateAll)
sampler.seed(for: .bass)
```

### Incorporate + Generate

```swift
// Incorporate as evidence (happens automatically on forward navigation)
sampler.incorporate(patch, weight: 1.0)

// Generate Data? (patch.values format) from current posterior
let data = sampler.generate()
patch.values = data
patch.rebuildRawSysex(name: entryName)
```

---

## Tuning Parameters

| Parameter | Default | Effect |
|---|---|---|
| `priorStrength` | 8.0 | Higher = posterior resists moving from seed |
| `snapThreshold` | 1.5 | Accumulator level that triggers regime switch |
| `decayRate` | 0.90 | How fast accumulator drains between observations |

Regimes are recorded in `regimeHistory` — each can be materialized to bytes for replay.

---

## Patch Menu

`Explore from Here…` lives in the **Patch** menu (added alongside Replicate and other patch-level operations). The notification `.explorePatch` is posted with the selected patch as object; ContentView receives it and presents `BayesianExplorerSheet` as a sheet.

```swift
// Post from menu / keyboard shortcut
NotificationCenter.default.post(name: .explorePatch, object: selectedPatch)

// Received in ContentView
.onReceive(NotificationCenter.default.publisher(for: .explorePatch)) { note in
    explorerPatch   = (note.object as? Patch) ?? patchSelection.selectedPatch
    showingExplorer = true
}
```

---

## Porting to Another Editor

1. Copy `BayesianVectorSampler.swift` verbatim
2. Add `vector(for: YourPatch) -> [Double]` to your GalaxyEngine — must return the same normalized space as anchor vectors
3. Write a `BayesianYourSynthPatchSampler` adapter (see `BayesianWavePatchSampler` as template)
4. Add a `rebuildRawSysex()` equivalent if your synth also has dual storage (JSON dict + raw bytes)
5. Port `BayesianExplorerSheet`, renaming Wave-specific types
6. Add `Explore from Here…` to your Patch menu and wire `.explorePatch` in ContentView

The vectorize function **must produce the same normalized space** as GalaxyEngine anchor vectors. If the spaces differ, the RMS divergence math breaks.

---

## Theme Group Colors

Added alongside the Bayesian work:

- `Theme+GroupColors.swift` — `GroupColorProviding` protocol + `WaveGroupColorProvider` (Wave section name → Color)
- `Theme.groupColor(for: String?)` — static API for panel sections to look up their accent color
- Custom providers can override the default via `Theme.setGroupColorProvider(_:)`

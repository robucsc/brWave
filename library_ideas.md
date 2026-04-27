# Behringer Wave Librarian & Library Management Ideas

This document outlines the architecture and feature set for the Behringer Wave librarian, summarizing the implementations and design decisions made to integrate hardware synchronization with intelligent software management.

## 1. Hardware Synchronization (MIDI/SysEx)
The system uses the `0x05` (Request) and `0x06` (Data) SysEx command set to bridge the hardware and software states.

- **Bulk Fetching**: Implement `fetchEntireSynth()` to sequentially iterate through all 200 hardware slots (Bank 0: 0-99, Bank 1: 0-99). Uses a 60ms delay between requests to avoid overwhelming the hardware buffer.
- **Bulk Transmission**: Implement `sendBankToSynth(patches:)` to push a collection of patches from the software library to the machine. Uses a 100ms delay to accommodate hardware EEPROM write times.
- **Live Edit Buffer**: Support `sendToEditBuffer()` for instant auditioning of library patches without overwriting hardware memory.

## 2. Integrated Library Hierarchy
A multi-tier structure to organize thousands of patches across multiple sources (Factory, PPG V8, Waldorf MicroWave, Custom).

- **Sets**: Global collections visible in the sidebar (e.g., "Factory Library", "V8 Import", "AI Search Results").
- **Banks**: Fixed 100-patch logical containers within a Set, mapping directly to hardware bank structures.
- **Patches**: Individual 121-byte objects containing both raw SysEx data and parsed `WavePatchValues`.

## 3. Galaxy AI & Smart Selection
Porting and refining "The Constellation Engine" (Galaxy) for intelligent librarian work.

### Smart Library Search Service
A surgical AI engine that translates natural language into rigid database queries.
- **Strict Logic**: Ability to parse commands like "warm pads not bass" to explicitly exclude the "BASS" category *before* mathematical scoring.
- **Vector Centroids**: Uses the `SimilarityEngine` to convert parameter states into multi-dimensional vectors. It calculates the centroid of valid matches and returns the nearest neighbors.

### Galaxy UI Integration
- **Galaxy Inspector**: Ported from Sledgitor to provide granular visibility controls (Show/Hide categories like Synth, Keys, Orchestral).
- **Search Highlighting**: Results from AI queries pulse in the Galaxy view, allowing the user to visually confirm the "location" of the result.
- **Batch Creation**: "Save as New Bank" button within the search UI to instantly manifest a selection into a persistent `PatchSet`.

## 4. Workflows & Utility
- **Dynamic Bank Creation**: Create new banks from any selection (Favorites, Trash, Search Results, or Lasso selections in Galaxy).
- **Keyword Classification**: Since the Wave 2.0 protocol lacks metadata, the librarian uses a keyword-based classifier (e.g., `seq` -> `Sequence`) to automatically tag patches upon import.
- **Cross-Platform Parity**: Support for importing Waldorf `.fxb`/`.fxp` and PPG V8 SysEx files, normalizing them into the dual-group Behringer Wave architecture.

## 5. File References
- `WaveSysExParser.swift`: Core protocol logic.
- `MIDIController.swift`: Bulk queue management.
- `SmartLibrarySearchService.swift`: AI query struct and logic.
- `GalaxyInspectorView.swift`: Visibility and selection UI.
- `GalaxyView.swift`: The main visualization canvas.

## 5b. Vector-Based Smart Features (planned — all use existing SimilarityEngine vectors)

All features below use `SimilarityEngine.patchToVector` / `euclideanDistance` already in the codebase.
They apply equally to **browsing**, **sorting**, and **generating** new patches.

### Browsing / Discovery

- **More Like This** — inspector shows 8 nearest neighbors in vector space for the selected patch. One click loads them into an audition list. Nearly free given `SimilarityEngine.findMatches`.
- **Density badge** — patches with no close neighbors are "unique/rare"; patches in dense clusters get "similar to N others." Helps triage after large imports.
- **Galaxy outlier highlight** — isolated patches pulse in the Galaxy view; dense clusters are visually de-emphasized. Guides which patches are worth keeping when thinning.

### Sorting

Add a **Sort** submenu to the Library menu (and a sort control in the patch list header):

| Sort mode | How |
|-----------|-----|
| Alphabetical | existing |
| Category | existing |
| Similarity to selected | Euclidean distance ascending from current patch |
| Most unique | Nearest-neighbor distance descending (rarest first) |
| Most common | Nearest-neighbor distance ascending (densest cluster first) |
| Parameter value | Any single parameter (cutoff, attack, etc.) ascending/descending |
| Import date | existing |

The "Similarity to selected" and "Most unique" modes are the highest-value new additions — they make the flat list genuinely useful for auditioning and curating.

### Generation

The same vector math that browses can **produce** new patches. All generation creates a parameter vector, then uses `WaveParameters` to clamp values to valid ranges and round to integers before writing a new `Patch`.

- **Interpolate (Blend)** — pick two patches A and B and a blend ratio (0–100%). Generate a new patch whose vector = `A*(1-t) + B*t`. At 50% this is the midpoint patch. The gradient/journey builder is a sequence of these at evenly-spaced t values.
- **Mutate** — take a patch and add Gaussian noise to its vector (σ configurable: "subtle" / "wild"). Each mutation is a new patch. Good for exploring variations around a patch you like.
- **Journey** — A → B gradient: produce N interpolated patches between two anchor patches. Ordered set suitable for a bank of evolving timbres.
- **Fill the Galaxy** — identify the most sparse region of parameter space in the current library, generate a patch at that centroid. Fills holes in timbral coverage.
- **Category centroid** — generate the "ideal exemplar" of a category by averaging all patch vectors in that category. The result is the most representative sound of that group.
- **Random in region** — draw a random point inside a user-drawn lasso region of the Galaxy and generate a patch there. Constrained random synthesis within a timbral zone.

### Deduplication & Init Cleanup

- **Vector-based dedup** — two patches with Euclidean distance below a threshold are functionally identical. Show as a collapsible pair; keep one, trash the other. Far more reliable than name-matching for cross-format imports (Waldorf FXB vs Behringer SYX of the same patch).
- **Init detector** — init patches form a tight cluster near the parameter-space origin (all defaults). Auto-detect during import; offer to quarantine to a separate "Init" library rather than polluting the main one.

### Library Menu Structure (planned)

```
Library
├── Fetch Synth (All 200 Slots)…        ← existing
├── Send Selection to Synth…            ← existing
├── ─────────────────────
├── Sort By ▶
│   ├── Name
│   ├── Category
│   ├── Similarity to Selected
│   ├── Most Unique First
│   └── Parameter Value… ▶
├── Generate ▶
│   ├── Interpolate Two Patches…
│   ├── Mutate Selected…
│   ├── Journey (A→B)…
│   ├── Fill Galaxy Gap…
│   └── Category Centroid…
├── ─────────────────────
├── Find Duplicates…                    ← vector dedup
├── Apply Names from Clipboard…        ← existing
└── Purge Library…                     ← existing
```

## 5c. Wavetable Vectors — Timbral Fingerprinting

### Why the index is wrong

The current `SimilarityEngine` uses the raw wavetable index (0–127) as a dimension in the patch vector. This is nearly meaningless: index 14 and 15 may be completely different timbres; index 10 and index 95 may be nearly identical. Using the raw index gives the galaxy and similarity searches false positives and misses real timbral neighbors.

### What we need instead

A compact descriptor computed from the **actual waveform** — something like the first 8–16 FFT magnitude coefficients of the averaged cycle, or spectral centroid + harmonic series shape. This gives a timbral fingerprint that is independent of the slot numbering scheme.

### Data availability

- **Factory wavetables 0–31**: Full 64-cycle × 128-sample data already exists in `WaveTables.swift` (PPG ROM data). Descriptors can be computed at build time or once at startup and cached.
- **User wavetables 64–127**: Not available unless fetched from hardware. No documented pull SysEx exists for PCM retrieval, so these slots fall back to a neutral/zero descriptor for now. If user has loaded a WT from brWave, we can use the source data.
- **Transient slots 32–63**: Similar problem — no pull path. Falls back to descriptor of all-zeros (silent).

### The descriptor approach

For each wavetable, compute from the first (or average) wave cycle:
1. **Spectral centroid** — brightness / tonal center of mass
2. **First N FFT magnitudes** (N=8 is sufficient) — harmonic shape
3. **Zero-crossing rate** — noisiness / transient density
4. Normalize to [0,1] range so the descriptor slots in the patch vector have comparable scale to the other parameters

Store as `[Double]` alongside the wavetable index in `WaveTables.swift`. Cache at startup. This replaces the single raw-index dimension in the patch vector with N timbral dimensions — a dramatically better signal for Galaxy and all vector-based features.

### Design decision: WT fingerprinting is opt-in via Settings

All vector-based library features (More Like This, dedup, generation, sorting) are built and
shipped **without** the wavetable timbral descriptor. The raw wavetable index is either
excluded from the vector entirely or treated as a weak hint.

A **Settings preference** — "Use wavetable timbral fingerprinting" (default: OFF) — gates
the enhanced wavetable dimension. When OFF, the similarity engine ignores the WT slot for
vector purposes. When ON, it substitutes the spectral descriptor.

This keeps the feature set portable to other editors (Sledgitor, OBsixer) that have no
wavetable concept at all. Those apps simply leave the toggle absent from their Settings.

When the WT fingerprinting is ON and a user WT slot (64–127) has no cached descriptor
(never sent from brWave, never heard), it falls back silently to the OFF behavior for
that dimension rather than producing garbage similarity scores.

### Getting good wavetable source data

**⚠️ WaveTables.swift data issue (2026-04-23)**: The current ROM data in `WaveTables.swift` was
extracted at 128 cycles × 256 samples per cycle, but the real PPG format is **64 cycles × 128
samples**. The data is 4× oversized and will need to be re-extracted at the correct dimensions
before spectral fingerprinting is viable. The `PPG_AIFFs/` exports and `make_aiffs.py` reflect
the same error. This is a prerequisite blocker for WT fingerprinting — do NOT build the
descriptor computation until the ROM data is corrected.

Also: the hardware WT/TR slot layout does not map cleanly to a linear 0–127 range. The
WAVETB parameter display shows: 0–31 factory WTs, 32–63 user transients, 64–127 user WTs.
But which factory WT index maps to which named table in the Behringer panel is **not yet
confirmed** and likely differs from the simple 0-based ordering in `WaveTables.swift`. Spy
SynthTribe MIDI traffic to confirm the exact slot-to-name correspondence before using slot
numbers as vector dimensions.

For user WTs that have been sent to hardware via brWave (wavetable send path), brWave has the source data and can compute descriptors at send time and cache them. This is the path to better coverage over time.

## 6. Current Status & Roadmap

### ✅ Completed & Integrated
- **Bulk MIDI Engine**: `MIDIController.swift` handles 200-slot fetch and send with ACK-driven ping-pong pacing (GCD coalescing fix applied).
- **Smart Search Service**: AI query engine (`SmartLibrarySearchService`) with strict pre-filtering + vector similarity fallback, wired into `GalaxyInspectorView`.
- **Librarian UI Port**: Full `GalaxyInspectorView` with visibility group toggles and category filtering.
- **Menu System**: Fetch/Send actions in Library menu; Sort/Generate sections planned (see §5b).
- **Star Map Filtering**: Galaxy canvas honors visibility states from inspector.
- **Wavetable + Transient Send**: Working with ping-pong ACK protocol. Transient pitched behavior confirmed: 128/2048/8192 sample counts = looped+pitched; other sizes = drum/static.

### ⏳ In Progress / High Priority
1. **Sync Progress UI** — `bulkTransferProgress` + `isBulkTransferActive` are published in `MIDIController` but nothing renders them. A 30-90s fetch is completely silent. Need a non-modal progress banner with slot counter and Cancel.
2. **More Like This** — nearest-neighbor inspector panel. Nearly free given existing `SimilarityEngine.findMatches`.
3. **Vector Dedup** — find functionally identical patches by Euclidean distance threshold; show as pairs for review.
4. **Sort menu** — add Sort By submenu to Library menu (similarity, uniqueness, parameter value).
5. **Generate menu** — Interpolate, Mutate, Journey, Fill Gap (see §5b for full spec).
6. **Wavetable Fingerprinting** — the wavetable index number (0–127) is nearly useless for similarity: index 14 and 15 may sound nothing alike, while 14 and 87 may be nearly identical tonally. The fix is to compute a timbral descriptor from the actual waveform cycles and use that in the patch vector instead of the raw index. See §5c below.
7. **Parametric Filtering UI** — dedicated filter controls for parameter ranges (cutoff > 80, attack < 10, etc.).

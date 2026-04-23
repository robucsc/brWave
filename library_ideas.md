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

## 6. Current Status & Roadmap

### ✅ Completed & Integrated
- **Bulk MIDI Engine**: `MIDIController.swift` now handles iterative 200-slot transfers with GCD-pacing to prevent hardware lockup.
- **Smart Search Service**: AI query engine with strict pre-filtering (Include/Exclude) + Vector similarity fallback.
- **Librarian UI Port**: Full `GalaxyInspectorView` with visibility group toggles and category filtering.
- **Menu System**: Direct integration of Fetch/Send actions into the macOS Library menu.
- **Star Map Filtering**: Galaxy canvas now honors visibility states from the Inspector sidebar.

### ⏳ In Progress / High Priority
- **AI Precision Tuning**: Refine the `@Generable` instructions in `SmartLibrarySearchService` to prevent result bloat.
- **Sync Progress UI**: Add a progress bar or overlay to visualzie the 30-90 second "Fetch Entire Synth" operation.
- **Wavetable Fingerprinting**: Enhance the `SimilarityEngine` to analyze the 256-sample PCM waveforms instead of just the Wavetable index for higher-accuracy "timbral" matches.
- **Parametric Filtering UI**: Build dedicated controls for "Inside/Outside parameter range" queries (e.g., Filtering by Cutoff/Attack values).
- **Library Deduplication & Init Cleanup**: 
    - **Vector-Based Discovery**: Identify identical patches using mathematical parameter vectors rather than unreliable names.
    - **Referential Consolidation**: Clean the global library by pointing multiple Bank/Set slots to a single master `Patch` record, maintaining bank integrity while removing redundant objects.
    - **Init Management**: Filter and consolidate factory default "Init" patches to prevent library bloat after bulk imports.

# Patch Menu — Implementation Guide

Last updated: 2026-04-26

This documents the Patch menu pattern established in brWave. The distinction from Library is intentional: **Library** manages collections (import, export, sets, dedup, trash). **Patch** operates on the selected patch as a musical entity — send it, copy it, tag it, explore it.

---

## Why a Separate Patch Menu

Without a Patch menu, patch-level actions accumulate in Library or Edit — neither is the right home. Replicate next to Duplicate in Edit is confusing because Replicate creates a new database entity while Duplicate copies a grid slot. Sending to hardware is not a library operation. Category and Favorite are patch metadata, not collection management. Keeping these in their own menu makes the intent of each action unambiguous.

---

## Menu Structure

```
Patch
  Send to Edit Buffer    ⌘E
  ─────────────────────────
  Replicate              ⌘⌥D
  ─────────────────────────
  Category ▶             (submenu — all PatchCategory cases)
  Mark as Favorite       (toggles to "Unfavorite" when already set)
  Move to Trash
  ─────────────────────────
  Explore from Here…
```

All items are disabled when no patch is selected.

---

## Implementation Pattern

All items live in `CommandMenu("Patch")` inside the `.commands` block of the main `WindowGroup` in `YourApp.swift`. The menu accesses `patchSelection` — a `@StateObject PatchSelection` injected into the environment and held at the app level.

```swift
CommandMenu("Patch") {
    Button("Send to Edit Buffer") {
        guard let patch = patchSelection.selectedPatch else { return }
        MIDIController.shared.sendToEditBuffer(payload: patch.rawBytes)
    }
    .keyboardShortcut("e", modifiers: .command)
    .disabled(patchSelection.selectedPatch == nil)

    Divider()

    Button("Replicate") {
        NotificationCenter.default.post(name: .replicatePatch,
                                        object: patchSelection.selectedPatch)
    }
    .keyboardShortcut("d", modifiers: [.command, .option])
    .disabled(patchSelection.selectedPatch == nil)

    Divider()

    Menu("Category") {
        ForEach(PatchCategory.allCases) { cat in
            Button(cat.rawValue) {
                guard let patch = patchSelection.selectedPatch else { return }
                patch.category = cat.rawValue
                try? persistenceController.container.viewContext.save()
            }
        }
    }
    .disabled(patchSelection.selectedPatch == nil)

    Button(patchSelection.selectedPatch?.isFavorite == true
           ? "Unfavorite" : "Mark as Favorite") {
        guard let patch = patchSelection.selectedPatch else { return }
        patch.isFavorite.toggle()
        try? persistenceController.container.viewContext.save()
    }
    .disabled(patchSelection.selectedPatch == nil)

    Button("Move to Trash") {
        guard let patch = patchSelection.selectedPatch else { return }
        patch.isTrashed = true
        try? persistenceController.container.viewContext.save()
    }
    .disabled(patchSelection.selectedPatch == nil)

    Divider()

    Button("Explore from Here…") {
        NotificationCenter.default.post(name: .explorePatch,
                                        object: patchSelection.selectedPatch)
    }
    .disabled(patchSelection.selectedPatch == nil)
}
```

---

## Notification-Driven Actions

Actions that need context (managed object context, library state, sheet presentation) are handled via `NotificationCenter` rather than directly in `brWaveApp.swift`. The menu posts; views receive and act.

| Action | Notification | Handler Location |
|---|---|---|
| Replicate | `.replicatePatch` | `ContentView` — creates new Patch entity, slots into current library |
| Explore from Here | `.explorePatch` | `ContentView` — sets `explorerPatch`, presents `BayesianExplorerSheet` |

**Why this pattern:** `brWaveApp.swift` has no access to the managed object context directly — the context lives in the environment of `ContentView`. Notifications bridge the gap cleanly without threading context down through every layer.

### Notification Name Declarations

All `Notification.Name` statics live in a single extension in `ContentView.swift`:

```swift
extension Notification.Name {
    static let replicatePatch = Notification.Name("replicatePatch")
    static let explorePatch   = Notification.Name("explorePatch")
    // ... other app-wide notifications
}
```

### Receiving in ContentView

```swift
.onReceive(NotificationCenter.default.publisher(for: .replicatePatch)) { note in
    let patch = (note.object as? Patch) ?? patchSelection.selectedPatch
    replicatePatch(patch)
}
.onReceive(NotificationCenter.default.publisher(for: .explorePatch)) { note in
    let patch = (note.object as? Patch) ?? patchSelection.selectedPatch
    guard let patch else { return }
    explorerPatch   = patch
    showingExplorer = true
}
```

The `?? patchSelection.selectedPatch` fallback means the same notification works whether posted from the menu (with the patch as object) or from a right-click context menu in a list (also with the patch as object, but useful to keep consistent).

---

## Replicate — Multi-Select Behaviour

Replicate is multi-select aware. When `patchSelection.selectedIDs` contains more than one entry, `replicatePatch` delegates to `replicatePatches(_:)` which handles the batch:

1. Fetches all selected patches from the context
2. Sorts them by their current slot position (so copies land in the same relative order)
3. Builds the occupied-slot set once, then grows it with each copy placed — preventing copies from colliding with each other
4. After saving, sets `patchSelection.selectedIDs` to all new copies so the user can see exactly what was created

The single-patch path is unchanged — `selectedIDs.count > 1` is the branch condition.

```swift
private func replicatePatch(_ patch: Patch?) {
    let ids = patchSelection.selectedIDs
    if ids.count > 1 {
        replicatePatches(ids)   // multi-select path
        return
    }
    // ... single-patch path unchanged
}
```

**Key detail:** the occupied set must grow inside the loop. If you fetch it once before the loop, a second copy can land in the same slot as the first copy before the context is saved. Append each new position to the set immediately after placing it.

---

## Replicate vs Duplicate

These are two different operations that must not be conflated:

| Operation | What it does | Where it lives |
|---|---|---|
| **Replicate** (⌘⌥D) | Creates an independent copy as a new Patch entity in the store. The copy gets its own UUID and appears in the library. | Patch menu |
| **Duplicate** (⌘D) | Copies a bank grid tile within the Banks view. Grid-local operation, no new Patch entity. | Edit menu |

Keep Replicate in Patch and Duplicate in Edit. Putting both in the same menu obscures the distinction.

---

## Favorite Toggle Label

The Favorite button label updates dynamically based on the selected patch state:

```swift
Button(patchSelection.selectedPatch?.isFavorite == true
       ? "Unfavorite" : "Mark as Favorite") { ... }
```

macOS menus re-evaluate their content on each open, so this works without any additional state tracking. The optional chain returns `false` when no patch is selected (no crash, button stays disabled anyway).

---

## Keyboard Shortcuts

| Item | Shortcut | Notes |
|---|---|---|
| Send to Edit Buffer | ⌘E | Chosen to evoke "emit to hardware" |
| Replicate | ⌘⌥D | ⌘D is taken by Duplicate in Edit |
| Explore from Here | (none) | Sheet opens; no shortcut to avoid accidental fires |

---

## Porting Checklist

1. Add `patchSelection: PatchSelection` as a `@StateObject` at the app level if not already present
2. Inject it via `.environmentObject(patchSelection)` on `WindowGroup { ContentView() }`
3. Add `CommandMenu("Patch")` to `.commands` — position it after the Edit-related groups and before Library
4. Add `Notification.Name` statics to ContentView's extension for any notification-driven actions
5. Add `.onReceive` handlers in ContentView for those notifications
6. Add matching `@State` vars in ContentView for any sheets the menu triggers
7. If your editor has a Bayesian sampler, `Explore from Here…` is already wired — just confirm `BayesianExplorerSheet` is in the target
8. Adapt `MIDIController.shared.sendToEditBuffer(payload:)` to your synth's MIDI method name
9. Confirm `PatchCategory.allCases` covers your synth's categories — the Category submenu generates itself from them

---

## Items Not Yet Implemented

- **Send to Slot…** — sheet with bank/program picker to write the patch to a specific hardware slot without overwriting the edit buffer. Deferred: requires a slot picker UI.
- **Add to Set…** — add the selected patch to an existing set as a shared reference (no copy). Deferred: requires a set picker sheet.

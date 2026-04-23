//
//  BankMemoryView.swift
//  brWave
//
//  2-bank × 100-program memory grid (200 slots total).
//  Bank 0 = Behringer factory, Bank 1 = Classic PPG Wave programs.
//  Ported from OBsixer BankMemoryView, adapted for brWave's 2×100 layout.
//

import SwiftUI
import CoreData

// MARK: - Notifications

extension Notification.Name {
    /// Post with `object: Int` — bank index 0 or 1.
    static let bankMemoryScrollTo   = Notification.Name("BankMemoryScrollTo")
}

// MARK: - Per-bank tint palette (2 banks)

private let bankTints: [Color] = [
    Color(red: 0.08, green: 0.25, blue: 0.75),   // 0 — PPG blue (factory)
    Color(red: 0.20, green: 0.45, blue: 0.90),   // 1 — lighter PPG blue (PPG classic)
]

// MARK: - Section descriptor

private struct BankSection: Identifiable {
    let bank:  Int   // 0 or 1
    let start: Int   // first position = bank * 100
    let end:   Int   // last position  = bank * 100 + 99

    var id: Int { start }
    var range: ClosedRange<Int> { start...end }
    var count: Int { 100 }
    var label: String { "Bank \(bank)" }

    static let all: [BankSection] = (0..<2).map { b in
        BankSection(bank: b, start: b * 100, end: b * 100 + 99)
    }
}

// MARK: - Main View

struct BankMemoryView: View {

    /// Which bank to scroll to on appear. Pass -1 to skip.
    let scrollToBank: Int

    @Environment(\.managedObjectContext) private var context

    @FetchRequest(fetchRequest: {
        let req = NSFetchRequest<PatchSet>(entityName: "PatchSet")
        req.sortDescriptors = [NSSortDescriptor(keyPath: \PatchSet.createdAt, ascending: true)]
        req.relationshipKeyPathsForPrefetching = ["slots", "slots.patch"]
        return req
    }())
    private var libraries: FetchedResults<PatchSet>

    @FetchRequest(
        entity: Patch.entity(),
        sortDescriptors: [
            NSSortDescriptor(keyPath: \Patch.bank, ascending: true),
            NSSortDescriptor(keyPath: \Patch.program, ascending: true)
        ]
    )
    private var allPatches: FetchedResults<Patch>

    @EnvironmentObject private var bankEditorState: BankEditorState
    @EnvironmentObject private var patchSelection:  PatchSelection

    private var selectedLibrary: PatchSet? {
        libraries.first { $0.uuid == bankEditorState.selectedLibraryID } ?? libraries.first
    }

    private var isFlatMode: Bool {
        switch bankEditorState.patchListMode {
        case .allPatches, .favorites, .trash: return true
        case .library: return false
        }
    }

    /// All patches for the current flat mode (allPatches / favorites / trash), sorted bank→program.
    private var flatPatches: [Patch] {
        switch bankEditorState.patchListMode {
        case .allPatches: return allPatches.filter { !$0.isTrashed }
        case .favorites:  return allPatches.filter {  $0.isFavorite && !$0.isTrashed }
        case .trash:      return allPatches.filter {  $0.isTrashed }
        case .library:    return []
        }
    }

    private var patchByPosition: [Int: Patch] {
        guard case .library = bankEditorState.patchListMode else { return [:] }
        return selectedLibrary?.patchByPosition ?? [:]
    }

    private var selectedPositions: Set<Int> {
        Set(patchByPosition.compactMap { (pos, patch) in
            patchSelection.selectedIDs.contains(patch.objectID) ? pos : nil
        })
    }
    private var lastTouchedPosition: Int? {
        get { bankEditorState.lastTouchedPosition }
        nonmutating set { bankEditorState.lastTouchedPosition = newValue }
    }

    @State private var didScrollOnAppear = false
    @FocusState private var gridFocused: Bool
    @State private var expandedBanks: Set<Int> = Set(BankSection.all.map { $0.id })
    @State private var viewEpoch = 0
    @State private var dragAnchorPos: Int? = nil
    @State private var slotGridWidth: CGFloat = 600

    private var allExpanded: Bool { expandedBanks.count == BankSection.all.count }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if isFlatMode {
                    flatGrid
                } else {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        let _ = viewEpoch
                        ForEach(BankSection.all) { section in
                            sectionHeader(section, lookup: patchByPosition)
                                .id("hdr-\(section.start)")

                            if expandedBanks.contains(section.id) {
                                slotGrid(section, lookup: patchByPosition)
                                    .padding(.bottom, 16)
                                    .transition(.opacity)
                            }
                        }
                    }
                    .padding(.bottom, 32)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.gridBackground)
            .focusable()
            .focused($gridFocused)
            .onAppear {
                guard !didScrollOnAppear else { return }
                didScrollOnAppear = true
                guard scrollToBank >= 0 else { return }
                let sectionStart = scrollToBank * 100
                DispatchQueue.main.async {
                    _ = expandedBanks.insert(sectionStart)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        withAnimation(.easeInOut(duration: 0.35)) {
                            proxy.scrollTo("hdr-\(sectionStart)", anchor: .top)
                        }
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .bankMemoryScrollTo)) { note in
                guard let bank = note.object as? Int, bank >= 0 else { return }
                let sectionStart = bank * 100
                withAnimation(.easeInOut(duration: 0.2)) { _ = expandedBanks.insert(sectionStart) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        proxy.scrollTo("hdr-\(sectionStart)", anchor: .top)
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("PerformCopy")))      { _ in performCopy() }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("PerformPaste")))     { _ in performPaste() }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("PerformClear")))     { _ in performClear() }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("PerformDuplicate"))) { _ in performDuplicate() }
            .onKeyPress(.escape) {
                patchSelection.selectedIDs          = []
                bankEditorState.lastTouchedPosition = nil
                return .handled
            }
        }
        .navigationTitle("Memory")
        .toolbar { toolbarContent }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {

        ToolbarItem(placement: .navigation) {
            Menu {
                ForEach(libraries) { lib in
                    Button {
                        bankEditorState.selectedLibraryID = lib.uuid
                    } label: {
                        let active = bankEditorState.selectedLibraryID == lib.uuid
                            || (bankEditorState.selectedLibraryID == nil && lib == libraries.first)
                        if active {
                            Label(lib.name ?? "Untitled", systemImage: "checkmark")
                        } else {
                            Text(lib.name ?? "Untitled")
                        }
                    }
                }
                Divider()
                Button("New Library") { createNewLibrary() }
            } label: {
                Label(selectedLibrary?.name ?? "No Library", systemImage: "books.vertical")
            }
            .help("Switch active library")
        }

        ToolbarItem(placement: .navigation) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expandedBanks = allExpanded ? [] : Set(BankSection.all.map { $0.id })
                }
            } label: {
                Image(systemName: allExpanded
                      ? "rectangle.compress.vertical"
                      : "rectangle.expand.vertical")
            }
            .help(allExpanded ? "Collapse All" : "Expand All")
        }

        ToolbarItem(placement: .status) {
            if !selectedPositions.isEmpty {
                Text("\(selectedPositions.count) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Flat grid (All Patches / Favorites / Trash)

    @ViewBuilder
    private var flatGrid: some View {
        let patches = flatPatches
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 110, maximum: 200))],
            spacing: 2
        ) {
            ForEach(patches, id: \.objectID) { patch in
                let pos = Int(patch.bank) * 100 + Int(patch.program)
                SlotCell(
                    position: pos,
                    patch: patch,
                    isSelected: patchSelection.selectedIDs.contains(patch.objectID),
                    onTap: { handleFlatTap(patch: patch) },
                    onDoubleTap: {
                        patchSelection.selectedPatch = patch
                        NotificationCenter.default.post(name: .bankMemoryOpenEditor, object: nil)
                    },
                    onCopy: {
                        patchSelection.selectedIDs = [patch.objectID]
                        performCopy()
                    }
                )
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(GeometryReader { geo in
            Color.clear.onAppear {
                DispatchQueue.main.async { slotGridWidth = geo.size.width - 16 }
            }
        })
    }

    private func handleFlatTap(patch: Patch) {
        gridFocused = true
        let mods = NSApp.currentEvent?.modifierFlags ?? []
        let id = patch.objectID
        if mods.contains(.command) {
            if patchSelection.selectedIDs.contains(id) { patchSelection.selectedIDs.remove(id) }
            else                                        { patchSelection.selectedIDs.insert(id) }
        } else if mods.contains(.shift) {
            patchSelection.selectedIDs.insert(id)
        } else {
            patchSelection.selectedIDs = [id]
            patchSelection.selectedPatch = patch
        }
    }

    // MARK: - Section header

    private func sectionHeader(_ section: BankSection, lookup: [Int: Patch]) -> some View {
        let tint       = bankTints[section.bank]
        let isExpanded = expandedBanks.contains(section.id)
        let occupied   = section.range.filter { lookup[$0] != nil }.count

        return HStack(spacing: 8) {
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .bold))
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .animation(.easeInOut(duration: 0.2), value: isExpanded)
                .foregroundStyle(Theme.waveHighlight.opacity(0.7))
                .frame(width: 12)

            Text("\(section.label)  —  \(occupied)/\(section.count)")
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .foregroundStyle(Theme.labelPrimary.opacity(0.75))

            Rectangle()
                .fill(Theme.labelSecondary.opacity(0.2))
                .frame(height: 1)

            Button {
                withAnimation {
                    let ids = section.range.compactMap { lookup[$0]?.objectID }
                    patchSelection.selectedIDs = Set(ids)
                    lastTouchedPosition = section.start
                }
            } label: {
                Image(systemName: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(Theme.waveHighlight.opacity(0.55))
            }
            .buttonStyle(.plain)
            .help("Select all slots in \(section.label)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(tint.opacity(0.18))
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                if isExpanded { _ = expandedBanks.remove(section.id) }
                else          { _ = expandedBanks.insert(section.id) }
            }
        }
    }

    // MARK: - Slot grid

    private func slotGrid(_ section: BankSection, lookup: [Int: Patch]) -> some View {
        return LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 110, maximum: 200))],
            spacing: 2
        ) {
            ForEach(section.range, id: \.self) { pos in
                SlotCell(
                    position:  pos,
                    patch:     lookup[pos],
                    isSelected: lookup[pos].map { patchSelection.selectedIDs.contains($0.objectID) } ?? false,
                    onTap: { handleTap(pos: pos) },
                    onDoubleTap: {
                        if let patch = lookup[pos] {
                            patchSelection.selectedPatch = patch
                            NotificationCenter.default.post(name: .bankMemoryOpenEditor, object: nil)
                        }
                    },
                    onCopy:  {
                        if let id = lookup[pos]?.objectID { patchSelection.selectedIDs = [id] }
                        lastTouchedPosition = pos
                        performCopy()
                    },
                    onPaste: {
                        lastTouchedPosition = pos
                        performPaste()
                    },
                    onClear: {
                        if let id = lookup[pos]?.objectID { patchSelection.selectedIDs = [id] }
                        lastTouchedPosition = pos
                        performClear()
                    },
                    onDragStarted: {
                        dragAnchorPos = pos
                        if let id = lookup[pos]?.objectID {
                            patchSelection.selectedIDs = [id]
                        } else {
                            patchSelection.selectedIDs = []
                        }
                        lastTouchedPosition = pos
                    },
                    onDragChanged: { translation in
                        guard let anchor = dragAnchorPos else { return }
                        handleDragUpdate(anchorPos: anchor, translation: translation)
                    },
                    onDragEnded: { dragAnchorPos = nil }
                )
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
        .background(GeometryReader { geo in
            Color.clear.onAppear {
                DispatchQueue.main.async { slotGridWidth = geo.size.width - 16 }
            }
        })
    }

    private func handleDragUpdate(anchorPos: Int, translation: CGSize) {
        let cols    = max(1, Int(slotGridWidth / 110))
        let cellW   = slotGridWidth / CGFloat(cols)
        let cellH: CGFloat = 44
        let colDelta = Int((translation.width  + cellW * 0.5) / cellW)
        let rowDelta = Int((translation.height + cellH * 0.5) / cellH)
        let target   = max(0, min(199, anchorPos + rowDelta * cols + colDelta))
        let lo = min(anchorPos, target)
        let hi = max(anchorPos, target)
        let ids = (lo...hi).compactMap { patchByPosition[$0]?.objectID }
        patchSelection.selectedIDs = Set(ids)
        lastTouchedPosition = target
    }

    // MARK: - Selection

    private func handleTap(pos: Int) {
        gridFocused = true
        let mods = NSApp.currentEvent?.modifierFlags ?? []
        lastTouchedPosition = pos

        if mods.contains(.command) {
            if let id = patchByPosition[pos]?.objectID {
                if patchSelection.selectedIDs.contains(id) { patchSelection.selectedIDs.remove(id) }
                else                                        { patchSelection.selectedIDs.insert(id) }
            }
        } else if mods.contains(.shift), let anchor = bankEditorState.lastTouchedPosition {
            let lo  = min(anchor, pos)
            let hi  = max(anchor, pos)
            let ids = (lo...hi).compactMap { patchByPosition[$0]?.objectID }
            patchSelection.selectedIDs.formUnion(ids)
        } else {
            if let id = patchByPosition[pos]?.objectID {
                patchSelection.selectedIDs = [id]
            } else {
                patchSelection.selectedIDs = []
            }
        }

        if patchSelection.selectedIDs.count == 1, let patch = patchByPosition[pos] {
            patchSelection.selectedPatch = patch
        }
    }

    // MARK: - Copy / Paste / Clear / Duplicate

    private func performCopy() {
        guard !selectedPositions.isEmpty else { return }
        let sorted = selectedPositions.sorted()
        let anchor = sorted.first!
        let lookup = patchByPosition
        bankEditorState.clipboard = sorted.compactMap { pos -> (Int, Patch)? in
            guard let patch = lookup[pos] else { return nil }
            return (pos - anchor, patch)
        }
    }

    private func performPaste() {
        guard !bankEditorState.clipboard.isEmpty,
              let lib = selectedLibrary else { return }
        let anchor = selectedPositions.sorted().first ?? bankEditorState.lastTouchedPosition
        guard let anchor else { return }
        let clip = bankEditorState.clipboard
        context.performAndWait {
            for (offset, src) in clip {
                writeSlot(position: anchor + offset, from: src, in: lib, ctx: context)
            }
            try? context.save()
        }
        viewEpoch += 1
    }

    private func performClear() {
        guard let lib = selectedLibrary else { return }
        let positions = selectedPositions
        let lookup    = lib.slotsArray.reduce(into: [Int: PatchSlot]()) { $0[Int($1.position)] = $1 }
        context.performAndWait {
            for pos in positions {
                lookup[pos]?.patch = nil
            }
            try? context.save()
        }
        viewEpoch += 1
    }

    private func performDuplicate() {
        guard !selectedPositions.isEmpty, let lib = selectedLibrary else { return }
        let sourcePairs = selectedPositions.sorted().compactMap { pos -> (Int, Patch)? in
            guard let patch = patchByPosition[pos] else { return nil }
            return (pos, patch)
        }
        guard !sourcePairs.isEmpty else { return }

        let occupied = Set(lib.slotsArray.compactMap { $0.patch != nil ? Int($0.position) : nil })
        let lastPos  = selectedPositions.max() ?? 0
        var nextFree = lastPos + 1
        var newPositions: [Int] = []

        context.performAndWait {
            for (_, src) in sourcePairs {
                while occupied.contains(nextFree) || newPositions.contains(nextFree) {
                    nextFree += 1
                    if nextFree >= 200 { break }
                }
                guard nextFree < 200 else { break }

                let copy             = Patch(context: context)
                copy.copyStoredState(from: src, nameOverride: (src.name ?? "Untitled") + " (copy)")
                PatchSlot.make(position: nextFree, patch: copy, in: lib, ctx: context)
                newPositions.append(nextFree)
                nextFree += 1
            }
            try? context.save()
        }

        lastTouchedPosition = newPositions.first
        viewEpoch += 1
        patchSelection.selectedIDs = Set(newPositions.compactMap { patchByPosition[$0]?.objectID })
    }

    // MARK: - Write helper

    private func writeSlot(position: Int, from src: Patch,
                           in library: PatchSet, ctx: NSManagedObjectContext) {
        guard position >= 0, position < 200 else { return }
        let existingSlot = library.slotsArray.first { Int($0.position) == position }

        if let slot = existingSlot, let dest = slot.patch {
            dest.copyStoredState(from: src)
        } else {
            let copy             = Patch(context: ctx)
            copy.copyStoredState(from: src)
            if let slot = existingSlot { slot.patch = copy }
            else { PatchSlot.make(position: position, patch: copy, in: library, ctx: ctx) }
        }
    }

    // MARK: - Library management

    private func createNewLibrary() {
        let lib = PatchSet.create(named: "New Library", in: context)
        try? context.save()
        bankEditorState.selectedLibraryID = lib.uuid
    }
}

// MARK: - Slot Cell

private struct SlotCell: View {
    let position:   Int
    let patch:      Patch?
    let isSelected: Bool
    var onTap:          () -> Void
    var onDoubleTap:    (() -> Void)? = nil
    var onCopy:         (() -> Void)? = nil
    var onPaste:        (() -> Void)? = nil
    var onClear:        (() -> Void)? = nil
    var onDragStarted:  (() -> Void)? = nil
    var onDragChanged:  ((CGSize) -> Void)? = nil
    var onDragEnded:    (() -> Void)? = nil

    @State private var isDraggingInternal = false

    private var bankNum:    Int    { position / 100 }
    private var programNum: Int    { position % 100 }
    private var posLabel:   String { String(format: "%d·%02d", bankNum, programNum) }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(posLabel)
                .font(.system(size: 9, design: .monospaced).weight(.semibold))
                .foregroundStyle(Theme.labelSecondary)

            if let patch {
                Text(patch.name ?? "—")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.labelPrimary)
                    .lineLimit(1)
            } else {
                Text("empty")
                    .font(.system(size: 11).italic())
                    .foregroundStyle(Theme.labelSecondary.opacity(0.30))
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(
                    isSelected
                        ? Theme.waveHighlight.opacity(0.30)
                        : patch != nil
                            ? Color.white.opacity(0.07)
                            : Color.white.opacity(0.02)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(
                            isSelected
                                ? Theme.waveHighlight.opacity(0.70)
                                : patch != nil
                                    ? Color.white.opacity(0.10)
                                    : Color.clear,
                            lineWidth: 1
                        )
                )
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onDoubleTap?() }
        .onTapGesture(count: 1) { onTap() }
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { value in
                    if !isDraggingInternal {
                        isDraggingInternal = true
                        onDragStarted?()
                    }
                    onDragChanged?(value.translation)
                }
                .onEnded { _ in
                    isDraggingInternal = false
                    onDragEnded?()
                }
        )
        .contextMenu {
            if let patch { Text(patch.name ?? "—").font(.headline); Divider() }
            Button("Copy")  { onCopy?() }
            if onPaste != nil { Button("Paste") { onPaste?() } }
            Button("Clear", role: .destructive) { onClear?() }
        }
    }
}

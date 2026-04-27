//
//  PatchListView.swift
//  brWave
//
//  Narrow patch browser panel shown left of the editor.
//  Routes between entity-based modes (All Patches, Favorites, Trash)
//  and slot-based library/bank mode based on BankEditorState.patchListMode.
//

import SwiftUI
import CoreData

// MARK: - Container

struct PatchListView: View {
    @EnvironmentObject private var bankEditorState: BankEditorState
    @EnvironmentObject private var patchSelection:  PatchSelection
    @Environment(\.managedObjectContext) private var context

    @State private var searchText = ""
    @State private var confirmingTrashAll = false
    @State private var confirmingEmptyTrash = false

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            listBody
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        .confirmationDialog("Move all patches to Trash?",
                            isPresented: $confirmingTrashAll, titleVisibility: .visible) {
            Button("Move All to Trash", role: .destructive) { trashAll() }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Permanently delete all trashed patches?",
                            isPresented: $confirmingEmptyTrash, titleVisibility: .visible) {
            Button("Empty Trash", role: .destructive) { emptyTrash() }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(headerTitle)
                    .font(.headline)
                    .foregroundStyle(isContentAvailable ? Color.primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                PatchCountLabel(mode: bankEditorState.patchListMode,
                                searchText: searchText,
                                selectedLibraryID: bankEditorState.selectedLibraryID,
                                selectedBankIndex: bankEditorState.selectedBankIndex,
                                context: context)
                if bankEditorState.patchListMode == .trash {
                    Button { confirmingEmptyTrash = true } label: {
                        Image(systemName: "trash.slash")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.borderless)
                    .help("Empty Trash")
                }
                if canAddPatch {
                    Menu {
                        Button { addPatch() } label: {
                            Label("New Patch", systemImage: "plus")
                        }
                        Divider()
                        Button(role: .destructive) { confirmingTrashAll = true } label: {
                            Label("Move All to Trash", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("New Patch / More")
                }
            }

            if isContentAvailable {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    TextField("Filter…", text: $searchText)
                        .font(.caption)
                        .textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.06))
                .cornerRadius(5)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    private var headerTitle: String {
        switch bankEditorState.patchListMode {
        case .allPatches: return "All Patches"
        case .favorites:  return "Favorites"
        case .trash:      return "Trash"
        case .library(let uuid, let bankIdx):
            let req: NSFetchRequest<PatchSet> = PatchSet.fetchRequest()
            req.predicate = NSPredicate(format: "uuid == %@", uuid as CVarArg)
            req.fetchLimit = 1
            let libName = (try? context.fetch(req).first?.name) ?? "Set"
            if let b = bankIdx { return "\(libName) › Bank \(b)" }
            return libName
        }
    }

    private var isContentAvailable: Bool {
        switch bankEditorState.patchListMode {
        case .allPatches, .favorites, .trash: return true
        case .library(let uuid, _): return uuid != UUID()
        }
    }

    private var canAddPatch: Bool {
        switch bankEditorState.patchListMode {
        case .allPatches, .favorites: return true
        case .trash, .library: return false
        }
    }

    private func trashAll() {
        let req: NSFetchRequest<Patch> = Patch.fetchRequest()
        req.predicate = NSPredicate(format: "isTrashed == NO OR isTrashed == nil")
        if let patches = try? context.fetch(req) {
            patches.forEach { $0.isTrashed = true }
            try? context.save()
        }
        patchSelection.selectedPatch = nil
    }

    private func emptyTrash() {
        let req: NSFetchRequest<Patch> = Patch.fetchRequest()
        req.predicate = NSPredicate(format: "isTrashed == YES")
        if let patches = try? context.fetch(req) {
            patches.forEach { context.delete($0) }
            try? context.save()
        }
        patchSelection.selectedPatch = nil
    }

    private func addPatch() {
        let patch = Patch(context: context)
        patch.uuid        = UUID()
        patch.name        = "New Patch"
        patch.dateCreated = Date()
        patch.dateModified = Date()
        patch.bank        = -1
        patch.program     = -1
        patch.category    = PatchCategory.uncategorized.rawValue
        let (values, _)   = PatchGenerator.generateValues(.uncategorized)
        patch.patchValues = values
        try? context.save()
        patchSelection.selectedPatch = patch
    }

    // MARK: - List body — route to correct sub-view

    @ViewBuilder
    private var listBody: some View {
        switch bankEditorState.patchListMode {
        case .allPatches:
            EntityPatchList(
                predicate: NSPredicate(format: "isTrashed == NO OR isTrashed == nil"),
                searchText: searchText,
                inTrash: false
            )
        case .favorites:
            EntityPatchList(
                predicate: NSPredicate(format: "isFavorite == YES AND (isTrashed == NO OR isTrashed == nil)"),
                searchText: searchText,
                inTrash: false
            )
        case .trash:
            EntityPatchList(
                predicate: NSPredicate(format: "isTrashed == YES"),
                searchText: searchText,
                inTrash: true
            )
        case .library(let uuid, let bankIdx):
            LibraryPatchList(libraryID: uuid, bankIndex: bankIdx, searchText: searchText)
        }
    }
}

// MARK: - Entity-based list (All Patches / Favorites / Trash)

private struct EntityPatchList: View {
    @EnvironmentObject private var patchSelection: PatchSelection

    let predicate: NSPredicate
    let searchText: String
    let inTrash: Bool

    @FetchRequest private var patches: FetchedResults<Patch>
    @State private var listSelectionID: NSManagedObjectID?

    init(predicate: NSPredicate, searchText: String, inTrash: Bool) {
        self.predicate = predicate
        self.searchText = searchText
        self.inTrash = inTrash
        _patches = FetchRequest(
            entity: Patch.entity(),
            sortDescriptors: [NSSortDescriptor(keyPath: \Patch.name, ascending: true)],
            predicate: predicate,
            animation: .default
        )
    }

    private var filtered: [Patch] {
        guard !searchText.isEmpty else { return Array(patches) }
        let q = searchText.lowercased()
        return patches.filter {
            ($0.name ?? "").lowercased().contains(q) ||
            ($0.designer ?? "").lowercased().contains(q)
        }
    }

    var body: some View {
        if filtered.isEmpty {
            VStack { Spacer(); emptyMessage; Spacer() }
        } else {
            ScrollViewReader { proxy in
                List(selection: $listSelectionID) {
                    ForEach(filtered, id: \.objectID) { patch in
                        PatchEntityRow(
                            patch: patch,
                            isSelected: listSelectionID == patch.objectID,
                            inTrash: inTrash
                        )
                        .tag(patch.objectID)
                        .id(patch.objectID)
                        .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                        .listRowSeparator(.hidden)
                        .listRowBackground(
                            listSelectionID == patch.objectID
                                ? Theme.waveHighlight.opacity(0.15)
                                : Color.clear
                        )
                    }
                }
                .listStyle(.plain)
                .scrollIndicators(.hidden)
                .tint(.clear)
                .onChange(of: listSelectionID) { _, id in
                    guard let id, let patch = filtered.first(where: { $0.objectID == id }) else { return }
                    if patchSelection.selectedPatch?.objectID != id {
                        patchSelection.selectedPatch = patch
                    }
                    withAnimation { proxy.scrollTo(id, anchor: .center) }
                }
                .onChange(of: patchSelection.selectedPatch) { _, p in
                    let id = p?.objectID
                    if listSelectionID != id { listSelectionID = id }
                    if let id, filtered.contains(where: { $0.objectID == id }) {
                        withAnimation { proxy.scrollTo(id, anchor: .center) }
                    }
                }
            }
        }
    }

    @ViewBuilder private var emptyMessage: some View {
        Text(searchText.isEmpty ? (inTrash ? "Trash is empty" : "Nothing here") : "No matches")
            .font(.caption).foregroundStyle(.tertiary)
    }
}

// MARK: - Library / bank slot-based list

private struct LibraryPatchList: View {
    @EnvironmentObject private var patchSelection: PatchSelection

    let libraryID: UUID
    let bankIndex: Int?
    let searchText: String

    @FetchRequest private var fetchedSlots: FetchedResults<PatchSlot>
    @FetchRequest private var fetchedLibrary: FetchedResults<PatchSet>
    @State private var listSelectionID: NSManagedObjectID?

    init(libraryID: UUID, bankIndex: Int?, searchText: String) {
        self.libraryID = libraryID
        self.bankIndex = bankIndex
        self.searchText = searchText

        var slotPredicates: [NSPredicate] = [
            NSPredicate(format: "patchSet.uuid == %@", libraryID as CVarArg),
            NSPredicate(format: "patch != nil")
        ]
        if let b = bankIndex {
            slotPredicates.append(NSPredicate(format: "position >= %d AND position <= %d",
                                              b * 100, b * 100 + 99))
        }
        _fetchedSlots = FetchRequest(
            entity: PatchSlot.entity(),
            sortDescriptors: [NSSortDescriptor(keyPath: \PatchSlot.position, ascending: true)],
            predicate: NSCompoundPredicate(andPredicateWithSubpredicates: slotPredicates),
            animation: .default
        )
        _fetchedLibrary = FetchRequest(
            entity: PatchSet.entity(),
            sortDescriptors: [],
            predicate: NSPredicate(format: "uuid == %@", libraryID as CVarArg)
        )
    }

    private var library: PatchSet? { fetchedLibrary.first }

    private var slots: [PatchSlot] {
        guard !searchText.isEmpty else { return Array(fetchedSlots) }
        let q = searchText.lowercased()
        return fetchedSlots.filter {
            ($0.patch?.name ?? "").lowercased().contains(q) ||
            ($0.patch?.designer ?? "").lowercased().contains(q)
        }
    }

    var body: some View {
        if library == nil {
            VStack {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "books.vertical").font(.title2).foregroundStyle(.tertiary)
                    Text("Select a library\nin the sidebar")
                        .font(.caption).foregroundStyle(.tertiary).multilineTextAlignment(.center)
                }
                Spacer()
            }
        } else if slots.isEmpty {
            VStack {
                Spacer()
                Text(searchText.isEmpty ? "Empty library" : "No matches")
                    .font(.caption).foregroundStyle(.tertiary)
                Spacer()
            }
        } else {
            ScrollViewReader { proxy in
                List(selection: $listSelectionID) {
                    ForEach(slots, id: \.objectID) { slot in
                        SlotPatchRow(
                            slot: slot,
                            isSelected: listSelectionID == slot.objectID
                        )
                        .tag(slot.objectID)
                        .id(slot.objectID)
                        .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                        .listRowSeparator(.hidden)
                        .listRowBackground(
                            listSelectionID == slot.objectID
                                ? Theme.waveHighlight.opacity(0.15)
                                : Color.clear
                        )
                        .contextMenu {
                            if let patch = slot.patch {
                                PatchContextMenuItems(patch: patch, inTrash: false)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollIndicators(.hidden)
                .tint(.clear)
                .onChange(of: listSelectionID) { _, id in
                    guard let id, let slot = slots.first(where: { $0.objectID == id }),
                          let patch = slot.patch else { return }
                    if patchSelection.selectedPatch?.objectID != patch.objectID {
                        patchSelection.selectedPatch = patch
                    }
                    withAnimation { proxy.scrollTo(id, anchor: .center) }
                }
                .onChange(of: patchSelection.selectedPatch) { _, p in
                    guard let p else { listSelectionID = nil; return }
                    // If current selection already points to this patch, don't clobber it.
                    // Prevents the feedback loop: click slot A → loads patch → finds slot B
                    // (earlier dupe) → overwrites listSelectionID → wrong row highlights.
                    if let curID = listSelectionID,
                       slots.first(where: { $0.objectID == curID })?.patch?.objectID == p.objectID {
                        withAnimation { proxy.scrollTo(curID, anchor: .center) }
                        return
                    }
                    if let slot = slots.first(where: { $0.patch?.objectID == p.objectID }) {
                        listSelectionID = slot.objectID
                        withAnimation { proxy.scrollTo(slot.objectID, anchor: .center) }
                    } else {
                        listSelectionID = nil
                    }
                }
            }
        }
    }
}

// MARK: - Patch row (entity mode)

private struct PatchEntityRow: View {
    @ObservedObject var patch: Patch
    let isSelected: Bool
    let inTrash: Bool

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Theme.waveHighlight.opacity(0.7))
                .frame(width: 7, height: 7)

            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(patch.name ?? "Untitled")
                        .font(.system(size: 12))
                        .foregroundStyle(isSelected ? Theme.waveHighlight : .primary)
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    if patch.isFavorite && !inTrash {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.waveHighlight)
                    }
                }
                if let designer = patch.designer, !designer.isEmpty {
                    Text(designer)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .tracking(0.3)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 3)
        .contextMenu { PatchContextMenuItems(patch: patch, inTrash: inTrash) }
    }
}

// MARK: - Slot row (library mode)

private struct SlotPatchRow: View {
    let slot: PatchSlot
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Theme.waveHighlight.opacity(0.7))
                .frame(width: 7, height: 7)

            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(slot.patch?.name ?? "Untitled")
                        .font(.system(size: 12))
                        .foregroundStyle(isSelected ? Theme.waveHighlight : .primary)
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    if slot.patch?.isFavorite == true {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.waveHighlight)
                    }
                    if let initials = designerInitials {
                        Text(initials)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(isSelected ? Theme.waveHighlight.opacity(0.7) : .secondary)
                    }
                }
                if let designer = slot.patch?.designer, !designer.isEmpty {
                    Text(designer)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .tracking(0.3)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 3)
    }

    private var designerInitials: String? {
        guard let designer = slot.patch?.designer, !designer.isEmpty else { return nil }
        let words = designer.split(separator: " ")
        if words.count >= 2 { return String(words[0].prefix(1) + words[1].prefix(1)) }
        return String(designer.prefix(2))
    }
}

// MARK: - Context menu items (shared)

private struct PatchContextMenuItems: View {
    @ObservedObject var patch: Patch
    let inTrash: Bool

    var body: some View {
        if inTrash {
            Button {
                patch.isTrashed = false
                try? patch.managedObjectContext?.save()
            } label: {
                Label("Restore", systemImage: "arrow.uturn.backward")
            }
            Divider()
            Button(role: .destructive) {
                patch.managedObjectContext?.delete(patch)
                try? patch.managedObjectContext?.save()
            } label: {
                Label("Delete Permanently", systemImage: "trash.fill")
            }
        } else {
            Button {
                patch.isFavorite.toggle()
                try? patch.managedObjectContext?.save()
            } label: {
                Label(patch.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                      systemImage: patch.isFavorite ? "star.fill" : "star")
            }
            Button {
                NotificationCenter.default.post(name: .replicatePatch, object: patch)
            } label: {
                Label("Replicate", systemImage: "plus.square.on.square")
            }
            Divider()
            Button(role: .destructive) {
                patch.isTrashed = true
                try? patch.managedObjectContext?.save()
            } label: {
                Label("Move to Trash", systemImage: "trash")
            }
        }
    }
}

// MARK: - Live count helper

private struct PatchCountLabel: View {
    let mode: PatchListMode
    let searchText: String
    let selectedLibraryID: UUID?
    let selectedBankIndex: Int?
    let context: NSManagedObjectContext

    var body: some View {
        Text("\(count)")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
    }

    private var count: Int {
        switch mode {
        case .allPatches:
            let req: NSFetchRequest<Patch> = Patch.fetchRequest()
            req.predicate = NSPredicate(format: "isTrashed == NO OR isTrashed == nil")
            return (try? context.count(for: req)) ?? 0
        case .favorites:
            let req: NSFetchRequest<Patch> = Patch.fetchRequest()
            req.predicate = NSPredicate(format: "isFavorite == YES AND (isTrashed == NO OR isTrashed == nil)")
            return (try? context.count(for: req)) ?? 0
        case .trash:
            let req: NSFetchRequest<Patch> = Patch.fetchRequest()
            req.predicate = NSPredicate(format: "isTrashed == YES")
            return (try? context.count(for: req)) ?? 0
        case .library(let uuid, let bankIdx):
            let req: NSFetchRequest<PatchSet> = PatchSet.fetchRequest()
            req.predicate = NSPredicate(format: "uuid == %@", uuid as CVarArg)
            req.fetchLimit = 1
            guard let lib = try? context.fetch(req).first else { return 0 }
            var all = lib.slotsArray.filter { $0.patch != nil }
            if let b = bankIdx {
                let minPos = b * 100; let maxPos = minPos + 99
                all = all.filter { Int($0.position) >= minPos && Int($0.position) <= maxPos }
            }
            return all.count
        }
    }
}

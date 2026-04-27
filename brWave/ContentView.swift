//
//  ContentView.swift
//  brWave
//

import SwiftUI
import CoreData

// MARK: - Inspector Bus

enum InspectorBus {
    static let toggle = Notification.Name("InspectorBus.toggle")
    static let show   = Notification.Name("InspectorBus.show")
    static let hide   = Notification.Name("InspectorBus.hide")
}

// MARK: - Bank Memory notification

extension Notification.Name {
    static let bankMemoryOpenEditor    = Notification.Name("bankMemoryOpenEditor")
    static let purgeLibrary            = Notification.Name("purgeLibrary")
    static let applyNamesFromClipboard = Notification.Name("applyNamesFromClipboard")
    static let showFetchRangeSheet     = Notification.Name("showFetchRangeSheet")
    static let removeDuplicatesAll     = Notification.Name("removeDuplicatesAll")
    static let replicatePatch          = Notification.Name("replicatePatch")
    static let explorePatch            = Notification.Name("explorePatch")
}

// MARK: - Sidebar Items

enum SidebarItem: Hashable {
    case allPatches
    case favorites
    case trash
    case library(UUID)
    case libraryBank(UUID, Int)

    var title: String {
        switch self {
        case .allPatches:              return "All Patches"
        case .favorites:               return "Favorites"
        case .trash:                   return "Trash"
        case .library:                 return "Set"
        case .libraryBank(_, let b):   return "Bank \(b)"
        }
    }
}

// MARK: - View Modes

enum AppViewMode: String, CaseIterable, Identifiable {
    case editor   = "Patch"
    case transient  = "Transient"
    case banks    = "Banks"
    case galaxy   = "Galaxy"
    case monitor  = "Monitor"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .editor:   return "slider.horizontal.3"
        case .transient:  return "pianokeys"
        case .banks:    return "building.columns"
        case .galaxy:   return "sparkles"
        case .monitor:  return "desktopcomputer"
        case .settings: return "gearshape"
        }
    }
}

// MARK: - Inspector Preference

struct InspectorBox: Equatable {
    let id: String
    let view: AnyView
    static func == (lhs: InspectorBox, rhs: InspectorBox) -> Bool { lhs.id == rhs.id }
}

struct InspectorContentKey: PreferenceKey {
    static var defaultValue = InspectorBox(id: "empty", view: AnyView(EmptyView()))
    static func reduce(value: inout InspectorBox, nextValue: () -> InspectorBox) { value = nextValue() }
}

// MARK: - Content View

struct ContentView: View {
    @State private var sidebarSelection: Set<SidebarItem> = [.allPatches]
    @State private var viewMode: AppViewMode = .editor
    @State private var inspectorPresented = true
    @State private var inspectorContent   = InspectorBox(id: "empty", view: AnyView(EmptyView()))
    @State private var showingNamesSheet      = false
    @State private var showingFetchRangeSheet = false
    @State private var showingExplorer        = false
    @State private var explorerPatch: Patch?
    @StateObject private var sampleMapperState = SampleMapperState()
    @AppStorage("patchListVisible") private var patchListVisible = true

    @EnvironmentObject var bankEditorState: BankEditorState
    @EnvironmentObject var patchSelection:  PatchSelection
    @Environment(\.managedObjectContext) var context

    private func handleSidebarChange(_ newValue: Set<SidebarItem>) {
        var libIDs: Set<UUID> = []
        for item in newValue {
            if case .library(let uuid) = item { libIDs.insert(uuid) }
        }
        bankEditorState.selectedLibraryIDs = libIDs

        var sources: Set<BankSource> = []
        for item in newValue {
            switch item {
            case .libraryBank(let uuid, let bankIdx):
                let req: NSFetchRequest<PatchSet> = PatchSet.fetchRequest()
                req.predicate = NSPredicate(format: "uuid == %@", uuid as CVarArg)
                req.fetchLimit = 1
                let name = (try? context.fetch(req).first?.name) ?? "Set"
                sources.insert(BankSource(libraryID: uuid, libraryName: name, bankIndex: bankIdx))
            case .library(let uuid):
                let req: NSFetchRequest<PatchSet> = PatchSet.fetchRequest()
                req.predicate = NSPredicate(format: "uuid == %@", uuid as CVarArg)
                req.fetchLimit = 1
                if let lib = try? context.fetch(req).first {
                    let name = lib.name ?? "Set"
                    var banks = Set<Int>()
                    lib.slotsArray.forEach { banks.insert($0.bankIndex) }
                    banks.forEach { sources.insert(BankSource(libraryID: uuid, libraryName: name, bankIndex: $0)) }
                }
            default: break
            }
        }
        bankEditorState.selectedBankSources = sources

        guard newValue.count == 1, let item = newValue.first else { return }
        switch item {
        case .allPatches:
            bankEditorState.patchListMode = .allPatches
            patchListVisible = true
        case .favorites:
            bankEditorState.patchListMode = .favorites
            patchListVisible = true
        case .trash:
            bankEditorState.patchListMode = .trash
            patchListVisible = true
        case .library(let uuid):
            bankEditorState.selectedLibraryID = uuid
            bankEditorState.selectedBankIndex = nil
            bankEditorState.patchListMode = .library(uuid, bankIndex: nil)
            patchListVisible = true
        case .libraryBank(let uuid, let bankIdx):
            bankEditorState.selectedLibraryID = uuid
            bankEditorState.selectedBankIndex = bankIdx
            bankEditorState.patchListMode = .library(uuid, bankIndex: bankIdx)
            patchListVisible = true
        }
    }

    private func replicatePatch(_ patch: Patch?) {
        // Multi-select: replicate all selected patches when more than one is selected.
        let ids = patchSelection.selectedIDs
        if ids.count > 1 {
            replicatePatches(ids)
            return
        }
        guard let src = patch else { return }

        let copy = Patch(context: context)
        copy.copyStoredState(from: src, nameOverride: (src.name ?? "Untitled") + " (copy)")
        copy.uuid = UUID()

        // Slot it into the current library if in library mode.
        if case .library(let libraryID, let bankIndex) = bankEditorState.patchListMode {
            let req: NSFetchRequest<PatchSet> = PatchSet.fetchRequest()
            req.predicate = NSPredicate(format: "uuid == %@", libraryID as CVarArg)
            req.fetchLimit = 1
            if let library = try? context.fetch(req).first {
                let occupied = Set(library.slotsArray.compactMap { $0.patch != nil ? Int($0.position) : nil })
                let srcPos = library.slotsArray.first(where: { $0.patch?.objectID == src.objectID }).map { Int($0.position) }
                var nextFree = (srcPos ?? occupied.max() ?? -1) + 1
                let bankMin = bankIndex.map { $0 * 100 } ?? 0
                let bankMax = bankIndex.map { $0 * 100 + 199 } ?? 199
                nextFree = max(nextFree, bankMin)
                while occupied.contains(nextFree) && nextFree <= bankMax { nextFree += 1 }
                if nextFree <= bankMax {
                    PatchSlot.make(position: nextFree, patch: copy, in: library, ctx: context)
                }
            }
        }

        try? context.save()
        patchSelection.selectedPatch = copy
    }

    private func replicatePatches(_ ids: Set<NSManagedObjectID>) {
        // Fetch all selected patches and sort by slot position so copies land in the same order.
        let sources: [Patch] = ids.compactMap { context.object(with: $0) as? Patch }

        guard !sources.isEmpty else { return }

        var copies: [Patch] = []

        if case .library(let libraryID, let bankIndex) = bankEditorState.patchListMode,
           let library = fetchLibrary(id: libraryID) {

            // Sort sources by their current slot position.
            let slotByID: [NSManagedObjectID: Int] = Dictionary(
                uniqueKeysWithValues: library.slotsArray.compactMap { slot in
                    guard let p = slot.patch else { return nil }
                    return (p.objectID, Int(slot.position))
                }
            )
            let sorted = sources.sorted {
                (slotByID[$0.objectID] ?? Int.max) < (slotByID[$1.objectID] ?? Int.max)
            }

            // Grow the occupied set as each copy is placed, so copies don't collide.
            var occupied = Set(library.slotsArray.compactMap { $0.patch != nil ? Int($0.position) : nil })
            let bankMin = bankIndex.map { $0 * 100 } ?? 0
            let bankMax = bankIndex.map { $0 * 100 + 199 } ?? 199

            for src in sorted {
                let copy = Patch(context: context)
                copy.copyStoredState(from: src, nameOverride: (src.name ?? "Untitled") + " (copy)")
                copy.uuid = UUID()
                copies.append(copy)

                let srcPos = slotByID[src.objectID] ?? occupied.max() ?? -1
                var nextFree = srcPos + 1
                nextFree = max(nextFree, bankMin)
                while occupied.contains(nextFree) && nextFree <= bankMax { nextFree += 1 }
                if nextFree <= bankMax {
                    PatchSlot.make(position: nextFree, patch: copy, in: library, ctx: context)
                    occupied.insert(nextFree)
                }
            }
        } else {
            // Outside library mode — just create the entities, no slots.
            for src in sources {
                let copy = Patch(context: context)
                copy.copyStoredState(from: src, nameOverride: (src.name ?? "Untitled") + " (copy)")
                copy.uuid = UUID()
                copies.append(copy)
            }
        }

        try? context.save()
        // Select all copies so the user can see what was created.
        patchSelection.selectedIDs  = Set(copies.map { $0.objectID })
        patchSelection.selectedPatch = copies.last
    }

    private func fetchLibrary(id: UUID) -> PatchSet? {
        let req: NSFetchRequest<PatchSet> = PatchSet.fetchRequest()
        req.predicate = NSPredicate(format: "uuid == %@", id as CVarArg)
        req.fetchLimit = 1
        return try? context.fetch(req).first
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $sidebarSelection, viewMode: $viewMode)
        } detail: {
            DetailView(
                viewMode: $viewMode,
                patchListVisible: $patchListVisible,
                sampleMapperState: sampleMapperState
            )
                .onPreferenceChange(InspectorContentKey.self) { box in
                    if inspectorContent.id != box.id { inspectorContent = box }
                }
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                patchListVisible.toggle()
                            }
                        } label: {
                            Label("Toggle Patch List", systemImage: "rectangle.ratio.9.to.16")
                        }
                    }

                    ToolbarItemGroup(placement: .principal) {
                        AppViewModePicker(selection: $viewMode)
                    }

                    ToolbarItemGroup(placement: .primaryAction) {
                        Button {
                            NotificationCenter.default.post(name: InspectorBus.toggle, object: nil)
                        } label: {
                            Label("Toggle Inspector", systemImage: "sidebar.right")
                        }
                    }
                }
        }
        .inspector(isPresented: $inspectorPresented) {
            inspectorContent.view
                .id(inspectorContent.id)
        }
        .onChange(of: sidebarSelection) { _, newValue in
            handleSidebarChange(newValue)
        }
        .onReceive(NotificationCenter.default.publisher(for: InspectorBus.toggle)) { _ in
            inspectorPresented.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: InspectorBus.show)) { _ in
            inspectorPresented = true
        }
        .onReceive(NotificationCenter.default.publisher(for: InspectorBus.hide)) { _ in
            inspectorPresented = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .bankMemoryOpenEditor)) { _ in
            viewMode = .editor
        }
        .onReceive(NotificationCenter.default.publisher(for: .applyNamesFromClipboard)) { _ in
            showingNamesSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .showFetchRangeSheet)) { _ in
            showingFetchRangeSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .replicatePatch)) { note in
            let patch = (note.object as? Patch) ?? patchSelection.selectedPatch
            replicatePatch(patch)
        }
        .onReceive(NotificationCenter.default.publisher(for: .explorePatch)) { note in
            let patch = (note.object as? Patch) ?? patchSelection.selectedPatch
            guard let patch else { return }
            explorerPatch    = patch
            showingExplorer  = true
        }
        .sheet(isPresented: $showingNamesSheet) {
            PatchNamesSheet()
                .environment(\.managedObjectContext, context)
        }
        .sheet(isPresented: $showingFetchRangeSheet) {
            FetchRangeSheet()
                .environment(\.managedObjectContext, context)
        }
        .sheet(isPresented: $showingExplorer) {
            if let patch = explorerPatch {
                BayesianExplorerSheet(patch: patch, context: context)
            }
        }
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @Binding var selection: Set<SidebarItem>
    @Binding var viewMode: AppViewMode

    @EnvironmentObject var bankEditorState: BankEditorState
    @Environment(\.managedObjectContext) private var context

    @FetchRequest(
        entity: PatchSet.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \PatchSet.createdAt, ascending: true)],
        animation: .default
    )
    private var libraries: FetchedResults<PatchSet>

    @State private var expandedLibraries: Set<UUID> = []
    @State private var deleteTarget: PatchSet?
    @State private var renameTarget: PatchSet?
    @State private var renameText = ""
    @State private var showingPurgeDialog  = false
    @State private var showingDedupDialog  = false

    private func occupiedBanks(for lib: PatchSet) -> [Int] {
        var banks = Set<Int>()
        for slot in lib.slotsArray { banks.insert(slot.bankIndex) }
        return banks.sorted()
    }

    private func bankName(_ index: Int) -> String {
        switch index {
        case 0: return "Bank 0 — Factory"
        case 1: return "Bank 1 — PPG Classic"
        default: return "Bank \(index)"
        }
    }

    private func rowBackground(_ item: SidebarItem) -> Color {
        selection.contains(item) ? Theme.waveHighlight.opacity(0.25) : .clear
    }

    var body: some View {
        List(selection: $selection) {
            Section("Library") {
                Label("All Patches", systemImage: "square.grid.2x2")
                    .tag(SidebarItem.allPatches)
                    .listRowBackground(rowBackground(.allPatches))
                Label("Favorites", systemImage: "star")
                    .tag(SidebarItem.favorites)
                    .listRowBackground(rowBackground(.favorites))
                Label("Trash", systemImage: "trash")
                    .tag(SidebarItem.trash)
                    .listRowBackground(rowBackground(.trash))
            }

            Section(header: HStack {
                Text("Sets")
                Spacer()
                Button {
                    let lib = PatchSet.create(named: "New Set", in: context)
                    try? context.save()
                    selection = [.library(lib.uuid!)]
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .help("New Set")
            }) {
                    ForEach(libraries) { lib in
                        let uuid = lib.uuid!
                        DisclosureGroup(
                            isExpanded: Binding(
                                get: { expandedLibraries.contains(uuid) },
                                set: { open in
                                    if open { expandedLibraries.insert(uuid) }
                                    else     { expandedLibraries.remove(uuid) }
                                }
                            )
                        ) {
                            ForEach(occupiedBanks(for: lib), id: \.self) { bank in
                                let bankItem = SidebarItem.libraryBank(uuid, bank)
                                let bankCount = lib.slotsArray.filter {
                                    $0.patch != nil && $0.bankIndex == bank
                                }.count
                                Label(bankName(bank), systemImage: "folder")
                                    .badge(bankCount)
                                    .tag(bankItem)
                                    .listRowBackground(rowBackground(bankItem))
                            }
                        } label: {
                            Label(lib.name ?? "Untitled", systemImage: "books.vertical")
                                .badge(lib.occupiedCount)
                                .contextMenu {
                                    Button("Rename…") {
                                        renameText   = lib.name ?? ""
                                        renameTarget = lib
                                    }
                                    Divider()
                                    Button("Delete", role: .destructive) { deleteTarget = lib }
                                }
                        }
                        .tag(SidebarItem.library(uuid))
                        .listRowBackground(rowBackground(.library(uuid)))
                    }
                }
        }
        .listStyle(.sidebar)
        .navigationTitle("brWave")
        .searchable(text: .constant(""), placement: .sidebar, prompt: "Search")
        .alert("Delete Set?",
               isPresented: Binding(get: { deleteTarget != nil },
                                    set: { if !$0 { deleteTarget = nil } })) {
            Button("Cancel", role: .cancel) { deleteTarget = nil }
            Button("Delete", role: .destructive) {
                if let lib = deleteTarget {
                    if bankEditorState.selectedLibraryID == lib.uuid {
                        bankEditorState.selectedLibraryID = nil
                    }
                    context.delete(lib)
                    try? context.save()
                }
                deleteTarget = nil
            }
        } message: {
            Text("The set \"\(deleteTarget?.name ?? "")\" and its slot assignments will be removed.")
        }
        .onReceive(NotificationCenter.default.publisher(for: .purgeLibrary)) { _ in
            showingPurgeDialog = true
        }
        .sheet(isPresented: $showingPurgeDialog) {
            LibraryPurgeDialog(mode: .purgeAll)
                .environment(\.managedObjectContext, context)
        }
        .onReceive(NotificationCenter.default.publisher(for: .removeDuplicatesAll)) { _ in
            showingDedupDialog = true
        }
        .sheet(isPresented: $showingDedupDialog) {
            LibraryPurgeDialog(mode: .removeAllDuplicates)
                .environment(\.managedObjectContext, context)
        }
        .alert("Rename Set", isPresented: Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) { renameTarget = nil }
            Button("Rename") {
                if let lib = renameTarget,
                   !renameText.trimmingCharacters(in: .whitespaces).isEmpty {
                    lib.name       = renameText.trimmingCharacters(in: .whitespaces)
                    lib.modifiedAt = Date()
                    try? context.save()
                }
                renameTarget = nil
            }
        } message: { EmptyView() }
    }
}

// MARK: - Detail

struct DetailView: View {
    @Binding var viewMode: AppViewMode
    @Binding var patchListVisible: Bool
    @ObservedObject var sampleMapperState: SampleMapperState

    @EnvironmentObject var bankEditorState: BankEditorState
    @EnvironmentObject var patchSelection:  PatchSelection
    @Environment(\.managedObjectContext) var context

    var body: some View {
        contentView
            .safeAreaInset(edge: .bottom, spacing: 0) {
                BulkTransferBanner()
            }
    }

    @ViewBuilder
    private var contentView: some View {
        switch viewMode {
        case .editor:
            HStack(spacing: 0) {
                if patchListVisible {
                    PatchListView()
                        .frame(minWidth: 220, maxWidth: 220)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    Divider()
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
                PatchEditorView()
                    .frame(maxWidth: .infinity)
            }
        case .transient:
            SampleMapperView(mapper: sampleMapperState)
        case .banks:
            BankMemoryView(scrollToBank: 0)
        case .galaxy:
            GalaxyView()
        case .monitor:
            MIDIMonitorView()
        case .settings:
            SettingsView()
        }
    }
}

// MARK: - Bulk Transfer Banner

private struct BulkTransferBanner: View {
    @ObservedObject private var midi = MIDIController.shared

    var body: some View {
        if midi.isBulkTransferActive {
            VStack(spacing: 0) {
                Divider()
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        if !midi.bulkOperationLabel.isEmpty {
                            Text(midi.bulkOperationLabel)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        ProgressView(value: midi.bulkTransferProgress)
                            .progressViewStyle(.linear)
                            .tint(Theme.waveHighlight)
                    }
                    .frame(maxWidth: .infinity)

                    let done = Int((midi.bulkTransferProgress * Double(midi.bulkTotalCount)).rounded())
                    Text("\(done) / \(midi.bulkTotalCount)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 60, alignment: .trailing)

                    Button {
                        midi.cancelBulkTransfer()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Cancel transfer")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.easeInOut(duration: 0.2), value: midi.isBulkTransferActive)
        }
    }
}

// MARK: - Helpers

func toggleSidebar() {
    NSApp.keyWindow?.firstResponder?.tryToPerform(
        #selector(NSSplitViewController.toggleSidebar(_:)), with: nil)
}

// MARK: - App View Mode Picker

private struct AppViewModePicker: View {
    @Binding var selection: AppViewMode

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppViewMode.allCases) { mode in
                Button {
                    selection = mode
                } label: {
                    Label(mode.rawValue, systemImage: mode.icon)
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .foregroundStyle(selection == mode ? Color.primary : Color.secondary)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(selection == mode
                                      ? Color.secondary.opacity(0.25)
                                      : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Fetch Range Sheet

struct FetchRangeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context

    @State private var bank: Int = 0
    @State private var fromSlot: Int = 0
    @State private var toSlot: Int = 99
    @State private var libraryName: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Fetch Patches from Synth")
                .font(.headline)

            Picker("Bank", selection: $bank) {
                Text("Bank 0 — Factory").tag(0)
                Text("Bank 1 — PPG Classic").tag(1)
            }
            .pickerStyle(.segmented)
            .onChange(of: bank)     { _, _ in refreshName() }
            .onChange(of: fromSlot) { _, _ in refreshName() }
            .onChange(of: toSlot)   { _, _ in refreshName() }

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("From slot")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("0", value: $fromSlot, formatter: slotFormatter)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                        .onChange(of: fromSlot) { _, v in
                            fromSlot = max(0, min(99, v))
                            if toSlot < fromSlot { toSlot = fromSlot }
                        }
                }
                Text("–")
                    .padding(.top, 16)
                VStack(alignment: .leading, spacing: 4) {
                    Text("To slot")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("99", value: $toSlot, formatter: slotFormatter)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                        .onChange(of: toSlot) { _, v in
                            toSlot = max(fromSlot, min(99, v))
                        }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Slots")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(toSlot - fromSlot + 1)")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(Theme.waveHighlight)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Save into set")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Library name", text: $libraryName)
                    .textFieldStyle(.roundedBorder)
            }

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Fetch") {
                    let name = libraryName.trimmingCharacters(in: .whitespaces).isEmpty
                        ? defaultLibraryName() : libraryName.trimmingCharacters(in: .whitespaces)
                    MIDIController.shared.fetchRange(bank: bank, fromSlot: fromSlot, toSlot: toSlot,
                                                     into: context, libraryName: name)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.waveHighlight)
                .keyboardShortcut(.defaultAction)
                .disabled(MIDIController.shared.isBulkTransferActive)
            }
        }
        .padding(24)
        .frame(width: 360)
        .onAppear { libraryName = defaultLibraryName() }
    }

    private func defaultLibraryName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let date = formatter.string(from: Date())
        if fromSlot == 0 && toSlot == 99 {
            return "B-Wave B\(bank) — \(date)"
        }
        return "B-Wave B\(bank) P\(String(format: "%02d", fromSlot))–P\(String(format: "%02d", toSlot)) — \(date)"
    }

    private func refreshName() {
        libraryName = defaultLibraryName()
    }

    private var slotFormatter: NumberFormatter {
        let f = NumberFormatter()
        f.minimum = 0
        f.maximum = 99
        f.allowsFloats = false
        return f
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        .environmentObject(BankEditorState())
        .environmentObject(PatchSelection())
}

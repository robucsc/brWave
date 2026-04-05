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
        case .library:                 return "Library"
        case .libraryBank(_, let b):   return "Bank \(b)"
        }
    }
}

// MARK: - View Modes

enum AppViewMode: String, CaseIterable, Identifiable {
    case editor   = "Patch"
    case samples  = "Samples"
    case banks    = "Banks"
    case galaxy   = "Galaxy"
    case monitor  = "Monitor"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .editor:   return "slider.horizontal.3"
        case .samples:  return "pianokeys"
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
    @State private var showingNamesSheet   = false
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
                let name = (try? context.fetch(req).first?.name) ?? "Library"
                sources.insert(BankSource(libraryID: uuid, libraryName: name, bankIndex: bankIdx))
            case .library(let uuid):
                let req: NSFetchRequest<PatchSet> = PatchSet.fetchRequest()
                req.predicate = NSPredicate(format: "uuid == %@", uuid as CVarArg)
                req.fetchLimit = 1
                if let lib = try? context.fetch(req).first {
                    let name = lib.name ?? "Library"
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
        .sheet(isPresented: $showingNamesSheet) {
            PatchNamesSheet()
                .environment(\.managedObjectContext, context)
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
    @State private var showingPurgeDialog = false

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
                Text("Libraries")
                Spacer()
                Button {
                    let lib = PatchSet.create(named: "New Library", in: context)
                    try? context.save()
                    selection = [.library(lib.uuid!)]
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .help("New Library")
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
        .alert("Delete Library?",
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
            Text("\"\(deleteTarget?.name ?? "")\" and its slot assignments will be removed.")
        }
        .onReceive(NotificationCenter.default.publisher(for: .purgeLibrary)) { _ in
            showingPurgeDialog = true
        }
        .sheet(isPresented: $showingPurgeDialog) {
            LibraryPurgeDialog()
                .environment(\.managedObjectContext, context)
        }
        .alert("Rename Library", isPresented: Binding(
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
        case .samples:
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

// MARK: - Preview

#Preview {
    ContentView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        .environmentObject(BankEditorState())
        .environmentObject(PatchSelection())
}

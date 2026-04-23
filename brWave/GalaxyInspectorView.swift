//
//  GalaxyInspectorView.swift
//  brWave
//

import SwiftUI
import CoreData

struct GalaxyHierarchy {
    struct Group: Hashable {
        let name: String
        let categories: [PatchCategory]
    }
    
    static let groups: [Group] = [
        Group(name: "Synth", categories: [.bass, .lead, .poly, .arp, .sequence]),
        Group(name: "Keys & Pad", categories: [.pad, .keys, .organ, .piano]),
        Group(name: "Orchestral", categories: [.strings, .brass]),
        Group(name: "FX & Perc", categories: [.fx, .percussion]),
        Group(name: "Other", categories: [.uncategorized])
    ]
    
    static let allCategoryNames: Set<String> = {
        var names = Set<String>()
        PatchCategory.allCases.forEach { names.insert($0.rawValue) }
        return names
    }()
    
    static func color(for cat: PatchCategory) -> Color { cat.color }
}

struct GalaxyInspectorView: View {
    @Binding var selected: Patch?
    var selectedIDs: Set<NSManagedObjectID> = []
    @Binding var visibleCategories: Set<String>
    @Binding var showConstellations: Bool
    @Binding var showLabels: Bool
    
    // Called when inspector search produces results
    var onSearchResult: ((Set<NSManagedObjectID>, Patch?) -> Void)?
    
    var sourcePatch: Patch?
    var similarMatches: [SimilarityEngine.Match] = []
    var onSelectMatch: ((Patch) -> Void)?
    
    @Environment(\.managedObjectContext) private var context
    
    // Search
    @StateObject private var searchService = SmartLibrarySearchService()
    @State private var searchText = ""
    
    @State private var patchSectionExpanded    = true
    @State private var statsSectionExpanded    = true
    @State private var similarSectionExpanded  = true
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                
                // ── Timbral Search ───────────────────────────────────────
                VStack(alignment: .leading, spacing: 6) {
                    Text("Timbral Search")
                        .font(.headline)
                    
                    HStack(spacing: 6) {
                        Image(systemName: "sparkle.magnifyingglass")
                            .foregroundStyle(Theme.waveHighlight)
                            .font(.system(size: 13))
                        
                        TextField("Describe a sound… or anything", text: $searchText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .onSubmit { performSearch() }
                        
                        if searchService.isProcessing {
                            ProgressView().controlSize(.mini)
                        } else if !searchText.isEmpty {
                            Button {
                                searchText = ""
                                searchService.clear()
                                onSearchResult?([], nil)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(Color.secondary)
                                    .font(.system(size: 12))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    
                    if let result = searchService.lastResult {
                        HStack {
                            Text(result.extractedDescription)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            Spacer()
                            Text("\(result.patches.count)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(Theme.waveHighlight)
                        }
                        
                        Button("Save as New Bank") {
                            newLibraryFromSearchResults()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.waveHighlight)
                        .controlSize(.mini)
                    }
                }
                .padding(10)
                .background(Theme.waveHighlight.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                
                if selectedIDs.count > 1 {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("\(selectedIDs.count) patches selected")
                                .font(.headline)
                            Spacer()
                            Button("Clear") {
                                onSearchResult?([], nil)
                            }
                            .font(.caption)
                            .buttonStyle(.link)
                        }
                        Button {
                            // fill bank
                            let formatter = DateFormatter()
                            formatter.dateFormat = "yyyy-MM-dd HH:mm"
                            let lib = PatchSet.create(named: "Selection \(formatter.string(from: Date()))", in: context)
                            let req: NSFetchRequest<Patch> = Patch.fetchRequest()
                            req.predicate = NSPredicate(format: "self IN %@", selectedIDs)
                            if let selectedPatches = try? context.fetch(req) {
                                for (idx, p) in selectedPatches.enumerated() {
                                    PatchSlot.make(position: idx, patch: p, in: lib, ctx: context)
                                }
                                try? context.save()
                            }
                        } label: {
                            Label("Fill Bank with Selection…", systemImage: "square.grid.3x3.fill")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.waveHighlight)
                    }
                    .padding(10)
                    .background(Theme.waveHighlight.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                
                Divider()
                
                // ── Selected patch ───────────────────────────────────────
                if let patch = selected {
                    DisclosureGroup(
                        isExpanded: $patchSectionExpanded,
                        content: {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Name: \(patch.name ?? "Untitled")").font(.body)
                                Text("Category: \(patch.patchCategory.rawValue)").font(.subheadline)
                                Text("Bank/Program: \(patch.bank) / \(patch.program)")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                            .padding(.top, 8)
                        },
                        label: {
                            Text(selectedIDs.count > 1 ? "Primary Patch" : "Selected Patch")
                                .font(.headline)
                        }
                    )
                    
                    if !similarMatches.isEmpty {
                        DisclosureGroup(
                            isExpanded: $similarSectionExpanded,
                            content: {
                                VStack(spacing: 4) {
                                    ForEach(similarMatches) { match in
                                        Button {
                                            onSelectMatch?(match.patch)
                                        } label: {
                                            HStack {
                                                Circle()
                                                    .fill(match.patch.patchCategory.color)
                                                    .frame(width: 8, height: 8)
                                                Text(match.patch.name ?? "Untitled")
                                                    .font(.subheadline)
                                                Spacer()
                                                Text(String(format: "%.2f", match.score))
                                                    .font(.caption2.monospacedDigit())
                                                    .foregroundStyle(.secondary)
                                            }
                                            .padding(6)
                                            .background(Color.secondary.opacity(0.05))
                                            .cornerRadius(6)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.top, 8)
                            },
                            label: {
                                Text("Similar Patches")
                                    .font(.headline)
                            }
                        )
                    }
                } else {
                    Text("Select a star to view details")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                        .padding(.vertical, 4)
                }
                
                Divider()
                
                GalaxyFilterSection(
                    visibleCategories: $visibleCategories,
                    showConstellations: $showConstellations,
                    showLabels: $showLabels
                )
            }
            .padding(12)
        }
        .scrollIndicators(.hidden)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private func performSearch() {
        Task {
            await searchService.search(input: searchText, in: context)
            if let result = searchService.lastResult {
                let ids = Set(result.patches.map(\.objectID))
                onSearchResult?(ids, result.patches.first)
            }
        }
    }
    
    private func newLibraryFromSearchResults() {
        guard let result = searchService.lastResult, !result.patches.isEmpty else { return }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let lib = PatchSet.create(named: "AI Search \(formatter.string(from: Date()))", in: context)
        for (idx, patch) in result.patches.enumerated() {
            PatchSlot.make(position: idx, patch: patch, in: lib, ctx: context)
        }
        try? context.save()
    }
}

// Sub-view for the Filter Logic
struct GalaxyFilterSection: View {
    @Binding var visibleCategories: Set<String>
    @Binding var showConstellations: Bool
    @Binding var showLabels: Bool
    
    @State private var isVisibilityExpanded: Bool = true
    
    var body: some View {
        DisclosureGroup(isExpanded: $isVisibilityExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                
                // Map & Labels
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(isOn: $showConstellations) {
                        Label("Show Map", systemImage: "network")
                    }
                    .toggleStyle(.checkbox)
                    
                    Toggle(isOn: $showLabels) {
                        Label("Show Labels", systemImage: "text.bubble")
                    }
                    .toggleStyle(.checkbox)
                    .padding(.leading, 20)
                }
                .padding(.vertical, 4)
                
                Divider()
                
                HStack {
                    Text("Categories")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    if visibleCategories.count < GalaxyHierarchy.allCategoryNames.count {
                        Button("Show All") {
                            withAnimation {
                                visibleCategories = GalaxyHierarchy.allCategoryNames
                            }
                        }
                        .font(.caption)
                        .buttonStyle(.link)
                    } else {
                        Button("Hide All") {
                            withAnimation {
                                visibleCategories.removeAll()
                            }
                        }
                        .font(.caption)
                        .buttonStyle(.link)
                    }
                }
                .padding(.trailing, 16)
                
                ForEach(GalaxyHierarchy.groups, id: \.name) { group in
                    GalaxyGroupRow(group: group, visibleCategories: $visibleCategories)
                }
            }
            .padding(.leading, 10)
            
        } label: {
            Text("Visibility")
                .font(.headline)
        }
    }
}

struct GalaxyGroupRow: View {
    let group: GalaxyHierarchy.Group
    @Binding var visibleCategories: Set<String>
    
    @State private var isExpanded: Bool = true
    
    private var isGroupChecked: Bool {
        return group.categories.allSatisfy { visibleCategories.contains($0.rawValue) }
    }
    
    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(group.categories) { category in
                    HStack {
                        Toggle(isOn: Binding(
                            get: { visibleCategories.contains(category.rawValue) },
                            set: { isOn in
                                if isOn {
                                    visibleCategories.insert(category.rawValue)
                                } else {
                                    visibleCategories.remove(category.rawValue)
                                }
                            }
                        )) {
                            Text(category.rawValue)
                                .font(.subheadline)
                        }
                        .toggleStyle(.checkbox)
                        .tint(GalaxyHierarchy.color(for: category))
                        Spacer()
                    }
                    .padding(.leading, 20)
                }
            }
        } label: {
            HStack {
                Toggle(isOn: Binding(
                    get: { isGroupChecked },
                    set: { isOn in
                        withAnimation {
                            if isOn {
                                for cat in group.categories { visibleCategories.insert(cat.rawValue) }
                            } else {
                                for cat in group.categories { visibleCategories.remove(cat.rawValue) }
                            }
                        }
                    }
                )) {
                    Text(group.name)
                        .fontWeight(.medium)
                }
                .toggleStyle(.checkbox)
            }
        }
    }
}

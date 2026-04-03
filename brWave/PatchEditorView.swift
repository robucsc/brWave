//
//  PatchEditorView.swift
//  brWave
//
//  Editor shell: FloatingToolbar + Panel / Table content.
//  WavePanelView will replace WavePanelPlaceholder once implemented.
//

import SwiftUI
import Combine

struct PatchEditorView: View {
    @EnvironmentObject var patchSelection: PatchSelection
    @Environment(\.managedObjectContext) var context

    @AppStorage("patchEditorLayoutMode") private var layoutMode: PatchDisplayMode = .panel
    @State private var saveTask: AnyCancellable?

    var body: some View {
        if let patch = patchSelection.selectedPatch {
            ZStack(alignment: .top) {
                content(for: patch)
                    .padding(.top, 52)

                FloatingToolbar(
                    patch: patch,
                    layoutMode: $layoutMode,
                    onInit: { initPatch(patch) }
                )
                .padding(.top, 8)
            }
            .preference(
                key: InspectorContentKey.self,
                value: InspectorBox(
                    id: "\(patch.objectID.uriRepresentation())",
                    view: AnyView(
                        PatchInspectorView(patch: patch)
                            .environment(\.managedObjectContext, context)
                            .environmentObject(patchSelection)
                    )
                )
            )
            .onReceive(NotificationCenter.default.publisher(for: .waveParameterChanged)) { _ in
                scheduleSave()
            }
        } else {
            ContentUnavailableView(
                "No Patch Selected",
                systemImage: "waveform",
                description: Text("Select a patch from the list.")
            )
        }
    }

    @ViewBuilder
    private func content(for patch: Patch) -> some View {
        switch layoutMode {
        case .table:
            ParameterTableView(patch: patch)
        case .panel:
            WavePanelView(patch: patch)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func initPatch(_ patch: Patch) {
        for desc in WaveParameters.all {
            patch.setValue(desc.range.lowerBound, for: desc.id, group: .a)
            if case .perGroup = desc.storage {
                patch.setValue(desc.range.lowerBound, for: desc.id, group: .b)
            }
        }
        try? context.save()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Just(())
            .delay(for: .seconds(1.5), scheduler: RunLoop.main)
            .sink { [weak context] _ in try? context?.save() }
    }
}


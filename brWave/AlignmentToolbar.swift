//
//  AlignmentToolbar.swift
//  brWave
//
//  Floating alignment and distribution toolbar shown in tuning mode.
//  Ported from OBsixer — ob6Blue → waveHighlight.
//

import SwiftUI

struct AlignmentToolbar: View {
    @ObservedObject var canonicalLayoutService = WavePanelLayoutService.shared

    private var hasSelection: Bool {
        !canonicalLayoutService.selectedIDs.isEmpty
    }
    private var hasThreePlus: Bool {
        canonicalLayoutService.selectedIDs.filter { !canonicalLayoutService.isPanelSelectionID($0) }.count > 2
    }
    private var hasMultipleAlignableItems: Bool {
        canonicalLayoutService.selectedIDs.count > 1
    }
    private var hasMultipleResizableItems: Bool {
        canonicalLayoutService.selectedIDs.count > 1
    }
    private var hasTwoSelectedPanels: Bool {
        canonicalLayoutService.selectedIDs.filter { canonicalLayoutService.isPanelSelectionID($0) }.count == 2
    }

    var body: some View {
        HStack(spacing: 0) {
            toolGroup {
                toolButton("align.horizontal.left",   help: "Align Left Edges",         enabled: hasMultipleAlignableItems)  { canonicalLayoutService.alignSelected(to: .left) }
                toolButton("align.horizontal.center", help: "Align Horizontal Centers", enabled: hasMultipleAlignableItems)  { canonicalLayoutService.alignSelected(to: .center) }
                toolButton("align.horizontal.right",  help: "Align Right Edges",        enabled: hasMultipleAlignableItems)  { canonicalLayoutService.alignSelected(to: .right) }
            }
            toolDivider()
            toolGroup {
                toolButton("align.vertical.top",    help: "Align Top Edges",        enabled: hasMultipleAlignableItems)  { canonicalLayoutService.alignSelected(to: .top) }
                toolButton("align.vertical.center", help: "Align Vertical Centers", enabled: hasMultipleAlignableItems)  { canonicalLayoutService.alignSelected(to: .middle) }
                toolButton("align.vertical.bottom", help: "Align Bottom Edges",     enabled: hasMultipleAlignableItems)  { canonicalLayoutService.alignSelected(to: .bottom) }
            }
            toolDivider()
            toolGroup {
                toolButton("distribute.horizontal", help: "Distribute Horizontally", enabled: hasThreePlus) { canonicalLayoutService.distributeSelected(horizontal: true) }
                toolButton("distribute.vertical",   help: "Distribute Vertically",   enabled: hasThreePlus) { canonicalLayoutService.distributeSelected(horizontal: false) }
            }
            toolDivider()
            toolGroup {
                toolButton("w.square", help: "Match Width", enabled: hasMultipleResizableItems) {
                    canonicalLayoutService.matchSelectedSize(width: true, height: false)
                }
                toolButton("h.square", help: "Match Height", enabled: hasMultipleResizableItems) {
                    canonicalLayoutService.matchSelectedSize(width: false, height: true)
                }
            }
            toolDivider()
            toolGroup {
                toolButton("arrow.left.and.right.square", help: "Apply Standard Horizontal Gap", enabled: hasTwoSelectedPanels) {
                    canonicalLayoutService.applyPanelGap(horizontal: true)
                }
                toolButton("arrow.up.and.down.square", help: "Apply Standard Vertical Gap", enabled: hasTwoSelectedPanels) {
                    canonicalLayoutService.applyPanelGap(horizontal: false)
                }
            }
            toolDivider()
            toolGroup {
                toolButton("square.and.arrow.up", help: "Export Overrides to Clipboard", enabled: true) {
                    canonicalLayoutService.exportToClipboard()
                }
                toolButton("xmark.circle", help: "Clear Selection", enabled: hasSelection) {
                    canonicalLayoutService.clearSelection()
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.82))
                .overlay(Capsule().strokeBorder(Theme.waveHighlight.opacity(0.45), lineWidth: 1))
        )
        .shadow(color: .black.opacity(0.5), radius: 6, x: 0, y: 3)
    }

    @ViewBuilder
    private func toolGroup<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 4) { content() }.padding(.horizontal, 4)
    }

    private func toolDivider() -> some View {
        Rectangle()
            .fill(Theme.waveHighlight.opacity(0.25))
            .frame(width: 1, height: 18)
            .padding(.horizontal, 4)
    }

    private func toolButton(
        _ systemImage: String,
        help: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 28, height: 28)
                .foregroundStyle(enabled ? Theme.waveHighlight : Color.secondary.opacity(0.4))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(help)
    }
}

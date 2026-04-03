//
//  GalaxyView.swift
//  brWave
//
//  Scatter-plot galaxy of all patches, clustered by sonic similarity.
//  Pinch = zoom · two-finger drag = pan · double-tap = reset
//  Click = select · shift+drag = lasso · cmd+click = toggle
//  Ported from OBsixer — adapted for brWave (waveBlue accent, no OB6Category).
//

import SwiftUI
import CoreData

struct GalaxyView: View {
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var patchSelection:  PatchSelection
    @EnvironmentObject private var bankEditorState: BankEditorState

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Patch.name, ascending: true)],
        animation: .default
    )
    private var patches: FetchedResults<Patch>

    @State private var showLabels         = true
    @State private var showConstellations = true

    @State private var similarMatches: [SimilarityEngine.Match] = []

    // Canvas navigation
    @State private var offset:     CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var scale:      CGFloat = 1.0
    @State private var lastScale:  CGFloat = 1.0

    // Zoom-to-cursor
    @State private var cursorLocation:    CGPoint = .zero
    @State private var viewSize:          CGSize  = .zero
    @State private var isPinching:        Bool    = false
    @State private var pinchAnchorCanvas: CGPoint = .zero

    // Lasso
    @State private var isLassoing: Bool    = false
    @State private var lassoRect:  CGRect? = nil

    // Selection
    @State private var selectedIDs:  Set<NSManagedObjectID> = []
    @State private var hoveredPatch: Patch?

    // Animated primary star position
    @State private var liveStarX: Double = 0
    @State private var liveStarY: Double = 0

    @AppStorage("brWaveGalaxyDotRadius") private var dotRadius: Double = 1.5
    @State private var searchText = ""

    private var highlightedIDs: Set<NSManagedObjectID> {
        guard !searchText.isEmpty else { return [] }
        let q = searchText.lowercased()
        return Set(patches.filter {
            ($0.name ?? "").lowercased().contains(q) ||
            ($0.category ?? "").lowercased().contains(q)
        }.map(\.objectID))
    }

    private var isDimming: Bool { selectedIDs.count > 1 || !highlightedIDs.isEmpty }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                Canvas { ctx, size in drawGalaxy(context: &ctx, size: size) }
                    .gesture(panGesture)
                    .gesture(zoomGesture)
                    .onTapGesture(count: 2) { resetView() }
                    .onTapGesture { loc in handleTap(location: loc, in: geo.size) }
                    .onContinuousHover { phase in
                        if case .active(let loc) = phase { cursorLocation = loc }
                    }

                if let r = lassoRect {
                    Rectangle()
                        .stroke(Theme.waveHighlight.opacity(0.8), lineWidth: 1)
                        .background(Theme.waveHighlight.opacity(0.06))
                        .frame(width: r.width, height: r.height)
                        .position(x: r.midX, y: r.midY)
                        .allowsHitTesting(false)
                }

                if let hovered = hoveredPatch { hoverTooltip(for: hovered) }

                overlayControls
            }
            .onAppear {
                DispatchQueue.main.async {
                    viewSize = geo.size
                    GalaxyEngine.shared.updateAll(in: context)
                }
                if let p = patchSelection.selectedPatch {
                    liveStarX = p.galaxyX * 400
                    liveStarY = p.galaxyY * 400
                }
            }
            .onChange(of: geo.size) { _, v in DispatchQueue.main.async { viewSize = v } }
        }
        .onChange(of: patchSelection.selectedPatch) { _, p in
            guard let p else { return }
            GalaxyEngine.shared.bootstrapLayout(for: p)
            withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                liveStarX = p.galaxyX * 400
                liveStarY = p.galaxyY * 400
            }
            similarMatches = SimilarityEngine.findSimilar(to: p, in: context, limit: 8)
        }
        .preference(
            key: InspectorContentKey.self,
            value: InspectorBox(
                id: "galaxy-\(patchSelection.selectedPatch?.objectID.uriRepresentation().absoluteString ?? "empty")",
                view: AnyView(
                    GalaxyInspectorPlaceholder(
                        selectedPatch: patchSelection.selectedPatch,
                        matchCount: similarMatches.count,
                        onRefresh: { GalaxyEngine.shared.updateAll(in: context) }
                    )
                    .environment(\.managedObjectContext, context)
                )
            )
        )
        .onKeyPress(.escape) { selectedIDs.removeAll(); return .handled }
    }

    // MARK: - Gestures

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { v in
                let mods = NSApp.currentEvent?.modifierFlags ?? []
                if lassoRect == nil && !isLassoing { isLassoing = mods.contains(.shift) }
                if isLassoing {
                    let s = v.startLocation, e = v.location
                    lassoRect = CGRect(x: min(s.x,e.x), y: min(s.y,e.y),
                                       width: abs(e.x-s.x), height: abs(e.y-s.y))
                } else {
                    offset = CGSize(width:  lastOffset.width  + v.translation.width,
                                    height: lastOffset.height + v.translation.height)
                }
            }
            .onEnded { _ in
                if isLassoing { commitLasso(); lassoRect = nil; isLassoing = false }
                else { lastOffset = offset }
            }
    }

    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { v in
                let newScale = min(max(lastScale * v, 0.1), 20.0)
                let center   = CGPoint(x: viewSize.width/2, y: viewSize.height/2)
                if !isPinching {
                    isPinching = true
                    pinchAnchorCanvas = CGPoint(
                        x: (cursorLocation.x - center.x - offset.width)  / scale,
                        y: (cursorLocation.y - center.y - offset.height) / scale
                    )
                }
                offset = CGSize(
                    width:  cursorLocation.x - center.x - pinchAnchorCanvas.x * newScale,
                    height: cursorLocation.y - center.y - pinchAnchorCanvas.y * newScale
                )
                scale = newScale
            }
            .onEnded { _ in lastScale = scale; lastOffset = offset; isPinching = false }
    }

    private func resetView() {
        withAnimation { offset = .zero; lastOffset = .zero; scale = 1.0; lastScale = 1.0 }
    }

    // MARK: - Tap

    private func handleTap(location: CGPoint, in size: CGSize) {
        let center = CGPoint(x: size.width/2, y: size.height/2)
        let lx = (location.x - (center.x + offset.width))  / scale
        let ly = (location.y - (center.y + offset.height)) / scale

        var closest: Patch?
        var closestDist: CGFloat = 20.0 / scale
        for patch in patches {
            let dx = lx - CGFloat(patch.galaxyX * 400)
            let dy = ly - CGFloat(patch.galaxyY * 400)
            let d  = sqrt(dx*dx + dy*dy)
            if d < closestDist { closestDist = d; closest = patch }
        }

        let mods = NSApp.currentEvent?.modifierFlags ?? []
        guard let match = closest else {
            if !mods.contains(.shift), !mods.contains(.command) {
                selectedIDs.removeAll(); patchSelection.selectedPatch = nil
            }
            return
        }

        if mods.contains(.command) {
            if selectedIDs.contains(match.objectID) { selectedIDs.remove(match.objectID) }
            else { selectedIDs.insert(match.objectID) }
            patchSelection.selectedPatch = match
        } else {
            selectedIDs = [match.objectID]
            patchSelection.selectedPatch = match
            hoveredPatch = match
        }
    }

    // MARK: - Lasso

    private func commitLasso() {
        guard let rect = lassoRect else { return }
        let center = CGPoint(x: viewSize.width/2, y: viewSize.height/2)
        let mods   = NSApp.currentEvent?.modifierFlags ?? []
        var newIDs: Set<NSManagedObjectID> = mods.contains(.command) ? selectedIDs : []
        var first: Patch?
        for patch in patches {
            let vx = center.x + offset.width  + CGFloat(patch.galaxyX * 400) * scale
            let vy = center.y + offset.height + CGFloat(patch.galaxyY * 400) * scale
            if rect.contains(CGPoint(x: vx, y: vy)) {
                newIDs.insert(patch.objectID)
                if first == nil { first = patch }
            }
        }
        selectedIDs = newIDs
        patchSelection.selectedPatch = first ?? patchSelection.selectedPatch
    }

    // MARK: - Drawing

    private func drawGalaxy(context: inout GraphicsContext, size: CGSize) {
        let center = CGPoint(x: size.width/2, y: size.height/2)
        context.translateBy(x: center.x + offset.width, y: center.y + offset.height)
        context.scaleBy(x: scale, y: scale)

        context.stroke(Path(ellipseIn: CGRect(x: -300, y: -300, width: 600, height: 600)),
                       with: .color(Color.white.opacity(0.08)), lineWidth: 1)

        let anchors = GalaxyEngine.shared.anchors

        if showConstellations {
            context.stroke(Path { p in
                for i in 0..<anchors.count {
                    for j in (i+1)..<anchors.count {
                        let p1 = anchors[i].position, p2 = anchors[j].position
                        let dx = Double(p1.x-p2.x)*400, dy = Double(p1.y-p2.y)*400
                        if sqrt(dx*dx+dy*dy) < 250 {
                            p.move(to:    CGPoint(x: Double(p1.x)*400, y: Double(p1.y)*400))
                            p.addLine(to: CGPoint(x: Double(p2.x)*400, y: Double(p2.y)*400))
                        }
                    }
                }
            }, with: .color(Color.white.opacity(isDimming ? 0.05 : 0.12)), lineWidth: 1)
        }

        for anchor in anchors {
            let x = Double(anchor.position.x) * 400
            let y = Double(anchor.position.y) * 400
            context.fill(Path(ellipseIn: CGRect(x: x-2, y: y-2, width: 4, height: 4)),
                         with: .color(anchor.category.color.opacity(0.4)))
            if showLabels {
                context.draw(
                    Text(anchor.category.rawValue.uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(anchor.category.color.opacity(0.5)),
                    at: CGPoint(x: x, y: y - 14)
                )
            }
        }

        let activeHighlight: Set<NSManagedObjectID> = {
            if selectedIDs.count > 1   { return selectedIDs }
            if !highlightedIDs.isEmpty { return highlightedIDs }
            return []
        }()

        let primary = patchSelection.selectedPatch
        for patch in patches {
            let catColor = patch.patchCategory.color
            let isPrimary  = patch.objectID == primary?.objectID
            let x = isPrimary ? liveStarX : patch.galaxyX * 400
            let y = isPrimary ? liveStarY : patch.galaxyY * 400
            let isSelected = activeHighlight.contains(patch.objectID)
            let isHovered  = patch.objectID == hoveredPatch?.objectID

            let opacity: Double = activeHighlight.isEmpty ? 0.6 : (isSelected ? 1.0 : 0.08)

            let baseR  = CGFloat(dotRadius)
            var radius = isSelected ? baseR*1.5 : (isHovered ? baseR*1.65 : baseR)
            if isPrimary { radius = baseR * 2.2 }

            if isSelected || isPrimary {
                let glowColor = isPrimary ? catColor : Theme.waveHighlight
                let glowR: CGFloat = isPrimary ? 12 : 8
                context.fill(
                    Path(ellipseIn: CGRect(x: x-glowR, y: y-glowR, width: glowR*2, height: glowR*2)),
                    with: .color(glowColor.opacity(isPrimary ? 0.28 : 0.20))
                )
            }

            if isPrimary {
                let rr = radius + 5
                context.stroke(Path(ellipseIn: CGRect(x: x-rr, y: y-rr, width: rr*2, height: rr*2)),
                               with: .color(catColor.opacity(0.9)), lineWidth: 1.5)
            } else if isSelected {
                let rr = radius + 3
                context.stroke(Path(ellipseIn: CGRect(x: x-rr, y: y-rr, width: rr*2, height: rr*2)),
                               with: .color(Theme.waveHighlight.opacity(0.75)), lineWidth: 1)
            }

            let dotColor = (isSelected && !isPrimary) ? Theme.waveHighlight : catColor
            context.fill(
                Path(ellipseIn: CGRect(x: x-radius, y: y-radius, width: radius*2, height: radius*2)),
                with: .color(dotColor.opacity(opacity))
            )
        }
    }

    // MARK: - Hover tooltip

    @ViewBuilder
    private func hoverTooltip(for patch: Patch) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(patch.name ?? "Untitled").font(.headline).foregroundColor(.white)
            if !selectedIDs.isEmpty {
                Text("\(selectedIDs.count) selected").font(.caption2).foregroundColor(Theme.waveHighlight)
            }
        }
        .padding(8)
        .background(Color.black.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.2)))
        .position(x: 110, y: 52)
    }

    // MARK: - Overlay controls

    @ViewBuilder
    private var overlayControls: some View {
        VStack {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search patches…", text: $searchText)
                    .textFieldStyle(.plain)
                    .foregroundColor(.white)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(.ultraThinMaterial.opacity(0.9))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .frame(maxWidth: 380)
            .padding(.top, 72)

            Spacer()

            HStack(spacing: 8) {
                Button {
                    withAnimation { showConstellations.toggle() }
                } label: {
                    Image(systemName: showConstellations ? "network" : "network.slash").padding(8)
                }
                .buttonStyle(.bordered).tint(.secondary)

                Button {
                    withAnimation { showLabels.toggle() }
                } label: {
                    Image(systemName: "textformat").padding(8)
                }
                .buttonStyle(.bordered).tint(showLabels ? Theme.waveHighlight : .secondary)

                if !selectedIDs.isEmpty {
                    Text("\(selectedIDs.count) selected")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Theme.waveHighlight.opacity(0.75))
                        .clipShape(Capsule())
                    Button("Clear") { selectedIDs.removeAll(); patchSelection.selectedPatch = nil }
                        .buttonStyle(.bordered).tint(.secondary).font(.caption)
                }

                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: "circle.fill").font(.system(size: 6)).foregroundStyle(.secondary)
                    Slider(value: $dotRadius, in: 0.5...5.0, step: 0.25).frame(width: 90).controlSize(.mini)
                    Image(systemName: "circle.fill").font(.system(size: 11)).foregroundStyle(.secondary)
                }

                .buttonStyle(.borderedProminent).tint(Theme.waveHighlight).padding(.vertical, 8)
            }
            .padding(.horizontal, 16)
        }
    }
}

// MARK: - Galaxy Inspector placeholder (replace with GalaxyInspectorView)

private struct GalaxyInspectorPlaceholder: View {
    let selectedPatch: Patch?
    let matchCount: Int
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Galaxy")
                .font(.headline)
                .foregroundStyle(Theme.waveHighlight)
            Divider()
            if let patch = selectedPatch {
                Text(patch.name ?? "Untitled").font(.body)
                Text("\(matchCount) similar patches").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Click a star to select a patch")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button("Refresh Layout", action: onRefresh)
                .buttonStyle(.borderedProminent)
                .tint(Theme.waveHighlight)
        }
        .padding()
    }
}

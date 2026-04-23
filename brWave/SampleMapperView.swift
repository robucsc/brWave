//
//  SampleMapperView.swift
//  brWave
//

import AppKit
import SwiftUI

struct SampleMapperView: View {
    @ObservedObject var mapper: SampleMapperState

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(minWidth: 280, idealWidth: 320, maxWidth: 360)

            Divider()

            mainWorkspace
        }
        .background(Theme.panelBackground.ignoresSafeArea())
        .alert(
            "Root Note Conflict",
            isPresented: Binding(
                get: { mapper.rootConflictChoice != nil },
                set: { if !$0 { mapper.rootConflictChoice = nil } }
            ),
            presenting: mapper.rootConflictChoice
        ) { choice in
            Button("Use File Name (\(choice.filenameRoot.shortLabel))") {
                mapper.resolveRootConflict(using: .filename)
            }
            Button("Use Audio Analysis (\(choice.analyzedRoot.shortLabel))") {
                mapper.resolveRootConflict(using: .analyzed)
            }
            Button("Keep Current", role: .cancel) {
                mapper.rootConflictChoice = nil
            }
        } message: { choice in
            Text("\(choice.filename) names this sample \(choice.filenameRoot.shortLabel), but the audio measures closer to \(choice.analyzedRoot.shortLabel). Choose which root brWave should trust.")
        }
        .preference(
            key: InspectorContentKey.self,
            value: InspectorBox(
                id: "sample-mapper-inspector-\(mapper.selectedSampleID?.uuidString ?? "none")",
                view: AnyView(
                    SampleMapperInspectorView(
                        samples: mapper.samples,
                        selectedSample: mapper.selectedSample,
                        waveform: mapper.selectedWaveform,
                        conflictChoice: mapper.rootConflictChoice
                    )
                )
            )
        )
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            mapperHeader

            if mapper.samples.isEmpty {
                ContentUnavailableView(
                    "No Samples Imported",
                    systemImage: "waveform.badge.plus",
                    description: Text("Import sample files or a folder to build a keyboard map.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(mapper.samples) { sample in
                            SampleRowCard(
                                sample: sample,
                                isSelected: mapper.selectedSampleID == sample.id
                            )
                            .onTapGesture {
                                mapper.selectSample(sample.id)
                            }
                        }
                    }
                    .padding(.trailing, 4)
                }
            }
        }
        .padding(20)
        .background(Theme.surfaceBackground)
    }

    private var mapperHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sample Mapper")
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundStyle(Theme.waveHighlight)
                    Text("Universal transient and sample keymapping")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            HStack(spacing: 10) {
                Button("Import Files…") { mapper.importFiles() }
                Button("Import Folder…") { mapper.importDirectory() }
            }
            .buttonStyle(.borderedProminent)

            HStack(spacing: 10) {
                Stepper("Lower Reach: \(mapper.lowerReachSemitones) st", value: $mapper.lowerReachSemitones, in: 0...24)
                Stepper("Upper Reach: \(mapper.upperReachSemitones) st", value: $mapper.upperReachSemitones, in: 0...24)
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button("Auto-Map") { mapper.autoMap() }
                    .buttonStyle(.bordered)
                Button("Clear") { mapper.clear() }
                    .buttonStyle(.bordered)
                    .disabled(mapper.samples.isEmpty)
            }
        }
    }

    private var mainWorkspace: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let sample = mapper.selectedSample {
                SampleWaveformPanel(
                    sample: sample,
                    waveform: mapper.selectedWaveform,
                    zoom: $mapper.waveformZoom,
                    pan: $mapper.waveformPan,
                    onLoopStartChange: { mapper.updateLoopStart(for: sample.id, to: $0) },
                    onLoopEndChange: { mapper.updateLoopEnd(for: sample.id, to: $0) }
                )
                .frame(height: 170)
                .padding(.horizontal, 20)
                .padding(.top, 20)

                SampleKeyboardMapView(
                    samples: mapper.samples,
                    selectedSampleID: mapper.selectedSampleID,
                    onSelectSample: { mapper.selectSample($0) },
                    onPreviewNote: { mapper.previewMappedSample(for: $0) },
                    onStopPreviewNote: { mapper.stopPreviewPlayback() }
                )
                    .frame(height: 194)
                    .padding(.horizontal, 20)

                SampleZoneEditorCard(
                    sample: sample,
                    onPlayRoot: { mapper.previewMappedSample(for: sample.rootNote.midi) },
                    onStopPlayback: { mapper.stopPreviewPlayback() },
                    onRootChange: { mapper.updateRoot(for: sample.id, to: $0) },
                    onLowChange: { mapper.updateLow(for: sample.id, to: $0) },
                    onHighChange: { mapper.updateHigh(for: sample.id, to: $0) },
                    onLoopStartChange: { mapper.updateLoopStart(for: sample.id, to: $0) },
                    onLoopEndChange: { mapper.updateLoopEnd(for: sample.id, to: $0) }
                )
                .padding(.horizontal, 20)

                Spacer()
            } else {
                ContentUnavailableView(
                    "Select A Sample",
                    systemImage: "pianokeys",
                    description: Text("Pick a sample from the list to inspect and adjust its zone.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

private struct SampleMapperInspectorView: View {
    let samples: [SampleZone]
    let selectedSample: SampleZone?
    let waveform: SampleWaveform?
    let conflictChoice: SampleMapperState.RootConflictChoice?
    @AppStorage("sampleMapperPathDisplayMode") private var pathDisplayMode = "homeRelative"
    @State private var pathExpanded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Sample Mapper")
                    .font(.headline)

                inspectorSection("Session") {
                    inspectorRow("Samples", "\(samples.count)")
                    inspectorRow("Detected Roots", "\(samples.filter(\.rootWasDetected).count)")
                    inspectorRow("Waveform Loaded", waveform == nil ? "No" : "Yes")
                    inspectorRow("Root Conflicts", "\(samples.filter(\.rootDetectionConflict).count)")
                }

                inspectorSection("Selection") {
                    if let selectedSample {
                        inspectorRow("Name", selectedSample.displayName)
                        inspectorRow("Format", selectedSample.format.label)
                        inspectorRow("Root", selectedSample.rootNote.shortLabel)
                        if let filenameRoot = selectedSample.filenameRootNote {
                            inspectorRow("Filename Root", filenameRoot.shortLabel)
                        }
                        if let analyzedRoot = selectedSample.analyzedRootNote {
                            inspectorRow("Audio Root", analyzedRoot.shortLabel)
                        }
                        inspectorRow("Range", "\(selectedSample.lowNote.shortLabel) → \(selectedSample.highNote.shortLabel)")
                        if let rate = selectedSample.sampleRate {
                            inspectorRow("Sample Rate", "\(Int(rate)) Hz")
                        }
                        if let frames = selectedSample.totalFrames {
                            inspectorRow("Frames", "\(frames)")
                        }
                        inspectorRow("Loop", "\(selectedSample.loopPoints.startFrame) → \(selectedSample.loopPoints.endFrame)")
                        if selectedSample.rootDetectionConflict {
                            Text("Filename and audio analysis disagree on this root.")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.orange)
                        }
                        pathInspectorRow(for: selectedSample.url)
                    } else {
                        Text("No sample selected.")
                            .foregroundStyle(.secondary)
                    }
                }

                if let conflictChoice {
                    inspectorSection("Attention") {
                        Text("Pending root choice for \(conflictChoice.filename)")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Name says \(conflictChoice.filenameRoot.shortLabel); audio says \(conflictChoice.analyzedRoot.shortLabel).")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
        }
    }

    private func inspectorSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func inspectorRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .textSelection(.enabled)
        }
    }

    private func pathInspectorRow(for url: URL) -> some View {
        let displayValue = pathExpanded ? formattedPath(for: url) : url.lastPathComponent

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Path")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        pathExpanded.toggle()
                    }
                } label: {
                    Image(systemName: pathExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Text(displayValue)
                .font(.system(size: 12, weight: .medium))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func formattedPath(for url: URL) -> String {
        switch pathDisplayMode {
        case "full":
            return url.path
        default:
            let homePath = NSHomeDirectory()
            if url.path == homePath {
                return "~"
            }
            if url.path.hasPrefix(homePath + "/") {
                return "~/" + String(url.path.dropFirst(homePath.count + 1))
            }
            return url.path
        }
    }
}

private struct SampleRowCard: View {
    let sample: SampleZone
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(sample.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer()
                Text(sample.format.label)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.waveHighlight)
            }

            HStack {
                Label(sample.rootNote.shortLabel, systemImage: sample.rootWasDetected ? "tuningfork" : "pencil")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(sample.rootWasDetected ? Color.green : Color.orange)
                Spacer()
                Text("\(sample.lowNote.shortLabel) → \(sample.highNote.shortLabel)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? Theme.waveHighlight.opacity(0.14) : Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? Theme.waveHighlight.opacity(0.7) : Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
}

private struct SampleWaveformPanel: View {
    let sample: SampleZone
    let waveform: SampleWaveform?
    @Binding var zoom: Double
    @Binding var pan: Double
    let onLoopStartChange: (Int) -> Void
    let onLoopEndChange: (Int) -> Void
    @State private var startHandleDragOrigin: CGFloat?
    @State private var endHandleDragOrigin: CGFloat?
    @State private var zoomGestureOrigin: Double?
    @State private var panGestureOrigin: Double?

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.white.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
                    .onTapGesture(count: 2) {
                        zoom = 1
                        pan = 0
                    }

                if let waveform, !waveform.peaks.isEmpty {
                    let visibleWindow = visiblePeakWindow(for: waveform)
                    let displayedPeaks = Array(waveform.peaks[visibleWindow])
                    Canvas { ctx, size in
                        let midY = size.height / 2
                        let widthStep = size.width / CGFloat(max(1, displayedPeaks.count - 1))
                        var upperPath = Path()
                        var lowerPath = Path()
                        var lowerPoints: [CGPoint] = []

                        for (index, peak) in displayedPeaks.enumerated() {
                            let x = CGFloat(index) * widthStep
                            let halfHeight = CGFloat(peak) * (size.height * 0.38)
                            let upper = CGPoint(x: x, y: midY - halfHeight)
                            let lower = CGPoint(x: x, y: midY + halfHeight)
                            lowerPoints.append(lower)

                            if index == 0 {
                                upperPath.move(to: upper)
                                lowerPath.move(to: lower)
                            } else {
                                upperPath.addLine(to: upper)
                                lowerPath.addLine(to: lower)
                            }
                        }

                        var fillPath = upperPath
                        for point in lowerPoints.reversed() {
                            fillPath.addLine(to: point)
                        }
                        fillPath.closeSubpath()

                        ctx.fill(fillPath, with: .linearGradient(
                            Gradient(colors: [
                                Theme.waveHighlight.opacity(0.32),
                                Theme.waveHighlight.opacity(0.1)
                            ]),
                            startPoint: CGPoint(x: 0, y: 0),
                            endPoint: CGPoint(x: 0, y: size.height)
                        ))
                        ctx.stroke(upperPath, with: .color(Theme.waveHighlight.opacity(0.95)), lineWidth: 1.15)
                        ctx.stroke(lowerPath, with: .color(Theme.waveHighlight.opacity(0.7)), lineWidth: 0.8)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)

                    WaveformInteractionCaptureView(
                        onMagnifyChanged: { magnification, locationFraction in
                            let anchor = min(1, max(0, locationFraction))
                            let originZoom = zoomGestureOrigin ?? zoom
                            let originPan = panGestureOrigin ?? pan

                            if zoomGestureOrigin == nil {
                                zoomGestureOrigin = zoom
                            }
                            if panGestureOrigin == nil {
                                panGestureOrigin = pan
                            }

                            let oldVisible = 1.0 / max(1.0, originZoom)
                            let oldStart = originPan * max(0, 1.0 - oldVisible)
                            let anchoredPosition = oldStart + (anchor * oldVisible)

                            let nextZoom = min(8, max(1, originZoom * (1 + magnification)))
                            let newVisible = 1.0 / nextZoom
                            let newTravel = max(0, 1.0 - newVisible)
                            let newStart = anchoredPosition - (anchor * newVisible)

                            zoom = nextZoom
                            pan = newTravel > 0 ? min(1, max(0, newStart / newTravel)) : 0

                            if nextZoom <= 1.01 {
                                pan = 0
                            }
                        },
                        onMagnifyEnded: {
                            zoomGestureOrigin = nil
                            panGestureOrigin = nil
                        },
                        onPanChanged: { translation in
                            guard zoom > 1.01 else { return }
                            let origin = panGestureOrigin ?? pan
                            if panGestureOrigin == nil {
                                panGestureOrigin = pan
                            }
                            let visibleFraction = 1.0 / zoom
                            let travel = max(0.001, 1.0 - visibleFraction)
                            let delta = Double(translation / max(1, geo.size.width)) * travel
                            pan = min(1, max(0, origin - delta))
                        },
                        onPanEnded: {
                            panGestureOrigin = nil
                        }
                    )

                    loopOverlay(in: geo.size, totalFrames: waveform.totalFrames, visibleWindow: visibleWindow, totalPeakCount: waveform.peaks.count)
                } else {
                    ContentUnavailableView(
                        "Waveform Unavailable",
                        systemImage: "waveform.path",
                        description: Text("This format will use the Hibiki loader later. For now, brWave can only draw waveforms it can read directly.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(sample.displayName)
                        .font(.system(size: 14, weight: .semibold))
                    Text("Loop \(sample.loopPoints.startFrame.formatted()) → \(sample.loopPoints.endFrame.formatted()) samples")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(14)

                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10, weight: .bold))
                    Text("\(zoom, specifier: "%.1f")x")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                }
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.black.opacity(0.24), in: Capsule())
                .padding(.trailing, 14)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
    }

    private func visiblePeakWindow(for waveform: SampleWaveform) -> Range<Int> {
        let zoomFactor = max(1.0, zoom)
        guard zoomFactor > 1.01 else { return 0..<waveform.peaks.count }

        let visibleCount = max(32, Int(Double(waveform.peaks.count) / zoomFactor))
        let travel = max(0, waveform.peaks.count - visibleCount)
        let lowerBound = Int(round(Double(travel) * min(1, max(0, pan))))
        let upperBound = min(waveform.peaks.count, lowerBound + visibleCount)
        return lowerBound..<upperBound
    }

    private func loopOverlay(in size: CGSize, totalFrames: Int, visibleWindow: Range<Int>, totalPeakCount: Int) -> some View {
        let width = max(1, size.width - 24)
        let startPeak = CGFloat(sample.loopPoints.startFrame) / CGFloat(max(1, totalFrames)) * CGFloat(max(1, totalPeakCount - 1))
        let endPeak = CGFloat(sample.loopPoints.endFrame) / CGFloat(max(1, totalFrames)) * CGFloat(max(1, totalPeakCount - 1))
        let visibleStart = CGFloat(visibleWindow.lowerBound)
        let visibleEnd = CGFloat(max(visibleWindow.lowerBound + 1, visibleWindow.upperBound - 1))
        let denominator = max(1, visibleEnd - visibleStart)
        let startX = ((startPeak - visibleStart) / denominator) * width
        let endX = ((endPeak - visibleStart) / denominator) * width

        return ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(width: max(2, min(width, endX) - max(0, startX)), height: size.height - 38)
                .offset(x: 12 + max(0, startX), y: 10)
                .allowsHitTesting(false)

            HStack(spacing: 10) {
                loopValuePill("Start", value: sample.loopPoints.startFrame, tint: Theme.waveHighlight)
                loopValuePill("End", value: sample.loopPoints.endFrame, tint: Theme.waveGroupBHighlight)
                loopValuePill("Length", value: max(0, sample.loopPoints.endFrame - sample.loopPoints.startFrame), tint: .white.opacity(0.7))
            }
            .offset(x: max(14, size.width - 328), y: 12)
            .allowsHitTesting(false)

            draggableHandle(
                positionX: startX,
                totalWidth: width,
                height: size.height - 20,
                color: Theme.waveHighlight,
                dragOrigin: $startHandleDragOrigin
            ) { fraction in
                let clampedFraction = max(0, min(1, fraction))
                let peakIndex = CGFloat(visibleWindow.lowerBound) + (CGFloat(visibleWindow.count - 1) * clampedFraction)
                let frame = Int((peakIndex / CGFloat(max(1, totalPeakCount - 1))) * CGFloat(totalFrames))
                onLoopStartChange(frame)
            }

            draggableHandle(
                positionX: endX,
                totalWidth: width,
                height: size.height - 20,
                color: Theme.waveGroupBHighlight,
                dragOrigin: $endHandleDragOrigin
            ) { fraction in
                let clampedFraction = max(0, min(1, fraction))
                let peakIndex = CGFloat(visibleWindow.lowerBound) + (CGFloat(visibleWindow.count - 1) * clampedFraction)
                let frame = Int((peakIndex / CGFloat(max(1, totalPeakCount - 1))) * CGFloat(totalFrames))
                onLoopEndChange(frame)
            }
        }
    }

    private func loopValuePill(_ label: String, value: Int, tint: Color) -> some View {
        HStack(spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(tint.opacity(0.9))
                .lineLimit(1)
            Text(value.formatted())
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)
                .frame(minWidth: 64, alignment: .leading)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .fixedSize(horizontal: true, vertical: false)
        .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(tint.opacity(0.35), lineWidth: 1)
        )
    }

    private func draggableHandle(
        positionX: CGFloat,
        totalWidth: CGFloat,
        height: CGFloat,
        color: Color,
        dragOrigin: Binding<CGFloat?>,
        onDrag: @escaping (CGFloat) -> Void
    ) -> some View {
        return ZStack(alignment: .bottom) {
            Rectangle()
                .fill(color.opacity(0.9))
                .frame(width: 3, height: height - 20)
                .offset(y: -12)

            InwardLoopHandleTriangle()
                .fill(color)
                .frame(width: 18, height: 14)

            InwardLoopHandleTriangle()
                .stroke(Color.white.opacity(0.25), lineWidth: 1)
                .frame(width: 18, height: 14)
        }
        .frame(width: 20, height: height)
        .contentShape(Rectangle())
        .offset(x: 12 + positionX - 10, y: 10)
        .allowsHitTesting(true)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let origin = dragOrigin.wrappedValue ?? positionX
                    if dragOrigin.wrappedValue == nil {
                        dragOrigin.wrappedValue = positionX
                    }
                    let localX = max(0, min(totalWidth, origin + value.translation.width))
                    let fraction = localX / max(1, totalWidth)
                    onDrag(fraction)
                }
                .onEnded { _ in
                    dragOrigin.wrappedValue = nil
                }
        )
    }
}

private struct WaveformInteractionCaptureView: NSViewRepresentable {
    let onMagnifyChanged: (CGFloat, CGFloat) -> Void
    let onMagnifyEnded: () -> Void
    let onPanChanged: (CGFloat) -> Void
    let onPanEnded: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onMagnifyChanged: onMagnifyChanged,
            onMagnifyEnded: onMagnifyEnded,
            onPanChanged: onPanChanged,
            onPanEnded: onPanEnded
        )
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor

        let recognizer = NSMagnificationGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleMagnify(_:))
        )
        recognizer.delaysMagnificationEvents = false
        view.addGestureRecognizer(recognizer)

        let panRecognizer = NSPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePan(_:))
        )
        panRecognizer.delaysPrimaryMouseButtonEvents = false
        view.addGestureRecognizer(panRecognizer)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onMagnifyChanged = onMagnifyChanged
        context.coordinator.onMagnifyEnded = onMagnifyEnded
        context.coordinator.onPanChanged = onPanChanged
        context.coordinator.onPanEnded = onPanEnded
    }

    final class Coordinator: NSObject {
        var onMagnifyChanged: (CGFloat, CGFloat) -> Void
        var onMagnifyEnded: () -> Void
        var onPanChanged: (CGFloat) -> Void
        var onPanEnded: () -> Void

        init(
            onMagnifyChanged: @escaping (CGFloat, CGFloat) -> Void,
            onMagnifyEnded: @escaping () -> Void,
            onPanChanged: @escaping (CGFloat) -> Void,
            onPanEnded: @escaping () -> Void
        ) {
            self.onMagnifyChanged = onMagnifyChanged
            self.onMagnifyEnded = onMagnifyEnded
            self.onPanChanged = onPanChanged
            self.onPanEnded = onPanEnded
        }

        @objc func handleMagnify(_ recognizer: NSMagnificationGestureRecognizer) {
            let location = recognizer.location(in: recognizer.view)
            let width = max(1, recognizer.view?.bounds.width ?? 1)
            let fraction = location.x / width
            onMagnifyChanged(recognizer.magnification, fraction)
            if recognizer.state == .ended || recognizer.state == .cancelled || recognizer.state == .failed {
                onMagnifyEnded()
            }
        }

        @objc func handlePan(_ recognizer: NSPanGestureRecognizer) {
            let translation = recognizer.translation(in: recognizer.view).x
            onPanChanged(translation)
            if recognizer.state == .ended || recognizer.state == .cancelled || recognizer.state == .failed {
                onPanEnded()
            }
        }
    }
}

private struct InwardLoopHandleTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct SampleZoneEditorCard: View {
    let sample: SampleZone
    let onPlayRoot: () -> Void
    let onStopPlayback: () -> Void
    let onRootChange: (SampleNote) -> Void
    let onLowChange: (SampleNote) -> Void
    let onHighChange: (SampleNote) -> Void
    let onLoopStartChange: (Int) -> Void
    let onLoopEndChange: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(sample.displayName)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.primary)

            HStack(spacing: 14) {
                detailPill("Format", sample.format.label)
                detailPill("Root", sample.rootNote.shortLabel)
                if let sampleRate = sample.sampleRate {
                    detailPill("Sample Rate", "\(Int(sampleRate)) Hz")
                }
                if let channels = sample.channelCount {
                    detailPill("Channels", "\(channels)")
                }

                Spacer()

                Button {
                    onPlayRoot()
                } label: {
                    Label("Play Root", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    onStopPlayback()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)
            }

            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Zone")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                    notePicker("Root Key", selection: sample.rootNote, onChange: onRootChange)
                    notePicker("Low Key", selection: sample.lowNote, onChange: onLowChange)
                    notePicker("High Key", selection: sample.highNote, onChange: onHighChange)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Loop")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                    loopStepper("Start", value: sample.loopPoints.startFrame, onChange: onLoopStartChange)
                    loopStepper("End", value: sample.loopPoints.endFrame, onChange: onLoopEndChange)
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Theme.waveHighlight.opacity(0.25), lineWidth: 1)
                )
        )
    }

    private func detailPill(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
    }

    private func notePicker(_ label: String, selection: SampleNote, onChange: @escaping (SampleNote) -> Void) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Picker(label, selection: Binding(
                get: { selection },
                set: onChange
            )) {
                ForEach(SampleNote.all) { note in
                    Text(note.shortLabel).tag(note)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 90)
        }
    }

    private func loopStepper(_ label: String, value: Int, onChange: @escaping (Int) -> Void) -> some View {
        Stepper {
            HStack {
                Text(label)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(value)")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
            }
        } onIncrement: {
            onChange(value + 128)
        } onDecrement: {
            onChange(max(0, value - 128))
        }
    }
}

private struct SampleKeyboardMapView: View {
    let samples: [SampleZone]
    let selectedSampleID: UUID?
    let onSelectSample: (UUID) -> Void
    let onPreviewNote: (Int) -> Void
    let onStopPreviewNote: () -> Void
    @State private var activePreviewMIDINote: Int?
    private let visibleRange = 24...96
    private let zoneBandHeight: CGFloat = 74
    private let keyBedHeight: CGFloat = 92
    private let blackKeyHeight: CGFloat = 56

    var body: some View {
        GeometryReader { geo in
            let whiteKeyWidth = geo.size.width / CGFloat(max(1, whiteKeyMIDIs.count))
            let indexMap = whiteKeyIndexMap()

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.white.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )

                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.black.opacity(0.22))
                    .frame(height: zoneBandHeight + 18)

                zoneOverlays(whiteKeyWidth: whiteKeyWidth, totalWidth: geo.size.width)

                VStack(spacing: 0) {
                    Spacer(minLength: zoneBandHeight)
                    ZStack(alignment: .topLeading) {
                        whiteKeys(whiteKeyWidth: whiteKeyWidth)
                        blackKeys(whiteKeyWidth: whiteKeyWidth)
                    }
                    .frame(height: keyBedHeight)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { gesture in
                                updatePreviewNote(
                                    noteAtPoint(
                                        gesture.location,
                                        whiteKeyWidth: whiteKeyWidth,
                                        indexMap: indexMap,
                                        totalWidth: geo.size.width
                                    )
                                )
                            }
                            .onEnded { _ in
                                stopPreviewNote()
                            }
                    )
                }
            }
        }
    }

    private var whiteKeyMIDIs: [Int] {
        Array(visibleRange).filter { !isBlackKey($0) }
    }

    private func whiteKeyIndexMap() -> [Int: Int] {
        Dictionary(uniqueKeysWithValues: whiteKeyMIDIs.enumerated().map { ($0.element, $0.offset) })
    }

    private func whiteKeys(whiteKeyWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(whiteKeyMIDIs, id: \.self) { midi in
                ZStack {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.98),
                                    Color.white.opacity(0.92),
                                    Color(red: 0.87, green: 0.88, blue: 0.9)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .overlay(alignment: .top) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.white.opacity(0.35))
                                .frame(height: 10)
                                .blur(radius: 1)
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: 2)
                                .stroke(Color.black.opacity(0.22), lineWidth: 0.8)
                        )
                        .overlay {
                            if activePreviewMIDINote == midi {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Theme.waveHighlight.opacity(0.18))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 2)
                                            .stroke(Theme.waveHighlight.opacity(0.9), lineWidth: 1.4)
                                    )
                                    .padding(.horizontal, 0.5)
                            }
                        }
                        .shadow(color: Color.black.opacity(0.08), radius: 1.5, y: 1)
                        .padding(.horizontal, 0.5)
                        .overlay(alignment: .bottomLeading) {
                            if midi % 12 == 0 {
                                Text(SampleNote(midi: midi).label)
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(Color.black.opacity(0.55))
                                    .padding(.leading, 3)
                                    .padding(.bottom, 3)
                            }
                        }
                }
                .frame(width: whiteKeyWidth)
            }
        }
        .frame(height: keyBedHeight)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 18,
                bottomTrailingRadius: 18,
                topTrailingRadius: 0
            )
        )
    }

    private func blackKeys(whiteKeyWidth: CGFloat) -> some View {
        let indexMap = whiteKeyIndexMap()

        return ZStack(alignment: .topLeading) {
            ForEach(Array(visibleRange), id: \.self) { midi in
                if isBlackKey(midi), let leftWhiteIndex = leftWhiteIndex(for: midi, indexMap: indexMap) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(activePreviewMIDINote == midi ? Theme.waveHighlight.opacity(0.92) : Color.black.opacity(0.95))
                        .overlay(alignment: .top) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(activePreviewMIDINote == midi ? Color.white.opacity(0.22) : Color.white.opacity(0.1))
                                .frame(height: 6)
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(activePreviewMIDINote == midi ? Color.white.opacity(0.45) : Color.white.opacity(0.06), lineWidth: activePreviewMIDINote == midi ? 1.0 : 0.6)
                        )
                        .frame(width: whiteKeyWidth * 0.54, height: blackKeyHeight)
                        .shadow(color: Color.black.opacity(0.28), radius: 1.2, y: 1)
                    .offset(x: CGFloat(leftWhiteIndex + 1) * whiteKeyWidth - (whiteKeyWidth * 0.26), y: -1)
                }
            }
        }
        .frame(height: keyBedHeight, alignment: .top)
    }

    private func zoneOverlays(whiteKeyWidth: CGFloat, totalWidth: CGFloat) -> some View {
        let indexMap = whiteKeyIndexMap()
        let laneMap = zoneLaneMap()

        return ZStack(alignment: .topLeading) {
            ForEach(Array(samples.enumerated()), id: \.element.id) { index, sample in
                let low = max(sample.lowNote.midi, visibleRange.lowerBound)
                let high = min(sample.highNote.midi, visibleRange.upperBound)

                if high >= low {
                    let lowX = noteStartX(for: low, whiteKeyWidth: whiteKeyWidth, indexMap: indexMap)
                    let highX = noteEndX(for: high, whiteKeyWidth: whiteKeyWidth, indexMap: indexMap)
                    let width = max(whiteKeyWidth * 0.7, highX - lowX)
                    let baseColor = index.isMultiple(of: 2) ? Theme.waveHighlight : Theme.waveGroupBHighlight
                    let isSelected = sample.id == selectedSampleID
                    let color = isSelected ? Theme.waveHighlight : baseColor

                    Button {
                        onSelectSample(sample.id)
                    } label: {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(color.opacity(isSelected ? 0.4 : 0.3))
                            .frame(width: width, height: 26)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(color.opacity(isSelected ? 1.0 : 0.8), lineWidth: isSelected ? 1.4 : 1)
                            )
                            .overlay(alignment: .leading) {
                                Text(sample.rootNote.shortLabel)
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                            }
                            .overlay(alignment: .leading) {
                                let rootX = noteCenterX(for: sample.rootNote.midi, whiteKeyWidth: whiteKeyWidth, indexMap: indexMap) - lowX
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(color.opacity(0.95))
                                    .frame(width: 10, height: 18)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 3)
                                            .stroke(Color.white.opacity(0.65), lineWidth: 1)
                                    )
                                    .offset(x: min(max(4, rootX + 4), max(4, width - 14)))
                            }
                    }
                    .buttonStyle(.plain)
                    .offset(x: lowX, y: 12 + CGFloat(laneMap[sample.id] ?? 0) * 30)
                }
            }
        }
        .frame(width: totalWidth, height: zoneBandHeight, alignment: .topLeading)
    }

    private func zoneLaneMap() -> [UUID: Int] {
        struct ZoneSpan {
            let id: UUID
            let low: Int
            let high: Int
        }

        let spans = samples
            .map {
                ZoneSpan(
                    id: $0.id,
                    low: max($0.lowNote.midi, visibleRange.lowerBound),
                    high: min($0.highNote.midi, visibleRange.upperBound)
                )
            }
            .filter { $0.high >= $0.low }
            .sorted {
                if $0.low == $1.low { return $0.high < $1.high }
                return $0.low < $1.low
            }

        var laneHighs: [Int] = []
        var result: [UUID: Int] = [:]

        for span in spans {
            var assignedLane: Int?

            for (lane, lastHigh) in laneHighs.enumerated() where lastHigh < span.low {
                assignedLane = lane
                laneHighs[lane] = span.high
                break
            }

            if assignedLane == nil {
                assignedLane = laneHighs.count
                laneHighs.append(span.high)
            }

            result[span.id] = assignedLane
        }

        return result
    }

    private func noteCenterX(for midi: Int, whiteKeyWidth: CGFloat, indexMap: [Int: Int]) -> CGFloat {
        if let whiteIndex = indexMap[midi] {
            return (CGFloat(whiteIndex) * whiteKeyWidth) + (whiteKeyWidth * 0.5)
        }

        if let leftWhite = nearestWhiteBelow(midi), let leftIndex = indexMap[leftWhite] {
            return CGFloat(leftIndex + 1) * whiteKeyWidth
        }

        return whiteKeyWidth * 0.5
    }

    private func noteStartX(for midi: Int, whiteKeyWidth: CGFloat, indexMap: [Int: Int]) -> CGFloat {
        let center = noteCenterX(for: midi, whiteKeyWidth: whiteKeyWidth, indexMap: indexMap)
        guard midi > visibleRange.lowerBound else { return 0 }

        let previousCenter = noteCenterX(for: midi - 1, whiteKeyWidth: whiteKeyWidth, indexMap: indexMap)
        return (previousCenter + center) * 0.5
    }

    private func noteEndX(for midi: Int, whiteKeyWidth: CGFloat, indexMap: [Int: Int]) -> CGFloat {
        let center = noteCenterX(for: midi, whiteKeyWidth: whiteKeyWidth, indexMap: indexMap)
        guard midi < visibleRange.upperBound else { return CGFloat(whiteKeyMIDIs.count) * whiteKeyWidth }

        let nextCenter = noteCenterX(for: midi + 1, whiteKeyWidth: whiteKeyWidth, indexMap: indexMap)
        return (center + nextCenter) * 0.5
    }

    private func nearestWhiteBelow(_ midi: Int) -> Int? {
        stride(from: midi - 1, through: visibleRange.lowerBound, by: -1).first { !isBlackKey($0) }
    }

    private func leftWhiteIndex(for midi: Int, indexMap: [Int: Int]) -> Int? {
        guard let leftWhite = nearestWhiteBelow(midi) else { return nil }
        return indexMap[leftWhite]
    }

    private func isBlackKey(_ midi: Int) -> Bool {
        [1, 3, 6, 8, 10].contains(midi % 12)
    }

    private func noteAtPoint(_ point: CGPoint, whiteKeyWidth: CGFloat, indexMap: [Int: Int], totalWidth: CGFloat) -> Int? {
        let clampedX = min(max(0, point.x), max(0, totalWidth - 1))
        let clampedY = min(max(0, point.y), keyBedHeight)

        if clampedY <= blackKeyHeight {
            for midi in visibleRange {
                guard isBlackKey(midi), let leftWhiteIndex = leftWhiteIndex(for: midi, indexMap: indexMap) else { continue }
                let blackWidth = whiteKeyWidth * 0.54
                let blackMinX = CGFloat(leftWhiteIndex + 1) * whiteKeyWidth - (whiteKeyWidth * 0.26)
                let blackMaxX = blackMinX + blackWidth
                if clampedX >= blackMinX && clampedX <= blackMaxX {
                    return midi
                }
            }
        }

        let whiteIndex = min(max(0, Int(clampedX / max(1, whiteKeyWidth))), max(0, whiteKeyMIDIs.count - 1))
        guard whiteKeyMIDIs.indices.contains(whiteIndex) else { return nil }
        return whiteKeyMIDIs[whiteIndex]
    }

    private func updatePreviewNote(_ midiNote: Int?) {
        guard let midiNote else {
            stopPreviewNote()
            return
        }
        guard activePreviewMIDINote != midiNote else { return }
        activePreviewMIDINote = midiNote
        onPreviewNote(midiNote)
    }

    private func stopPreviewNote() {
        guard activePreviewMIDINote != nil else { return }
        activePreviewMIDINote = nil
        onStopPreviewNote()
    }
}

//
//  SampleMapperView.swift
//  brWave
//

import SwiftUI

struct SampleMapperView: View {
    @StateObject private var mapper = SampleMapperState()

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(minWidth: 280, idealWidth: 320, maxWidth: 360)

            Divider()

            mainWorkspace
        }
        .background(Theme.panelBackground.ignoresSafeArea())
        .preference(
            key: InspectorContentKey.self,
            value: InspectorBox(
                id: "sample-mapper-inspector-\(mapper.selectedSampleID?.uuidString ?? "none")",
                view: AnyView(
                    SampleMapperInspectorView(
                        samples: mapper.samples,
                        selectedSample: mapper.selectedSample,
                        waveform: mapper.selectedWaveform
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
                    onLoopStartChange: { mapper.updateLoopStart(for: sample.id, to: $0) },
                    onLoopEndChange: { mapper.updateLoopEnd(for: sample.id, to: $0) }
                )
                .frame(height: 170)
                .padding(.horizontal, 20)
                .padding(.top, 20)

                SampleKeyboardMapView(samples: mapper.samples)
                    .frame(height: 220)
                    .padding(.horizontal, 20)

                SampleZoneEditorCard(
                    sample: sample,
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Sample Mapper")
                    .font(.headline)

                inspectorSection("Session") {
                    inspectorRow("Samples", "\(samples.count)")
                    inspectorRow("Detected Roots", "\(samples.filter(\.rootWasDetected).count)")
                    inspectorRow("Waveform Loaded", waveform == nil ? "No" : "Yes")
                }

                inspectorSection("Selection") {
                    if let selectedSample {
                        inspectorRow("Name", selectedSample.displayName)
                        inspectorRow("Format", selectedSample.format.label)
                        inspectorRow("Root", selectedSample.rootNote.shortLabel)
                        inspectorRow("Range", "\(selectedSample.lowNote.shortLabel) → \(selectedSample.highNote.shortLabel)")
                        if let rate = selectedSample.sampleRate {
                            inspectorRow("Sample Rate", "\(Int(rate)) Hz")
                        }
                        if let frames = selectedSample.totalFrames {
                            inspectorRow("Frames", "\(frames)")
                        }
                        inspectorRow("Loop", "\(selectedSample.loopPoints.startFrame) → \(selectedSample.loopPoints.endFrame)")
                        inspectorRow("Path", selectedSample.url.path)
                    } else {
                        Text("No sample selected.")
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
    let onLoopStartChange: (Int) -> Void
    let onLoopEndChange: (Int) -> Void

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.white.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )

                if let waveform, !waveform.peaks.isEmpty {
                    Canvas { ctx, size in
                        let midY = size.height / 2
                        let widthStep = size.width / CGFloat(max(1, waveform.peaks.count - 1))
                        var path = Path()
                        path.move(to: CGPoint(x: 0, y: midY))

                        for (index, peak) in waveform.peaks.enumerated() {
                            let x = CGFloat(index) * widthStep
                            let halfHeight = CGFloat(peak) * (size.height * 0.38)
                            path.move(to: CGPoint(x: x, y: midY - halfHeight))
                            path.addLine(to: CGPoint(x: x, y: midY + halfHeight))
                        }

                        ctx.stroke(path, with: .color(Theme.waveHighlight.opacity(0.95)), lineWidth: 1)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)

                    loopOverlay(in: geo.size, totalFrames: waveform.totalFrames)
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
                    Text("Loop handles are live here; sample start/end can come next.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(14)
            }
        }
    }

    @ViewBuilder
    private func loopOverlay(in size: CGSize, totalFrames: Int) -> some View {
        let width = max(1, size.width - 24)
        let startX = CGFloat(sample.loopPoints.startFrame) / CGFloat(max(1, totalFrames)) * width
        let endX = CGFloat(sample.loopPoints.endFrame) / CGFloat(max(1, totalFrames)) * width

        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(width: max(2, endX - startX), height: size.height - 20)
                .offset(x: 12 + startX, y: 10)

            draggableHandle(positionX: startX, totalWidth: width, height: size.height - 20, color: Theme.waveHighlight) { fraction in
                onLoopStartChange(Int(fraction * CGFloat(totalFrames)))
            }

            draggableHandle(positionX: endX, totalWidth: width, height: size.height - 20, color: Theme.waveGroupBHighlight) { fraction in
                onLoopEndChange(Int(fraction * CGFloat(totalFrames)))
            }
        }
    }

    private func draggableHandle(positionX: CGFloat, totalWidth: CGFloat, height: CGFloat, color: Color, onDrag: @escaping (CGFloat) -> Void) -> some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(color)
                .frame(width: 3, height: height)

            Circle()
                .fill(color)
                .frame(width: 12, height: 12)
        }
        .frame(width: 20, height: height)
        .contentShape(Rectangle())
        .offset(x: 12 + positionX - 10, y: 10)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let localX = max(0, min(totalWidth, positionX + value.translation.width))
                    let fraction = localX / max(1, totalWidth)
                    onDrag(fraction)
                }
        )
    }
}

private struct SampleZoneEditorCard: View {
    let sample: SampleZone
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
    private let visibleRange = 24...96

    var body: some View {
        GeometryReader { geo in
            let noteWidth = geo.size.width / CGFloat(visibleRange.count)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.white.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )

                whiteKeys(noteWidth: noteWidth)
                zoneOverlays(noteWidth: noteWidth, totalWidth: geo.size.width)
                blackKeys(noteWidth: noteWidth)
            }
        }
    }

    private func whiteKeys(noteWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(visibleRange), id: \.self) { midi in
                Rectangle()
                    .fill(isBlackKey(midi) ? Color.clear : Color.white.opacity(0.9))
                    .frame(width: noteWidth)
                    .overlay(alignment: .bottomLeading) {
                        if midi % 12 == 0 {
                            Text(SampleNote(midi: midi).label)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(Color.black.opacity(0.55))
                                .padding(.leading, 2)
                                .padding(.bottom, 2)
                        }
                    }
                    .overlay(
                        Rectangle()
                            .stroke(Color.black.opacity(0.15), lineWidth: 0.5)
                    )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func blackKeys(noteWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(visibleRange), id: \.self) { midi in
                ZStack(alignment: .leading) {
                    if isBlackKey(midi) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.black.opacity(0.95))
                            .frame(width: noteWidth * 0.7, height: 85)
                            .offset(x: -noteWidth * 0.35)
                    }
                }
                .frame(width: noteWidth)
            }
        }
        .padding(.top, 1)
    }

    private func zoneOverlays(noteWidth: CGFloat, totalWidth: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(samples.enumerated()), id: \.element.id) { index, sample in
                let low = max(sample.lowNote.midi, visibleRange.lowerBound)
                let high = min(sample.highNote.midi, visibleRange.upperBound)

                if high >= low {
                    let x = CGFloat(low - visibleRange.lowerBound) * noteWidth
                    let width = CGFloat((high - low) + 1) * noteWidth
                    let color = index.isMultiple(of: 2) ? Theme.waveHighlight : Theme.waveGroupBHighlight

                    RoundedRectangle(cornerRadius: 8)
                        .fill(color.opacity(0.3))
                        .frame(width: width, height: 26)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(color.opacity(0.8), lineWidth: 1)
                        )
                        .overlay(alignment: .leading) {
                            Text(sample.rootNote.shortLabel)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                        }
                        .offset(x: x, y: 112 + CGFloat(index % 4) * 28)
                }
            }
        }
        .frame(width: totalWidth, height: 220, alignment: .topLeading)
    }

    private func isBlackKey(_ midi: Int) -> Bool {
        [1, 3, 6, 8, 10].contains(midi % 12)
    }
}

//
//  WaveWheelControl.swift
//  brWave
//
//  Ported from OBsixer. Visual wheels for Pitch and Modulation.
//

import SwiftUI
import AppKit

struct WaveWheelControl: View {
    var title: String
    @Binding var value: Double
    var isPitch: Bool = false
    var nudgeID: String? = nil

    @State private var dragStart: Double = 0
    @State private var displayValue: Double = 0

    @Environment(\.waveControlHighlight) private var highlight

    private let wheelGradient = LinearGradient(
        stops: [
            .init(color: Color(white: 0.1), location: 0.0),
            .init(color: Color(white: 0.25), location: 0.2),
            .init(color: Color(white: 0.35), location: 0.5),
            .init(color: Color(white: 0.25), location: 0.8),
            .init(color: Color(white: 0.1), location: 1.0)
        ],
        startPoint: .leading,
        endPoint: .trailing
    )

    var body: some View {
        VStack(spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(1.0)
                .foregroundStyle(Color.secondary.opacity(0.8))

            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.black.opacity(0.5))

                GeometryReader { geo in
                    ZStack {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(wheelGradient)

                        Canvas { ctx, size in
                            let spacing: CGFloat = 10
                            let scroll = wheelOffset.truncatingRemainder(dividingBy: spacing)
                            var y = scroll - spacing
                            while y <= size.height + spacing {
                                var path = Path()
                                path.move(to: CGPoint(x: 0, y: y))
                                path.addLine(to: CGPoint(x: size.width, y: y))
                                ctx.stroke(path, with: .color(.black.opacity(0.25)), lineWidth: 1)
                                y += spacing
                            }
                            // Glow/indicator
                            let midY = size.height / 2 + centerLineOffset
                            var ind = Path()
                            ind.move(to: CGPoint(x: 2, y: midY))
                            ind.addLine(to: CGPoint(x: geo.size.width - 2, y: midY))
                            ctx.stroke(ind, with: .color(highlight.opacity(0.6)), lineWidth: 2)
                        }
                        .frame(width: geo.size.width, height: geo.size.height)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                .padding(2)
            }
            .frame(width: 32, height: 110)
            .shadow(color: .black.opacity(0.4), radius: 4, x: 0, y: 2)

            Text(valueText)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(highlight)
        }
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { gesture in
                    let delta = -gesture.translation.height / 120
                    if isPitch {
                        value = max(-1, min(1, dragStart + delta))
                    } else {
                        value = max(0, min(1, dragStart + delta))
                    }
                    displayValue = value
                }
                .onEnded { _ in
                    dragStart = value
                    if isPitch {
                        value = 0.0
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                            displayValue = 0.0
                        }
                    }
                }
        )
        .onTapGesture { dragStart = value }
        .onChange(of: value) { _, newVal in
            if isPitch && newVal == 0.0 && abs(displayValue) > 0.001 {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                    displayValue = 0.0
                }
            } else {
                displayValue = newVal
            }
        }
        .nudgeable(id: nudgeID ?? "wheel.\(title.lowercased())", controlType: .label)
    }

    private var valueText: String {
        if isPitch {
            let midi = value < 0 ? Int(value * 8192) : Int(value * 8191)
            return midi >= 0 ? "+\(midi)" : "\(midi)"
        } else {
            return "\(Int(value * 127))"
        }
    }

    private var wheelOffset: CGFloat {
        isPitch ? CGFloat(-displayValue) * 80 : CGFloat(-displayValue) * 160
    }

    private var centerLineOffset: CGFloat {
        isPitch ? CGFloat(-displayValue) * 50 : CGFloat(0.5 - displayValue) * 100
    }
}

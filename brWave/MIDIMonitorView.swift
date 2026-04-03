//
//  MIDIMonitorView.swift
//  brWave
//
//  MIDI traffic monitor for the Behringer Wave.
//  Shows live message log, device pickers, NRPN decoder, and manual NRPN sender.
//  Ported from OBsixer — stripped OB-6-specific decode, adapted for Wave 3-message NRPN.
//

import SwiftUI
import CoreMIDI

struct MIDIMonitorView: View {
    @StateObject private var midi = MIDIController.shared

    @State private var manualNRPN  = 0
    @State private var manualValue = 0
    @State private var showManualSend = false
    @State private var autoscroll    = true

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            logList
            if showManualSend { Divider(); manualSendPanel }
        }
        .background(Color.black.opacity(0.85))
        .navigationTitle("MIDI Monitor")
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("MIDI Monitor")
                    .font(.headline)
                    .foregroundStyle(Theme.waveHighlight)
                Spacer()
                Toggle("Auto-scroll", isOn: $autoscroll)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                Button("Clear") { midi.clearLogs() }
                    .buttonStyle(.bordered)
                Button("Refresh") { midi.refreshEndpoints() }
                    .buttonStyle(.bordered)
                Button("Copy Log") { copyLog() }
                    .buttonStyle(.bordered)
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Receive from:").font(.caption).foregroundStyle(.secondary)
                    Picker("", selection: $midi.selectedSourceUID) {
                        Text("None").tag(MIDIUniqueID?.none)
                        ForEach(midi.availableSources) { src in
                            Text(src.name).tag(Optional(src.uid))
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 200)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Send to:").font(.caption).foregroundStyle(.secondary)
                    Picker("", selection: $midi.selectedDestinationUID) {
                        Text("None").tag(MIDIUniqueID?.none)
                        ForEach(midi.availableDestinations) { dest in
                            Text(dest.name).tag(Optional(dest.uid))
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 200)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Channel:").font(.caption).foregroundStyle(.secondary)
                    Picker("", selection: $midi.globalChannel) {
                        ForEach(1...16, id: \.self) { ch in
                            Text("\(ch)").tag(ch)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 70)
                }

                Spacer()

                Menu {
                    Button("Edit Buffer") { midi.requestEditBuffer() }
                    Divider()
                    ForEach(0..<2, id: \.self) { bank in
                        Button("Bank \(bank), Program 0") {
                            midi.requestPreset(bank: bank, program: 0)
                        }
                    }
                } label: { Text("Request Dump") }
                .buttonStyle(.bordered)
                .disabled(midi.selectedDestinationUID == nil)

                Button {
                    showManualSend.toggle()
                } label: {
                    Label("NRPN Send", systemImage: "dial.max")
                }
                .buttonStyle(.bordered)
                .tint(showManualSend ? Theme.waveHighlight : .secondary)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial)
    }

    // MARK: - Log list

    private var logList: some View {
        ScrollViewReader { proxy in
            List(midi.logs) { entry in
                MessageRow(entry: entry)
                    .id(entry.id)
                    .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                    .listRowBackground(entry.direction == .input
                        ? Color.clear
                        : Color.blue.opacity(0.06))
            }
            .listStyle(.plain)
            .onChange(of: midi.logs.count) { _, _ in
                guard autoscroll, let last = midi.logs.last else { return }
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
        .background(Color.black.opacity(0.75))
    }

    // MARK: - Manual NRPN sender

    private var manualSendPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Manual NRPN Sender")
                    .font(.headline)
                    .foregroundStyle(Theme.waveHighlight)
                Spacer()
                Button("Close") { showManualSend = false }
            }

            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("NRPN (0–46)").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        TextField("0", value: $manualNRPN, format: .number)
                            .frame(width: 70)
                            .textFieldStyle(.roundedBorder)
                        // Future: look up WaveParameters.byNRPN[manualNRPN]
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Value: \(manualValue)").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Slider(value: Binding(
                            get: { Double(manualValue) },
                            set: { manualValue = Int($0) }
                        ), in: 0...127, step: 1)
                        .frame(width: 220)
                        TextField("0", value: $manualValue, format: .number)
                            .frame(width: 60)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                Button("Send NRPN") {
                    midi.sendNRPN(nrpn: manualNRPN, value: manualValue)
                }
                .buttonStyle(.borderedProminent)
                .disabled(midi.selectedDestinationUID == nil)

                Spacer()
            }
        }
        .padding(12)
        .background(.ultraThinMaterial)
    }

    // MARK: - Helpers

    private func copyLog() {
        let text = midi.exportLogsToString()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

// MARK: - Message row

private struct MessageRow: View {
    let entry: MIDIController.LogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(entry.direction == .input ? "IN" : "OUT")
                .font(.system(.caption2, design: .monospaced).weight(.semibold))
                .foregroundStyle(entry.direction == .input ? Color.green : Theme.waveHighlight)
                .frame(width: 28)

            Text(timestampString)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 70, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                if let comment = entry.comment, entry.data.isEmpty {
                    Text(comment)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .italic()
                } else {
                    Text(entry.hexString)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.primary)

                    if let decoded = decode(entry.data) {
                        Text(decoded)
                            .font(.caption)
                            .foregroundStyle(Theme.waveHighlight)
                    }
                    if let comment = entry.comment {
                        Text(comment)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            if !entry.data.isEmpty {
                Text("\(entry.data.count)B")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    private var timestampString: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f.string(from: entry.timestamp)
    }

    /// Human-readable description for Behringer Wave MIDI messages.
    private func decode(_ data: [UInt8]) -> String? {
        guard let first = data.first else { return nil }
        let ch = Int(first & 0x0F) + 1

        switch first & 0xF0 {
        case 0xB0: // CC
            guard data.count >= 3 else { return nil }
            let cc  = Int(data[1])
            let val = Int(data[2])
            switch cc {
            case 99: return "NRPN MSB = \(val)"
            case 98: return "NRPN LSB = \(val)  (param \(val))"
            case  6: return "Data Entry = \(val)  (ch \(ch))"
            default: return "CC \(cc) = \(val)  (ch \(ch))"
            }
        case 0xC0:
            guard data.count >= 2 else { return nil }
            return "Program Change \(data[1])  (ch \(ch))"
        case 0xF0 where first == 0xF0:
            return decodeSysEx(data)
        default:
            return nil
        }
    }

    /// Minimal Behringer Wave SysEx decoder.
    private func decodeSysEx(_ data: [UInt8]) -> String? {
        guard data.count >= 7, data[0] == 0xF0 else { return nil }
        // Wave: F0 00 20 32 00 01 39 …
        guard data[1] == 0x00, data[2] == 0x20, data[3] == 0x32,
              data[4] == 0x00, data[5] == 0x01, data[6] == 0x39 else {
            return "SysEx (\(data.count) bytes)"
        }
        guard data.count >= 9 else { return "Wave SysEx (\(data.count) bytes)" }
        let pkt  = data[7]
        let spkt = data.count >= 9 ? data[8] : 0
        switch pkt {
        case 0x74:
            switch spkt {
            case 0x05: return "Wave Program Request"
            case 0x06: return "Wave Program Preset (\(data.count) bytes)"
            case 0x07: return "Wave Edit Buffer Request"
            case 0x08: return "Wave Edit Buffer (\(data.count) bytes)"
            case 0x0A: return "Wave ACK (dump to preset)"
            case 0x0C: return "Wave ACK (dump to edit buffer)"
            case 0x0D: return "Wave Sequencer Request"
            case 0x0E: return "Wave Sequencer Data (\(data.count) bytes)"
            case 0x5D: return "Wave User Wavetable (\(data.count) bytes)"
            case 0x5E: return "Wave Wavetable ACK"
            case 0x5F: return "Wave TR/WT Name Request"
            case 0x60: return "Wave TR/WT Name List (\(data.count) bytes)"
            default:   return "Wave PKT 74 SPKT \(String(format: "%02X", spkt)) (\(data.count) bytes)"
            }
        case 0x75: return "Wave Global Param Request"
        case 0x76: return "Wave Global Params (\(data.count) bytes)"
        default:   return "Wave SysEx PKT \(String(format: "%02X", pkt)) (\(data.count) bytes)"
        }
    }
}

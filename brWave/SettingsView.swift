//
//  SettingsView.swift
//  brWave
//
//  App settings: MIDI configuration, patch behaviour, about.
//  Ported from OBsixer — adapted for brWave's 3-message NRPN and Wave identity.
//

import SwiftUI
import CoreMIDI

private let settingsFieldWidth: CGFloat = 320

struct SettingsView: View {
    @ObservedObject var midi = MIDIController.shared
    @AppStorage("autoSendPatchOnSelection") private var autoSendPatchOnSelection = false
    @AppStorage("sampleMapperPathDisplayMode") private var sampleMapperPathDisplayMode = "homeRelative"

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 24) {

                // Left column
                VStack(alignment: .leading, spacing: 24) {

                    SettingsCard(title: "MIDI Configuration") {
                        VStack(alignment: .leading, spacing: 12) {

                            HStack(alignment: .center, spacing: 8) {
                                Text("Input Device").font(.callout)
                                Spacer(minLength: 8)
                                Picker("", selection: $midi.selectedSourceUID) {
                                    Text("None").tag(MIDIUniqueID?.none)
                                    ForEach(midi.availableSources) { src in
                                        Text(src.name).tag(Optional(src.uid))
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(maxWidth: settingsFieldWidth)
                            }

                            HStack(alignment: .center, spacing: 8) {
                                Text("Output Device").font(.callout)
                                Spacer(minLength: 8)
                                Picker("", selection: $midi.selectedDestinationUID) {
                                    Text("None").tag(MIDIUniqueID?.none)
                                    ForEach(midi.availableDestinations) { dest in
                                        Text(dest.name).tag(Optional(dest.uid))
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(maxWidth: settingsFieldWidth)
                            }

                            HStack(alignment: .center, spacing: 8) {
                                Text("MIDI Channel").font(.callout)
                                Spacer(minLength: 8)
                                Picker("", selection: $midi.globalChannel) {
                                    ForEach(1...16, id: \.self) { ch in
                                        Text("Channel \(ch)").tag(ch)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(maxWidth: settingsFieldWidth)
                            }

                            Divider().padding(.top, 2)

                            HStack {
                                Spacer()
                                Button { midi.refreshEndpoints() } label: {
                                    Label("Refresh Devices", systemImage: "arrow.clockwise")
                                }
                            }
                        }
                    }

                    SettingsCard(title: "About") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("App")
                                Spacer()
                                Text("brWave").foregroundStyle(.secondary)
                            }
                            HStack {
                                Text("Version")
                                Spacer()
                                Text(appVersion).foregroundStyle(.secondary)
                            }
                            HStack {
                                Text("Build")
                                Spacer()
                                Text(appBuild).foregroundStyle(.secondary)
                            }
                            HStack {
                                Text("Hardware")
                                Spacer()
                                Text("Behringer WAVE").foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                // Right column
                VStack(alignment: .leading, spacing: 24) {
                    SettingsCard(title: "Patch Behaviour") {
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle("Auto-send patch to WAVE", isOn: $autoSendPatchOnSelection)
                            Text("When enabled, selecting a patch in the library immediately sends it to the Wave edit buffer.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    SettingsCard(title: "Sample Mapper") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .center, spacing: 8) {
                                Text("Path Display")
                                    .font(.callout)
                                Spacer(minLength: 8)
                                Picker("", selection: $sampleMapperPathDisplayMode) {
                                    Text("From ~").tag("homeRelative")
                                    Text("Full Path").tag("full")
                                }
                                .pickerStyle(.menu)
                                .frame(maxWidth: settingsFieldWidth)
                            }

                            Text("Controls how imported sample paths appear in the inspector when the path row is expanded.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: 980)
            .padding(.horizontal, 24)
            .padding(.vertical, 24)
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }
    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 2)
            VStack(alignment: .leading, spacing: 10) {
                content
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
                    )
            )
        }
    }
}

#Preview { SettingsView() }

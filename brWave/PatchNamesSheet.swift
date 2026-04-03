//
//  PatchNamesSheet.swift
//  brWave
//
//  "Apply Names from Clipboard" sheet.
//  Parses pasted text (manual, website, plain list) into (program, name) pairs,
//  lets the user pick a target library + bank, previews the matches, then applies.
//

import SwiftUI
import CoreData

// MARK: - Parser

enum PatchNameParser {

    /// KEYB mode keywords — used to split fields in the manual's table format
    private static let keybKeywords = [
        "A poly, B mono", "A-Quad, B-Quad", "Quad A/B", "Poly", "Quad", "Mono"
    ]

    struct ParsedEntry {
        let program: Int    // 0–99
        let name: String
    }

    /// Parse arbitrary pasted text into (program 0–99, name) pairs.
    /// Handles two layouts found in the Behringer Wave manual:
    ///   Bank 0: "N  Poly  WT  Name  X"
    ///   Bank 1: "N  Name  Poly  WT"
    /// Also handles simple formats: "N - Name", "N. Name", "N Name"
    static func parse(_ text: String) -> [ParsedEntry] {
        var results: [ParsedEntry] = []

        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            // Must start with a 1–2 digit program number
            guard let match = line.range(of: #"^\d{1,2}"#, options: .regularExpression),
                  let prog = Int(line[match]),
                  prog >= 0, prog <= 99 else { continue }

            // Strip the leading number and any separator (space, dash, dot, comma)
            var rest = String(line[match.upperBound])
                .trimmingCharacters(in: .whitespaces)
            if rest.hasPrefix("-") || rest.hasPrefix(".") || rest.hasPrefix(",") {
                rest = String(rest.dropFirst()).trimmingCharacters(in: .whitespaces)
            }

            guard let name = extractName(from: rest), !name.isEmpty else { continue }
            results.append(ParsedEntry(program: prog, name: name))
        }

        return results
    }

    /// Extract the patch name from the remainder of a line after the program number.
    /// Strips KEYB keywords, trailing WT numbers, and trailing X/AT markers.
    private static func extractName(from text: String) -> String? {
        var s = text

        // If line starts with a KEYB keyword → name comes after "KEYB  WT  "
        // Pattern: "Poly  21  Thimje  X" → skip keyword + number → "Thimje"
        for kw in keybKeywords {
            if s.hasPrefix(kw) {
                s = String(s.dropFirst(kw.count)).trimmingCharacters(in: .whitespaces)
                // Skip the WT/TR number
                if let numRange = s.range(of: #"^\d+"#, options: .regularExpression) {
                    s = String(s[numRange.upperBound]).trimmingCharacters(in: .whitespaces)
                }
                break
            }
        }

        // Now s should start with the name. Strip everything from the first KEYB
        // keyword onward (for Bank 1 format: "WAVE Spill  Poly  17")
        for kw in keybKeywords {
            if let range = s.range(of: "  " + kw) {
                s = String(s[..<range.lowerBound])
            } else if let range = s.range(of: "\t" + kw) {
                s = String(s[..<range.lowerBound])
            }
        }

        // Strip trailing X / AT markers and trailing numbers
        s = s.replacingOccurrences(of: #"\s+X\s*$"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s+\d+\s*$"#, with: "", options: .regularExpression)
        s = s.trimmingCharacters(in: .whitespaces)

        // Reject if what's left looks like a keyword or is empty
        let lower = s.lowercased()
        if lower.isEmpty || lower == "name" || lower == "prog" { return nil }

        return s.isEmpty ? nil : s
    }
}

// MARK: - Sheet

struct PatchNamesSheet: View {
    @Environment(\.managedObjectContext) var context
    @Environment(\.dismiss) var dismiss

    @FetchRequest(
        entity: PatchSet.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \PatchSet.createdAt, ascending: true)]
    )
    private var libraries: FetchedResults<PatchSet>

    @State private var selectedLibraryID: UUID?
    @State private var selectedBank: Int = 0
    @State private var parsed: [PatchNameParser.ParsedEntry] = []
    @State private var applied = false

    private struct MatchedEntry: Identifiable {
        let id: Int   // program number — unique within a bank
        let entry: PatchNameParser.ParsedEntry
        let current: String
    }

    private var selectedLibrary: PatchSet? {
        libraries.first { $0.uuid == selectedLibraryID }
    }

    /// Parsed entries that have a matching slot in the chosen library+bank
    private var matchedEntries: [MatchedEntry] {
        guard let lib = selectedLibrary else { return [] }
        let slots = lib.slotsArray.filter { $0.bankIndex == selectedBank }
        let byProgram = Dictionary(uniqueKeysWithValues: slots.compactMap { slot -> (Int, String)? in
            guard let patch = slot.patch else { return nil }
            return (slot.programIndex, patch.name ?? "")
        })
        return parsed.compactMap { entry in
            guard byProgram[entry.program] != nil else { return nil }
            return MatchedEntry(id: entry.program, entry: entry, current: byProgram[entry.program]!)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Apply Names from Clipboard")
                .font(.headline)

            if parsed.isEmpty {
                Text("No recognisable patch names found in clipboard.\n\nCopy a patch list (from the manual, a website, or a plain numbered list) then try again.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                Text("Found \(parsed.count) name\(parsed.count == 1 ? "" : "s"). Choose which library and bank to apply them to.")
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Picker("Library", selection: $selectedLibraryID) {
                        ForEach(libraries) { lib in
                            Text(lib.name ?? "Untitled").tag(lib.uuid as UUID?)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    Picker("Bank", selection: $selectedBank) {
                        Text("Bank 0 — Factory").tag(0)
                        Text("Bank 1 — PPG Classic").tag(1)
                    }
                    .frame(width: 180)
                }

                if !matchedEntries.isEmpty {
                    Text("\(matchedEntries.count) of \(parsed.count) names match occupied slots:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Table(matchedEntries) {
                        TableColumn("Prog") { row in
                            Text(String(format: "%02d", row.entry.program))
                                .font(.system(.caption, design: .monospaced))
                        }
                        .width(36)
                        TableColumn("New Name") { row in
                            Text(row.entry.name)
                                .font(.system(size: 12))
                        }
                        TableColumn("Current Name") { row in
                            Text(row.current.isEmpty ? "—" : row.current)
                                .font(.system(size: 12))
                                .foregroundStyle(row.current == row.entry.name ? .secondary : .primary)
                        }
                    }
                    .frame(minHeight: 200, maxHeight: 340)
                } else if selectedLibrary != nil {
                    Text("No occupied slots in Bank \(selectedBank) match the parsed program numbers.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 20)
                }
            }

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if applied {
                    Label("Applied", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                Button("Apply Names") { applyNames() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(matchedEntries.isEmpty)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 560)
        .onAppear {
            parsed = PatchNameParser.parse(NSPasteboard.general.string(forType: .string) ?? "")
            selectedLibraryID = libraries.first?.uuid
        }
    }

    private func applyNames() {
        guard let lib = selectedLibrary else { return }
        let slots = lib.slotsArray.filter { $0.bankIndex == selectedBank }
        let byProgram = Dictionary(grouping: slots, by: { $0.programIndex })

        for entry in parsed {
            if let slot = byProgram[entry.program]?.first, let patch = slot.patch {
                patch.name = String(entry.name.prefix(16))
            }
        }
        try? context.save()
        applied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { dismiss() }
    }
}

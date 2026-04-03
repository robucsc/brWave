//
//  ParameterTableView.swift
//  brWave
//
//  Spreadsheet-style view of all Wave parameters for a selected patch.
//  Shows Group A and Group B values side-by-side for per-group params.
//

import SwiftUI

struct ParameterTableView: View {
    @ObservedObject var patch: Patch

    @State private var sortOrder = [KeyPathComparator(\WaveParamDescriptor.nrpnSort)]

    private var sortedParams: [WaveParamDescriptor] {
        WaveParameters.all.sorted(using: sortOrder)
    }

    var body: some View {
        Table(sortedParams, sortOrder: $sortOrder) {

            TableColumn("Parameter", value: \.displayName) { desc in
                Text(desc.displayName)
                    .fontWeight(.medium)
            }
            .width(min: 120, ideal: 160)

            TableColumn("Section", value: \.groupSortKey) { desc in
                Text(desc.group.rawValue)
                    .foregroundStyle(.secondary)
            }
            .width(min: 80, ideal: 110)

            TableColumn("Value A") { desc in
                ParamValueCell(patch: patch, desc: desc, group: .a)
            }
            .width(min: 100, ideal: 130)

            TableColumn("Value B") { desc in
                if case .perGroup = desc.storage {
                    ParamValueCell(patch: patch, desc: desc, group: .b)
                } else {
                    Text("—")
                        .foregroundStyle(.quaternary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .width(min: 100, ideal: 130)

            TableColumn("Range", value: \.range.lowerBound) { desc in
                Text("\(desc.range.lowerBound)…\(desc.range.upperBound)")
                    .foregroundStyle(.tertiary)
                    .font(.caption)
            }
            .width(min: 60, ideal: 80)

            TableColumn("NRPN", value: \.nrpnSort) { desc in
                Text(desc.nrpn.map { "\($0)" } ?? "—")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .width(min: 50, ideal: 60)
        }
    }
}

// MARK: - Value Cell

private struct ParamValueCell: View {
    @ObservedObject var patch: Patch
    let desc: WaveParamDescriptor
    let group: WaveGroup

    private var valueBinding: Binding<Int> {
        Binding(
            get: { patch.value(for: desc.id, group: group) },
            set: { patch.setValue($0, for: desc.id, group: group) }
        )
    }

    var body: some View {
        if desc.range == 0...1 {
            Toggle("", isOn: Binding(
                get: { patch.value(for: desc.id, group: group) != 0 },
                set: { patch.setValue($0 ? 1 : 0, for: desc.id, group: group) }
            ))
            .labelsHidden()
        } else {
            HStack(spacing: 4) {
                TextField("", value: valueBinding, format: .number)
                    .labelsHidden()
                    .frame(width: 52)
                    .multilineTextAlignment(.trailing)
                Stepper("", value: valueBinding,
                        in: desc.range.lowerBound...desc.range.upperBound)
                    .labelsHidden()
            }
        }
    }
}

// MARK: - Sort helpers

private extension WaveParamDescriptor {
    /// Nil NRPNs sort to the end.
    var nrpnSort: Int { nrpn ?? Int.max }
    /// Stable sort key for section column.
    var groupSortKey: String { group.rawValue }
}

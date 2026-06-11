// Sources/App/Fixture/StoreSheets.swift
import SwiftUI
import SaettaKit

/// One programmer attribute and its running (relative) offset, for the store preview.
struct StoredValue: Identifiable {
    let label: String
    let value: String
    var id: String { label }
}

/// Store the desk's current programmer into a cue. Sequence prefilled from the
/// active song. Shows the exact command before firing.
struct StoreCueSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var sequence: Int
    @State var cue: Int
    @State var mode: StoreMode
    var selection: String = ""
    var values: [StoredValue] = []
    let onStore: (String) -> Void

    var body: some View {
        StoreSheetScaffold(
            title: "Store to Cue",
            command: FixtureControlBuilder.storeCue(sequence: sequence, cue: cue, mode: mode),
            mode: $mode,
            actionTitle: "Store",
            selection: selection,
            values: values,
            onConfirm: { onStore(FixtureControlBuilder.storeCue(sequence: sequence, cue: cue, mode: mode)); dismiss() },
            onCancel: { dismiss() }
        ) {
            numField("Sequence", value: $sequence)
            numField("Cue", value: $cue)
        }
    }

    @ViewBuilder private func numField(_ label: String, value: Binding<Int>) -> some View {
        HStack {
            Text(label).foregroundStyle(Theme.textDim)
            Spacer()
            TextField("", value: value, format: .number)
                .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                .font(.system(size: 18, weight: .bold).monospacedDigit())
                .foregroundStyle(Theme.text).frame(width: 90)
                .padding(.vertical, 8).padding(.horizontal, 10)
                .background(Theme.surface3, in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
        }
    }
}

/// Overwrite/merge an existing preset from the current programmer.
struct UpdatePresetSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var pool: Pool = .color
    @State var number: Int = 1
    @State var mode: StoreMode
    var selection: String = ""
    var values: [StoredValue] = []
    let onUpdate: (String) -> Void

    var body: some View {
        StoreSheetScaffold(
            title: "Update Preset",
            command: FixtureControlBuilder.updatePreset(pool: pool, number: number, mode: mode),
            mode: $mode,
            actionTitle: "Update",
            selection: selection,
            values: values,
            onConfirm: { onUpdate(FixtureControlBuilder.updatePreset(pool: pool, number: number, mode: mode)); dismiss() },
            onCancel: { dismiss() }
        ) {
            HStack {
                Text("Pool").foregroundStyle(Theme.textDim)
                Spacer()
                Picker("Pool", selection: $pool) {
                    ForEach(Pool.allCases, id: \.self) { Text("\($0.rawValue.capitalized) (\($0.number))").tag($0) }
                }.tint(Theme.accentSolid)
            }
            HStack {
                Text("Preset #").foregroundStyle(Theme.textDim)
                Spacer()
                TextField("", value: $number, format: .number)
                    .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                    .font(.system(size: 18, weight: .bold).monospacedDigit())
                    .foregroundStyle(Theme.text).frame(width: 90)
                    .padding(.vertical, 8).padding(.horizontal, 10)
                    .background(Theme.surface3, in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
            }
        }
    }
}

/// Shared chrome: title, fields slot, overwrite/merge toggle, command preview, actions.
private struct StoreSheetScaffold<Fields: View>: View {
    let title: String
    let command: String
    @Binding var mode: StoreMode
    let actionTitle: String
    var selection: String = ""
    var values: [StoredValue] = []
    let onConfirm: () -> Void
    let onCancel: () -> Void
    @ViewBuilder let fields: () -> Fields

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.canvas
                VStack(alignment: .leading, spacing: 16) {
                    fields()
                    Picker("Mode", selection: $mode) {
                        ForEach(StoreMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented)
                    StorePreview(selection: selection, values: values)
                    Text(command).font(.system(size: 13).monospacedDigit())
                        .foregroundStyle(Theme.textFaint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10).background(Theme.surface1, in: RoundedRectangle(cornerRadius: Theme.radius))
                    Button(action: onConfirm) {
                        Text(actionTitle).font(.system(size: 17, weight: .bold))
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(Theme.accentSolid, in: RoundedRectangle(cornerRadius: Theme.radiusLarge))
                            .foregroundStyle(.white)
                    }.buttonStyle(.plain)
                    Spacer()
                }
                .padding(20)
            }
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Cancel", action: onCancel) } }
        }
    }
}

/// "What will be stored": the selection + every programmer attribute and its
/// running offset, laid out as a clean two-column list. Values are RED to mirror
/// grandMA3's programmer convention, and shown as RELATIVE session changes
/// (the app has no desk read-back, so it reports what *you* changed, not absolutes).
private struct StorePreview: View {
    let selection: String
    let values: [StoredValue]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Will store", systemImage: "tray.and.arrow.down.fill")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.textDim)
                Spacer()
                Text("relative").font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.textFaint)
            }
            .padding(.bottom, 8)

            HStack(alignment: .firstTextBaseline) {
                Text("Fixtures").font(.system(size: 13)).foregroundStyle(Theme.textFaint)
                Spacer()
                Text(selection.isEmpty ? "—" : selection)
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
                    .lineLimit(1).truncationMode(.head)
            }

            Divider().overlay(Theme.border).padding(.vertical, 8)

            if values.isEmpty {
                Label("Nothing changed this session — the programmer is empty.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12)).foregroundStyle(Theme.warn)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView {
                    VStack(spacing: 7) {
                        ForEach(values) { v in
                            HStack {
                                Text(v.label).font(.system(size: 14)).foregroundStyle(Theme.text)
                                Spacer()
                                Text(v.value)
                                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Theme.danger)   // red = programmer values (MA convention)
                            }
                        }
                    }
                }
                .frame(maxHeight: 190)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface1, in: RoundedRectangle(cornerRadius: Theme.radius))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.border, lineWidth: 0.5))
    }
}

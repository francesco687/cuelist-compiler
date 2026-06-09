// Sources/App/Fixture/SelectionKeypadSheet.swift
import SwiftUI
import SaettaKit

/// Builds a grandMA3 selection command on a numeric keypad and fires it on Select.
struct SelectionKeypadSheet: View {
    @Environment(\.dismiss) private var dismiss
    /// Called with the assembled command (e.g. "Fixture 101 Thru 105").
    let onSelect: (String) -> Void

    @State private var entry = SelectionEntry()

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.canvas
                VStack(spacing: 16) {
                    Text(entry.isEmpty ? "—" : entry.command)
                        .font(.system(size: 20, weight: .bold).monospacedDigit())
                        .foregroundStyle(entry.isEmpty ? Theme.textFaint : Theme.accentSolid)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .padding(.horizontal, 12)
                        .background(Theme.surface1, in: RoundedRectangle(cornerRadius: Theme.radius))

                    HStack(spacing: 8) {
                        keyword(.fixture, "Fixture")
                        keyword(.group, "Group")
                        keyword(.thru, "Thru")
                        keyword(.plus, "+")
                    }

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                        ForEach(1...9, id: \.self) { d in digit(d) }
                        Button { entry.backspace() } label: { keyLabel("⌫", tint: Theme.surface3) }
                        digit(0)
                        Button { entry.reset() } label: { keyLabel("Clr", tint: Theme.surface3) }
                    }

                    Button {
                        let cmd = entry.command
                        guard !cmd.isEmpty else { return }
                        onSelect(cmd); dismiss()
                    } label: {
                        Text("Select").font(.system(size: 17, weight: .bold))
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(entry.isEmpty ? Theme.surface2 : Theme.accentSolid,
                                        in: RoundedRectangle(cornerRadius: Theme.radiusLarge))
                            .foregroundStyle(entry.isEmpty ? Theme.textDim : .white)
                    }
                    .buttonStyle(.plain).disabled(entry.isEmpty)
                }
                .padding(20)
            }
            .navigationTitle("Select").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Cancel") { dismiss() } } }
        }
    }

    private func digit(_ d: Int) -> some View {
        Button { entry.tapDigit(d) } label: { keyLabel(String(d), tint: Theme.surface2) }
    }
    private func keyword(_ k: SelectionEntry.Keyword, _ title: String) -> some View {
        Button { entry.tapKeyword(k) } label: {
            Text(title).font(.system(size: 14, weight: .semibold))
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(Theme.surface3, in: RoundedRectangle(cornerRadius: Theme.radius))
                .foregroundStyle(Theme.accentSolid)
        }.buttonStyle(.plain)
    }
    private func keyLabel(_ s: String, tint: Color) -> some View {
        Text(s).font(.system(size: 22, weight: .semibold)).foregroundStyle(Theme.text)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(tint, in: RoundedRectangle(cornerRadius: Theme.radius))
    }
}

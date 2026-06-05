import SwiftUI
import CuelistCompilerKit

/// Edit or clear a single cue's saved note (the `\n`-joined `cue.notes` blob).
/// Distinct from NotesCaptureView, which *captures/routes* new notes.
struct EditNoteView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let cueN: Double
    @State private var text: String

    init(cueN: Double, initialText: String) {
        self.cueN = cueN
        _text = State(initialValue: initialText)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.canvas
                VStack(alignment: .leading, spacing: 14) {
                    TextField("Note", text: $text, axis: .vertical)
                        .lineLimit(3...10)
                        .padding(12)
                        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: Theme.radius))
                        .foregroundStyle(Theme.text)

                    HStack(spacing: 12) {
                        Button(role: .destructive) {
                            store.setNote(cueN: cueN, text: "")
                            dismiss()
                        } label: {
                            Label("Clear", systemImage: "trash")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Theme.danger)
                                .padding(.vertical, 10).padding(.horizontal, 16)
                                .overlay(RoundedRectangle(cornerRadius: Theme.radius)
                                    .strokeBorder(Theme.danger.opacity(0.35), lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        Button {
                            store.setNote(cueN: cueN, text: text)
                            dismiss()
                        } label: {
                            Text("Save")
                                .font(.system(size: 14, weight: .semibold))
                                .padding(.vertical, 10).padding(.horizontal, 20)
                                .background(Theme.aqua, in: RoundedRectangle(cornerRadius: Theme.radius))
                                .foregroundStyle(Theme.aquaInk)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
                .padding(16)
            }
            .navigationTitle("Edit note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

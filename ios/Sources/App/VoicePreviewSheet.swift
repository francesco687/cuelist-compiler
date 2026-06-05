import SwiftUI
import CuelistCompilerKit

/// Renders a VoiceCaptureController.Pending: transcript + change summary + warnings,
/// with Apply / Discard. Apply is disabled for clarification-only results.
struct VoicePreviewSheet: View {
    let pending: VoiceCaptureController.Pending
    let onApply: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("Heard") { Text("\u{201C}\(pending.transcript)\u{201D}").italic() }

                if let q = pending.clarification {
                    Section("Needs clarification") {
                        Label(q, systemImage: "questionmark.circle").foregroundStyle(Theme.warn)
                    }
                }

                if !pending.summary.isEmpty {
                    Section("Will change") {
                        ForEach(Array(pending.summary.enumerated()), id: \.offset) { _, line in
                            Label(line, systemImage: "pencil")
                        }
                    }
                }

                if !pending.warnings.isEmpty {
                    Section("Skipped") {
                        ForEach(Array(pending.warnings.enumerated()), id: \.offset) { _, w in
                            Label(w, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.textDim)
                        }
                    }
                }
            }
            .navigationTitle("Voice command")
            .navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden)
            .background(Theme.canvas)
            .tint(Theme.accentSolid)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Discard", role: .cancel, action: onDiscard) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply", action: onApply).disabled(!pending.canApply).bold()
                }
            }
        }
    }
}

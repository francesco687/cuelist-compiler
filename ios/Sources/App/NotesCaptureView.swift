import SwiftUI
import CuelistCompilerKit

/// Sheet for adding a note by text or voice. If `targetCue` is set the note is
/// pinned to that cue; otherwise the router decides which cue(s) it belongs to,
/// and a routing preview is shown before applying.
struct NotesCaptureView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(NotesCaptureController.self) private var notes
    @Environment(\.dismiss) private var dismiss

    /// nil = global brain-dump; set = per-cue.
    let targetCue: Double?

    @State private var text = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.canvas
                VStack(alignment: .leading, spacing: 14) {
                    TextField("Type a note, or use the mic...", text: $text, axis: .vertical)
                        .lineLimit(3...8)
                        .padding(12)
                        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: Theme.radius))
                        .foregroundStyle(Theme.text)

                    HStack(spacing: 12) {
                        micButton
                        Spacer()
                        Button {
                            Task {
                                await notes.routeText(text, project: store.project, targetCue: targetCue)
                                if case .preview = notes.phase, targetCue != nil {
                                    store.applyNotes(notes.routed); notes.reset(); dismiss()
                                }
                            }
                        } label: {
                            Text(targetCue == nil ? "Route" : "Add")
                                .font(.system(size: 14, weight: .semibold))
                                .padding(.vertical, 10).padding(.horizontal, 20)
                                .background(Theme.aqua, in: RoundedRectangle(cornerRadius: Theme.radius))
                                .foregroundStyle(Theme.aquaInk)
                        }
                        .buttonStyle(.plain)
                        .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                        .opacity(text.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
                    }

                    if case .routing = notes.phase { ProgressView("Routing...").tint(Theme.aqua) }
                    if case let .error(msg) = notes.phase {
                        Label(msg, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 12)).foregroundStyle(Theme.danger)
                    }

                    if targetCue == nil, case .preview = notes.phase, !notes.routed.isEmpty {
                        routingPreview
                    }
                    Spacer()
                }
                .padding(16)
            }
            .navigationTitle(targetCue == nil ? "Notes" : "Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { notes.reset(); dismiss() }
                }
            }
        }
        .onAppear { notes.reset() }
    }

    @ViewBuilder private var micButton: some View {
        if notes.phase.isNotesRecording {
            Button {
                Task { let t = await notes.stopAndTranscribe(); if !t.isEmpty { text = text.isEmpty ? t : text + " " + t } }
            } label: {
                Label("Stop", systemImage: "stop.circle.fill")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.danger)
            }.buttonStyle(.plain)
        } else if case .transcribing = notes.phase {
            ProgressView().tint(Theme.aqua)
        } else {
            Button { Task { await notes.startRecording() } } label: {
                Label("Mic", systemImage: "mic.fill")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.aqua)
            }.buttonStyle(.plain)
        }
    }

    private var routingPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Routes to").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.textDim)
            ForEach(Array(notes.routed.enumerated()), id: \.offset) { _, e in
                HStack(spacing: 8) {
                    Text("Cue \(formatN(e.cue))").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.aqua)
                    Text(e.text).font(.system(size: 12)).foregroundStyle(Theme.text)
                }
                .padding(.vertical, 6).padding(.horizontal, 10)
                .background(Theme.aquaTint, in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
            }
            Button {
                store.applyNotes(notes.routed); notes.reset(); dismiss()
            } label: {
                Text("Add \(notes.routed.count) note\(notes.routed.count == 1 ? "" : "s")")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity).padding(.vertical, 11)
                    .background(Theme.aquaGradient, in: RoundedRectangle(cornerRadius: Theme.radius))
                    .foregroundStyle(Theme.aquaInk)
            }.buttonStyle(.plain).padding(.top, 4)
        }
    }

    private func formatN(_ n: Double) -> String { n.rounded() == n ? String(Int(n)) : String(n) }
}

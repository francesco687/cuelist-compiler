import SwiftUI
import CuelistCompilerKit

struct CueCardView: View {
    @Environment(ProjectStore.self) private var store
    @Binding var cue: Cue

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    cue.collapsed.toggle()
                } label: {
                    Image(systemName: cue.collapsed ? "chevron.right" : "chevron.down")
                }
                TextField("n", value: $cue.n, format: .number)
                    .frame(width: 48).textFieldStyle(.roundedBorder).keyboardType(.decimalPad)
                TextField("Cue name", text: $cue.name).textFieldStyle(.roundedBorder)
                Button(role: .destructive) {
                    store.removeCue(id: cue.id)
                } label: { Image(systemName: "trash") }
            }

            if cue.collapsed {
                let summary = CueSummary.text(for: cue)
                if !summary.isEmpty {
                    Text(summary).font(.caption).foregroundStyle(.secondary)
                }
            } else {
                CopyFromBar(cue: $cue)                     // Task 14
                ForEach($cue.actions) { $action in
                    ActionBlockView(cue: $cue, action: $action)   // Task 13
                }
                Button {
                    store.addActionBlock(cueId: cue.id)
                } label: { Label("Add Group block", systemImage: "plus.rectangle") }
                    .font(.callout)
                HStack {
                    Text("Fade"); TextField("", text: $cue.fade)
                        .textFieldStyle(.roundedBorder).frame(width: 60).keyboardType(.decimalPad)
                    Text("Delay"); TextField("", text: $cue.delay)
                        .textFieldStyle(.roundedBorder).frame(width: 60).keyboardType(.decimalPad)
                }.font(.caption)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
    }
}

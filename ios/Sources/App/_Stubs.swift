import SwiftUI
import CuelistCompilerKit

// Temporary placeholders so RootView compiles; replaced in Tasks 12 & 15.
struct SendBarView: View { var body: some View { EmptyView() } }
struct SettingsView: View { var body: some View { Text("Settings — Task 15") } }
struct DefaultsView: View { var body: some View { Text("Defaults — Task 15") } }

struct ActionBlockView: View {
    @Binding var cue: Cue
    @Binding var action: Action
    var body: some View { Text("group: \(action.group)") }
}
struct CopyFromBar: View {
    @Binding var cue: Cue
    var body: some View { EmptyView() }
}

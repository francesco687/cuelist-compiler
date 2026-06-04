import SwiftUI
import CuelistCompilerKit

struct RootView: View {
    @Environment(ProjectStore.self) private var store
    @State private var showSettings = false
    @State private var showDefaults = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SongBarView()
                CueListView()              // added in Task 12
                SendBarView()              // added in Task 15
            }
            .navigationTitle("Cuelist Compiler")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Defaults…") { showDefaults = true }
                        Button("Settings…") { showSettings = true }
                    } label: { Image(systemName: "slider.horizontal.3") }
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }     // Task 15
            .sheet(isPresented: $showDefaults) { DefaultsView() }     // Task 15
        }
    }
}

import SwiftUI
import SaettaKit

/// Third tab — absorbs the old Author top slider-menu.
struct SettingsTabView: View {
    @State private var showPull = false
    @State private var showDefaults = false
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.canvas
                List {
                    Section {
                        row("Pull from MA\u{2026}", systemImage: "arrow.down.circle") { showPull = true }
                    }
                    Section {
                        row("Defaults\u{2026}", systemImage: "slider.horizontal.3") { showDefaults = true }
                        row("Settings\u{2026}", systemImage: "gearshape") { showSettings = true }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .sheet(isPresented: $showPull) { PullSequencesView() }
            .sheet(isPresented: $showDefaults) { DefaultsView() }
            .sheet(isPresented: $showSettings) { SettingsView() }
        }
    }

    private func row(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .foregroundStyle(Theme.text)
        }
        .listRowBackground(Theme.surface1)
    }
}

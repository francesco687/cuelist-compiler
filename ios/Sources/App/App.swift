import SwiftUI
import CuelistCompilerKit

@main
struct CuelistCompilerApp: App {
    var body: some Scene {
        WindowGroup {
            VStack(spacing: 12) {
                Text("Cuelist Compiler").font(.title.bold())
                Text("Engine v\(CuelistCompilerKit.schemaVersion) — UI lands in later tasks")
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }
}

import SwiftUI
import CuelistCompilerKit

@main
struct CuelistCompilerApp: App {
    @State private var store = ProjectStore()
    @State private var hub = HubClient(makeConnection: { url in
        URLSessionWebSocketConnection(url: url)
    })

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(hub)
                .onAppear { if !hub.host.isEmpty { hub.connect() } }
        }
    }
}

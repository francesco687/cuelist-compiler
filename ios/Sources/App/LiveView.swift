import SwiftUI
import CuelistCompilerKit

/// The Live tab — run cues on the console-selected executor.
/// Bare command-line transport (GO+/GO-/PAUSE) over the hub's `cmd` passthrough.
/// Optimistic: each tap fires immediately with haptic + a press pulse; buttons
/// disable when the hub is offline.
struct LiveView: View {
    @Environment(HubClient.self) private var hub
    @State private var fireCount = 0

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.canvas
                VStack(spacing: 14) {
                    connectionRow
                    VStack(spacing: 14) {
                        TransportButton(title: "GO+", symbol: "arrow.right.circle.fill",
                                        tint: Theme.ok) { fire("Go+") }
                        TransportButton(title: "PAUSE", symbol: "pause.circle.fill",
                                        tint: Theme.warn) { fire("Pause") }
                        TransportButton(title: "GO-", symbol: "arrow.left.circle.fill",
                                        tint: Theme.textFaint) { fire("Go-") }
                    }
                    .disabled(!hub.state.isOnline)
                    .opacity(hub.state.isOnline ? 1 : 0.4)
                }
                .padding(20)
            }
            .navigationTitle("Live")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .sensoryFeedback(.impact(weight: .medium), trigger: fireCount)
        }
    }

    private func fire(_ line: String) {
        fireCount += 1
        hub.sendCommand(line)
    }

    private var connectionRow: some View {
        Button { hub.connect() } label: {
            HStack(spacing: 10) {
                LiveIndicator(state: hub.state)
                Spacer()
                Text(hub.state.isOnline ? "Connected" : "Tap to connect")
                    .font(.system(size: 12)).foregroundStyle(Theme.textDim)
            }
            .padding(.vertical, 12).padding(.horizontal, 14)
            .background(Theme.surface1, in: RoundedRectangle(cornerRadius: Theme.radius))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// One large transport button: big symbol + title, tinted fill, press-scale feedback.
private struct TransportButton: View {
    let title: String
    let symbol: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 36, weight: .bold))
                Text(title).font(.system(size: 24, weight: .heavy))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(tint.gradient, in: RoundedRectangle(cornerRadius: Theme.radiusLarge))
        }
        .buttonStyle(PressScaleStyle())
    }
}

/// Brief scale + dim while pressed — the optimistic "it fired" pulse.
private struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.snappy(duration: 0.12), value: configuration.isPressed)
    }
}

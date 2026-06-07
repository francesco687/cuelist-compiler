import SwiftUI
import SaettaKit

/// The Live tab — run cues on the console-selected executor.
/// Bare command-line transport (GO+/GO-/PAUSE) over the hub's `cmd` passthrough.
/// Optimistic: each tap fires immediately with haptic + a press pulse; buttons
/// disable when the hub is offline.
struct LiveView: View {
    @Environment(HubClient.self) private var hub
    @State private var fireCount = 0
    @State private var messageText = ""
    @State private var didSend = false
    @State private var sentResetTask: Task<Void, Never>?

    private var canSend: Bool {
        hub.state.isOnline && ConsoleMessage.line(text: messageText) != nil
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.canvas
                VStack(spacing: 14) {
                    connectionRow

                    // Transport — flexible top region, absorbs vertical slack.
                    VStack(spacing: 14) {
                        TransportButton(title: "GO+", symbol: "arrow.right.circle.fill",
                                        tint: Theme.ok) { fire("Go+") }
                        TransportButton(title: "PAUSE", symbol: "pause.circle.fill",
                                        tint: Theme.warn) { fire("Pause") }
                        TransportButton(title: "GO-", symbol: "arrow.left.circle.fill",
                                        tint: Theme.textFaint) { fire("Go-") }
                    }
                    .frame(maxHeight: .infinity)
                    .disabled(!hub.state.isOnline)
                    .opacity(hub.state.isOnline ? 1 : 0.4)

                    // Assignable macro pad — fires on the desk-selected executor.
                    MacroPadView(onFire: { fireCount += 1 })

                    // Message-to-console field.
                    controlSection
                }
                .padding(20)
            }
            .navigationTitle("Live")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .sensoryFeedback(.impact(weight: .medium), trigger: fireCount)
        }
    }

    // MARK: Control area

    @ViewBuilder private var controlSection: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                TextField("Message to console\u{2026}", text: $messageText)
                    .textFieldStyle(.plain)
                    .submitLabel(.send)
                    .onSubmit { sendMessage() }
                    .padding(.vertical, 10).padding(.horizontal, 12)
                    .background(Theme.surface1, in: RoundedRectangle(cornerRadius: Theme.radius))

                Button("Send") { sendMessage() }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accentSolid)
                    .disabled(!canSend)
            }
            if didSend {
                Label("Sent", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12)).foregroundStyle(Theme.ok)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }
        }
    }

    private func sendMessage() {
        guard canSend else { return }
        hub.sendConsoleMessage(messageText)
        fireCount += 1                         // haptic, same trigger as transport
        messageText = ""
        withAnimation { didSend = true }
        sentResetTask?.cancel()                  // supersede any prior "Sent" timer
        sentResetTask = Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if Task.isCancelled { return }
            withAnimation { didSend = false }
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
struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.snappy(duration: 0.12), value: configuration.isPressed)
    }
}

import SwiftUI
import SaettaKit

/// The Live tab — run cues on the console-selected executor.
/// Bare command-line transport (GO+/GO-/PAUSE) over the hub's `cmd` passthrough.
/// Optimistic: each tap fires immediately with haptic + a press pulse; buttons
/// disable when the hub is offline.
struct LiveView: View {
    @Environment(HubClient.self) private var hub
    @State private var fireCount = 0
    @State private var showCompose = false
    @State private var didSend = false
    @State private var sentResetTask: Task<Void, Never>?

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
            .sheet(isPresented: $showCompose) {
                MessageComposeSheet(onSend: sendMessage)
            }
        }
    }

    // MARK: Control area

    // The keyboard would cover an inline field this low on the screen, so the
    // row is just a tap target that opens a compose sheet pinned above the keyboard.
    @ViewBuilder private var controlSection: some View {
        VStack(spacing: 8) {
            Button { showCompose = true } label: {
                HStack(spacing: 10) {
                    Text("Message to console\u{2026}")
                        .foregroundStyle(Theme.textFaint)
                    Spacer()
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textFaint)
                }
                .padding(.vertical, 10).padding(.horizontal, 12)
                .hudPanel()
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if didSend {
                Label("Sent", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12)).foregroundStyle(Theme.ok)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }
        }
    }

    private func sendMessage(_ text: String) {
        guard hub.state.isOnline, ConsoleMessage.line(text: text) != nil else { return }
        hub.sendConsoleMessage(text)
        fireCount += 1                         // haptic, same trigger as transport
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
                Text(hub.state.isOnline ? "CONNECTED" : "TAP TO CONNECT")
                    .font(Theme.mono(size: 11, weight: .medium)).hudLabel().foregroundStyle(Theme.textDim)
            }
            .padding(.vertical, 12).padding(.horizontal, 14)
            .hudPanel()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Compact compose popup for the message-to-console field. Lives in a short
/// sheet detent so the field stays visible above the keyboard. Starts empty on
/// every presentation and auto-focuses so the keyboard comes straight up.
private struct MessageComposeSheet: View {
    @Environment(HubClient.self) private var hub
    @Environment(\.dismiss) private var dismiss
    let onSend: (String) -> Void

    @State private var text = ""
    @FocusState private var focused: Bool

    private var canSend: Bool {
        hub.state.isOnline && ConsoleMessage.line(text: text) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Message to console")
                .font(Theme.mono(size: 11, weight: .medium)).hudLabel()
                .foregroundStyle(Theme.textDim)

            HStack(spacing: 10) {
                TextField("Type a message\u{2026}", text: $text)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .submitLabel(.send)
                    .onSubmit { send() }
                    .foregroundStyle(Theme.text)
                    .padding(.vertical, 10).padding(.horizontal, 12)
                    .hudPanel()

                Button("Send") { send() }
                    .buttonStyle(AmberCTAStyle())
                    .disabled(!canSend)
            }
        }
        .padding(.horizontal, 20).padding(.top, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .presentationDetents([.height(130)])
        .presentationDragIndicator(.visible)
        .presentationBackground {
            Color(red: 0.09, green: 0.07, blue: 0.04)  // canvas-family dark amber
        }
        .onAppear { focused = true }
    }

    private func send() {
        guard canSend else { return }
        onSend(text)
        dismiss()
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
                Text(title).font(Theme.mono(size: 24, weight: .heavy)).hudLabel()
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

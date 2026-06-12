import SwiftUI
import SaettaKit

/// The Live tab — run cues on the console-selected executor via the assignable
/// macro pad, with a one-tap output lock (hold to unlock) so a pocketed or
/// handed-over phone can't fire anything. Optimistic: each tap fires immediately
/// with haptic + a press pulse; cells disable when the hub is offline.
struct LiveView: View {
    @Environment(HubClient.self) private var hub
    @State private var fireCount = 0
    @State private var showCompose = false
    @State private var didSend = false
    @State private var sentResetTask: Task<Void, Never>?
    /// Live-tab output lock — session-scoped UI state (relaunch starts unlocked,
    /// same convention as the executor belief). Locks THIS tab's surface only;
    /// the HubClient send path is not gated.
    @State private var isLocked = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.canvas
                VStack(spacing: 14) {
                    connectionRow            // stays live while locked — reconnect is harmless

                    ZStack {
                        VStack(spacing: 14) {
                            lockBar

                            // Assignable macro pad — fires on the desk-selected executor.
                            MacroPadView(onFire: { fireCount += 1 }, isLocked: isLocked)
                                .frame(maxHeight: .infinity, alignment: .top)

                            // Message-to-console field.
                            controlSection
                        }
                        .opacity(isLocked ? 0.3 : 1)
                        .allowsHitTesting(!isLocked)

                        if isLocked {
                            LockOverlay {
                                withAnimation(.easeOut(duration: 0.2)) { isLocked = false }
                            }
                            .transition(.opacity)
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle("Live")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .sensoryFeedback(.impact(weight: .medium), trigger: fireCount)
            .sensoryFeedback(.impact(weight: .heavy), trigger: isLocked)
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

    /// Slim full-width arm bar. Locking is a single frictionless tap; unlocking
    /// requires the overlay's press-and-hold.
    private var lockBar: some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) { isLocked = true }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "lock.open.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textDim)
                Text("TAP TO LOCK")
                    .font(Theme.mono(size: 11, weight: .medium)).hudLabel()
                    .foregroundStyle(Theme.textDim)
                Spacer()
            }
            .padding(.vertical, 12).padding(.horizontal, 14)
            .hudPanel()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Lock controls")
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

/// The locked state: a big centered lock with a hold-to-unlock progress ring.
/// Tap-engage / hold-release asymmetry is the point — a stray pocket tap can
/// lock but never unlock. Releasing before the ring closes cancels the unlock.
private struct LockOverlay: View {
    let onUnlock: () -> Void
    @State private var holdProgress: CGFloat = 0

    private static let holdDuration: TimeInterval = 1.0

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(Theme.borderStrong, lineWidth: 5)
                Circle()
                    .trim(from: 0, to: holdProgress)
                    .stroke(Theme.accentSolid, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: "lock.fill")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(Theme.text)
            }
            .frame(width: 110, height: 110)

            Text("HOLD TO UNLOCK")
                .font(Theme.mono(size: 12, weight: .medium)).hudLabel()
                .foregroundStyle(Theme.textDim)
        }
        .padding(40)                            // generous press target around the ring
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: Self.holdDuration, maximumDistance: 40) {
            onUnlock()
        } onPressingChanged: { pressing in
            if pressing {
                withAnimation(.linear(duration: Self.holdDuration)) { holdProgress = 1 }
            } else {
                withAnimation(.easeOut(duration: 0.2)) { holdProgress = 0 }
            }
        }
        .accessibilityLabel("Locked. Hold to unlock")
        .accessibilityAction { onUnlock() }     // VoiceOver can't sustain a hold
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

// Sources/App/Fixture/FixtureControlView.swift
import SwiftUI
import SaettaKit

/// The Fixtures tab: select → pick parameter → nudge/recall → store/update.
/// Stateless remote control — every action fires a command line at the desk.
struct FixtureControlView: View {
    @Environment(HubClient.self) private var hub
    @Environment(ProjectStore.self) private var store

    enum Category: String, CaseIterable, Identifiable {
        case intensity = "Int", position = "Pos", color = "Color"
        case gobo = "Gobo", beam = "Beam", focus = "Focus"
        var id: String { rawValue }
    }

    @State private var selection = ""          // last sent selection command, for display
    @State private var category: Category = .position
    @State private var fine = false
    @State private var showKeypad = false
    @State private var showStoreCue = false
    @State private var showUpdatePreset = false
    @State private var fireCount = 0

    // A fader awaiting reset confirmation (set by double-tap). Identifiable so
    // it can drive a presenting alert; carries what's needed to undo the offset.
    private struct PendingReset: Identifiable {
        let key: String
        let attribute: String?     // nil = bare intensity
        let label: String
        let offset: Int
        var id: String { key }
    }
    @State private var pendingReset: PendingReset?

    // One accumulator per attribute key; reset on Clear / new selection.
    @State private var accumulators: [String: NudgeAccumulator] = [:]
    // Running per-key offset for fader display. Value-type @State so SwiftUI
    // updates the fader's valueText in place without changing its identity
    // (changing .id mid-drag would destroy the JogFader's gesture state).
    @State private var offsets: [String: Int] = [:]
    // Attribute keys that have gone into the programmer this selection. Drives the
    // red "touched" indicator on the category bar (mirrors grandMA3's red programmer
    // values). Sticky until Clear / new selection; a per-fader reset un-marks its key.
    @State private var touched: Set<String> = []

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.canvas
                VStack(spacing: 14) {
                    connectionRow
                    VStack(spacing: 14) {
                        selectionChip
                        categoryPicker
                        controlArea.frame(maxHeight: .infinity)
                        clearButton
                        storeBar
                    }
                    .disabled(!hub.state.isOnline)
                    .opacity(hub.state.isOnline ? 1 : 0.5)
                }
                .padding(20)
            }
            .navigationTitle("Fixtures").navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .sensoryFeedback(.impact(weight: .light), trigger: fireCount)
            .sheet(isPresented: $showKeypad) {
                SelectionKeypadSheet { cmd in selection = cmd; resetAccumulators(); send(cmd) }
            }
            .sheet(isPresented: $showStoreCue) {
                StoreCueSheet(sequence: store.activeSong.sequence, cue: 1, mode: store.project.storeMode,
                              selection: selection, values: programmerSnapshot) { send($0) }
            }
            .sheet(isPresented: $showUpdatePreset) {
                UpdatePresetSheet(mode: store.project.storeMode,
                                  selection: selection, values: programmerSnapshot) { send($0) }
            }
            .alert("Reset \(pendingReset?.label ?? "")?",
                   isPresented: Binding(get: { pendingReset != nil },
                                        set: { if !$0 { pendingReset = nil } }),
                   presenting: pendingReset) { pr in
                Button("Reset", role: .destructive) { resetFader(pr) }
                Button("Cancel", role: .cancel) {}
            } message: { pr in
                Text("Returns \(pr.label) to its session baseline on the desk (\(offsetSigned(pr.offset))).")
            }
        }
    }

    // MARK: control area per category

    @ViewBuilder private var controlArea: some View {
        if category == .gobo { goboGrid(items(.gobo)) }
        else { faderRow(items(category)) }
    }

    /// Single source of truth for each category's faders: (display label,
    /// attribute name or nil for bare-intensity). Used by the layouts AND by the
    /// category bar's "touched" check, so the two can't drift.
    private func items(_ c: Category) -> [(String, String?)] {
        switch c {
        case .intensity: return [("Dimmer", nil)]
        case .position:  return [("Pan", "Pan"), ("Tilt", "Tilt")]
        case .beam:      return [("Zoom", "Zoom"), ("Focus", "Focus"), ("Iris", "Iris")]
        case .focus:     return [("Focus", "Focus")]
        case .color:     return [("Cyan", "Cyan"), ("Magenta", "Magenta"), ("Yellow", "Yellow")]
        case .gobo:      return [("Gobo 1", "Gobo1"), ("Rot 1", "Gobo1Pos"),
                                 ("Gobo 2", "Gobo2"), ("Rot 2", "Gobo2Pos")]
        }
    }

    /// True if any of the category's attributes have gone into the programmer.
    private func isTouched(_ c: Category) -> Bool {
        items(c).contains { touched.contains($0.1 ?? "Dimmer") }
    }

    /// Every attribute that's gone into the programmer this session, with its
    /// running (relative) offset — feeds the "what will be stored" preview.
    /// Ordered by category then attribute; de-duplicated across categories.
    private var programmerSnapshot: [StoredValue] {
        var seen = Set<String>(); var out: [StoredValue] = []
        for c in Category.allCases {
            for item in items(c) {
                let key = item.1 ?? "Dimmer"
                if touched.contains(key), !seen.contains(key) {
                    seen.insert(key)
                    out.append(StoredValue(label: item.0, value: offsetSigned(offsets[key] ?? 0)))
                }
            }
        }
        return out
    }

    /// One full-height fader per item in a single row + the Coarse/Fine picker.
    private func faderRow(_ items: [(String, String?)]) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                ForEach(items, id: \.0) { fader($0) }
            }
            coarseFinePicker
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Four gobo faders in a 2×2 grid (shorter than the single-row faders so two
    /// rows fit) + the shared Coarse/Fine picker.
    private func goboGrid(_ items: [(String, String?)]) -> some View {
        VStack(spacing: 12) {
            ForEach(Array(stride(from: 0, to: items.count, by: 2)), id: \.self) { i in
                HStack(spacing: 12) {
                    ForEach(items[i..<min(i + 2, items.count)], id: \.0) { fader($0) }
                }
            }
            coarseFinePicker
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// One jog fader wired to the nudge/flush/reset handlers for `item`.
    @ViewBuilder private func fader(_ item: (String, String?)) -> some View {
        let key = item.1 ?? "Dimmer"
        JogFader(
            label: item.0,
            valueText: offsetText(key),
            fine: fine,
            onNudge: { nudge(key: key, attribute: item.1, delta: $0) },
            onEnd: { flush(key: key, attribute: item.1) },
            onReset: { requestReset(key: key, attribute: item.1, label: item.0) }
        )
    }

    private var coarseFinePicker: some View {
        Picker("", selection: $fine) {
            Text("Coarse").tag(false); Text("Fine").tag(true)
        }.pickerStyle(.segmented).frame(maxWidth: 200)
    }

    // MARK: intent → command

    private func nudge(key: String, attribute: String?, delta: Int) {
        let acc = accumulator(key)
        let emit = acc.accept(delta: delta, atMs: nowMs())
        offsets[key] = acc.offset                 // live display update, identity stable
        if !touched.contains(key) { touched.insert(key) }   // mark red on the category bar
        if let emit { sendNudge(attribute: attribute, delta: emit) }
    }
    private func flush(key: String, attribute: String?) {
        let acc = accumulator(key)
        if let emit = acc.flush(atMs: nowMs()) { sendNudge(attribute: attribute, delta: emit) }
        offsets[key] = acc.offset
    }
    private func sendNudge(attribute: String?, delta: Int) {
        let line = attribute == nil
            ? FixtureControlBuilder.intensityNudge(delta)
            : FixtureControlBuilder.attributeNudge(attribute!, delta)
        if let line { send(line, haptic: false) }
    }

    /// Double-tap on a fader: ask to confirm before undoing its nudges. No-op
    /// when there's nothing to undo (offset already zero).
    private func requestReset(key: String, attribute: String?, label: String) {
        let offset = offsets[key] ?? 0
        guard offset != 0 else { return }
        pendingReset = PendingReset(key: key, attribute: attribute, label: label, offset: offset)
    }
    /// Confirmed reset: send the inverse nudge so the desk returns to this
    /// session's baseline, then zero the local accumulator + display.
    private func resetFader(_ pr: PendingReset) {
        sendNudge(attribute: pr.attribute, delta: -pr.offset)
        accumulators[pr.key] = nil
        offsets[pr.key] = 0
        touched.remove(pr.key)   // back to baseline → no longer red
        fireCount += 1   // confirm haptic (sendNudge fires silently)
    }

    private func accumulator(_ key: String) -> NudgeAccumulator {
        if let a = accumulators[key] { return a }
        let a = NudgeAccumulator(); accumulators[key] = a; return a
    }
    private func offsetText(_ key: String) -> String { offsetSigned(offsets[key] ?? 0) }
    private func offsetSigned(_ o: Int) -> String { o > 0 ? "+\(o)" : "\(o)" }
    private func resetAccumulators() { accumulators.removeAll(); offsets.removeAll(); touched.removeAll() }
    private func nowMs() -> Int { Int(ProcessInfo.processInfo.systemUptime * 1000) }

    private func send(_ line: String, haptic: Bool = true) {
        hub.sendCommand(line)
        if haptic { fireCount += 1 }
    }

    // MARK: chrome

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
        }.buttonStyle(.plain)
    }

    private var selectionChip: some View {
        Button { showKeypad = true } label: {
            HStack {
                Text(selection.isEmpty ? "No selection" : selection)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(selection.isEmpty ? Theme.textFaint : Theme.accentSolid)
                Spacer()
                Image(systemName: "keyboard").foregroundStyle(Theme.textDim)
            }
            .padding(.vertical, 12).padding(.horizontal, 14)
            .background(Theme.surface2, in: RoundedRectangle(cornerRadius: Theme.radius))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.border, lineWidth: 0.5))
        }.buttonStyle(.plain)
    }

    /// Custom segmented bar so each segment can colour independently: a category
    /// with values in the programmer turns RED (grandMA3's programmer convention);
    /// the selected one gets the amber pill. Standard SwiftUI segmented pickers
    /// can't tint individual segments, hence the hand-rolled control.
    private var categoryPicker: some View {
        HStack(spacing: 3) {
            ForEach(Category.allCases) { cat in
                let selected = cat == category
                Button { category = cat } label: {
                    Text(cat.rawValue)
                        .font(.system(size: 12.5, weight: selected ? .semibold : .medium))
                        .foregroundStyle(isTouched(cat) ? Theme.danger
                                         : (selected ? Theme.text : Theme.textDim))
                        .lineLimit(1).minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity).padding(.vertical, 7)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 7).fill(Theme.accentTint)
                                    .overlay(RoundedRectangle(cornerRadius: 7)
                                        .strokeBorder(Theme.accentBorder, lineWidth: 1))
                            }
                        }
                        .contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 9))
    }

    private var clearButton: some View {
        Button { send(FixtureControlBuilder.clear); resetAccumulators() } label: {
            Text("Clear").font(.system(size: 15, weight: .semibold))
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(Theme.surface3, in: RoundedRectangle(cornerRadius: Theme.radius))
                .foregroundStyle(Theme.textDim)
        }.buttonStyle(.plain)
    }

    private var storeBar: some View {
        HStack(spacing: 10) {
            Button { showStoreCue = true } label: {
                Text("Store to Cue").font(.system(size: 15, weight: .bold))
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(Theme.accentSolid, in: RoundedRectangle(cornerRadius: Theme.radiusLarge))
                    .foregroundStyle(.white)
            }.buttonStyle(.plain)
            Button { showUpdatePreset = true } label: {
                Text("Update Preset").font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(Theme.surface2, in: RoundedRectangle(cornerRadius: Theme.radiusLarge))
                    .overlay(RoundedRectangle(cornerRadius: Theme.radiusLarge).strokeBorder(Theme.border, lineWidth: 0.5))
                    .foregroundStyle(Theme.accentSolid)
            }.buttonStyle(.plain)
        }
    }
}

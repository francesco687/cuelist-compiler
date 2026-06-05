# iOS UI follow-ups (round 2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Declutter the Cuelist Compiler iPhone app by moving Send→MA to its own bottom tab (reflowed full-page), and add note edit/clear, collapse/expand-all cues, and a typed sequence field.

**Architecture:** Three new Kit mutations + one controller method (all TDD'd at the Kit unit level), then six SwiftUI front-end changes that re-front the existing `ProjectStore` / `HubClient` / `NotesCaptureController` (all already `@Environment`, no plumbing change). `RootView` gains a `TabView`; `SendBarView` is replaced by a reflowed `SendView`.

**Tech Stack:** Swift 5.9, SwiftUI, `@Observable`, xcodegen project (`ios/project.yml`), XCTest. iOS 17 target.

**Conventions (do not break):**
- Two-accent rule: `Theme.aqua`/`aquaGradient`/`aquaTint` = capture/voice/notes; `Theme.accentGradient`/`accentSolid` = Send→MA.
- `Cue.notes` is one `\n`-joined `String`. `setNote` overwrites the whole blob.
- Kit mutations live in `ios/Sources/Kit/Store/ProjectStore+Mutations.swift`; `private func activeSongIndex()` there is file-scope-accessible to new functions in the same file.
- Tests are `@MainActor` XCTest classes; `ProjectStore(directory:)` with a temp dir is the standard fixture.

**Build / test commands** (run from `ios/`):
```bash
cd /Users/jordanbabev/cuelist-compiler/ios
xcodegen generate            # regen the .xcodeproj after adding/removing source files
# Pick an installed simulator name if "iPhone 16 Pro" is absent:
#   xcrun simctl list devices available | grep iPhone
xcodebuild test  -project CuelistCompiler.xcodeproj -scheme CuelistCompilerKit \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' 2>&1 | tail -25
xcodebuild build -project CuelistCompiler.xcodeproj -scheme CuelistCompiler \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' 2>&1 | tail -25
```

**First action:** create a feature branch off `main`.
```bash
cd /Users/jordanbabev/cuelist-compiler && git checkout main && git pull --ff-only && \
  git checkout -b feat/ios-ui-followups-2
```

---

## File Structure

| File | Responsibility | Change |
|------|----------------|--------|
| `ios/Sources/Kit/Store/ProjectStore+Mutations.swift` | store mutations | add `setNote`, `collapseAllCues`, `expandAllCues` |
| `ios/Sources/Kit/Voice/NotesCaptureController.swift` | note capture/routing state | add `removeRoute(at:)` |
| `ios/Tests/KitTests/ProjectStoreNotesTests.swift` | note-mutation tests | add `setNote` tests |
| `ios/Tests/KitTests/ProjectStoreMutationTests.swift` | mutation tests | add collapse/expand tests |
| `ios/Tests/KitTests/NotesCaptureControllerTests.swift` | controller tests | add `removeRoute` test |
| `ios/Sources/App/EditNoteView.swift` | **new** — edit/clear a saved cue note | create |
| `ios/Sources/App/CueCardView.swift` | cue card | note line → tappable, present `EditNoteView` |
| `ios/Sources/App/NotesCaptureView.swift` | note capture sheet | ✕ to drop a routing-preview row |
| `ios/Sources/App/SeqField.swift` | **new** — typed sequence field | create |
| `ios/Sources/App/SendView.swift` | **new** — reflowed full-page Send tab | create |
| `ios/Sources/App/SendBarView.swift` | old bottom send bar | **delete** |
| `ios/Sources/App/RootView.swift` | root shell | TabView; rebuilt subbar; Notes button → Author toolbar; drop `SendBarView` |

---

## Task 1: Kit mutation — `setNote`

**Files:**
- Modify: `ios/Sources/Kit/Store/ProjectStore+Mutations.swift`
- Test: `ios/Tests/KitTests/ProjectStoreNotesTests.swift`

- [ ] **Step 1: Write the failing tests**

Add to `ProjectStoreNotesTests.swift` (inside the class, after the existing tests):

```swift
    func testSetNoteOverwritesExisting() {
        let s = store()
        s.appendNote(cueN: 1, text: "old")
        s.setNote(cueN: 1, text: "new note")
        XCTAssertEqual(s.project.songs[0].cues[0].notes, "new note")
    }
    func testSetNoteClearsOnWhitespace() {
        let s = store()
        s.appendNote(cueN: 1, text: "remove me")
        s.setNote(cueN: 1, text: "   ")
        XCTAssertEqual(s.project.songs[0].cues[0].notes, "")
    }
    func testSetNoteIgnoresUnknownCue() {
        let s = store()
        s.appendNote(cueN: 1, text: "stay")
        s.setNote(cueN: 99, text: "lost")
        XCTAssertEqual(s.project.songs[0].cues[0].notes, "stay")
    }
    func testSetNoteTrims() {
        let s = store()
        s.setNote(cueN: 2, text: "  trimmed  ")
        XCTAssertEqual(s.project.songs[0].cues[1].notes, "trimmed")
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project CuelistCompiler.xcodeproj -scheme CuelistCompilerKit -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:CuelistCompilerKitTests/ProjectStoreNotesTests 2>&1 | tail -25`
Expected: compile FAIL — `value of type 'ProjectStore' has no member 'setNote'`.

- [ ] **Step 3: Write the implementation**

In `ProjectStore+Mutations.swift`, add after `appendNote(...)` (around line 101):

```swift
    /// Overwrite (or clear) the note of the active song's cue number `n`.
    /// Empty/whitespace text clears the note. Unknown cue numbers are ignored.
    func setNote(cueN n: Double, text: String) {
        let i = activeSongIndex()
        guard let c = project.songs[i].cues.firstIndex(where: { $0.n == n }) else { return }
        project.songs[i].cues[c].notes = text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run the same `-only-testing:...ProjectStoreNotesTests` command.
Expected: PASS (all 7 tests in the class).

- [ ] **Step 5: Commit**

```bash
git add ios/Sources/Kit/Store/ProjectStore+Mutations.swift ios/Tests/KitTests/ProjectStoreNotesTests.swift
git commit -m "feat(kit): setNote overwrites/clears a cue note"
```

---

## Task 2: Kit mutations — `collapseAllCues` / `expandAllCues`

**Files:**
- Modify: `ios/Sources/Kit/Store/ProjectStore+Mutations.swift`
- Test: `ios/Tests/KitTests/ProjectStoreMutationTests.swift`

- [ ] **Step 1: Write the failing tests**

Add to `ProjectStoreMutationTests.swift` (inside the class):

```swift
    func testCollapseAndExpandAllCues() {
        let s = store()
        s.addCue(); s.addCue()
        s.collapseAllCues()
        XCTAssertTrue(s.activeSong.cues.allSatisfy { $0.collapsed })
        s.expandAllCues()
        XCTAssertTrue(s.activeSong.cues.allSatisfy { !$0.collapsed })
    }
    func testCollapseAllOnEmptySongIsNoOp() {
        let s = store()
        s.collapseAllCues()                       // no cues — must not crash
        XCTAssertEqual(s.activeSong.cues.count, 0)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project CuelistCompiler.xcodeproj -scheme CuelistCompilerKit -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:CuelistCompilerKitTests/ProjectStoreMutationTests 2>&1 | tail -25`
Expected: compile FAIL — no member `collapseAllCues`.

- [ ] **Step 3: Write the implementation**

In `ProjectStore+Mutations.swift`, add after `setNote(...)`:

```swift
    /// Collapse every cue of the active song.
    func collapseAllCues() {
        let i = activeSongIndex()
        for c in project.songs[i].cues.indices { project.songs[i].cues[c].collapsed = true }
    }

    /// Expand every cue of the active song.
    func expandAllCues() {
        let i = activeSongIndex()
        for c in project.songs[i].cues.indices { project.songs[i].cues[c].collapsed = false }
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run the same `-only-testing:...ProjectStoreMutationTests` command.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ios/Sources/Kit/Store/ProjectStore+Mutations.swift ios/Tests/KitTests/ProjectStoreMutationTests.swift
git commit -m "feat(kit): collapseAllCues / expandAllCues on the active song"
```

---

## Task 3: Controller method — `removeRoute(at:)`

**Files:**
- Modify: `ios/Sources/Kit/Voice/NotesCaptureController.swift`
- Test: `ios/Tests/KitTests/NotesCaptureControllerTests.swift`

`routed` is `public private(set)` so the view cannot mutate it — it drops a pending preview row through this method.

- [ ] **Step 1: Write the failing test**

Add to `NotesCaptureControllerTests.swift` (inside the class):

```swift
    func testRemoveRouteDropsOneEditByIndex() async {
        let c = NotesCaptureController(recorder: NoopRecorder(), transcriber: NoopTranscriber(text: ""),
                                       router: StubRouter(result: [NoteEdit(cue: 1, text: "dim"),
                                                                    NoteEdit(cue: 2, text: "hard")]))
        await c.routeText("two notes", project: project(), targetCue: nil)
        XCTAssertEqual(c.routed.count, 2)
        c.removeRoute(at: 0)
        XCTAssertEqual(c.routed, [NoteEdit(cue: 2, text: "hard")])
        c.removeRoute(at: 5)                       // out of range — no-op
        XCTAssertEqual(c.routed.count, 1)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project CuelistCompiler.xcodeproj -scheme CuelistCompilerKit -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:CuelistCompilerKitTests/NotesCaptureControllerTests 2>&1 | tail -25`
Expected: compile FAIL — no member `removeRoute`.

- [ ] **Step 3: Write the implementation**

In `NotesCaptureController.swift`, add just before `public func reset()`:

```swift
    /// Drop one pending routed note (preview stage) by index. Out-of-range is ignored.
    public func removeRoute(at index: Int) {
        guard routed.indices.contains(index) else { return }
        routed.remove(at: index)
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run the same `-only-testing:...NotesCaptureControllerTests` command.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ios/Sources/Kit/Voice/NotesCaptureController.swift ios/Tests/KitTests/NotesCaptureControllerTests.swift
git commit -m "feat(kit): removeRoute(at:) drops a pending routed note"
```

---

## Task 4: `EditNoteView` + tappable note line on the cue card

**Files:**
- Create: `ios/Sources/App/EditNoteView.swift`
- Modify: `ios/Sources/App/CueCardView.swift`

This is UI — verified by building the app target, not a unit test.

- [ ] **Step 1: Create `EditNoteView.swift`**

```swift
import SwiftUI
import CuelistCompilerKit

/// Edit or clear a single cue's saved note (the `\n`-joined `cue.notes` blob).
/// Distinct from NotesCaptureView, which *captures/routes* new notes.
struct EditNoteView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let cueN: Double
    @State private var text: String

    init(cueN: Double, initialText: String) {
        self.cueN = cueN
        _text = State(initialValue: initialText)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.canvas
                VStack(alignment: .leading, spacing: 14) {
                    TextField("Note", text: $text, axis: .vertical)
                        .lineLimit(3...10)
                        .padding(12)
                        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: Theme.radius))
                        .foregroundStyle(Theme.text)

                    HStack(spacing: 12) {
                        Button(role: .destructive) {
                            store.setNote(cueN: cueN, text: "")
                            dismiss()
                        } label: {
                            Label("Clear", systemImage: "trash")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Theme.danger)
                                .padding(.vertical, 10).padding(.horizontal, 16)
                                .overlay(RoundedRectangle(cornerRadius: Theme.radius)
                                    .strokeBorder(Theme.danger.opacity(0.35), lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        Button {
                            store.setNote(cueN: cueN, text: text)
                            dismiss()
                        } label: {
                            Text("Save")
                                .font(.system(size: 14, weight: .semibold))
                                .padding(.vertical, 10).padding(.horizontal, 20)
                                .background(Theme.aqua, in: RoundedRectangle(cornerRadius: Theme.radius))
                                .foregroundStyle(Theme.aquaInk)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
                .padding(16)
            }
            .navigationTitle("Edit note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
```

- [ ] **Step 2: Make the note line tappable in `CueCardView.swift`**

Add a state var next to the existing ones (after line 9, `@State private var addingNote = false`):

```swift
    @State private var editingNote = false
```

Replace the note-line block (currently lines 51–61, the `if !cue.notes.isEmpty { HStack(...) ... }`) with a `Button` wrapper:

```swift
            if !cue.notes.isEmpty {
                Button { editingNote = true } label: {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "square.and.pencil").font(.system(size: 10)).foregroundStyle(Theme.aqua)
                        Text(cue.notes).font(.system(size: 11)).foregroundStyle(Theme.text.opacity(0.85))
                            .lineLimit(cue.collapsed ? 2 : nil)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 5).padding(.horizontal, 8)
                    .background(Theme.aquaTint, in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
                    .overlay(Rectangle().frame(width: 2).foregroundStyle(Theme.aqua.opacity(0.5)), alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
```

Add the sheet next to the existing `.sheet(isPresented: $addingNote)` (after line 120):

```swift
        .sheet(isPresented: $editingNote) { EditNoteView(cueN: cue.n, initialText: cue.notes) }
```

- [ ] **Step 3: Regenerate the project (new file) and build**

```bash
cd /Users/jordanbabev/cuelist-compiler/ios && xcodegen generate
xcodebuild build -project CuelistCompiler.xcodeproj -scheme CuelistCompiler -destination 'platform=iOS Simulator,name=iPhone 16 Pro' 2>&1 | tail -25
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add ios/Sources/App/EditNoteView.swift ios/Sources/App/CueCardView.swift ios/project.yml ios/CuelistCompiler.xcodeproj
git commit -m "feat(ios): tap a cue note to edit or clear it"
```

---

## Task 5: ✕ to drop a routing-preview row in `NotesCaptureView`

**Files:**
- Modify: `ios/Sources/App/NotesCaptureView.swift`

- [ ] **Step 1: Add a remove button to each preview row**

In `NotesCaptureView.swift`, replace the `ForEach` inside `routingPreview` (currently lines 97–104) with:

```swift
            ForEach(Array(notes.routed.enumerated()), id: \.offset) { idx, e in
                HStack(spacing: 8) {
                    Text("Cue \(formatN(e.cue))").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.aqua)
                    Text(e.text).font(.system(size: 12)).foregroundStyle(Theme.text)
                    Spacer(minLength: 4)
                    Button { notes.removeRoute(at: idx) } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14)).foregroundStyle(Theme.textFaint)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 6).padding(.horizontal, 10)
                .background(Theme.aquaTint, in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
            }
```

Note: when the last row is removed `notes.routed` becomes empty; the `if ... !notes.routed.isEmpty` guard at line 57 already hides the whole preview, and the "Add N notes" count is reactive.

- [ ] **Step 2: Build the app**

```bash
cd /Users/jordanbabev/cuelist-compiler/ios
xcodebuild build -project CuelistCompiler.xcodeproj -scheme CuelistCompiler -destination 'platform=iOS Simulator,name=iPhone 16 Pro' 2>&1 | tail -25
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add ios/Sources/App/NotesCaptureView.swift
git commit -m "feat(ios): drop a routing-preview row before applying notes"
```

---

## Task 6: `SeqField` + rebuilt subbar (typed seq + collapse/expand-all)

**Files:**
- Create: `ios/Sources/App/SeqField.swift`
- Modify: `ios/Sources/App/RootView.swift`

- [ ] **Step 1: Create `SeqField.swift`**

```swift
import SwiftUI
import CuelistCompilerKit

/// Tappable numeric sequence field. Replaces the seq Stepper — type a value,
/// committed on focus-loss/return, clamped to 1...9999.
struct SeqField: View {
    @Binding var sequence: Int
    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 5) {
            Text("Seq").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.textDim)
            TextField("1", text: $text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(Theme.text)
                .frame(width: 54)
                .padding(.vertical, 5)
                .background(Theme.surface2, in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
                .focused($focused)
        }
        .onAppear { text = String(sequence) }
        .onChange(of: sequence) { _, new in if !focused { text = String(new) } }
        .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = false }
            }
        }
    }

    private func commit() {
        let parsed = Int(text.filter(\.isNumber)) ?? sequence
        let clamped = min(9999, max(1, parsed))
        sequence = clamped
        text = String(clamped)
    }
}
```

- [ ] **Step 2: Rebuild the `subbar` in `RootView.swift`**

Replace the entire `subbar` computed property (currently lines 102–118) with:

```swift
    @ViewBuilder private var subbar: some View {
        @Bindable var store = store
        if let i = activeIndex {
            HStack(spacing: 12) {
                SeqField(sequence: $store.project.songs[i].sequence)
                if !store.project.songs[i].cues.isEmpty {
                    Button { withAnimation(.snappy(duration: 0.2)) { store.collapseAllCues() } } label: {
                        Image(systemName: "rectangle.compress.vertical")
                            .font(.system(size: 14)).foregroundStyle(Theme.accentSolid)
                    }
                    .buttonStyle(.plain)
                    Button { withAnimation(.snappy(duration: 0.2)) { store.expandAllCues() } } label: {
                        Image(systemName: "rectangle.expand.vertical")
                            .font(.system(size: 14)).foregroundStyle(Theme.accentSolid)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Text("\(store.project.songs[i].cues.count) cue\(store.project.songs[i].cues.count == 1 ? "" : "s")")
                    .font(.system(size: 11)).foregroundStyle(Theme.textFaint)
            }
            .padding(.horizontal, 16).padding(.bottom, 8)
        }
    }
```

(`store.project.songs[i].sequence` is `Int` — see `Song`. `SeqField` takes `Binding<Int>`.)

- [ ] **Step 3: Regenerate (new file) and build**

```bash
cd /Users/jordanbabev/cuelist-compiler/ios && xcodegen generate
xcodebuild build -project CuelistCompiler.xcodeproj -scheme CuelistCompiler -destination 'platform=iOS Simulator,name=iPhone 16 Pro' 2>&1 | tail -25
```
Expected: `** BUILD SUCCEEDED **`. (If `Song.sequence` is not `Int`, adjust `SeqField`'s binding type to match — verify with `grep -n "var sequence" ios/Sources/Kit/Models/Song.swift`.)

- [ ] **Step 4: Commit**

```bash
git add ios/Sources/App/SeqField.swift ios/Sources/App/RootView.swift ios/project.yml ios/CuelistCompiler.xcodeproj
git commit -m "feat(ios): typed seq field + collapse/expand-all in the subbar"
```

---

## Task 7: Bottom TabView + reflowed `SendView`; remove `SendBarView`; relocate Notes button

**Files:**
- Create: `ios/Sources/App/SendView.swift`
- Delete: `ios/Sources/App/SendBarView.swift`
- Modify: `ios/Sources/App/RootView.swift`

- [ ] **Step 1: Create `SendView.swift` (reflowed full page)**

```swift
import SwiftUI
import CuelistCompilerKit

/// The Send tab — a full-page OSC send flow (replaces the old bottom SendBarView).
/// Violet accent family (Send→MA), distinct from the aqua capture family.
struct SendView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(HubClient.self) private var hub

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            ZStack {
                Theme.canvas
                VStack(spacing: 22) {
                    // Connection
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

                    // Store mode
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Store mode").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.textDim)
                        Picker("Store", selection: $store.project.storeMode) {
                            ForEach(StoreMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }

                    // Primary actions
                    VStack(spacing: 12) {
                        Button {
                            hub.send(project: store.project, defaults: store.defaults, selection: .current)
                        } label: {
                            Label("Send \u{2192} MA", systemImage: "paperplane.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 15)
                                .background(Theme.accentGradient, in: RoundedRectangle(cornerRadius: Theme.radius))
                                .foregroundStyle(.white)
                                .shadow(color: Theme.accentSolid.opacity(0.4), radius: 14, y: 3)
                        }
                        Button {
                            hub.send(project: store.project, defaults: store.defaults, selection: .all)
                        } label: {
                            Text("Send All Songs")
                                .font(.system(size: 14, weight: .medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(Theme.surface2, in: RoundedRectangle(cornerRadius: Theme.radius))
                                .foregroundStyle(Theme.text)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(!hub.state.isOnline)
                    .opacity(hub.state.isOnline ? 1 : 0.5)

                    resultRow
                    Spacer()
                }
                .padding(20)
            }
            .navigationTitle("Send to MA")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
        }
    }

    @ViewBuilder private var resultRow: some View {
        if let p = hub.progress {
            VStack(spacing: 6) {
                ProgressView(value: Double(p.sent), total: Double(max(1, p.total))).tint(Theme.accentSolid)
                Text("sending \(p.sent)/\(p.total)\u{2026}").font(.system(size: 12)).foregroundStyle(Theme.textDim)
            }
        } else if let result = hub.lastResult {
            switch result {
            case let .done(total):
                Label("Sent \(total) lines", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 13)).foregroundStyle(Theme.ok)
            case let .failed(msg):
                Label(msg, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 13)).foregroundStyle(Theme.danger)
            }
        }
    }
}
```

- [ ] **Step 2: Restructure `RootView.swift` into a TabView**

Replace the whole `body` (currently lines 18–67) with:

```swift
    var body: some View {
        TabView {
            authorTab
                .tabItem { Label("Author", systemImage: "square.and.pencil") }
            SendView()
                .tabItem { Label("Send", systemImage: "paperplane") }
        }
        .tint(Theme.accentSolid)
    }

    private var authorTab: some View {
        @Bindable var store = store
        return NavigationStack {
            ZStack {
                Theme.canvas
                VStack(spacing: 0) {
                    subbar
                    CueListView()
                    TalkBarView()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { songMenu }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showNotes = true } label: {
                        Image(systemName: "square.and.pencil").foregroundStyle(Theme.aqua)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showPull = true } label: { Label("Pull from MA\u{2026}", systemImage: "arrow.down.circle") }
                        Divider()
                        Button("Defaults\u{2026}") { showDefaults = true }
                        Button("Settings\u{2026}") { showSettings = true }
                    } label: { Image(systemName: "slider.horizontal.3") }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showDefaults) { DefaultsView() }
            .sheet(isPresented: $showPull) { PullSequencesView() }
            .sheet(isPresented: $showNotes) { NotesCaptureView(targetCue: nil) }
            .sheet(isPresented: previewBinding) {
                if let pending = voice.pending {
                    VoicePreviewSheet(
                        pending: pending,
                        onApply: { store.apply(pending.result); voice.cancel() },
                        onDiscard: { voice.cancel() }
                    )
                }
            }
            .alert("Voice", isPresented: errorBinding) {
                Button("OK") { voice.cancel() }
            } message: { Text(errorText) }
            .alert("Rename song", isPresented: $showRename) {
                TextField("Name", text: $renameText)
                Button("Save") {
                    if let i = activeIndex { store.project.songs[i].name = renameText }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
```

(The `songMenu`, `subbar`, `previewBinding`, `errorBinding`, `errorText` properties and the `@State`/`@Environment` declarations stay unchanged.)

- [ ] **Step 3: Delete `SendBarView.swift`**

```bash
git rm ios/Sources/App/SendBarView.swift
```

- [ ] **Step 4: Regenerate and build**

```bash
cd /Users/jordanbabev/cuelist-compiler/ios && xcodegen generate
xcodebuild build -project CuelistCompiler.xcodeproj -scheme CuelistCompiler -destination 'platform=iOS Simulator,name=iPhone 16 Pro' 2>&1 | tail -25
```
Expected: `** BUILD SUCCEEDED **` with no remaining references to `SendBarView` (the only references were in `RootView`, now removed).

- [ ] **Step 5: Commit**

```bash
git add ios/Sources/App/SendView.swift ios/Sources/App/RootView.swift ios/project.yml ios/CuelistCompiler.xcodeproj
git commit -m "feat(ios): move Send to its own tab (reflowed full page); Notes button to Author toolbar"
```

---

## Task 8: Full Kit test suite + on-device smoke

**Files:** none (verification only)

- [ ] **Step 1: Run the full Kit test suite**

```bash
cd /Users/jordanbabev/cuelist-compiler/ios
xcodebuild test -project CuelistCompiler.xcodeproj -scheme CuelistCompilerKit -destination 'platform=iOS Simulator,name=iPhone 16 Pro' 2>&1 | tail -15
```
Expected: `** TEST SUCCEEDED **`, all existing + 3 new test methods green.

- [ ] **Step 2: Build for the device and install on jPhone (2)**

```bash
cd /Users/jordanbabev/cuelist-compiler/ios
xcodebuild -project CuelistCompiler.xcodeproj -scheme CuelistCompiler \
  -destination 'platform=iOS,id=7DF307B3-6B1F-5CB1-8793-5DB9437E7FF8' \
  -derivedDataPath build clean build 2>&1 | tail -20
xcrun devicectl device install app \
  --device 7DF307B3-6B1F-5CB1-8793-5DB9437E7FF8 \
  build/Build/Products/Debug-iphoneos/CuelistCompiler.app
```
Expected: build succeeds and `Installed application … com.blearred.cuelistcompiler`. (If the device must be unlocked / trusted, prompt Jordan.)

- [ ] **Step 3: On-device smoke checklist (Jordan drives the phone)**

Confirm with Jordan:
- Author ↔ Send tab switch works; Send page shows live pill + store-mode + big violet Send/All; result/progress shows on send (or correct offline state).
- Edit a cue note (tap aqua line → change text → Save); clear a note (tap → Clear).
- Global Notes (toolbar ✎) → route a brain-dump → drop a preview row with ✕ → Add the rest.
- Subbar: tap Seq → type a number (e.g. 500) → it commits/clamps; collapse-all then expand-all flips every cue.

- [ ] **Step 4: Verify branch ref before any push**

```bash
cd /Users/jordanbabev/cuelist-compiler
git rev-parse feat/ios-ui-followups-2 && git rev-parse HEAD   # must match
git log --oneline main..feat/ios-ui-followups-2
```
Then **confirm push/merge approach with Jordan** (collaborator repo francesco687/cuelist-compiler — last round was merged locally to `main`). Do not push unprompted.

---

## Self-Review

- **Spec coverage:** (1) Send→tab + reflow → Task 7 ✓. (2) note edit/clear → Task 1 (`setNote`) + Task 4 (`EditNoteView`) ✓; routing-preview row removal → Task 3 (`removeRoute`) + Task 5 ✓. (3) collapse/expand-all → Task 2 + Task 6 ✓. (4) typed seq → Task 6 (`SeqField`) ✓. Notes-button relocation → Task 7 ✓. Tests → Tasks 1–3 + Task 8 ✓.
- **Placeholder scan:** none — every code step shows full code; every command shows expected output.
- **Type consistency:** `setNote(cueN:text:)`, `collapseAllCues()`, `expandAllCues()`, `removeRoute(at:)`, `EditNoteView(cueN:initialText:)`, `SeqField(sequence:)` are referenced consistently across tasks. `Selection.current`/`.all`, `StoreMode.allCases`, `LiveIndicator(state:)`, `hub.progress`/`hub.lastResult`/`hub.state.isOnline` all match the deleted `SendBarView`'s usage.
- **Assumption to verify at runtime:** `Song.sequence` is `Int` (Task 6 Step 3 notes the check). The reflowed `SendView` reuses byte-for-byte the same `hub.*` calls the old bar made, so behavior parity is preserved.

# iOS UI Followups Round 3 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restructure the Author tab — pinned bottom action cluster (Add Cue · Note · Talk), an Edit mode for multi-delete + drag-reorder, cue renumbering, a dedicated Settings tab, and a bigger mic in the Notes sheet.

**Architecture:** Four new `ProjectStore` mutations (TDD'd in the Kit suite) back the UI. The cue list converts from a hand-styled `ScrollView`/`LazyVStack` to a restyled SwiftUI `List` so `List(selection:)` + `.onMove` give multi-select and reorder natively. The voice button is extracted from `TalkBarView` into a reusable component used both in the new bottom trio and (full-width) in the Notes sheet. The old top slider-menu collapses into a third `Settings` tab.

**Tech Stack:** Swift 5.9, SwiftUI, `@Observable` `ProjectStore`, xcodegen project, XCTest (Kit), iPhone 17 Pro sim.

---

## File Structure

| File | Responsibility |
|---|---|
| `ios/Sources/Kit/Store/ProjectStore+Mutations.swift` | + `moveCues(from:to:)`, `removeCues(ids:)`, `renumberFromOne()`, `setCueNumber(id:to:)` |
| `ios/Tests/KitTests/ProjectStoreMutationTests.swift` | tests for the four new methods |
| `ios/Sources/App/Components/VoiceButton.swift` *(new)* | reusable voice record/stop button body (extracted from TalkBarView) |
| `ios/Sources/App/TalkBarView.swift` | thin wrapper around `VoiceButton` (compact, for the trio) |
| `ios/Sources/App/BottomCluster.swift` *(new)* | pinned trio: Add Cue · Note · Talk; swaps to Delete bar in edit mode |
| `ios/Sources/App/CueListView.swift` | `ScrollView`→styled `List`; `selection` + `.onMove`; drop in-scroll Add Cue |
| `ios/Sources/App/CueCardView.swift` | tappable `CueBadge`→renumber-one alert |
| `ios/Sources/App/SettingsTabView.swift` *(new)* | third tab: rows for Pull / Defaults / Settings |
| `ios/Sources/App/RootView.swift` | third tab; strip Author top bar to song-menu + Edit; host BottomCluster; subbar `list.number`; own `editMode` + `selection` state |

---

## Task 1: Kit — `moveCues(from:to:)`

**Files:**
- Modify: `ios/Sources/Kit/Store/ProjectStore+Mutations.swift`
- Test: `ios/Tests/KitTests/ProjectStoreMutationTests.swift`

- [ ] **Step 1: Write the failing test**

Add to `ProjectStoreMutationTests`:

```swift
func testMoveCuesReordersActiveSong() {
    let s = store()
    s.addCue(); s.addCue(); s.addCue()          // n = 1,2,3 in array order
    XCTAssertEqual(s.activeSong.cues.map(\.n), [1, 2, 3])
    s.moveCues(from: IndexSet(integer: 0), to: 3)  // move first to end
    XCTAssertEqual(s.activeSong.cues.map(\.n), [2, 3, 1])
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ios && xcodebuild test -scheme CuelistCompilerKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:KitTests/ProjectStoreMutationTests/testMoveCuesReordersActiveSong 2>&1 | tail -20`
Expected: FAIL — `value of type 'ProjectStore' has no member 'moveCues'`.

- [ ] **Step 3: Write minimal implementation**

Add to `ProjectStore+Mutations.swift` (in the `// MARK: Cues` area):

```swift
/// Reorder the active song's cues (for List `.onMove`).
func moveCues(from source: IndexSet, to destination: Int) {
    let i = activeSongIndex()
    project.songs[i].cues.move(fromOffsets: source, toOffset: destination)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run the same command as Step 2.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ios/Sources/Kit/Store/ProjectStore+Mutations.swift ios/Tests/KitTests/ProjectStoreMutationTests.swift
git commit -m "feat(kit): moveCues reorders the active song's cues"
```

---

## Task 2: Kit — `removeCues(ids:)`

**Files:**
- Modify: `ios/Sources/Kit/Store/ProjectStore+Mutations.swift`
- Test: `ios/Tests/KitTests/ProjectStoreMutationTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
func testRemoveCuesBulkDeletesByID() {
    let s = store()
    s.addCue(); s.addCue(); s.addCue()
    let ids = Set([s.activeSong.cues[0].id, s.activeSong.cues[2].id])
    s.removeCues(ids: ids)
    XCTAssertEqual(s.activeSong.cues.map(\.n), [2])     // middle one survives
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ios && xcodebuild test -scheme CuelistCompilerKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:KitTests/ProjectStoreMutationTests/testRemoveCuesBulkDeletesByID 2>&1 | tail -20`
Expected: FAIL — no member `removeCues`.

- [ ] **Step 3: Write minimal implementation**

```swift
/// Bulk-remove cues of the active song whose id is in `ids`.
func removeCues(ids: Set<UUID>) {
    let i = activeSongIndex()
    project.songs[i].cues.removeAll { ids.contains($0.id) }
}
```

- [ ] **Step 4: Run test to verify it passes**

Same command as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ios/Sources/Kit/Store/ProjectStore+Mutations.swift ios/Tests/KitTests/ProjectStoreMutationTests.swift
git commit -m "feat(kit): removeCues bulk-deletes cues by id set"
```

---

## Task 3: Kit — `renumberFromOne()`

**Files:**
- Modify: `ios/Sources/Kit/Store/ProjectStore+Mutations.swift`
- Test: `ios/Tests/KitTests/ProjectStoreMutationTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
func testRenumberFromOneAssignsSequentialIntegers() {
    let s = store()
    s.addCue(); s.addCue(); s.addCue()
    s.updateActiveCue(id: s.activeSong.cues[0].id) { $0.n = 10 }
    s.updateActiveCue(id: s.activeSong.cues[1].id) { $0.n = 2.5 }
    s.renumberFromOne()
    XCTAssertEqual(s.activeSong.cues.map(\.n), [1, 2, 3])   // display order, integer steps
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ios && xcodebuild test -scheme CuelistCompilerKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:KitTests/ProjectStoreMutationTests/testRenumberFromOneAssignsSequentialIntegers 2>&1 | tail -20`
Expected: FAIL — no member `renumberFromOne`.

- [ ] **Step 3: Write minimal implementation**

```swift
/// Reassign cue numbers 1,2,3… in current display (array) order. Integer steps.
func renumberFromOne() {
    let i = activeSongIndex()
    for k in project.songs[i].cues.indices {
        project.songs[i].cues[k].n = Double(k + 1)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Same command as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ios/Sources/Kit/Store/ProjectStore+Mutations.swift ios/Tests/KitTests/ProjectStoreMutationTests.swift
git commit -m "feat(kit): renumberFromOne re-labels cues 1..n in display order"
```

---

## Task 4: Kit — `setCueNumber(id:to:)`

**Files:**
- Modify: `ios/Sources/Kit/Store/ProjectStore+Mutations.swift`
- Test: `ios/Tests/KitTests/ProjectStoreMutationTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
func testSetCueNumberChangesOneCueAllowingDecimalsAndDuplicates() {
    let s = store()
    s.addCue(); s.addCue()                      // n = 1,2
    s.setCueNumber(id: s.activeSong.cues[1].id, to: 1.5)
    XCTAssertEqual(s.activeSong.cues.map(\.n), [1, 1.5])
    s.setCueNumber(id: s.activeSong.cues[1].id, to: 1)   // duplicates allowed (n is a label)
    XCTAssertEqual(s.activeSong.cues.map(\.n), [1, 1])
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ios && xcodebuild test -scheme CuelistCompilerKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:KitTests/ProjectStoreMutationTests/testSetCueNumberChangesOneCueAllowingDecimalsAndDuplicates 2>&1 | tail -20`
Expected: FAIL — no member `setCueNumber`.

- [ ] **Step 3: Write minimal implementation**

```swift
/// Set one cue's number. No auto-sort; duplicates allowed (n is a free label).
func setCueNumber(id: UUID, to n: Double) {
    updateActiveCue(id: id) { $0.n = n }
}
```

- [ ] **Step 4: Run test to verify it passes**

Same command as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ios/Sources/Kit/Store/ProjectStore+Mutations.swift ios/Tests/KitTests/ProjectStoreMutationTests.swift
git commit -m "feat(kit): setCueNumber edits a single cue's number"
```

---

## Task 5: Extract `VoiceButton` component

Pull the voice record/stop button body out of `TalkBarView` so it can be reused (compact in the trio, full-width in the Notes sheet). No behavior change yet.

**Files:**
- Create: `ios/Sources/App/Components/VoiceButton.swift`
- Modify: `ios/Sources/App/TalkBarView.swift`

- [ ] **Step 1: Create the component**

Create `ios/Sources/App/Components/VoiceButton.swift`:

```swift
import SwiftUI
import CuelistCompilerKit

/// Reusable aqua tap-to-talk button. Drives the shared VoiceCaptureController.
/// `fullWidth` = the original full-bleed pill; otherwise it sizes to fit a row.
struct VoiceButton: View {
    @Environment(ProjectStore.self) private var store
    @Environment(VoiceCaptureController.self) private var voice
    var fullWidth: Bool = true
    var showLabel: Bool = true

    var body: some View {
        Button {
            Task {
                if voice.phase.isRecording {
                    await voice.stopAndProcess(project: store.project, defaults: store.defaults)
                } else {
                    await voice.startRecording()
                }
            }
        } label: {
            HStack(spacing: 8) {
                if voice.phase.isBusy {
                    ProgressView().tint(Theme.aquaInk)
                } else {
                    Image(systemName: voice.phase.isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: showLabel ? 18 : 16, weight: .bold))
                        .symbolEffect(.pulse, isActive: voice.phase.isRecording)
                }
                if showLabel {
                    Text(voice.phase.talkBarLabel)
                        .font(.system(size: 14, weight: .bold)).lineLimit(1)
                }
            }
            .foregroundStyle(Theme.aquaInk)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(maxWidth: .infinity)
            .padding(.vertical, fullWidth ? 16 : 14)
            .background(Theme.aquaGradient, in: RoundedRectangle(cornerRadius: Theme.radiusLarge))
            .shadow(color: Theme.aqua.opacity(0.5), radius: fullWidth ? 22 : 12, y: 4)
            .opacity(voice.phase.isBusy ? 0.7 : 1)
        }
        .buttonStyle(.plain)
        .disabled(voice.phase.isBusy)
    }
}
```

- [ ] **Step 2: Reduce `TalkBarView` to a wrapper**

Replace the body of `ios/Sources/App/TalkBarView.swift` with:

```swift
import SwiftUI
import CuelistCompilerKit

/// Full-width voice bar (kept for the Notes sheet's big mic). The Author tab now
/// uses VoiceButton directly inside BottomCluster.
struct TalkBarView: View {
    var body: some View {
        VoiceButton(fullWidth: true)
            .padding(.horizontal, 12).padding(.bottom, 12).padding(.top, 4)
    }
}
```

- [ ] **Step 3: Build to verify it compiles**

Run: `cd ios && xcodegen generate >/dev/null && xcodebuild build -scheme CuelistCompiler -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add ios/Sources/App/Components/VoiceButton.swift ios/Sources/App/TalkBarView.swift
git commit -m "refactor(ios): extract reusable VoiceButton from TalkBarView"
```

---

## Task 6: Notes sheet — big aqua mic

Replace the small "Mic"/"Stop" label button in the Notes sheet with a full-width `VoiceButton`-style mic. The Notes sheet records via `NotesCaptureController` (not `VoiceCaptureController`), so this is a styling change to the existing `micButton`, not a `VoiceButton` swap.

**Files:**
- Modify: `ios/Sources/App/NotesCaptureView.swift`

- [ ] **Step 1: Rewrite `micButton`**

In `ios/Sources/App/NotesCaptureView.swift`, replace the `micButton` computed property with a full-width aqua pill:

```swift
@ViewBuilder private var micButton: some View {
    if notes.phase.isNotesRecording {
        bigMic(symbol: "stop.fill", text: "Stop", pulse: true) {
            Task { let t = await notes.stopAndTranscribe(); if !t.isEmpty { text = text.isEmpty ? t : text + " " + t } }
        }
    } else if case .transcribing = notes.phase {
        HStack { Spacer(); ProgressView().tint(Theme.aquaInk); Spacer() }
            .padding(.vertical, 16)
            .background(Theme.aquaGradient, in: RoundedRectangle(cornerRadius: Theme.radiusLarge))
            .opacity(0.7)
    } else {
        bigMic(symbol: "mic.fill", text: "Tap to talk", pulse: false) {
            Task { await notes.startRecording() }
        }
    }
}

private func bigMic(symbol: String, text: String, pulse: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 18, weight: .bold))
                .symbolEffect(.pulse, isActive: pulse)
            Text(text).font(.system(size: 14, weight: .bold))
        }
        .foregroundStyle(Theme.aquaInk)
        .frame(maxWidth: .infinity).padding(.vertical, 16)
        .background(Theme.aquaGradient, in: RoundedRectangle(cornerRadius: Theme.radiusLarge))
        .shadow(color: Theme.aqua.opacity(0.5), radius: 18, y: 4)
    }
    .buttonStyle(.plain)
}
```

- [ ] **Step 2: Move the mic above the Route/Add row so it's the primary affordance**

In `body`, change the `HStack { micButton; Spacer(); Button {…} Route/Add }` so the big mic is its own full-width row above the submit button. Replace that `HStack(spacing: 12) { … }` block with:

```swift
micButton

HStack {
    Spacer()
    Button {
        Task {
            await notes.routeText(text, project: store.project, targetCue: targetCue)
            if case .preview = notes.phase, let cue = targetCue {
                store.applyNotes(notes.routed.map { NoteEdit(cue: cue, text: $0.text) })
                notes.reset(); dismiss()
            }
        }
    } label: {
        Text(targetCue == nil ? "Route" : "Add")
            .font(.system(size: 14, weight: .semibold))
            .padding(.vertical, 10).padding(.horizontal, 20)
            .background(Theme.aqua, in: RoundedRectangle(cornerRadius: Theme.radius))
            .foregroundStyle(Theme.aquaInk)
    }
    .buttonStyle(.plain)
    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
    .opacity(text.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
}
```

- [ ] **Step 3: Build to verify it compiles**

Run: `cd ios && xcodegen generate >/dev/null && xcodebuild build -scheme CuelistCompiler -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add ios/Sources/App/NotesCaptureView.swift
git commit -m "feat(ios): big aqua mic in the Notes capture sheet"
```

---

## Task 7: `CueListView` → styled `List` with selection + reorder

Convert the cue list to a `List` restyled to match today's look, wired for multi-select and `.onMove`. The in-scroll "Add Cue" button is removed (it moves to BottomCluster in Task 9). The list takes `selection` and `editMode` bindings owned by RootView (Task 9).

**Files:**
- Modify: `ios/Sources/App/CueListView.swift`

- [ ] **Step 1: Rewrite `CueListView`**

Replace the whole file with:

```swift
import SwiftUI
import CuelistCompilerKit

struct CueListView: View {
    @Environment(ProjectStore.self) private var store
    @Binding var selection: Set<UUID>

    private var activeIndex: Int? {
        store.project.songs.firstIndex(where: { $0.id == store.project.activeSongId })
    }

    var body: some View {
        @Bindable var store = store
        if let i = activeIndex {
            if store.project.songs[i].cues.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "music.note.list")
                        .font(.largeTitle).foregroundStyle(Theme.textFaint)
                    Text("No cues yet")
                        .font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.textDim)
                    Text("Tap “Add Cue” to start.")
                        .font(.system(size: 12)).foregroundStyle(Theme.textFaint)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity).padding(.top, 60)
            } else {
                List(selection: $selection) {
                    ForEach($store.project.songs[i].cues) { $cue in
                        CueCardView(cue: $cue)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 5, leading: 14, bottom: 5, trailing: 14))
                    }
                    .onMove { store.moveCues(from: $0, to: $1) }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.defaultMinListRowHeight, 0)
            }
        }
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

`CueListView()` is still called in `RootView` without the new binding — expect a compile error here; that is fixed in Task 9. To verify this file in isolation, build after Task 9. For now run:

Run: `cd ios && xcodegen generate >/dev/null && xcodebuild build -scheme CuelistCompiler -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -8`
Expected: FAIL — `missing argument for parameter 'selection'` at the `CueListView()` call site in RootView. This is expected and resolved in Task 9. Do **not** commit yet — Tasks 7→9 land together.

> Note: Tasks 7, 8, 9 are interdependent (RootView wires selection/editMode into the list and renumber alert). Implement 7→8→9, then build and commit once at the end of Task 9.

---

## Task 8: Tappable `CueBadge` → renumber-one alert + edit-mode compact rendering

**Files:**
- Modify: `ios/Sources/App/CueCardView.swift`

- [ ] **Step 1: Add renumber state, edit-mode read, and a compact flag**

In `CueCardView`, add near the existing `@State` vars:

```swift
@Environment(\.editMode) private var editMode
@State private var renumbering = false
@State private var renumberText = ""

private var isEditing: Bool { editMode?.wrappedValue == .active }
```

This drives O1: in edit mode the card renders compact **without mutating `cue.collapsed`**, so there is no prior state to restore on exit.

- [ ] **Step 2: Make the badge tappable**

In `body`, wrap the `CueBadge(n: cue.n)` (inside the collapse `Button`'s `HStack`) so the badge has its own tap that opens the alert instead of toggling collapse. Replace `CueBadge(n: cue.n)` with:

```swift
CueBadge(n: cue.n)
    .onTapGesture {
        renumberText = formatN(cue.n)
        renumbering = true
    }
```

(Because `.onTapGesture` on the badge is more specific than the enclosing button, tapping the number opens the alert; tapping elsewhere still toggles collapse.)

- [ ] **Step 3: Add the alert modifier**

Add alongside the existing `.confirmationDialog`/`.sheet` modifiers on the card:

```swift
.alert("Cue number", isPresented: $renumbering) {
    TextField("Number", text: $renumberText)
        .keyboardType(.decimalPad)
    Button("Save") {
        if let v = Double(renumberText.replacingOccurrences(of: ",", with: ".")) {
            store.setCueNumber(id: cue.id, to: v)
        }
    }
    Button("Cancel", role: .cancel) { }
} message: { Text("Set the number for this cue.") }
```

- [ ] **Step 4: Force compact rendering in edit mode**

So a tall expanded card doesn't make dragging/selecting awkward, render only the compact header while editing. Two edits in `body`:

1. Disable the name field while editing — change `.disabled(cue.collapsed)` on the name `TextField` to:

```swift
.disabled(cue.collapsed || isEditing)
```

2. Gate the expanded section — change the top-level `if cue.collapsed {` (the branch that shows chips vs. full action blocks) to:

```swift
if cue.collapsed || isEditing {
```

This shows the compact chips row (or nothing) instead of action blocks, steppers, and the Note/Delete row while in edit mode. The model is untouched; exiting edit mode restores the exact prior expand state.

- [ ] **Step 5: Defer build/commit to Task 9** (interdependent — see Task 7 note).

---

## Task 9: RootView — third tab, stripped top bar, bottom cluster, subbar renumber

Wire everything: own `editMode` + `selection`, pass them to the list, host the bottom cluster (Task 10 provides `BottomCluster`), add `list.number` to the subbar, add the Settings tab (Task 11 provides `SettingsTabView`), and strip the Author top bar.

> Implement Tasks 10 and 11 first if doing this inline; under subagent-driven execution they are separate tasks dispatched before this integration. The code below references `BottomCluster` (Task 10) and `SettingsTabView` (Task 11).

**Files:**
- Modify: `ios/Sources/App/RootView.swift`

- [ ] **Step 1: Add edit/selection state + the third tab**

In `RootView`, add state:

```swift
@State private var editMode: EditMode = .inactive
@State private var selection: Set<UUID> = []
```

Replace the `TabView { … }` body with:

```swift
TabView {
    authorTab
        .tabItem { Label("Author", systemImage: "square.and.pencil") }
    SendView()
        .tabItem { Label("Send", systemImage: "paperplane") }
    SettingsTabView()
        .tabItem { Label("Settings", systemImage: "gearshape") }
}
.tint(Theme.accentSolid)
```

- [ ] **Step 2: Strip the Author top bar and host the bottom cluster**

Rewrite `authorTab` so the `VStack` ends with `BottomCluster`, the list gets the bindings, and the toolbar keeps only the song menu + an Edit button. Remove the `showNotes`/`showDefaults`/`showSettings`/`showPull` sheet-from-toolbar wiring that moved to the Settings tab (keep `showNotes` — Note now opens from BottomCluster, and the sheet still lives here). Replace `authorTab` with:

```swift
private var authorTab: some View {
    @Bindable var store = store
    return NavigationStack {
        ZStack {
            Theme.canvas
            VStack(spacing: 0) {
                subbar
                CueListView(selection: $selection)
                if editMode == .active {
                    deleteBar
                } else {
                    BottomCluster(onAddCue: { store.addCue() },
                                  onNote: { showNotes = true })
                }
            }
        }
        .environment(\.editMode, $editMode)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { songMenu }
            ToolbarItem(placement: .topBarTrailing) {
                Button(editMode == .active ? "Done" : "Edit") {
                    withAnimation { editMode = editMode == .active ? .inactive : .active }
                    if editMode == .inactive { selection.removeAll() }
                }
                .foregroundStyle(Theme.accentSolid)
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
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

@ViewBuilder private var deleteBar: some View {
    Button(role: .destructive) {
        store.removeCues(ids: selection); selection.removeAll()
    } label: {
        Text(selection.isEmpty ? "Select cues to delete"
                               : "Delete \(selection.count) cue\(selection.count == 1 ? "" : "s")")
            .font(.system(size: 16, weight: .semibold))
            .frame(maxWidth: .infinity).padding(.vertical, 16)
            .background(selection.isEmpty ? Theme.surface2 : Theme.danger,
                        in: RoundedRectangle(cornerRadius: Theme.radiusLarge))
            .foregroundStyle(selection.isEmpty ? Theme.textDim : .white)
    }
    .buttonStyle(.plain).disabled(selection.isEmpty)
    .padding(.horizontal, 12).padding(.bottom, 12).padding(.top, 4)
}
```

Then delete the now-unused `@State private var showDefaults`, `showPull`, `showSettings` declarations (keep `showNotes`, `showRename`, `renameText`).

- [ ] **Step 3: Add `list.number` to the subbar**

In `subbar`, after the expand-all button (inside the `if !cues.isEmpty` block), add:

```swift
Button { withAnimation(.snappy(duration: 0.2)) { store.renumberFromOne() } } label: {
    Image(systemName: "list.number")
        .font(.system(size: 14)).foregroundStyle(Theme.accentSolid)
}
.buttonStyle(.plain)
```

- [ ] **Step 4: Build to verify (lands Tasks 7–11 together)**

Run: `cd ios && xcodegen generate >/dev/null && xcodebuild build -scheme CuelistCompiler -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Run the full Kit suite**

Run: `cd ios && xcodebuild test -scheme CuelistCompilerKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -5`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit (Tasks 7–11)**

```bash
git add ios/Sources/App/CueListView.swift ios/Sources/App/CueCardView.swift ios/Sources/App/RootView.swift ios/Sources/App/BottomCluster.swift ios/Sources/App/SettingsTabView.swift
git commit -m "feat(ios): edit mode (multi-delete + reorder), pinned bottom cluster, renumber, settings tab"
```

---

## Task 10: `BottomCluster` component

The pinned trio (Add Cue · Note · Talk). Built before Task 9 integration.

**Files:**
- Create: `ios/Sources/App/BottomCluster.swift`

- [ ] **Step 1: Create the component**

```swift
import SwiftUI
import CuelistCompilerKit

/// Pinned bottom trio on the Author tab: Add Cue (violet) · Note (aqua) · Talk (aqua).
struct BottomCluster: View {
    let onAddCue: () -> Void
    let onNote: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onAddCue) {
                clusterLabel("Add Cue", symbol: "plus", ink: .white)
                    .background(Theme.accentGradient, in: RoundedRectangle(cornerRadius: Theme.radiusLarge))
                    .shadow(color: Theme.accentSolid.opacity(0.4), radius: 12, y: 3)
            }
            .buttonStyle(.plain)

            Button(action: onNote) {
                clusterLabel("Note", symbol: "square.and.pencil", ink: Theme.aqua)
                    .background(Theme.aquaTint, in: RoundedRectangle(cornerRadius: Theme.radiusLarge))
                    .overlay(RoundedRectangle(cornerRadius: Theme.radiusLarge)
                        .strokeBorder(Theme.aqua.opacity(0.45), lineWidth: 1))
            }
            .buttonStyle(.plain)

            VoiceButton(fullWidth: false, showLabel: false)
        }
        .padding(.horizontal, 12).padding(.bottom, 12).padding(.top, 4)
    }

    private func clusterLabel(_ text: String, symbol: String, ink: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 15, weight: .bold))
            Text(text).font(.system(size: 13, weight: .bold)).lineLimit(1)
        }
        .foregroundStyle(ink)
        .frame(maxWidth: .infinity).padding(.vertical, 16)
    }
}
```

- [ ] **Step 2: Build verification deferred to Task 9** (integrated there).

---

## Task 11: `SettingsTabView`

The third tab: rows for Pull from MA / Defaults / Settings, opening the existing views. Built before Task 9 integration.

**Files:**
- Create: `ios/Sources/App/SettingsTabView.swift`

- [ ] **Step 1: Create the tab**

```swift
import SwiftUI
import CuelistCompilerKit

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
                        row("Pull from MA…", systemImage: "arrow.down.circle") { showPull = true }
                    }
                    Section {
                        row("Defaults…", systemImage: "slider.horizontal.3") { showDefaults = true }
                        row("Settings…", systemImage: "gearshape") { showSettings = true }
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
```

- [ ] **Step 2: Build verification deferred to Task 9** (integrated there).

---

## Task 12: On-device smoke + final verification

**Files:** none (verification only).

- [ ] **Step 1: Confirm full Kit suite + build green**

Run: `cd ios && xcodegen generate >/dev/null && xcodebuild test -scheme CuelistCompilerKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -5`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 2: Install on jPhone (2) and smoke**

Build for the device and install (device id `7DF307B3-6B1F-5CB1-8793-5DB9437E7FF8`, bundle `com.blearred.cuelistcompiler`). Manually verify:
- Author top bar shows only the song menu + Edit.
- Bottom trio: Add Cue (violet) adds a cue; Note opens the Notes sheet; Talk records.
- Edit → cues go compact; multi-select several → Delete N cue(s) works; drag-reorder works; Done restores cards.
- Tap a cue number badge → renumber alert sets the number (try `1.5`).
- Subbar `list.number` renumbers 1..n in order.
- Settings tab opens Pull / Defaults / Settings.
- Notes sheet shows a big aqua mic that records.

- [ ] **Step 3: Final commit (if any device-smoke tweaks were needed)**

```bash
git add -A && git commit -m "chore(ios): round-3 UI followups device-smoke fixes"
```

---

## Self-Review Notes

- **Spec coverage:** §1 Settings tab → Task 11+9; §2 stripped top bar → Task 9; §3 bottom cluster → Task 10+9; §4 edit mode (List/select/reorder/delete bar) → Tasks 1,2,7,9; §5 renumber-one → Tasks 4,8 and enumerate-from-1 → Tasks 3,9; §6 big mic → Task 6. Kit methods → Tasks 1–4. All covered.
- **Interdependency:** Tasks 7–11 compile only together; they share one build+commit at Task 9 Step 6. Kit Tasks 1–4 and the VoiceButton refactor (Task 5) and the Notes mic (Task 6) are independently committable.
- **Type consistency:** `moveCues(from:to:)`, `removeCues(ids:)`, `renumberFromOne()`, `setCueNumber(id:to:)`, `VoiceButton(fullWidth:showLabel:)`, `BottomCluster(onAddCue:onNote:)`, `CueListView(selection:)`, `SettingsTabView()` — names match across tasks.
- **Open questions resolved per spec defaults:** O1 (collapse on edit) handled by `editMode` driving compact rows; O2 Add Cue appends (unchanged `addCue`); O3 duplicates allowed (Task 4 test asserts it).

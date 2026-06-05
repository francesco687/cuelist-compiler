# iOS UI follow-ups (round 2) — design

**Date:** 2026-06-05
**Branch base:** `main` (`18c3cba`)
**Working dir:** `/Users/jordanbabev/cuelist-compiler/ios`
**Repo:** francesco687/cuelist-compiler (collaborator — Jordan has push; confirm push per change)

## Goal

Four independent iPhone UI improvements for the Cuelist Compiler authoring app:

1. **Declutter** — move the whole Send→MA OSC flow off the main authoring screen into its own bottom tab, reflowed as a proper full-page layout.
2. **Note delete/edit** — let a cue's note be edited or cleared after creation; let a routing-preview row be dropped before applying.
3. **Collapse-all / Expand-all** cues.
4. **Typed sequence entry** — replace the seq Stepper with a tappable numeric field.

## Constraints (do not relitigate)

- **Two-accent rule:** aqua (`Theme.aqua`/`aquaGradient`/`aquaTint`) = capture/voice/notes family; violet (`Theme.accentGradient`/`accentSolid`) = Send→MA. Keep the split.
- Voice/notes pipeline unchanged — UI only re-fronts `VoiceCaptureController` / `NotesCaptureController` / `AnthropicNoteRouter`.
- `Cue.notes` is one `\n`-joined `String` (not structured entries). Editing/clearing operates on the whole blob.
- `ProjectStore` + `HubClient` + `VoiceCaptureController` + `NotesCaptureController` are all `@Environment` — shared across tabs with no plumbing change.

## Architecture

### 1. Bottom TabView + reflowed Send page

`RootView.body` wraps the current content in a `TabView`:

- **Tab "Author"** (`systemImage: "square.and.pencil"`, label "Author"):
  - `subbar` + `CueListView` + `TalkBarView` (today's authoring stack, minus `SendBarView`).
  - The existing `.toolbar` (song menu in `.principal`, ⚙︎ menu in `.topBarTrailing`) stays on this tab.
  - The global **Notes** brain-dump button (currently inside `SendBarView`) relocates here — added to the `.topBarTrailing` toolbar as a `square.and.pencil` aqua button that sets `showNotes = true`. (Keeps global note capture on the authoring screen; preserves aqua family.)
- **Tab "Send"** (`systemImage: "paperplane"`, label "Send"):
  - New `SendView` — a proper full-page layout (not the old bottom bar):
    - **Top:** connection state — the `LiveIndicator(state:)` pill, tappable to `hub.connect()`, with a short status caption.
    - **Mid:** `StoreMode` segmented picker (full-width, labeled "Store mode").
    - **Center:** the primary violet **Send → MA** button (large, `accentGradient`) + a secondary **Send All** button. Disabled + dimmed when `!hub.state.isOnline`.
    - **Below:** `resultRow` — progress bar while sending, success/failure label after.
  - Lives in its own `NavigationStack` with an inline title "Send to MA".

`SendBarView.swift` is **replaced** by `SendView.swift` (the bottom-bar struct is removed; its `resultRow`/button internals are reused inside the reflowed layout). `RootView` no longer references `SendBarView`.

State sharing: both tabs read the same `@Environment` objects, so live hub state, progress, and project edits stay consistent across tab switches. No model/store change for this item.

### 2. Note edit/clear

**Per-cue note (saved):**
- The aqua note line in `CueCardView` (currently a static `HStack`) becomes a `Button` that sets `editingNote = true`.
- New **`EditNoteView`** sheet (`NotesCaptureView` is for *capture*; this is for *edit* — separate, single-purpose view):
  - `TextField("Note", text:, axis: .vertical)` pre-filled with `cue.notes`, lineLimit 3...10, on `Theme.surface2`.
  - **Save** (aqua) — calls `store.setNote(cueN: cue.n, text: edited)`; empty/whitespace text ⇒ note cleared.
  - **Clear** (destructive) — sets text to `""` and saves (note disappears), dismisses.
  - **Cancel** — dismiss without write.
- New Kit mutation on `ProjectStore+Mutations`:
  ```swift
  /// Overwrite (or clear) the note of the active song's cue number `n`.
  /// Empty/whitespace text clears the note. Unknown cue numbers are ignored.
  func setNote(cueN n: Double, text: String) {
      let i = activeSongIndex()
      guard let c = project.songs[i].cues.firstIndex(where: { $0.n == n }) else { return }
      project.songs[i].cues[c].notes = text.trimmingCharacters(in: .whitespacesAndNewlines)
  }
  ```

**Routing-preview row (pending, not yet applied):**
- In `NotesCaptureView.routingPreview`, each "Routes to" row gets a trailing `✕` button that removes that entry from `notes.routed` before the user taps "Add N notes".
- Requires `notes.routed` to be mutable from the view. Check `NotesCaptureController`: if `routed` is a settable published/`@Observable` property, drop the row via index; the "Add" button count updates reactively. If `routed` is read-only, add a `removeRoute(at:)` method on the controller. (Implementation decides based on the actual declaration — see Open Items.)

### 3 + 4. Subbar: typed seq + collapse/expand-all

`RootView.subbar` is rebuilt as a single slim `HStack`:

```
Seq [ 666 ]   ⊟  ⊞            3 cues
```

- **Typed seq** — a `TextField` bound to `songs[i].sequence` (Int) through a String bridge:
  - Local `@State private var seqText: String`, synced from the model `.onAppear` and on active-song change.
  - `.keyboardType(.numberPad)`, fixed compact width (~64pt), monospaced digits, on `Theme.surface2`.
  - On commit / focus-loss: parse Int, clamp `1...9999`, write back to model; if unparseable, revert `seqText` to the model value. The old `Stepper(value:in:)` is removed.
- **⊟ Collapse-all / ⊞ Expand-all** — two icon buttons (`rectangle.compress.vertical` / `rectangle.expand.vertical`, or `chevron.up.chevron.down`), `accentSolid` tint, calling the new mutations. Hidden when the active song has 0 cues.
- Cue count text stays trailing.

New Kit mutations on `ProjectStore+Mutations`:
```swift
func collapseAllCues() {
    let i = activeSongIndex()
    for c in project.songs[i].cues.indices { project.songs[i].cues[c].collapsed = true }
}
func expandAllCues() {
    let i = activeSongIndex()
    for c in project.songs[i].cues.indices { project.songs[i].cues[c].collapsed = false }
}
```

## Files

| File | Change |
|------|--------|
| `ios/Sources/App/RootView.swift` | TabView restructure; rebuilt subbar (typed seq + ⊟/⊞); Notes button → Author toolbar; drop `SendBarView` ref |
| `ios/Sources/App/SendView.swift` | **new** — reflowed full-page Send tab |
| `ios/Sources/App/SendBarView.swift` | **removed** (internals migrate into `SendView`) |
| `ios/Sources/App/CueCardView.swift` | note line → tappable; `EditNoteView` sheet via `editingNote` state |
| `ios/Sources/App/EditNoteView.swift` | **new** — edit/clear sheet |
| `ios/Sources/App/NotesCaptureView.swift` | ✕ to drop a routing-preview row |
| `ios/Sources/Kit/Store/ProjectStore+Mutations.swift` | `setNote`, `collapseAllCues`, `expandAllCues` |
| `ios/Tests/...` | tests for the 3 new mutations |

## Testing

- **Kit unit tests** (mirror existing mutation tests):
  - `setNote`: sets text on a known cue; clears on empty/whitespace; no-op on unknown cue number; trims.
  - `collapseAllCues` / `expandAllCues`: all cues' `collapsed` flag flips; empty song is a no-op.
- **App build** green (`xcodegen generate` if project regen needed, then `xcodebuild`).
- **On-device smoke** on jPhone (2) (`7DF307B3-6B1F-5CB1-8793-5DB9437E7FF8`, bundle `com.blearred.cuelistcompiler`):
  - Tab switch Author↔Send; Send still reaches MA (or shows offline correctly).
  - Edit a note, clear a note; drop a routing-preview row.
  - Type a seq number; collapse-all then expand-all.

## Execution & ship

- Subagent-driven execution (like last round). Atomic-ish commits per item on a feature branch off `main`.
- Verify `git rev-parse <branch>` == last SHA before any push (subagent branch-ref drift gotcha).
- **Collaborator repo** — confirm push approach with Jordan before pushing; merged locally last round.

## Open items (resolve during implementation, not blocking)

- Exact `NotesCaptureController.routed` mutability — read declaration; add `removeRoute(at:)` if `routed` isn't view-settable.
- SF Symbol choice for collapse/expand (pick whichever renders cleanly at subbar size).
- Whether `SendView` keeps its own `NavigationStack` or relies on the TabView host (decide for cleanest large-title behavior).

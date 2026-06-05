# iOS UI: bottom talk bar, safe cue-delete, and cue notes

**Date:** 2026-06-05
**Surface:** iPhone app (`ios/Sources/App` + `ios/Sources/Kit`)
**Status:** Design approved, ready for planning

## Problem

Three usability problems on the iPhone, raised from live one-handed use of the cuelist editor:

1. **Voice is out of thumb reach.** The mic lives in the top-left nav toolbar. Holding the phone one-handed, it's awkward to reach and small to hit.
2. **Cues get deleted by accident.** On a collapsed cue card the red trash sits immediately left of the expand chevron, both on the right edge where the thumb taps to expand. Mis-taps delete a cue outright, with no confirmation.
3. **No way to attach notes to cues.** There's no place to jot "keep the intro dim" or "chorus should hit harder" against the cues they refer to.

## Goals

- A large, aqua, bottom-anchored voice control that's easy to hit one-handed.
- Make accidental cue deletion structurally hard, and confirm before deleting.
- Let the operator capture notes by text or voice and have them land on the right cue(s) via a light LLM pass — both as a global brain-dump (LLM routes) and per-cue (LLM tidies).

## Non-goals

- No change to the voice **interpret pipeline** itself (transcribe → `AnthropicInterpreter` → `ShowEditApplier` → preview). We're re-fronting it, not rebuilding it.
- No change to the desktop/web app, the hub, or the project-JSON contract beyond one additive, backward-compatible field.
- No swipe-to-delete (the cue list is a `LazyVStack`, not a `List`; a custom swipe gesture was considered and rejected as more code for less benefit).
- No multi-note model (notes are a single appended text blob per cue, not structured/timestamped entries). YAGNI for now.

## Design decisions (locked in brainstorming)

| Fork | Decision |
|------|----------|
| Voice button placement | **Full-width aqua "talk bar"** as the bottom-most element; Send→MA / All shrink to a slim strip above it |
| Talk gesture | **Tap to start / tap to stop** (matches today's behavior; frees the thumb during long commands) |
| Cue delete | **Expand to delete** — collapsed cards show only the chevron; delete lives in the expanded card footer + confirmation |
| Delete confirmation | System **`confirmationDialog`** ("Delete cue N "name"? — Delete / Cancel") |
| Notes entry | **Both** — a global ✎ Notes button (LLM routes to cues) **and** a per-cue ✎ Note button (LLM tidies for that one cue) |
| Notes write semantics | **Append** (newline-joined), never overwrite |
| Notes interpreter | A **separate** `NoteRouter` (own prompt + tool), not an extension of `AnthropicInterpreter` |

## Architecture

The work splits into three independently-committable slices. Recommended order is **A → B → C** (smallest/safest first).

### Slice A — Safe cue delete (`CueCardView.swift`)

Current `CueCardView` header is one tappable `Button` (toggles `cue.collapsed`) containing the name field, a nested destructive trash `Button`, and the chevron. The trash fires `store.removeCue(id:)` immediately.

Changes, all within `ios/Sources/App/CueCardView.swift`:

1. **Remove the trash button from the header.** The collapsed header becomes: badge · name · chevron. Nothing destructive near the tap-to-expand target.
2. **Add an expanded-card footer row** (only rendered in the `else`/expanded branch, after the Fade/Delay steppers): a trailing-aligned **`🗑 Delete cue`** button styled with `Theme.danger` (outlined, clearly separated). In Slice C this row also gains the per-cue **`✎ Note`** button.
3. **Confirmation.** Delete tap sets `@State private var confirmingDelete = false`; a `.confirmationDialog("Delete cue \(cue.n) "\(cue.name)"?", isPresented: $confirmingDelete, titleVisibility: .visible)` offers a destructive **Delete** (`store.removeCue(id: cue.id)`) and **Cancel**.

No model or store changes. `store.removeCue(id:)` is reused as-is.

**Tests:** view logic is thin; cover by confirming `removeCue` still works (existing `ProjectStore` mutation tests) and add a small assertion that a cue removed by id is gone. The UI wiring (dialog presentation) is verified in device smoke, not unit tests.

### Slice B — Bottom aqua talk bar (`Theme.swift`, new `TalkBarView.swift`, `RootView.swift`, `SendBarView.swift`)

1. **Theme token** (`Theme.swift`): add
   - `static let aqua = Color(hex: "#21D4C4")!`
   - `static var aquaGradient` (radial/linear bright-teal, e.g. `#3DF0DC → #16C6B4`)
   - a documented comment that this is the new iOS accent for voice/notes; mirror into the desktop CSS `:root` later if desired. Hex is tunable.
2. **`TalkBarView`** (new, `ios/Sources/App/TalkBarView.swift`): a full-width, tall, rounded **aqua** bar that reads `voice.phase` and renders:
   - `.idle`/`.error` → "🎙 Tap to talk", tap → `voice.startRecording()`
   - `.recording` → "Listening… tap to stop" with a pulse/`symbolEffect`; tap → `voice.stopAndProcess(project:defaults:)`
   - `.transcribing`/`.interpreting` → "Thinking…" + `ProgressView`, non-interactive
   - `.preview` → bar disabled (the existing `VoicePreviewSheet` is already presenting via `RootView`)
   It takes `VoiceCaptureController` and `ProjectStore` from the environment exactly as the current toolbar mic does.
3. **`RootView.swift`**: remove the `micButton` toolbar item and the `micButton` view. Add `TalkBarView()` as the bottom-most element of the root `VStack` (below `SendBarView()`). The `VoicePreviewSheet`/error-alert wiring stays unchanged.
4. **`SendBarView.swift`**: unchanged structurally, but it's now the *slim strip above* the talk bar. In Slice C it gains the global ✎ Notes button in its action row.

**Tests:** add a `TalkBarView` label/state mapping test if the phase→label logic is factored into a pure function (preferred: a small `talkBarLabel(for: Phase) -> String` so it's unit-testable). Otherwise rely on device smoke. No change to `VoiceCaptureController` tests.

### Slice C — Cue notes (model + `NoteRouter` + global & per-cue entry)

**Model** (`ios/Sources/Kit/Models/Cue.swift`):
- Add `public var notes: String = ""`.
- Add `notes` to `CodingKeys` and decode with `try c.decodeIfPresent(String.self, forKey: .notes) ?? ""` (backward compatible — old JSON and the web/desktop side are unaffected; the field is omitted on encode if empty is acceptable, or always encoded as `""`).
- Add `notes` to the memberwise `init` with a default so existing call sites compile unchanged.

**`NoteRouter`** (new, `ios/Sources/Kit/Voice/NoteRouter.swift`): same forced-tool-use shape as `AnthropicInterpreter` (reuses `HTTPTransport`, `cache_control` on system+tool, Sonnet). Two roles, one entry point:

```
func route(transcript: String, project: Project, targetCue: Double?) async throws -> [NoteEdit]
```
- `NoteEdit { cue: Double; text: String }` (new small type alongside `InterpretedCommand`).
- Tool `attach_notes` → `{ notes: [{ cue: number, text: string }] }`.
- **Global** (`targetCue == nil`): system prompt = "given the show JSON and the operator's free-form notes, attach each note to the cue(s) it refers to; condense to a short imperative line; if a note is ambiguous, attach to the most likely cue." Returns one-or-more `NoteEdit`s.
- **Per-cue** (`targetCue` set): the cue is pinned; the prompt just **tidies/condenses** the dictated text into a short note for that cue. Returns a single `NoteEdit` with `cue == targetCue`.
- Errors reuse `VoiceError` (missingKey/api/badResponse) so the existing error-alert path renders them.

**Store mutation** (`ProjectStore+Mutations.swift`): add `func appendNote(cueN: Double, text: String)` (and/or `applyNotes(_ edits: [NoteEdit])`) that appends `text` to the matching cue's `notes`, newline-joined, trimming and skipping empties. Mirrors the existing mutation style. Triggers a save like other mutations.

**Global ✎ Notes entry**:
- Button added to `SendBarView`'s action row (aqua-tinted), opens a new **`NotesCaptureView`** sheet: a multiline `TextField` + a mic toggle (reusing the same `AudioRecorder`/`Transcriber` the voice path uses — inject a small capture controller or reuse `VoiceCaptureController`'s recorder/transcriber via a dedicated `NotesCaptureController`).
- On submit: transcribe (if voice) → `NoteRouter.route(targetCue: nil)` → show a **routing preview** ("Intro ← 'keep it dim…'", one row per `NoteEdit`, editable/removable) → Confirm → `store.applyNotes(edits)`.

**Per-cue ✎ Note entry** (in the expanded-card footer from Slice A):
- Opens the same `NotesCaptureView` but pinned to `cue.n`. On submit → `NoteRouter.route(targetCue: cue.n)` → the single tidied line shown inline/editable → Save → `store.appendNote(cueN: cue.n, text:)`. No routing preview needed (one known target).

**Note display on the card** (`CueCardView`): when `!cue.notes.isEmpty`, render an aqua left-border note line under the name (visible in both collapsed and expanded states), as in the approved mockup.

**Wiring** (`App.swift`): construct the notes capture controller / `NoteRouter` alongside the existing `voice` controller, reusing the same Keychain API keys (`KeychainAIKeyStore`). Inject into the environment.

**Tests** (the meat of the unit coverage):
- `NoteRouter` response parsing: given a canned `attach_notes` tool-use JSON → correct `[NoteEdit]` (mirror `AnthropicInterpreter.parse` tests). Cover the per-cue pinned case and the ambiguous→best-guess case via fixture responses through a stub `HTTPTransport`.
- `Cue` decode: old JSON without `notes` → `notes == ""`; round-trip with notes preserves them.
- `ProjectStore.appendNote`/`applyNotes`: appends newline-joined, skips empties, no-op on unknown cue number, fires save.

## Data flow

```
Voice command (talk bar):
  TalkBarView → VoiceCaptureController → Whisper → AnthropicInterpreter
    → ShowEditApplier → VoicePreviewSheet → store.apply        [UNCHANGED pipeline]

Global notes (✎ Notes):
  NotesCaptureView (text|voice) → [Whisper] → NoteRouter(target=nil)
    → routing preview → store.applyNotes([NoteEdit])

Per-cue note (✎ Note on expanded card):
  NotesCaptureView (pinned cue) → [Whisper] → NoteRouter(target=cue.n)
    → inline tidied line → store.appendNote(cueN, text)
```

## Error handling

- Reuse `VoiceError` end-to-end; missing API key / API error / bad response surface through the **existing** error-alert in `RootView` (extend the alert binding to also cover the notes controller's error state, or give `NotesCaptureView` its own inline error row).
- Delete confirmation cancels cleanly (no state left behind).
- Notes routing that returns zero edits shows a "couldn't place that note" message rather than silently dropping it.
- Talk bar in `.error` returns to a tappable "Tap to talk" (same as today's mic recovery).

## Theming

- New `Theme.aqua` (~`#21D4C4`) for: talk bar fill (aqua gradient + glow), per-cue note line left-border + ✎ icons, global ✎ Notes button tint.
- Send→MA keeps the existing violet→blue `accentGradient` (it stays the primary "commit to desk" action; aqua is the new "capture/voice" family). This intentional two-accent split reads as: violet = push to MA, aqua = capture into the app.

## Open / tunable (non-blocking)

- Exact aqua hex — pick `#21D4C4`, nudge after seeing it on device.
- Whether `NotesCaptureController` is a new small type or a reuse of `VoiceCaptureController`'s recorder/transcriber — implementer's call during planning; both keep the recorder/transcriber shared.
- Whether empty `notes` is encoded as `""` or omitted — omit-if-empty keeps JSON clean; either is backward compatible.

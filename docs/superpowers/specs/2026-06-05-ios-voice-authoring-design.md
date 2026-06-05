# iOS Voice Authoring — Design Spec

**Date:** 2026-06-05
**Branch:** `feat/voice-authoring` (off `feat/ios-shell`, the Plan B native iOS app)
**Status:** Approved design → ready for implementation plan

## 1. Goal

Add a **freeform voice command** capability to the Cuelist Compiler iOS app: the
operator speaks a natural-language instruction, it is transcribed by the **OpenAI
Whisper API**, interpreted by an **Anthropic LLM** into a set of validated edit
operations over the show, previewed in plain language, and applied to the local
project only after explicit confirmation.

"The text does exactly what it is supposed to do" = spoken words become
**correctly-filled structured cue data** (songs, cues, groups, pool presets,
fades), not free text the user must re-place by hand.

This is a pure **authoring** feature. It never talks to the hub or the grandMA3
desk. The existing "Send → MA" flow is unchanged and runs afterward, whenever the
operator chooses.

## 2. Decisions (locked during brainstorming)

| Decision | Choice |
|---|---|
| Unit of a voice capture | **Freeform command** over the whole show (create/rename/delete songs, add/edit/delete cues, set presets, sequence, defaults, store mode) |
| Transcription | **OpenAI Whisper API** (`whisper-1`), audio recorded on device and uploaded |
| Where AI runs | **Phone-direct** — the app calls OpenAI + Anthropic itself via `URLSession` |
| API keys | Stored in the **iOS Keychain**, entered once in Settings (per operator) |
| Apply mode | **Preview + confirm** — show a plain-language summary, then Apply / Discard |
| LLM output mechanism | **Approach A — operation list via Anthropic tool-use** (whitelisted, validated ops) |

## 3. Architecture & Components

Follows the existing `CuelistCompilerKit` (logic, testable, behind protocols) +
thin-app (UI, AVFoundation) split. Mic capture and UI live in the app; the AI
clients and the edit engine live in Kit.

### New Kit code — `Sources/Kit/Voice/`

- **`Transcriber`** — `protocol Transcriber { func transcribe(_ audio: URL) async throws -> String }`
  + `WhisperTranscriber` (multipart POST to `https://api.openai.com/v1/audio/transcriptions`,
  model `whisper-1`). Protocol so tests inject a fake.
- **`CommandInterpreter`** — `protocol CommandInterpreter { func interpret(transcript: String, project: Project, defaults: Defaults) async throws -> InterpretedCommand }`
  + `AnthropicInterpreter`. Calls the Anthropic Messages API with forced tool-use.
- **`ShowEdit`** — the validated edit-operation type (§4). `Codable`, decodes
  straight from the Anthropic tool input. This is the whitelist; nothing outside it
  can be expressed.
- **`ShowEditApplier`** — **pure function**
  `apply(_ edits: [ShowEdit], to project: Project, defaults: Defaults) -> ApplyResult`
  where `ApplyResult = (project: Project, defaults: Defaults, summary: [String], warnings: [String])`.
  Reuses the logic in `ProjectStore+Mutations`. The deterministic, heavily-tested core.
- **`InterpretedCommand`** — `{ transcript: String, edits: [ShowEdit], clarification: String? }`.
- **`AIKeyStore`** — Keychain read/write for the OpenAI and Anthropic keys.
- Wire structs for the OpenAI and Anthropic request/response payloads.

### New App code — `Sources/App/`

- **`VoiceCaptureController`** (`@Observable`) — owns `AVAudioRecorder`, mic-permission
  handling, and the state machine:
  `idle → recording → transcribing → interpreting → preview → applying → idle`.
  Holds the `InterpretedCommand` and the computed `ApplyResult` for the sheet.
- **Mic button** near the song bar + a recording/working indicator.
- **`VoicePreviewSheet`** — transcript + plain-language change summary + warnings +
  **Apply / Discard** (Apply disabled when there are no edits / a clarification is shown).
- **`SettingsView`** gains two `SecureField`s (OpenAI + Anthropic keys → Keychain).

### Data flow

```
tap mic → AVAudioRecorder (m4a) → stop
   → WhisperTranscriber.transcribe(file)            → transcript: String
   → AnthropicInterpreter.interpret(transcript, project, defaults)
        → InterpretedCommand { edits: [ShowEdit], clarification? }
   → ShowEditApplier.apply(edits, project, defaults) on a COPY
        → ApplyResult { newProject, newDefaults, summary, warnings }
   → VoicePreviewSheet (transcript + summary + warnings)
        → Apply   → commit newProject/newDefaults into ProjectStore → autosave
        → Discard → nothing changes
```

The phone never touches the hub for this.

## 4. The `ShowEdit` Operation Vocabulary

**Reference convention:** the LLM never sees UUIDs. It addresses targets the way a
human speaks — **song** by ordinal (`"2"`) or name (omitted = active song),
**cue** by its number `n`, **pool** by name, **action block** by index (default `0`
= first). The applier resolves these to real model objects; unresolved references
become warnings and that op is skipped.

| Group | Op | Fields | Effect |
|---|---|---|---|
| **Song** | `addSong` | `name?, sequence?` | append a song, make it active |
| | `renameSong` | `song, name` | set `song.name` |
| | `setSequence` | `song, sequence` | set `song.sequence` (Int) |
| | `selectSong` | `song` | set active song |
| | `deleteSong` | `song` | remove song (never drops below one) |
| **Cue** | `addCue` | `song?, n?, name?, fade?, delay?, position?` | append a cue (n auto-next if omitted) + set fields |
| | `setCue` | `song?, cue, field, value` | edit one field (`field` ∈ name/fade/delay/position/number) |
| | `deleteCue` | `song?, cue` | remove cue |
| | `sortCues` | `song?` | sort cues by number |
| **Action / preset** | `setGroup` | `song?, cue, group, block?` | set `action.group` |
| | `setPreset` | `song?, cue, pool, name?, fade?, delay?, block?` | set `action.presets[pool]` |
| | `clearPreset` | `song?, cue, pool, block?` | empty that preset slot |
| | `addActionBlock` | `song?, cue` | append an action block |
| | `removeActionBlock` | `song?, cue, block` | remove a block (never zero) |
| | `copyActions` | `song?, fromCue, toCue` | replace target cue's blocks with a deep copy |
| **Defaults** | `setDefault` | `pool, fade?, delay?` | set per-pool default fade/delay |
| **Project** | `setStoreMode` | `mode` (Overwrite/Merge) | set store mode |

The set is broad but **bounded** — a 1:1 cover of the existing mutation surface plus
field setters. The six pools are the canonical `Pool` cases:
`color, dimmer, position, gobo, beam, focus`.

**`song` resolution rule:** if `song` parses as a positive integer *and* that 1-based
index exists, treat it as an index; otherwise match by name (case-insensitive,
trimmed); otherwise warn + skip. Documented so behavior is unambiguous.

### Worked example

Transcript: *"In the intro cue set group 1 to deep blue with a five second fade,
and dimmer to full."*

```json
{ "edits": [
  { "op": "setGroup",  "cue": 1, "group": "1" },
  { "op": "setPreset", "cue": 1, "pool": "color",  "name": "Deep Blue", "fade": "5" },
  { "op": "setPreset", "cue": 1, "pool": "dimmer", "name": "full" }
] }
```

(`cue: 1` resolves by number; `song` omitted → active song.)

## 5. Preview / Apply — the safety contract

- The **preview summary is computed by the app, not the LLM.** `ShowEditApplier`
  runs the ops against a *copy* of the project and produces both the resulting
  project **and** the human-readable summary + warnings (e.g. "cue 5 not found —
  skipped"). The sheet shows exactly that.
- On **Apply**, the app commits the already-computed copy — no re-run, no drift.
  The preview can never disagree with what actually happens.
- If the command is ambiguous or unsupported, the LLM returns `clarification` text
  and **empty** edits. The sheet shows the question; **Apply is disabled**; the
  operator re-records. **v1 is one-shot — no multi-turn dialog.**
- Summary lines are generated deterministically from the validated ops (e.g.
  `setPreset cue 1 color → "Deep Blue" fade 5` renders as
  *"Cue 1 · color = Deep Blue (fade 5s)"*).

## 6. Anthropic integration

- **Messages API + forced tool-use.** One tool, `apply_show_edits`, whose
  `input_schema` *is* the §4 vocabulary. `tool_choice: { type: "tool", name:
  "apply_show_edits" }` forces structured output — we never parse prose. The tool
  input is `{ edits: [ShowEdit], clarification?: string }`.
- **Prompt caching** (required, per the claude-api skill). The system prompt
  (domain rules: the six pools + their MA3 numbers, group/fade/delay semantics, cue
  numbering, store modes, few-shot examples) + the tool schema are large and stable
  → marked with `cache_control` for a cache hit on every command. Only the variable
  parts — a **compact JSON snapshot of the current project** + the transcript — go
  uncached in the user message.
- **Project snapshot** sent to the model: a compact projection — each song with its
  1-based index, name, sequence; each cue with `n`, name, fade, delay; each action
  with group and its non-empty presets. Enough to resolve references; omits UUIDs and
  empty fields to stay small.
- **Model:** **Claude Sonnet 4.6** (`claude-sonnet-4-6`) by default — stronger
  interpretation of messy, freeform lighting commands, at the cost of some latency
  vs Haiku. A constant for now; no user-facing model picker in v1. (Haiku 4.5 remains
  a drop-in cheaper/faster alternative if latency ever matters more than accuracy.)
- `anthropic-version` header pinned; `max_tokens` modest (op lists are small).

## 7. Security & keys

- Two keys (OpenAI, Anthropic) live in the **iOS Keychain** (`AIKeyStore`), entered
  via `SecureField`s in Settings. Never written to the project JSON, logs, or
  `UserDefaults`.
- BYO-key: each operator (Jordan, Francesco) supplies their own. No keys ship in the
  binary or repo.
- Audio is uploaded to OpenAI; project snapshot + transcript go to Anthropic — both
  over HTTPS. A one-line note in Settings states this so it is not surprising.
- `NSMicrophoneUsageDescription` added to the app Info.plist.

## 8. Error handling & edge cases

| Situation | Behavior |
|---|---|
| Missing API key(s) | Mic action shows a prompt → "Add your keys in Settings"; deep-link to Settings |
| Mic permission denied | Inline explanation + link to system Settings |
| Whisper error / empty transcript | Toast + return to idle; nothing changes; offer retry |
| Anthropic error / timeout | Toast + return to idle; nothing changes; offer retry |
| LLM returns no edits + clarification | Preview shows the question; Apply disabled |
| Op references a missing target | Op skipped; surfaced as a warning in the preview before Apply |
| Recording too long | Soft cap (e.g. 30s) with an indicator; auto-stop |
| Apply with warnings | Allowed — valid ops apply, skipped ones are shown |

No partial half-applied state: apply is all-or-nothing against the precomputed copy.

## 9. Testing strategy

- **`ShowEditApplier` (pure)** — the bulk of the value. Table-driven tests: each op
  type → expected project transform; reference resolution (index vs name, missing
  target → warning); never-zero invariants (action blocks, songs) preserved; summary
  line text.
- **`ShowEdit` decoding** — tool-input JSON → `[ShowEdit]`, including unknown op →
  graceful skip/warn, and the `clarification`-only shape.
- **`AnthropicInterpreter` with a mocked transport** — given a canned Anthropic
  tool-use response, produce the right `InterpretedCommand`; verify the request body
  (tool schema, `tool_choice`, `cache_control` placement, project snapshot
  projection).
- **`WhisperTranscriber` with a mocked transport** — multipart request shape;
  response parsing; error mapping.
- **`VoiceCaptureController`** — state-machine transitions with mocked
  `Transcriber` + `CommandInterpreter` (happy path, each error path).
- Real API calls are validated by a **manual device smoke** (like the hub smoke),
  not in unit tests.

## 10. Scope — v1 in / out

**In:** the full §4 op vocabulary; Whisper transcription; Anthropic tool-use
interpretation with caching; preview + confirm; Keychain key entry; the error paths
in §8; unit tests per §9.

**Out (deferred):** multi-turn clarification dialog (v1 is one-shot); on-device
transcription fallback; streaming partial results; a user-facing model picker;
voice that triggers "Send → MA"; localization of the voice UI; conversation history /
"undo last voice command" beyond the app's normal editing.

## 11. Open questions for plan stage

- Exact wording/format of the deterministic summary lines (cosmetic; settle in the plan).
- Whisper `language` hint (force `en`/`it` vs auto) — default auto for v1.
- Soft recording cap value (30s assumed).

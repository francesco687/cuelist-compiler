# Monorepo Housekeeping Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restructure the single-file Cuelist Compiler web app into a collaboration-ready monorepo with a shared MA3 command contract, a no-build module split, and contribution infrastructure — without changing any runtime behaviour.

**Architecture:** Move the existing app into `web/`, split its one HTML file into `web/css/styles.css` + ordered `web/js/*.js` files (plain `<script src>`, no build, functions stay global with a per-file `CC.<module>` public-surface manifest). Extract the MA3 command sequence into `shared/ma3-command-spec.md`. Add `ios/` and `docs/` placeholders and collaboration infra.

**Tech Stack:** Vanilla HTML/CSS/JS (no framework, no build). Node.js only for the existing OSC proxy. Git/GitHub for collaboration.

---

## Conventions for this plan

- **Behaviour-preserving:** Tasks 2–3 move code **verbatim**. Do not edit logic, rename functions, or change strings. The only additions are file header comments and the `CC.<module>` manifest block at each file's end.
- **Source anchors:** Line numbers below refer to the **original committed `cuelist-compiler.html`** (2,656 lines). After Task 1 it lives at `web/index.html`; after Task 2 the `<style>` block is gone so line numbers shift — always cut from the pre-split content, using function **names** as the source of truth, line numbers as a guide.
- **No automated test suite** exists and none is added (per the design's non-goals). Verification is `node --check` for syntax + a **human smoke checkpoint** (Task 9) using the `examples/SONG_1.*` regression anchor. Steps that say "MANUAL" require a person with a browser; a subagent should stop at that checkpoint and report.
- **Namespace manifest pattern** added to the bottom of each JS module:

```js
// --- public surface (functions remain global; this documents the module API) ---
window.CC = window.CC || {};
CC.state = { newProject, activeSong, saveState, loadState /* ...all public names... */ };
```

- Every commit ends with the trailer:
  `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`

---

## File map (decomposition reference)

| Target file | Source functions / blocks (by name) | Original lines |
|-------------|-------------------------------------|----------------|
| `web/css/styles.css` | entire `<style>` body (strip tags) | 7–733 |
| `web/index.html` | `<!DOCTYPE>`…head + body markup only; `<link>` + 8 `<script>` tags | 1–5, 736–865 |
| `web/js/constants.js` | `STORAGE_KEY*`, `POOLS`, `POOL_NUM`, `FPS`, `OSC_PROXY_URL`, `OSC_SEND_INTERVAL_MS`; `POOL_ACCENT`, `POOL_TITLE`, `POOL_ABBR`, `ACTION_COLORS` | 870–878, 1117–1148 |
| `web/js/util.js` | `timecodeToSeconds`, `secondsToTimecode`, `secondsToMMSS`, `genId`, `escapeHtml`, `download` | 880–903, 923–925, 1304–1308, 2358–2368 |
| `web/js/state.js` | `let state/moods/defaults/pools` init; `newSong`, `newProject`, `activeSong`, `newCue`, `newAction`, `migrateActions`, `migrateCues`, `migrateState`, `loadState`, `saveState`, `loadMoods`, `saveMoods`, `newMood`, `makeDefaults`, `loadDefaults`, `saveDefaults`, `emptyPools`, `loadPools`, `savePools`, `cloneActions`, `actionIsEmpty`, `parsePoolsPaste`, `saveProject`, `loadProject`, `parseCsv`, `importCsv` | 905–908, 927–1115, 1255–1302, 1789–1818, 2256–2356 |
| `web/js/compile.js` | `songToLuaEntry`, `buildLua`, `buildCmdLines`, `exportLua`, `exportAllLua` | 1640–1787 |
| `web/js/audio.js` | audio state vars; `loadAudioFile`, `setActiveAudioFromCache`, `setChannelMute`, `drawWaveform`, `renderAudioPanel`, `wireLoadAudio`, `togglePlay`, `startPlayheadLoop`, `stopPlayheadLoop`, `updatePlayhead`, `updateCurrentMarker`, `renderMarkers` | 910–921, 1923–2254 |
| `web/js/osc.js` | osc state vars; `setOscState`, `oscConnect`, `oscSendLine`, `sendCmdLinesViaOsc`, `sendCurrentViaOsc`, `sendAllViaOsc` | 2497–2601 |
| `web/js/render.js` | `_colorPopoverOnPick`, `openColorPopover`, `closeColorPopover`, `colorPopoverOutsideClick`, `_poolPickerState`, `openPoolPicker`, `closePoolPicker`, `pickPoolValue`, `renderPoolPickerGrid`, `render`, `renderSidebar`, `cueSummary`, `renderCue`, `renderAction`, `openMoodModal`, `closeMoodModal`, `openDefaultsModal`, `closeDefaultsModal`, `renderDefaultsModal`, `renderMoodModal`, `renderMoodCard`, `openPoolsModal`, `closePoolsModal`, `refreshPoolsStatus` | 1150–1253, 1310–1638, 1820–1921, 2442–2457 |
| `web/js/main.js` | every top-level `addEventListener` / wiring block, `keydown`/`resize` handlers, `wireLoadAudio()` call, and the final `render(); oscConnect();` | 2370–2440, 2458–2495, 2603–2652 |

**Load order (fixed):** `constants → util → state → compile → audio → osc → render → main`. Dependencies only point upward; all cross-file references are function calls resolved at runtime (every file is loaded before any user interaction), so global ordering is safe.

`plugins/` (the `export_pools.lua` MA3 helper) and `examples/` (SONG_1 fixtures) stay at the repo root — `examples/` is the shared regression anchor referenced by the spec.

---

## Task 1: Restructure into monorepo layout

**Files:**
- Move: `cuelist-compiler.html` → `web/index.html`
- Create dirs: `web/css/`, `web/js/`, `shared/`, `ios/`, `docs/` (already exists), `.github/ISSUE_TEMPLATE/`
- `proxy/`, `plugins/`, `examples/` stay in place

- [ ] **Step 1: Create the new directories**

```bash
cd ~/cuelist-compiler
mkdir -p web/css web/js shared ios .github/ISSUE_TEMPLATE
```

- [ ] **Step 2: Move the app file, preserving history**

```bash
git mv cuelist-compiler.html web/index.html
```

- [ ] **Step 3: Verify the move**

Run: `git status --short && ls web/`
Expected: `R  cuelist-compiler.html -> web/index.html`, and `web/` contains `index.html` (plus empty `css/` `js/` which git won't show).

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "chore: move web app into web/ for monorepo layout

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Extract CSS into `web/css/styles.css`

**Files:**
- Create: `web/css/styles.css`
- Modify: `web/index.html` (remove `<style>` block, add `<link>`)

- [ ] **Step 1: Create `web/css/styles.css`**

Cut the entire contents **between** `<style>` (original line 6) and `</style>` (original line 734) — i.e. original lines 7–733 — verbatim into `web/css/styles.css`. Do not change any rule.

- [ ] **Step 2: Replace the `<style>` block in `web/index.html` with a link**

In `web/index.html` `<head>`, delete the whole `<style>…</style>` block and put in its place:

```html
<link rel="stylesheet" href="css/styles.css">
```

- [ ] **Step 3: MANUAL — verify styling intact**

Open `web/index.html` in a browser. The dark themed UI must look identical (sidebar, cue cards, buttons styled). If it's unstyled, the `<link>` path or the cut boundaries are wrong.

- [ ] **Step 4: Commit**

```bash
git add web/css/styles.css web/index.html
git commit -m "chore: extract stylesheet into web/css/styles.css

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Split the JavaScript into `web/js/*.js`

**Files:**
- Create: `web/js/{constants,util,state,compile,audio,osc,render,main}.js`
- Modify: `web/index.html` (replace the single `<script>` block with 8 `<script src>` tags)

Use the **File map** table above for exactly which functions go in each file. Move bodies **verbatim**. Add to each file: (1) a top header comment, (2) the `CC.<module>` manifest at the bottom. Do NOT add `'use strict';` per file — it is unnecessary for this pass and changing strictness could alter behaviour; leave the code as-is.

- [ ] **Step 1: Create `web/js/constants.js`**

Header, then the constants from original lines 870–878 and 1117–1148, then manifest:

```js
// constants.js — shared constants. No dependencies. Load first.
'use strict';

// ...move STORAGE_KEY*, POOLS, POOL_NUM, FPS, OSC_PROXY_URL, OSC_SEND_INTERVAL_MS (orig 870-878)
// ...move POOL_ACCENT, POOL_TITLE, POOL_ABBR, ACTION_COLORS (orig 1117-1148) verbatim...

window.CC = window.CC || {};
CC.constants = { POOLS, POOL_NUM, FPS, POOL_ACCENT, POOL_TITLE, POOL_ABBR, ACTION_COLORS };
```

(Keep `'use strict';` only in this first file is unnecessary — remove the line if it was not in the original module top. The original had `'use strict';` once at script top (line 868); place it once, here, at the top of `constants.js`, since this is the first script loaded.)

- [ ] **Step 2: Create `web/js/util.js`**

```js
// util.js — pure helpers (timecode, ids, escaping, download). Depends on: constants (FPS).

// ...move timecodeToSeconds, secondsToTimecode, secondsToMMSS (orig 880-903),
//    genId (923-925), escapeHtml (1304-1308), download (2358-2368) verbatim...

window.CC = window.CC || {};
CC.util = { timecodeToSeconds, secondsToTimecode, secondsToMMSS, genId, escapeHtml, download };
```

- [ ] **Step 3: Create `web/js/state.js`**

```js
// state.js — data model, persistence, migration, project/CSV IO.
// Depends on: constants, util. Defines the global `state`, `moods`, `defaults`, `pools`.

// ...move the init lines `let state = loadState() || newProject();`
//    `let moods = loadMoods(); let defaults = loadDefaults(); let pools = loadPools();` (orig 905-908)
// ...move newSong..savePools (927-1115), cloneActions/actionIsEmpty/parsePoolsPaste (1255-1302),
//    saveProject/loadProject (1789-1818), parseCsv/importCsv (2256-2356) verbatim...

window.CC = window.CC || {};
CC.state = {
  newSong, newProject, activeSong, newCue, newAction,
  migrateState, loadState, saveState,
  loadMoods, saveMoods, newMood,
  makeDefaults, loadDefaults, saveDefaults,
  emptyPools, loadPools, savePools,
  cloneActions, actionIsEmpty, parsePoolsPaste,
  saveProject, loadProject, parseCsv, importCsv
};
```

- [ ] **Step 4: Create `web/js/compile.js`**

```js
// compile.js — SINGLE SOURCE OF TRUTH for the MA3 command sequence.
// buildLua() (exported .lua plugin) and buildCmdLines() (live OSC) MUST emit the
// same sequence. Any change here must also update shared/ma3-command-spec.md in
// the same PR. Depends on: constants (POOLS, POOL_NUM), state (defaults, activeSong, state), util (download).

// ...move songToLuaEntry, buildLua, buildCmdLines, exportLua, exportAllLua (orig 1640-1787) verbatim...

window.CC = window.CC || {};
CC.compile = { songToLuaEntry, buildLua, buildCmdLines, exportLua, exportAllLua };
```

- [ ] **Step 5: Create `web/js/audio.js`**

```js
// audio.js — WebAudio decode/playback, channel gain, waveform, playhead, cue markers.
// Depends on: constants, util, state, render (calls render()/activeSong() at runtime).

// ...move audio state vars (orig 910-921) and loadAudioFile..renderMarkers (1923-2254) verbatim...

window.CC = window.CC || {};
CC.audio = {
  loadAudioFile, setActiveAudioFromCache, setChannelMute, drawWaveform,
  renderAudioPanel, wireLoadAudio, togglePlay,
  startPlayheadLoop, stopPlayheadLoop, updatePlayhead, updateCurrentMarker, renderMarkers
};
```

- [ ] **Step 6: Create `web/js/osc.js`**

```js
// osc.js — WebSocket client to the proxy; throttled command send; status pill.
// Depends on: constants (OSC_PROXY_URL, OSC_SEND_INTERVAL_MS), compile (buildCmdLines), state (activeSong, state).

// ...move osc state vars + setOscState, oscConnect, oscSendLine, sendCmdLinesViaOsc,
//    sendCurrentViaOsc, sendAllViaOsc (orig 2497-2601) verbatim...

window.CC = window.CC || {};
CC.osc = { setOscState, oscConnect, sendCurrentViaOsc, sendAllViaOsc };
```

- [ ] **Step 7: Create `web/js/render.js`**

```js
// render.js — all DOM rendering: sidebar, cues, actions, modals, popovers, pickers.
// Depends on: constants, util, state, audio (renderMarkers). Provides render().

// ...move color popover (orig 1150-1192), pool picker (1194-1253),
//    render/renderSidebar/cueSummary/renderCue/renderAction (1310-1638),
//    mood + defaults modal renderers (1820-1921), pools modal open/close/refresh (2442-2457) verbatim...

window.CC = window.CC || {};
CC.render = {
  render, renderSidebar, renderCue, renderAction,
  openColorPopover, openPoolPicker,
  openMoodModal, closeMoodModal, openDefaultsModal, closeDefaultsModal,
  renderMoodModal, renderDefaultsModal,
  openPoolsModal, closePoolsModal, refreshPoolsStatus
};
```

- [ ] **Step 8: Create `web/js/main.js`**

```js
// main.js — boot + all event wiring. Loaded LAST so every function above exists.
// Depends on: every other module.

// ...move ALL top-level addEventListener wiring and handlers:
//    orig 2370-2440 (header/cue/song/toolbar/mood/defaults wiring),
//    2458-2495 (pools modal wiring),
//    2603-2649 (osc buttons, keydown, wireLoadAudio() call, resize, clearAll, poolpicker wiring),
//    2651-2652 (render(); oscConnect();) verbatim...
```

main.js needs no manifest (it exposes nothing).

- [ ] **Step 9: Rewrite `web/index.html` as a shell**

Replace the entire `<script>…</script>` block (originally 867–2653) with the 8 ordered tags placed at the **end of `<body>`** (so the DOM exists when wiring runs). The final `web/index.html` is:

```html
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Cuelist Compiler</title>
<link rel="stylesheet" href="css/styles.css">
</head>
<body>
  <!-- ...existing body markup, original lines 737-865, unchanged... -->

  <script src="js/constants.js"></script>
  <script src="js/util.js"></script>
  <script src="js/state.js"></script>
  <script src="js/compile.js"></script>
  <script src="js/audio.js"></script>
  <script src="js/osc.js"></script>
  <script src="js/render.js"></script>
  <script src="js/main.js"></script>
</body>
</html>
```

- [ ] **Step 10: Syntax-check every module**

Run: `node --check web/js/constants.js && node --check web/js/util.js && node --check web/js/state.js && node --check web/js/compile.js && node --check web/js/audio.js && node --check web/js/osc.js && node --check web/js/render.js && node --check web/js/main.js && echo "ALL OK"`
Expected: `ALL OK` (no syntax errors). `node --check` parses without executing, so browser globals like `localStorage`/`document` are fine.

- [ ] **Step 11: Confirm no code was lost**

Run: `git show HEAD:web/index.html | grep -c 'function '` to count functions in the pre-split file, then `cat web/js/*.js | grep -c 'function '`. The js/ total should be **>=** the original (anonymous handlers may add a few). Spot-check that `buildCmdLines`, `renderCue`, `loadAudioFile`, `migrateState`, `oscConnect` each appear exactly once across `web/js/*.js`:

Run: `grep -rl 'function buildCmdLines' web/js/ | wc -l`
Expected: `1`

- [ ] **Step 12: MANUAL — smoke test the split app**

Open `web/index.html`. Open DevTools console (must be **zero** errors on load). Then: add a song, add a cue with a group + a color preset, set a fade. Click **Export current .lua** — a file downloads. Confirm the UI behaves exactly as before. (Full regression is Task 9.)

- [ ] **Step 13: Commit**

```bash
git add web/index.html web/js/
git commit -m "chore: split web app into no-build js modules

Functions remain global (zero call-site changes, behaviour preserved);
each module exposes a CC.<module> public-surface manifest. Loaded via
ordered <script src> tags. compile.js is the single source of truth for
the MA3 command sequence.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Write the shared MA3 command contract

**Files:**
- Create: `shared/ma3-command-spec.md`

- [ ] **Step 1: Create `shared/ma3-command-spec.md`** with this exact content:

````markdown
# MA3 Command Contract

The single source of truth for the grandMA3 command sequence Cuelist Compiler
emits. **Both** frontends implement this identically:

- Web: `web/js/compile.js` — `buildLua()` (exported `.lua` plugin) and
  `buildCmdLines()` (live OSC). `compile.js` is the executable reference.
- iOS: the native Swift command builder (to be written) must reproduce it.

> **Rule:** any change to the sequence updates this file **and** `web/js/compile.js`
> in the same pull request. They must never diverge.

## Pool numbers

| Pool | Number |
|------|--------|
| dimmer | 1 |
| position | 2 |
| gobo | 3 |
| color | 4 |
| beam | 5 |
| focus | 6 |

## Store mode

A show is stored with one flag, chosen by the user:

- `/Overwrite` (default)
- `/Merge`

Every `Store` also carries `/NoConfirmation`.

## Per-cue sequence

For each song (in show order), for each cue (sorted ascending by cue number):

1. `ClearAll`
2. For each **group block** whose group name is non-empty:
   - `Group "<groupName>"`
   - For each of the 6 pools, in order `color, dimmer, position, gobo, beam, focus`,
     whose preset name is non-empty:
     - `At Preset <poolNumber>."<presetName>"`
     - If a fade value resolves (see Fade/Delay resolution): `Fade <f> FeatureGroup <poolNumber>`
     - If a delay value resolves: `Delay <d> FeatureGroup <poolNumber>`
3. Store the cue:
   - With a cue name: `Store Sequence <seq> Cue <n> "<cueName>" <FLAG> /NoConfirmation`
   - Without a cue name: `Store Sequence <seq> Cue <n> <FLAG> /NoConfirmation`
4. If the cue has a fade: `Set Sequence <seq> Cue <n> Fade <f>`
5. If the cue has a delay: `Set Sequence <seq> Cue <n> Delay <d>`

After all songs and cues: a final `ClearAll`.

## Fade / Delay resolution

Per preset attribute, the value used is:

1. The preset's own `fade`/`delay` if non-empty, else
2. The per-pool default (`defaults[pool].fade` / `.delay`) if non-empty, else
3. Omitted (no `Fade`/`Delay` line emitted).

Cue-level `fade`/`delay` have no default fallback — emitted only if set on the cue.

## String escaping

Group, preset, and cue names have `"` replaced with `\"`. Names are trimmed.

## Notes

- `buildLua()` wraps this sequence in a Lua plugin that calls `Cmd(...)` per line
  and prints progress; `buildCmdLines()` returns the raw command strings for OSC.
  Both must produce the **same ordered command list**.
- The live-OSC path requires MA3 OSC **Echo Input = Yes** for `/cmd` to dispatch.
````

- [ ] **Step 2: Commit**

```bash
git add shared/ma3-command-spec.md
git commit -m "docs: add shared MA3 command contract

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: Write the architecture doc

**Files:**
- Create: `docs/architecture.md`

- [ ] **Step 1: Create `docs/architecture.md`** with this exact content:

````markdown
# Architecture

Cuelist Compiler builds per-song grandMA3 cuelists and ships them either as a
`.lua` plugin or live over OSC. It is a monorepo with two frontends sharing one
command contract.

```
                ┌─────────────────────────────┐
                │  shared/ma3-command-spec.md  │  ← the contract
                └──────────────┬──────────────┘
                               │ implemented by
            ┌──────────────────┴───────────────────┐
            ▼                                       ▼
   web/ (HTML/CSS/JS, no build)            ios/ (native SwiftUI — planned)
   compile.js = reference impl
            │                                       │
            │  .lua export        live OSC          │ live OSC
            ▼                        ▼               ▼
   paste into MA3 plugin      proxy/ (WS→OSC) ──► grandMA3 (onPC / console)
```

## Components

- **`web/`** — the authoring app. Open `web/index.html` in a browser; no build,
  no dependencies. Modules load in order:
  `constants → util → state → compile → audio → osc → render → main`.
  Functions are global; each module also exposes a `CC.<module>` manifest of its
  public surface. State persists in `localStorage`.
- **`shared/ma3-command-spec.md`** — the exact MA3 command sequence both frontends
  emit. `web/js/compile.js` is its executable reference.
- **`ios/`** — planned native SwiftUI frontend. Reuses the proxy and implements
  the shared contract; not yet built.
- **`proxy/`** — a small Node WebSocket→OSC bridge (`ws://127.0.0.1:8765` →
  UDP OSC to MA3) used by the live-send path. `start.sh` (macOS/Linux) /
  `start.bat` (Windows).
- **`plugins/export_pools.lua`** — MA3 plugin that exports Groups + the 6 preset
  pools so the web app can autocomplete real names.
- **`examples/`** — `SONG_1.json` (a saved project) and `SONG_1.lua` (its export),
  used as the regression anchor when changing `compile.js`.

## Data model

`state → songs[] → cues[] → actions[] → presets{color,dimmer,position,gobo,beam,focus}`,
plus sibling stores `moods`, `defaults`, `pools`. A migration layer
(`migrateState`) upgrades older saved formats; preserve it when adding fields.
````

- [ ] **Step 2: Commit**

```bash
git add docs/architecture.md
git commit -m "docs: add architecture overview

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: Add collaboration infrastructure

**Files:**
- Create: `CONTRIBUTING.md`, `.editorconfig`, `CHANGELOG.md`,
  `.github/PULL_REQUEST_TEMPLATE.md`,
  `.github/ISSUE_TEMPLATE/bug_report.md`, `.github/ISSUE_TEMPLATE/feature_request.md`
- Modify: `.gitignore`

- [ ] **Step 1: Create `.editorconfig`**

```ini
root = true

[*]
charset = utf-8
end_of_line = lf
insert_final_newline = true
trim_trailing_whitespace = true
indent_style = space
indent_size = 2

[*.md]
trim_trailing_whitespace = false
```

- [ ] **Step 2: Append to `.gitignore`**

Read the existing `.gitignore` first, then append (do not duplicate existing lines):

```gitignore

# macOS
.DS_Store

# Node (proxy)
node_modules/
proxy/node_modules/

# Xcode / Swift (ios)
ios/build/
ios/DerivedData/
*.xcuserstate
xcuserdata/
.swiftpm/
```

- [ ] **Step 3: Create `CONTRIBUTING.md`**

````markdown
# Contributing

Two-person project. Keep `main` releasable; do all work on branches and merge via
pull request.

## Workflow

1. Branch off `main`: `feat/<thing>`, `fix/<thing>`, or `chore/<thing>`.
2. Make focused commits. Split work by module (e.g. one of you in `audio.js`/`osc.js`,
   the other in `compile.js`/`render.js`) to avoid same-file conflicts.
3. Open a PR. The **other** person reviews and merges. No direct pushes to `main`.
4. Pull `main` before starting new work.

## Running the web app

Open `web/index.html` in Chrome or Edge. No build, no install. Edits to
`web/js/*.js` or `web/css/styles.css` show on refresh.

## Running the OSC proxy (live send)

- macOS/Linux: `cd proxy && ./start.sh`
- Windows: `cd proxy && start.bat`

First run installs `ws`; then it bridges `ws://127.0.0.1:8765` → OSC UDP to MA3.
MA3 needs OSC Input enabled with **Echo Input = Yes** (see `proxy/README.md`).

## The command contract

`web/js/compile.js` is the single source of truth for the MA3 command sequence,
documented in `shared/ma3-command-spec.md`. **If you change the command sequence,
update both files in the same PR.** `buildLua()` and `buildCmdLines()` must stay
in sync with each other.

## Manual smoke test (before opening a PR)

There is no automated test suite. Before requesting review:

1. Open `web/index.html` — no console errors on load.
2. Load `examples/SONG_1.json` (Load Project) and Export `.lua`; the command
   logic should still match `examples/SONG_1.lua`.
3. Import a CuePoints `.csv` — songs/cues appear.
4. Load an audio file — waveform + cue markers render, playhead moves.
5. With the proxy running, the OSC pill reaches "online".

## Commit messages

Conventional prefixes: `feat:`, `fix:`, `chore:`, `docs:`. Imperative mood.

## Branch protection (repo owner / admin only)

Enable on `main`: **Settings → Branches → Add rule**: require a pull request
before merging, require 1 approval, dismiss stale approvals. (A non-admin
collaborator cannot set this.)
````

- [ ] **Step 4: Create `.github/PULL_REQUEST_TEMPLATE.md`**

```markdown
## What

<!-- What does this change do? -->

## Why

<!-- Motivation / linked issue -->

## Testing

<!-- What did you do to verify? Ran the manual smoke test? -->

- [ ] Ran the manual smoke test in CONTRIBUTING.md
- [ ] If I changed the MA3 command sequence, I updated **both**
      `web/js/compile.js` and `shared/ma3-command-spec.md`
```

- [ ] **Step 5: Create `.github/ISSUE_TEMPLATE/bug_report.md`**

```markdown
---
name: Bug report
about: Something doesn't work as expected
labels: bug
---

**What happened**

**What you expected**

**Steps to reproduce**
1.

**Environment** (browser / OS / MA3 version, onPC or console)
```

- [ ] **Step 6: Create `.github/ISSUE_TEMPLATE/feature_request.md`**

```markdown
---
name: Feature request
about: Suggest an idea
labels: enhancement
---

**Problem / use case**

**Proposed solution**

**Which frontend** (web / iOS / both)
```

- [ ] **Step 7: Create `CHANGELOG.md`**

```markdown
# Changelog

All notable changes to this project are documented here. Format based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Changed
- Restructured into a monorepo (`web/ ios/ proxy/ shared/ docs/`).
- Split the single-file web app into no-build modules under `web/js/` with a
  `CC.<module>` public surface; extracted CSS to `web/css/styles.css`.

### Added
- `shared/ma3-command-spec.md` — the MA3 command contract both frontends implement.
- `docs/architecture.md`; contribution infra (CONTRIBUTING, PR/issue templates,
  editorconfig, expanded gitignore, changelog).
- `proxy/start.sh` for macOS/Linux.
```

- [ ] **Step 8: Commit**

```bash
git add .editorconfig .gitignore CONTRIBUTING.md CHANGELOG.md .github/
git commit -m "chore: add collaboration infra (contributing, templates, editorconfig, changelog)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: Make the proxy cross-platform

**Files:**
- Create: `proxy/start.sh`
- Move: `proxy/README.txt` → `proxy/README.md`

- [ ] **Step 1: Read `proxy/start.bat`** to mirror its behaviour.

Run: `cat proxy/start.bat`
Expected: shows it installs `ws` if missing then runs `node ws2osc.js`.

- [ ] **Step 2: Create `proxy/start.sh`**

```sh
#!/usr/bin/env bash
# Start the WebSocket->OSC bridge (macOS/Linux). Mirrors start.bat.
set -e
cd "$(dirname "$0")"
if [ ! -d node_modules ]; then
  echo "Installing dependencies (ws)..."
  npm install
fi
exec node ws2osc.js
```

- [ ] **Step 3: Make it executable**

```bash
chmod +x proxy/start.sh
git update-index --chmod=+x proxy/start.sh 2>/dev/null || true
```

- [ ] **Step 4: Convert the proxy readme to Markdown**

```bash
git mv proxy/README.txt proxy/README.md
```

Then read `proxy/README.md` and, if it is plain text, lightly format it as
Markdown (a `#` title, fenced code for commands) **without changing any
instructions or values** (ports, IPs, the Echo Input note).

- [ ] **Step 5: Verify the script is valid shell**

Run: `bash -n proxy/start.sh && echo "OK"`
Expected: `OK`

- [ ] **Step 6: Commit**

```bash
git add proxy/start.sh proxy/README.md
git commit -m "chore: add cross-platform proxy start script + markdown readme

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 8: Rewrite the root README

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Read the current `README.md`** to preserve the accurate feature descriptions and MA3 setup details.

- [ ] **Step 2: Rewrite `README.md`** as a monorepo entry point. Use this structure, importing the existing feature/quick-start/OSC prose (updating paths: `cuelist-compiler.html` → `web/index.html`, `plugins/` and `proxy/` unchanged):

````markdown
# Cuelist Compiler

Author per-song cuelists for grandMA3 and ship them as a runnable Lua plugin or
send them live over OSC.

## Repo layout

| Path | What |
|------|------|
| `web/` | The authoring web app (open `web/index.html` — no build). |
| `ios/` | Native SwiftUI frontend (planned). |
| `proxy/` | WebSocket→OSC bridge for live send. |
| `shared/` | `ma3-command-spec.md` — the command contract both frontends implement. |
| `plugins/` | `export_pools.lua` — MA3 plugin to import Group + preset pool names. |
| `examples/` | Sample project + its `.lua` export (regression anchor). |
| `docs/` | Architecture and design docs. |

## Quick start (web)

1. Open `web/index.html` in Chrome or Edge.
2. (Recommended) Run `plugins/export_pools.lua` once on your MA3 show to import
   Groups + preset pool names for autocomplete.
3. Import a CuePoints `.csv`, or add songs manually.
4. Fill in cues (Group + preset names + fade/delay).
5. **Export .lua** and paste into a gma3 plugin slot, or use **live OSC** below.

<!-- import the existing Features and OSC live-mode sections here, paths updated -->

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Two-person project; work on branches,
merge via PR.
````

Preserve the existing **Features** and **OSC live mode** sections from the old
README verbatim (only fixing file paths).

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: rewrite README as monorepo entry point

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 9: Final verification + PR

**Files:** none (verification + PR only)

- [ ] **Step 1: Tree sanity check**

Run: `git ls-files | sort` and confirm the layout matches the design: `web/index.html`, `web/css/styles.css`, `web/js/{constants,util,state,compile,audio,osc,render,main}.js`, `shared/ma3-command-spec.md`, `docs/architecture.md`, `CONTRIBUTING.md`, `CHANGELOG.md`, `.editorconfig`, `.github/...`, `proxy/start.sh`, `proxy/README.md`.

- [ ] **Step 2: All modules still parse**

Run: `for f in web/js/*.js; do node --check "$f" || echo "FAIL $f"; done; echo done`
Expected: `done` with no `FAIL`.

- [ ] **Step 3: MANUAL — full regression against the SONG_1 anchor**

1. Open `web/index.html` (no console errors).
2. **Load Project** → `examples/SONG_1.json`.
3. **Export current .lua**. Open the downloaded file.
4. Compare its command logic to `examples/SONG_1.lua` — the `Group`/`At Preset`/
   `Store`/`Set` lines and order must match (only the `-- Generated:` timestamp
   comment may differ).
5. Import a CuePoints `.csv` → songs appear. Load an audio file → waveform +
   markers render. Start the proxy (`./proxy/start.sh`) → OSC pill goes "online".

If all pass, the restructure changed structure only, not behaviour.

- [ ] **Step 4: Push and open the PR**

```bash
git push -u origin chore/monorepo-housekeeping
gh pr create --title "Monorepo housekeeping: structure, module split, shared contract" \
  --body "$(cat <<'EOF'
Restructures the single-file app into a collaboration-ready monorepo. No behaviour change.

## What
- Monorepo layout: `web/ ios/ proxy/ shared/ docs/`.
- Split the web app into no-build `web/js/*.js` modules + `web/css/styles.css`.
  Functions stay global (zero call-site changes); each module exposes a
  `CC.<module>` public-surface manifest.
- `shared/ma3-command-spec.md` — the MA3 command contract both frontends implement.
- `docs/architecture.md`; contribution infra (CONTRIBUTING, PR/issue templates,
  editorconfig, gitignore, changelog).
- `proxy/start.sh` for macOS/Linux.

## Verification
Behaviour-preserving. Verified by loading `examples/SONG_1.json` and confirming
the `.lua` export matches `examples/SONG_1.lua`, plus a manual smoke pass
(CSV import, audio/markers, OSC online). `node --check` passes on all modules.

See `docs/design/2026-06-04-monorepo-housekeeping.md` for the full design.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 5: Report the PR URL** to the user for Francesco's review.

---

## Self-review notes

- **Spec coverage:** monorepo layout (T1), CSS+JS split with no-build modules (T2–T3),
  shared command contract (T4), architecture doc (T5), collaboration infra incl.
  branch-protection-as-doc (T6), cross-platform proxy (T7), README rewrite (T8),
  SONG_1 regression + PR (T9). All design sections mapped.
- **Namespace decision:** realized as a per-module `CC.<module>` manifest over global
  functions (behaviour-preserving) rather than IIFE encapsulation requiring call-site
  rewrites — noted in Task 3 and to be confirmed with the user.
- **No automated tests** by design; verification is `node --check` + the manual
  SONG_1 anchor. MANUAL steps are explicit checkpoints for subagent execution.
- **Branch protection** requires repo admin (likely the owner, not the collaborator);
  delivered as documentation, not an automated step.

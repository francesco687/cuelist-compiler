# Monorepo Housekeeping — Design

**Date:** 2026-06-04
**Branch:** `chore/monorepo-housekeeping`
**Status:** Proposed (awaiting review)

## Purpose

Cuelist Compiler is currently a single-file web app (`cuelist-compiler.html`)
maintained by two collaborators. A native iPhone (SwiftUI) frontend is planned,
sharing the same MA3 command logic as the web app. Before that work starts, this
pass makes the repository ready for long-term, two-person collaboration and lays
the structure the iOS app will slot into.

This pass is **housekeeping only** — no new product features. The web app's
behaviour must be byte-for-byte unchanged.

## Goals

1. Restructure the repo into a monorepo with clear homes for `web/`, `ios/`,
   `proxy/`, and the `shared/` contract between them.
2. Establish a single source of truth for the MA3 command sequence so the web
   app and the future Swift app can never drift apart.
3. Split the 2,650-line HTML file into focused, separately-editable modules so
   two people can work in parallel without constant merge conflicts.
4. Add lightweight collaboration infrastructure (contributing guide, PR/issue
   templates, changelog, editorconfig, gitignore).

## Non-goals

- No automated test suite (the app has none; adding one is a separate decision).
- No build toolchain. The web app must still run by opening the HTML file
  directly in a browser — no `npm install`, no dev server.
- No new features, no UI changes, no behavioural changes.
- The iOS app itself is **not** built here — only its placeholder and the
  contract it will implement.

## Key decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| iOS relationship | Native Swift, shared backend | iOS is its own codebase reusing the OSC proxy + command contract; web app stays. |
| Repo shape | Monorepo (`web/ ios/ proxy/ shared/ docs/`) | One place for the whole product; clean iOS slot. |
| Module system | Plain namespaced `<script src>` (no build) | Preserves the zero-setup "open the file in Chrome" property, which matters more as the web app becomes the secondary surface. Migratable to ES modules later if ever needed. |
| First-pass scope | Full cleanup (move + infra + shared spec + file split) | Cleanest foundation before feature/iOS work begins. |

## Target structure

```
cuelist-compiler/
├─ README.md              # rewritten: monorepo overview, links to web/ + ios/
├─ LICENSE                # unchanged (MIT)
├─ CHANGELOG.md           # new — Keep a Changelog format
├─ CONTRIBUTING.md        # new — branch/PR workflow + how to run/test
├─ .editorconfig          # new — 2-space, LF, utf-8, trim trailing ws
├─ .gitignore             # expanded — macOS, node, Xcode/Swift
├─ .github/
│  ├─ PULL_REQUEST_TEMPLATE.md
│  └─ ISSUE_TEMPLATE/{bug_report,feature_request}.md
├─ docs/
│  ├─ architecture.md     # how web / ios / proxy / shared fit together
│  └─ design/             # design docs (this file)
├─ shared/
│  └─ ma3-command-spec.md # ⭐ the contract both apps emit
├─ web/
│  ├─ index.html          # was cuelist-compiler.html — now a thin shell
│  ├─ css/styles.css      # extracted from <style>
│  └─ js/
│     ├─ constants.js     # POOLS, POOL_NUM, accent/title maps, storage keys, OSC cfg
│     ├─ util.js          # timecode helpers, genId, escapeHtml, download
│     ├─ state.js         # model, persistence, migration, activeSong, clone/empty checks
│     ├─ compile.js       # buildLua + buildCmdLines  ← single source of truth
│     ├─ audio.js         # WebAudio, waveform, playhead, markers
│     ├─ osc.js           # WebSocket client
│     ├─ render.js        # render + sidebar/cue/action + all modals + color popover
│     └─ main.js          # boot + event wiring (the glue)
├─ ios/
│  └─ README.md           # placeholder pointing at shared/ma3-command-spec.md
└─ proxy/
   ├─ ws2osc.js, package.json, package-lock.json   # unchanged
   ├─ start.bat           # Windows
   ├─ start.sh            # new — macOS/Linux (only .bat exists today)
   └─ README.md           # converted from README.txt
```

## The module split (behaviour-preserving)

The split is a pure cut-and-reorganize. No logic changes. Each file exposes its
public surface under a single global namespace to avoid the "everything is a bare
global" hazard:

```js
// state.js
window.CC = window.CC || {};
CC.state = (function () { /* existing logic, unchanged */ return { /* public fns */ }; })();
```

**Load order** (ordered `<script src>` tags in `index.html`), dependencies only
ever point upward in this list:

```
constants → util → state → compile → audio → osc → render → main
```

**Module responsibilities:**

- `constants.js` — `POOLS`, `POOL_NUM`, `FPS`, OSC URL/interval, `POOL_ACCENT`,
  `POOL_TITLE`, `POOL_ABBR`, `ACTION_COLORS`, the four `STORAGE_KEY_*`.
- `util.js` — `timecodeToSeconds`, `secondsToTimecode`, `secondsToMMSS`,
  `genId`, `escapeHtml`, `download`.
- `state.js` — `state`/`moods`/`defaults`/`pools` model; `new*`, `load*`,
  `save*`, `migrate*`; `activeSong`, `cloneActions`, `actionIsEmpty`,
  `parsePoolsPaste`.
- `compile.js` — `songToLuaEntry`, `buildLua`, `buildCmdLines`. The single source
  of truth for the MA3 command sequence. File header restates the
  "keep buildLua and buildCmdLines in sync, and in sync with
  shared/ma3-command-spec.md" rule.
- `audio.js` — WebAudio decode/playback, per-channel gain, canvas waveform,
  playhead loop, cue markers on the timeline.
- `osc.js` — WebSocket client to the proxy, send-with-throttle, status pill state.
- `render.js` — `render` and all DOM builders (sidebar, cue, action), the mood /
  defaults / pools / pool-picker modals, and the colour popover.
- `main.js` — initial `render()` + `oscConnect()` boot, and all top-level event
  listeners that wire the DOM to the modules above.

**Regression anchor:** the repo ships `examples/SONG_1.json` and
`examples/SONG_1.lua`. After the split, loading `SONG_1.json` and clicking Export
must reproduce the logic in `SONG_1.lua`. This is the concrete "the refactor
changed nothing" check, backed by a manual smoke pass (CSV import, audio load,
OSC pill state).

## The shared contract (`shared/ma3-command-spec.md`)

A plain-language description of the exact MA3 command sequence both apps emit,
derived from `buildCmdLines`. Contents:

- Pool number map (`dimmer=1, position=2, gobo=3, color=4, beam=5, focus=6`).
- Store flags (`/Overwrite` | `/Merge`, plus `/NoConfirmation`).
- Per-cue sequence:
  1. `ClearAll`
  2. for each group block with a non-empty group:
     - `Group "name"`
     - for each pool with a non-empty preset name:
       - `At Preset N."presetName"`
       - if fade resolved: `Fade f FeatureGroup N`
       - if delay resolved: `Delay d FeatureGroup N`
  3. `Store Sequence S Cue n ["cueName"] FLAG /NoConfirmation`
  4. if cue fade: `Set Sequence S Cue n Fade f`
  5. if cue delay: `Set Sequence S Cue n Delay d`
  - after all cues: a final `ClearAll`.
- The fade/delay **default-fallback rule**: a per-attribute value falls back to
  the per-pool default (`defaults[pool]`) when blank; omitted entirely if both
  are blank.
- Quote-escaping of names (`"` → `\"`).
- A statement that `web/js/compile.js` is the executable reference, and that any
  change to the sequence updates **both** the spec and `compile.js` in the same PR.

## Collaboration workflow & infra

- **Branching:** no direct commits to `main`. Work on `feat/…`, `fix/…`, or
  `chore/…` branches → open a PR → the other collaborator reviews and merges.
  Split work by module (e.g. audio/osc/ios vs. compile/render core) to minimise
  same-file edits.
- **`CONTRIBUTING.md`:** the branching rule; how to run the web app (open
  `web/index.html`); how to run the proxy (`start.sh` / `start.bat`); the manual
  smoke checklist; the `compile.js` ↔ spec sync rule; commit-message style.
- **`PULL_REQUEST_TEMPLATE.md`:** what / why, testing done, and a checkbox —
  "If I touched the command sequence, I updated both `compile.js` and
  `ma3-command-spec.md`."
- **Issue templates:** bug report + feature request.
- **`CHANGELOG.md`:** seeded with this restructure under an `Unreleased` section.
- **`.editorconfig`:** 2-space indent, LF, utf-8, trim trailing whitespace,
  final newline.
- **`.gitignore`:** add macOS (`.DS_Store`), node (`proxy/node_modules`),
  Xcode/Swift (`ios/` build output, `DerivedData`, `*.xcuserstate`).
- **Branch protection on `main`** (require PR + 1 review): requires repo **admin**,
  which the collaborator account likely does not have. Exact settings are
  documented in `CONTRIBUTING.md` for the repo owner to enable; it cannot be set
  from a non-admin account.

## Delivery plan

One branch — `chore/monorepo-housekeeping` — committed in clean, reviewable steps:

1. This design doc (committed first, for review).
2. `git mv` files into the monorepo layout (no content change).
3. Split HTML → `web/css/styles.css` + `web/js/*.js` (behaviour-preserving).
4. Add `shared/ma3-command-spec.md` + `docs/architecture.md`.
5. Add collaboration infra (CONTRIBUTING, templates, editorconfig, gitignore,
   CHANGELOG, README rewrite).
6. Add `proxy/start.sh`, convert `proxy/README.txt` → `README.md`.

Then open a PR for review.

## Verification

Before the work is considered done:

1. Open `web/index.html` directly in a browser (no server).
2. Load `examples/SONG_1.json` via Load Project.
3. Export `.lua`; confirm the emitted command logic matches
   `examples/SONG_1.lua`.
4. Smoke: import a CuePoints `.csv`, load an audio file (waveform + markers
   render), confirm the OSC pill reaches "online" with the proxy running.

A green run of all four = the housekeeping changed structure only, not behaviour.

## Risks

- **Large diff.** The file split touches everything at once. Mitigated by clean
  per-step commits and the behaviour-preserving constraint + regression anchor.
- **Merge conflicts with in-flight work.** Mitigated by landing this before any
  feature branches start.
- **Global-namespace ordering bugs** from the split. Mitigated by the fixed load
  order and the smoke checklist.

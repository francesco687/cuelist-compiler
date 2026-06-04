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

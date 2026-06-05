# Cuelist Compiler — "Tinted Vibrancy" UI Redesign

**Date:** 2026-06-05
**Branch:** `feat/desktop-ui-vibrancy`
**Status:** Design — approved in brainstorming, pending spec review

## Goal

Restyle the Cuelist Compiler UI into a slick, minimal, Apple-flavored desktop app
("Tinted Vibrancy" direction): a dark gradient canvas, translucent CSS materials,
and a violet→blue gradient accent. Plus one targeted structural tidy: collapse the
cramped 10-button bottom toolbar into a grouped action bar.

This is a **visual pass**. App logic, OSC/UDP transport, compile, audio, and the
embedded hub are not touched.

## Decisions (locked in brainstorming)

| Decision | Choice |
|---|---|
| Design language | **C · Tinted Vibrancy** — dark, translucent materials, violet→blue gradient accent |
| Ambition | **Reskin + tidy** — restyle everything; restructure only the bottom action bar |
| Scope | **Shared** — restyle the single `web/css/styles.css`; browser build and Electron desktop both inherit it |
| Vibrancy | **CSS materials only** — blur/translucency in CSS over a dark gradient. No change to `desktop/main.js`, identical on browser / Windows / Mac |

## Non-goals (YAGNI)

- No real native macOS window vibrancy or custom inset titlebar (would touch `desktop/main.js`, diverge per-platform).
- No IA / screen-flow rework. The cue editor, modals, and audio timeline keep their structure and behavior.
- No changes to compile output, OSC protocol, hub WS protocol, or project-JSON shape.
- No light theme.

## Architecture

Three layers, smallest blast radius first:

### 1. Design tokens (new — single source of truth)

Add a `:root` token block at the top of `web/css/styles.css`. Every component
references these instead of hard-coded hex. This is what makes the look coherent
and tweakable in one place.

```css
:root {
  --bg: radial-gradient(120% 120% at 0% 0%, #1b1e26 0%, #15171c 60%, #111319 100%);
  --surface-1: rgba(255,255,255,.045);   /* cards, sidebar items */
  --surface-2: rgba(255,255,255,.06);    /* inputs, secondary buttons */
  --border: rgba(255,255,255,.075);      /* hairline */
  --border-strong: rgba(255,255,255,.14);/* dashed "add" affordances */
  --accent: linear-gradient(135deg, #7a5cff, #5e8bff);
  --accent-solid: #6f78ff;               /* focus rings, single-color needs */
  --accent-tint: rgba(122,92,255,.12);   /* action-block fill */
  --text: #e9eaf0;
  --text-dim: #9a9eaa;
  --text-faint: #7c8090;
  --ok: #5fe08a; --ok-bg: rgba(48,209,88,.16);
  --warn: #f0b850;
  --danger: #ff6b6b;
  --radius: 11px; --radius-sm: 7px; --radius-pill: 999px;
  --blur: blur(12px);
}
```

### 2. Component restyle (the bulk — CSS only)

Restyle every existing selector in `styles.css` to use the tokens. No HTML/DOM
changes for these; the cascade does the work. Affected component groups:

- **Body / canvas** — gradient `--bg`, SF system font (already present), tabular numerals for times/sequence numbers.
- **Sidebar (`#sidebar`, `.song-item`)** — translucent `--surface-1`, active song uses the gradient accent with an inset ring.
- **Header (`#header`, `#headerActions`)** — larger song name; "Moods / Defaults / Pools" become quiet `--surface-2` chips.
- **Audio panel + timeline** — material panel; playhead/marker colors retuned to the accent + `--warn`.
- **Cue cards (`.cue-card`, `.cue-header`, `.cue-num`)** — material surface, gradient cue-number badge, rounded chevrons.
- **Action blocks / presets (`.action-block`, `.preset-row`, `.group-row`, chips)** — accent-tinted fill, gradient preset chips, fade=accent / delay=warn underline kept.
- **Inputs, buttons, ghosts** — `--surface-2`, accent focus ring, gradient primary buttons, danger uses `--danger`.
- **Modals (`.modal-content`, `.modal-header`, `.pool-tile`, `.mood-card`, `.defaults-row`)** — same material + radius treatment; layouts unchanged.
- **Status pills (`.osc-pill`, `.phone-pill`, `.desk-status`)** — refined pill styling; semantic colors via `--ok` / `--warn` / `--danger`. (They keep their current DOM position — there is no custom titlebar to host them.)

### 3. Action-bar tidy (the one structural change)

Restructure `#toolbar` in `web/index.html` from a flat 10-button row into a grouped
bar. **Every existing element ID is preserved** so the event wiring in
`web/js/main.js` (which binds via `getElementById`) keeps working unchanged.

Target structure:

- **Store mode** — a segmented control (Overwrite / Merge). Implemented as an
  *adapter*: keep the existing `<select id="storeMode">` in the DOM but visually
  hidden; render two segment buttons that set `storeMode.value` and dispatch a
  `change` event. All existing code that reads `storeMode.value` is untouched.
  Because `render.js:119` sets `storeMode.value` directly on project load (without
  dispatching `change`), one line is added there to call the adapter's
  `syncStoreModeSegment()` so the segment buttons reflect the loaded state.
- **Send → MA** — primary gradient split-button. `#sendOscCurrent` is the main
  button; `#sendOscAll` lives in a native `<details>` disclosure (the "⌄").
- **Export** — secondary split-button. `#export` main, `#exportAll` in a `<details>`.
- **⋯ overflow** — a native `<details class="menu">` holding the secondary file ops:
  `#saveProject`, `#loadBtn` (+ hidden `#loadProject`), `#importCsvBtn` (+ hidden
  `#importCsv`), and `#clearAll` (danger styling).

Menus use the native `<details>`/`<summary>` element — **no new menu JS, no
click-outside handler, no popover library.** The only new JS is the small,
isolated `storeMode` segmented adapter (~15 lines, added to `main.js` init).

## Data flow / behavior

Unchanged. The redesign is presentational. The segmented adapter writes through to
the same `<select>` the rest of the app already reads, so export/send logic sees no
difference. `<details>` menus are pure DOM disclosure.

## Error handling

No new failure modes. `<details>` degrades gracefully (works without JS). If the
segmented adapter's JS fails to init, the hidden `<select>` is still present and
could be un-hidden as a fallback — but this is a non-critical local control.

## Testing & verification

- **Existing logic tests stay green** (we touch no logic): `web` transport 3/3,
  `desktop` settings 7/7, `hub` 12/12. Run them to prove no regression.
- **`git diff hub/` stays empty** — frozen contract intact.
- **Manual visual verification** in both targets:
  - Browser: open `web/index.html`, exercise add song / add cue / open each modal /
    expand-collapse / store-mode toggle / overflow menu.
  - Electron: `cd desktop && npm start`, confirm the same plus the desk-status row /
    settings dialog render correctly with the new tokens.
- No screenshot tests; this is a hand-verified visual change.

## Files touched

| File | Change |
|---|---|
| `web/css/styles.css` | Token block + full component restyle (bulk of the work) |
| `web/index.html` | Restructure `#toolbar` into the grouped action bar; hide `<select id="storeMode">`, add segmented control + `<details>` menus (all existing IDs preserved) |
| `web/js/main.js` | ~15-line `storeMode` segmented adapter in init (exports `syncStoreModeSegment()`) |
| `web/js/render.js` | One line after L119: call `syncStoreModeSegment()` so the segment reflects loaded state |

`desktop/main.js`, `web/js/{compile,osc,transport,audio,state,constants,util}.js`,
and everything under `hub/` are **not** touched.

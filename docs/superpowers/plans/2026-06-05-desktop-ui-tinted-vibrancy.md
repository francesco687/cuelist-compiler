# Tinted Vibrancy UI Redesign — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restyle the Cuelist Compiler UI into a dark, translucent, Apple-flavored "Tinted Vibrancy" look driven by CSS design tokens, and collapse the cramped 10-button bottom toolbar into a grouped action bar — without touching app logic.

**Architecture:** A new `:root` token block in the single shared `web/css/styles.css` is the source of truth; every component is restyled to reference tokens. The only structural change is `#toolbar` in `web/index.html`, restructured into a grouped action bar that preserves every existing element ID (so `main.js` event wiring is untouched). One small `storeMode` segmented adapter is added to `main.js`, with a one-line sync call in `render.js`.

**Tech Stack:** Plain HTML/CSS/JS (no framework). Native `<details>`/`<summary>` for menus. Electron desktop and browser both consume the same `web/`.

**Important — tasks are sequential.** Tasks 1–8 all edit `web/css/styles.css` (and Task 8 also edits HTML/JS). Do not parallelize; apply in order. The design spec is at `docs/superpowers/specs/2026-06-05-desktop-ui-tinted-vibrancy-design.md`.

**Verification model.** No new CSS unit tests. Each task ends with: (a) reload `web/index.html` in a browser and visually confirm the region; (b) check the devtools console for errors. The final task runs all existing suites to prove no logic regression and visually verifies in Electron.

---

### Task 1: Design tokens + canvas base

**Files:**
- Modify: `web/css/styles.css:1-11` (top of file — base/body)

- [ ] **Step 1: Add the token block at the very top of the file (before `* { box-sizing }`)**

```css
:root {
  --bg: radial-gradient(120% 120% at 0% 0%, #1b1e26 0%, #15171c 60%, #111319 100%);
  --surface-1: rgba(255,255,255,.045);
  --surface-2: rgba(255,255,255,.06);
  --surface-3: rgba(255,255,255,.09);
  --border: rgba(255,255,255,.075);
  --border-strong: rgba(255,255,255,.14);
  --accent: linear-gradient(135deg, #7a5cff, #5e8bff);
  --accent-solid: #6f78ff;
  --accent-tint: rgba(122,92,255,.12);
  --accent-ring: rgba(122,92,255,.45);
  --text: #e9eaf0;
  --text-dim: #9a9eaa;
  --text-faint: #7c8090;
  --ok: #5fe08a;       --ok-bg: rgba(48,209,88,.16);   --ok-border: rgba(48,209,88,.32);
  --warn: #f0b850;
  --danger: #ff6b6b;   --danger-bg: rgba(255,107,107,.16);
  --radius: 11px; --radius-sm: 7px; --radius-pill: 999px;
  --blur: blur(12px);
}
```

- [ ] **Step 2: Replace the base body/heading rules (current L1-11)**

```css
  * { box-sizing: border-box; }
  body {
    font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', 'Segoe UI', Roboto, sans-serif;
    background: var(--bg);
    background-attachment: fixed;
    color: var(--text);
    margin: 0;
    padding: 10px;
    -webkit-font-smoothing: antialiased;
  }
  .wrap { max-width: 1600px; margin: 0; }
  h1 { color: #f3f3f7; margin: 0 0 4px 0; font-size: 1.55em; font-weight: 600; letter-spacing: -0.2px; }
  .sub { color: var(--text-dim); font-size: 0.9em; margin-bottom: 18px; }
```

- [ ] **Step 3: Verify**

Open `web/index.html` in a browser (or reload). Expected: dark gradient background fills the window, title and subtitle render in the new tones, no console errors.

- [ ] **Step 4: Commit**

```bash
git add web/css/styles.css
git commit -m "feat(ui): add design tokens + restyle canvas base"
```

---

### Task 2: Sidebar + header

**Files:**
- Modify: `web/css/styles.css:19-82` (sidebar, song-item, addSong) and `:116-126` (header)

- [ ] **Step 1: Replace the sidebar rules (current L19-78, keep the media query at L79-82 as-is)**

```css
  #sidebar {
    background: var(--surface-1);
    border: 1px solid var(--border);
    border-radius: var(--radius);
    padding: 10px;
    position: sticky;
    top: 10px;
    max-height: calc(100vh - 20px);
    overflow-y: auto;
    backdrop-filter: var(--blur);
  }
  #sidebar h2 {
    font-size: 0.72em; color: var(--text-dim);
    text-transform: uppercase; letter-spacing: 1.2px;
    margin: 2px 0 12px 2px; padding: 0;
  }
  #songList { list-style: none; padding: 0; margin: 0 0 8px 0; }
  .song-item {
    display: flex; align-items: center; gap: 6px;
    padding: 9px 11px; border-radius: 9px; cursor: pointer;
    color: var(--text-dim); border: 1px solid transparent; margin-bottom: 5px;
    transition: background .12s, color .12s;
  }
  .song-item:hover { background: var(--surface-2); color: var(--text); }
  .song-item.active {
    background: linear-gradient(135deg, rgba(122,92,255,.22), rgba(94,139,255,.16));
    color: #fff; border-color: transparent;
    box-shadow: inset 0 0 0 1px var(--accent-ring);
  }
  .song-item .song-label { flex: 1; min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .song-item .song-seq { font-size: 0.75em; color: var(--text-dim); flex-shrink: 0; font-variant-numeric: tabular-nums; }
  .song-item.active .song-seq { color: #bcb6ff; }
  .song-item .song-remove {
    background: none; border: none; color: var(--text-faint);
    padding: 2px 6px; font-size: 1em; cursor: pointer; border-radius: 6px; flex-shrink: 0;
  }
  .song-item .song-remove:hover { background: var(--danger-bg); color: var(--danger); }
  #addSong {
    width: 100%; background: transparent; border: 1px dashed var(--border-strong);
    color: var(--text-dim); font-weight: 400; padding: 9px; font-size: 0.9em; border-radius: 9px;
  }
  #addSong:hover { border-color: var(--accent-ring); color: var(--text); }
```

- [ ] **Step 2: Replace the header rules (current L116-126)**

```css
  #header {
    display: flex; gap: 10px; margin-bottom: 16px;
    align-items: center; flex-wrap: wrap;
  }
  #header label { color: var(--text-dim); font-size: 0.9em; }
  #songName { flex: 1; min-width: 200px; padding: 8px 12px; font-size: 1.05em; font-weight: 500; }
  #sequence { width: 80px; padding: 8px 12px; font-variant-numeric: tabular-nums; }
  #headerActions { display: flex; gap: 6px; margin-left: auto; }
```

- [ ] **Step 3: Verify**

Reload. Expected: sidebar is a translucent panel, active song shows the violet→blue gradient with an inset ring, "+ New Song" is a subtle dashed chip, header song name is larger. No console errors.

- [ ] **Step 4: Commit**

```bash
git add web/css/styles.css
git commit -m "feat(ui): restyle sidebar and header"
```

---

### Task 3: Inputs, buttons, ghost/danger controls

**Files:**
- Modify: `web/css/styles.css:84-114`

- [ ] **Step 1: Replace the input/button rules (current L84-114)**

```css
  input, button, select { font: inherit; }
  input[type="text"], input[type="number"] {
    background: var(--surface-2); border: 1px solid var(--border);
    color: var(--text); padding: 5px 9px; border-radius: var(--radius-sm);
    outline: none; font-size: 0.9em; transition: border-color .12s, box-shadow .12s;
  }
  input[type="text"]:focus, input[type="number"]:focus {
    border-color: var(--accent-solid);
    box-shadow: 0 0 0 3px var(--accent-tint);
  }
  button {
    background: var(--accent); border: none; color: #fff;
    padding: 7px 13px; border-radius: var(--radius-sm); cursor: pointer;
    font-weight: 600; font-size: 0.9em; transition: filter .12s, transform .05s;
    box-shadow: 0 1px 8px rgba(122,92,255,.25);
  }
  button:hover { filter: brightness(1.08); }
  button:active { transform: translateY(0.5px); }
  button.danger { background: var(--danger); box-shadow: none; }
  button.danger:hover { filter: brightness(1.08); }
  button.ghost {
    background: var(--surface-2); border: 1px solid var(--border);
    color: var(--text-dim); font-weight: 500; box-shadow: none;
  }
  button.ghost:hover { background: var(--surface-3); color: var(--text); border-color: var(--border-strong); }
```

- [ ] **Step 2: Verify**

Reload. Expected: primary buttons are gradient with a soft glow, ghost buttons are quiet solid chips (no longer dashed), inputs show a violet focus ring. No console errors.

- [ ] **Step 3: Commit**

```bash
git add web/css/styles.css
git commit -m "feat(ui): restyle inputs, buttons, ghost/danger controls"
```

---

### Task 4: Cue cards, action blocks, presets

**Files:**
- Modify: `web/css/styles.css:128-330` (cue-card through add-action) and `:529-577` (cue-mood-bar, defaults-row)

- [ ] **Step 1: Replace cue-card / header / chevron rules (current L128-169)**

```css
  .cue-card {
    background: var(--surface-1); border: 1px solid var(--border);
    border-radius: var(--radius); padding: 10px 12px; margin-bottom: 9px;
  }
  .cue-card.collapsed { padding: 8px 12px; }
  .cue-header { display: flex; gap: 8px; align-items: center; }
  .cue-card:not(.collapsed) .cue-header { margin-bottom: 9px; }
  .cue-num {
    width: auto; min-width: 44px; text-align: center; font-weight: 700;
    font-variant-numeric: tabular-nums; padding: 3px 9px; border-radius: var(--radius-sm);
    background: var(--accent); color: #fff; font-size: 0.92em;
  }
  .cue-name { flex: 1; font-weight: 500; }
  .cue-summary {
    color: var(--text-faint); font-size: 0.8em; margin-left: 6px;
    white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
  }
  .chevron {
    width: 26px; height: 26px; padding: 0; background: var(--surface-2);
    color: var(--text-dim); border: 1px solid var(--border);
    font-size: 0.9em; line-height: 1; border-radius: var(--radius-sm); box-shadow: none;
  }
  .chevron:hover { color: var(--text); border-color: var(--border-strong); background: var(--surface-3); }
  .icon-btn { width: 26px; height: 26px; padding: 0; font-size: 1em; line-height: 1; border-radius: var(--radius-sm); }
```

- [ ] **Step 2: Replace the action-block rule (current L171-182)**

```css
  .action-block {
    background: var(--accent-tint);
    border-left: 3px solid var(--accent-solid);
    box-shadow: none;
    padding: 6px 8px; margin: 6px 0; border-radius: 9px;
    display: flex; flex-direction: row; align-items: center; gap: 6px;
  }
```

Note: this drops the old per-action `--action-color` color-mix tinting in favor of a single accent tint. The `--action-color`/`--pool-color`/`--swatch-color` custom properties set inline by `render.js` still apply where referenced (swatches, preset-row left border) — do not remove those references.

- [ ] **Step 3: Restyle group-row + preset-row (current L241-307; keep media queries L308-316)**

```css
  .group-row {
    display: flex; gap: 4px; align-items: center; margin-bottom: 0;
    flex: 0 0 135px; padding-right: 8px; border-right: 1px solid var(--border);
  }
  .group-row label { color: var(--text-dim); font-size: 0.72em; min-width: auto; }
  .group-row input.group-name { flex: 1; min-width: 0; font-size: 0.8em; padding: 3px 6px; }
  .group-row .pick-btn { padding: 3px 6px; font-size: 0.8em; }

  .presets-grid { display: flex; flex: 1; gap: 4px; min-width: 0; }
  .preset-row {
    display: flex; align-items: center; gap: 4px; flex: 1 1 0; min-width: 130px;
    padding-left: 6px; border-left: 3px solid var(--pool-color, var(--accent-solid)); border-radius: var(--radius-sm);
  }
  .preset-row > label {
    font-size: 0.58em; color: var(--text-dim); text-transform: uppercase;
    font-weight: 700; letter-spacing: 0.3px; width: 22px; flex-shrink: 0;
    text-align: center; padding: 3px 1px; border-radius: 5px;
    background: var(--surface-2); cursor: pointer;
    transition: background .1s, color .1s; border: 1px solid transparent; user-select: none;
  }
  .preset-row > label:hover { background: var(--accent-tint); color: #fff; border-color: var(--accent-ring); }
  .preset-row input.preset-name { flex: 1; min-width: 0; font-size: 0.75em; padding: 3px 5px; }
  .preset-row .ptime { display: flex; align-items: center; gap: 2px; flex-shrink: 0; }
  .preset-row .ptime input { width: 36px; padding: 3px; font-size: 0.78em; text-align: center; border-radius: 5px; font-variant-numeric: tabular-nums; }
  .preset-row .ptime input.preset-fade { border-top: 2px solid var(--accent-ring); }
  .preset-row .ptime input.preset-delay { border-top: 2px solid rgba(240,184,80,.5); }
```

- [ ] **Step 4: Restyle cue-timing + cue-mood-bar + defaults-row (current L318-328, L529-548, L550-577)**

```css
  .cue-timing {
    margin-top: 9px; padding-top: 8px; border-top: 1px solid var(--border);
    display: flex; gap: 10px; align-items: center; flex-wrap: wrap;
  }
  .cue-timing label { color: var(--text-dim); font-size: 0.85em; }
  .cue-timing input { width: 70px; font-variant-numeric: tabular-nums; }

  .cue-mood-bar {
    display: flex; gap: 8px; align-items: center;
    padding-bottom: 8px; margin-bottom: 8px; border-bottom: 1px dashed var(--border);
  }
  .cue-mood-bar label { color: var(--text-dim); font-size: 0.8em; }
  .cue-mood-bar select {
    background: var(--surface-2); border: 1px solid var(--border); color: var(--text);
    padding: 5px 9px; border-radius: var(--radius-sm); flex: 1; min-width: 0; font-size: 0.85em;
  }
  .cue-mood-bar button { padding: 5px 11px; font-size: 0.82em; }

  .defaults-row {
    display: grid; grid-template-columns: 80px 1fr 1fr; gap: 10px; align-items: center;
    padding: 7px 4px; border-bottom: 1px solid var(--border);
  }
  .defaults-row:last-child { border-bottom: none; }
  .defaults-row label { text-transform: uppercase; font-size: 0.78em; color: var(--text-dim); font-weight: 600; letter-spacing: 0.5px; }
  .defaults-row .col-head { font-size: 0.72em; color: var(--text-faint); text-align: center; font-weight: 600; text-transform: uppercase; letter-spacing: 0.5px; }
  .defaults-row input { width: 100%; text-align: center; font-variant-numeric: tabular-nums; }
```

- [ ] **Step 5: Verify**

Reload, add a cue, expand it, add an action + presets. Expected: cue-number badge is a gradient pill, action blocks have a soft accent tint, preset rows read cleanly, color swatches (driven by inline `--swatch-color`) still show their per-action colors. No console errors.

- [ ] **Step 6: Commit**

```bash
git add web/css/styles.css
git commit -m "feat(ui): restyle cue cards, action blocks, presets, timing"
```

---

### Task 5: Audio panel + timeline

**Files:**
- Modify: `web/css/styles.css:579-704`

- [ ] **Step 1: Replace the audioPanel/controls rules (current L579-628)**

```css
  #audioPanel {
    background: var(--surface-1); border: 1px solid var(--border);
    border-radius: var(--radius); padding: 10px 12px; margin-bottom: 14px;
  }
  #audioPanel.empty { padding: 14px; text-align: center; color: var(--text-faint); }
  #audioControls { display: flex; gap: 8px; align-items: center; margin-bottom: 8px; flex-wrap: wrap; }
  #audioControls .filename { flex: 1; color: var(--text-dim); font-size: 0.85em; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; min-width: 0; }
  #audioControls .time { color: var(--text); font-size: 0.85em; font-family: ui-monospace, 'SF Mono', Consolas, monospace; min-width: 95px; text-align: right; }
  .channel-toggle {
    background: var(--surface-2); border: 1px solid var(--border); color: var(--text-dim);
    padding: 5px 11px; font-size: 0.82em; font-weight: 600; box-shadow: none; border-radius: var(--radius-sm);
  }
  .channel-toggle.active { background: var(--ok-bg); border-color: var(--ok-border); color: var(--ok); }
  .channel-toggle.muted { background: var(--surface-2); border-color: var(--border); color: var(--text-faint); }
  #playBtn { min-width: 70px; }
```

- [ ] **Step 2: Retune the timeline accent colors (current L630-704 — change only the color values noted below; keep geometry)**

In the timeline block, update these specific declarations:
- `#timeline` background → `#0e0f13`; border → `1px solid var(--border)`.
- `#timeline .channel-wave` border-bottom → `1px solid var(--border)`.
- `#timeline .playhead` background stays `#ff5a5a`.
- `#timeline .marker` background → `rgba(240,184,80,.5)`; hover → `rgba(240,184,80,1)`.
- `#timeline .marker.current` background → `var(--accent-solid)`.
- `#timeline .marker .marker-label` color → `var(--warn)`; current label background → `rgba(111,120,255,.9)`.

- [ ] **Step 3: Verify**

Reload, load an audio file. Expected: audio panel is a material card, waveform sits on a near-black track, markers are warm-amber, the current marker uses the accent color. No console errors.

- [ ] **Step 4: Commit**

```bash
git add web/css/styles.css
git commit -m "feat(ui): restyle audio panel and timeline"
```

---

### Task 6: Modals, pool picker, color popover, moods

**Files:**
- Modify: `web/css/styles.css:184-240` (color swatch/popover/tiles), `:362-414` (empty-hint, modal), `:416-527` (pool picker, pick-btn, mood-card)

- [ ] **Step 1: Replace the modal rules (current L371-414)**

```css
  .modal.hidden { display: none; }
  .modal { position: fixed; inset: 0; z-index: 100; display: flex; align-items: center; justify-content: center; }
  .modal-backdrop { position: absolute; inset: 0; background: rgba(0,0,0,.55); backdrop-filter: blur(3px); }
  .modal-content {
    position: relative; background: rgba(30,32,40,.92);
    border: 1px solid var(--border); border-radius: 14px; padding: 18px 20px;
    width: min(820px, 92vw); max-height: 88vh; overflow-y: auto;
    box-shadow: 0 24px 60px rgba(0,0,0,.55); backdrop-filter: var(--blur);
  }
  .modal-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 14px; padding-bottom: 10px; border-bottom: 1px solid var(--border); }
  .modal-header h2 { margin: 0; font-size: 1.15em; color: #f3f3f7; font-weight: 600; }
  .close-modal { background: var(--surface-2); color: var(--text-dim); border: 1px solid var(--border); width: 30px; height: 30px; padding: 0; border-radius: var(--radius-sm); box-shadow: none; }
  .close-modal:hover { color: var(--danger); background: var(--danger-bg); border-color: var(--danger); }
```

- [ ] **Step 2: Replace empty-hint + mood-card + addMood + mood-empty (current L362-369, L497-527)**

```css
  .empty-hint { text-align: center; color: var(--text-faint); padding: 40px 20px; border: 1.5px dashed var(--border-strong); border-radius: var(--radius); margin-bottom: 20px; }
  .mood-card { background: var(--surface-1); border: 1px solid var(--border); border-radius: var(--radius); padding: 10px 12px; margin-bottom: 10px; }
  .mood-header { display: flex; gap: 8px; align-items: center; margin-bottom: 8px; }
  .mood-name { flex: 1; font-weight: 500; }
  .mood-empty { text-align: center; color: var(--text-faint); padding: 30px 20px; border: 1.5px dashed var(--border-strong); border-radius: var(--radius); margin-bottom: 12px; }
  #addMood { width: 100%; background: transparent; border: 1.5px dashed var(--border-strong); color: var(--text-dim); padding: 10px; font-size: 0.95em; border-radius: var(--radius); box-shadow: none; }
  #addMood:hover { border-color: var(--accent-ring); color: var(--text); }
```

- [ ] **Step 3: Replace pool-picker + pool-tile + pick-btn (current L416-495)**

```css
  .pool-picker-toolbar { display: flex; gap: 8px; margin-bottom: 12px; align-items: center; }
  .pool-picker-toolbar input[type="text"] { flex: 1; }
  .pool-picker-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(130px, 1fr)); gap: 8px; max-height: 60vh; overflow-y: auto; padding-right: 4px; }
  .pool-tile {
    position: relative; background: var(--surface-2); border: 1px solid var(--border);
    border-radius: 9px; padding: 18px 8px 8px 8px; cursor: pointer; font-size: 0.85em;
    color: var(--text); text-align: center; min-height: 56px; display: flex; align-items: center;
    justify-content: center; word-break: break-word; line-height: 1.25;
    transition: background .1s, border-color .1s, transform .05s; user-select: none;
  }
  .pool-tile:hover { background: var(--surface-3); border-color: var(--accent-ring); }
  .pool-tile:active { transform: scale(0.97); }
  .pool-tile.current { border-color: var(--warn); background: rgba(240,184,80,.12); }
  .pool-tile .pool-tile-no { position: absolute; top: 3px; left: 6px; font-size: 0.7em; color: var(--text-dim); font-weight: 600; letter-spacing: 0.3px; }
  .pool-tile-accent { position: absolute; top: 0; left: 0; right: 0; height: 3px; border-radius: 9px 9px 0 0; }
  .pool-empty { text-align: center; color: var(--text-dim); padding: 30px 20px; font-size: 0.9em; grid-column: 1 / -1; }
  .pool-empty code { background: var(--surface-2); padding: 1px 5px; border-radius: 4px; }
  .input-with-picker { display: flex; gap: 4px; flex: 1; min-width: 0; }
  .input-with-picker input[type="text"] { flex: 1; min-width: 0; }
  .pick-btn { background: var(--surface-2); border: 1px solid var(--border); color: var(--text-dim); padding: 5px 9px; border-radius: var(--radius-sm); cursor: pointer; font-size: 0.95em; line-height: 1; flex-shrink: 0; }
  .pick-btn:hover { background: var(--surface-3); color: var(--text); border-color: var(--accent-ring); }
```

- [ ] **Step 4: Restyle color popover/tiles (current L202-240 — change container chrome, keep grid geometry and inline `--c` swatch colors)**

```css
  #colorPopover {
    position: absolute; z-index: 200; background: rgba(30,32,40,.95);
    border: 1px solid var(--border); border-radius: 10px; padding: 8px;
    box-shadow: 0 12px 28px rgba(0,0,0,.55); backdrop-filter: var(--blur);
    display: grid; grid-template-columns: repeat(5, 1fr); gap: 6px;
  }
  #colorPopover.hidden { display: none; }
  .color-tile.current { outline: 2px solid var(--warn); outline-offset: 2px; }
```

(Leave `.color-swatch`, `.color-tile` base geometry and the inline `--c`/`--swatch-color` references intact — they carry per-color values from `render.js`.)

- [ ] **Step 5: Verify**

Reload. Open Moods, Defaults, and Pools modals; open the color popover on an action. Expected: modals are frosted material panels with 14px corners, pool tiles are material chips, color swatches still show their real colors, the close "×" turns red on hover. No console errors.

- [ ] **Step 6: Commit**

```bash
git add web/css/styles.css
git commit -m "feat(ui): restyle modals, pool picker, color popover, moods"
```

---

### Task 7: Status pills, desk-status row, settings dialog, cues-toolbar, add-cue

**Files:**
- Modify: `web/css/styles.css:330-360` (cues-toolbar, addCue, toolbar spacing), `:706-751` (osc-pill, desk-status, phone-pill, osc-btn)

- [ ] **Step 1: Restyle cues-toolbar + addCue (current L330-349)**

```css
  .add-action { font-size: 0.8em; margin-top: 4px; padding: 4px 9px; }
  .cues-toolbar { display: flex; gap: 8px; margin-bottom: 9px; align-items: center; }
  .cues-toolbar .spacer { flex: 1; }
  #addCue {
    width: 100%; padding: 12px; background: transparent;
    border: 1.5px dashed var(--border-strong); color: var(--text-dim);
    font-size: 1em; margin-bottom: 18px; border-radius: var(--radius); box-shadow: none;
  }
  #addCue:hover { border-color: var(--accent-ring); color: var(--text); }
```

- [ ] **Step 2: Restyle osc-pill / desk-status / phone-pill / settings-error / osc-btn (current L706-751)**

```css
  .osc-pill {
    display: inline-flex; align-items: center; padding: 4px 11px; border-radius: var(--radius-pill);
    font-size: 0.8em; cursor: pointer; user-select: none; border: 1px solid var(--border);
    margin-left: 6px; font-weight: 600;
  }
  .osc-pill.offline { background: var(--surface-2); color: var(--text-dim); border-color: var(--border); }
  .osc-pill.connecting { background: rgba(240,184,80,.16); color: var(--warn); border-color: rgba(240,184,80,.32); }
  .osc-pill.online { background: var(--ok-bg); color: var(--ok); border-color: var(--ok-border); }
  .osc-pill.sending { background: var(--accent-tint); color: #b9a9ff; border-color: var(--accent-ring); }

  .desk-status { display: flex; align-items: center; gap: 10px; margin-top: 10px; padding: 6px 0; font-size: 0.85em; color: var(--text-dim); }
  .phone-pill {
    display: inline-flex; align-items: center; padding: 4px 11px; border-radius: var(--radius-pill);
    font-size: 0.9em; border: 1px solid var(--border); background: var(--surface-2); color: var(--text-dim); font-weight: 600;
  }
  .phone-pill.connected { background: var(--ok-bg); color: var(--ok); border-color: var(--ok-border); }
  .settings-error { margin: 6px 0 0; color: var(--danger); font-size: 0.85em; }
  .osc-btn { background: var(--surface-2); border: 1px solid var(--border); color: var(--text); box-shadow: none; }
  .osc-btn:hover:not(:disabled) { background: var(--surface-3); }
  .osc-btn:disabled { background: var(--surface-1); color: var(--text-faint); border-color: var(--border); cursor: not-allowed; }
```

- [ ] **Step 3: Style the settings `<dialog>` (append new rules — there is currently no styling for `#settingsDialog`)**

```css
  #settingsDialog {
    background: rgba(30,32,40,.95); color: var(--text);
    border: 1px solid var(--border); border-radius: 14px; padding: 18px 20px;
    box-shadow: 0 24px 60px rgba(0,0,0,.55); backdrop-filter: var(--blur); min-width: 320px;
  }
  #settingsDialog::backdrop { background: rgba(0,0,0,.5); backdrop-filter: blur(3px); }
  #settingsForm label { display: flex; justify-content: space-between; align-items: center; gap: 12px; margin: 8px 0; font-size: 0.9em; color: var(--text-dim); }
  #settingsForm menu { display: flex; gap: 8px; justify-content: flex-end; margin: 14px 0 0; padding: 0; }
```

- [ ] **Step 4: Verify**

Reload. Expected: "+ Add Cue" is a clean dashed affordance; OSC pill shows semantic colors (toggle states if reachable). In Electron the desk-status row + Settings dialog (open it) render as frosted panels. No console errors.

- [ ] **Step 5: Commit**

```bash
git add web/css/styles.css
git commit -m "feat(ui): restyle status pills, add-cue, settings dialog"
```

---

### Task 8: Action-bar restructure (HTML + segmented adapter)

**Files:**
- Modify: `web/index.html:49-67` (the `#toolbar` block)
- Modify: `web/js/main.js` (add segmented adapter in init; export `syncStoreModeSegment`)
- Modify: `web/js/render.js:119` (add sync call)
- Modify: `web/css/styles.css:351-360` (replace `#toolbar` rules + add action-bar classes)

- [ ] **Step 1: Replace the `#toolbar` markup in `web/index.html` (current L49-67)**

```html
      <div id="toolbar">
        <div class="seg" id="storeModeSeg" role="group" aria-label="Store mode">
          <button type="button" class="seg-btn" data-mode="Overwrite">Overwrite</button>
          <button type="button" class="seg-btn" data-mode="Merge">Merge</button>
        </div>
        <select id="storeMode" class="visually-hidden" tabindex="-1" aria-hidden="true">
          <option value="Overwrite">Overwrite</option>
          <option value="Merge">Merge</option>
        </select>

        <div class="split">
          <button id="sendOscCurrent" class="osc-btn primary-send" disabled>Send → MA</button>
          <details class="split-menu">
            <summary class="split-caret" aria-label="More send options">⌄</summary>
            <div class="menu-pop">
              <button id="sendOscAll" class="menu-item" disabled>Send all → MA</button>
            </div>
          </details>
        </div>

        <div class="split">
          <button id="export" class="ghost">Export .lua</button>
          <details class="split-menu">
            <summary class="split-caret" aria-label="More export options">⌄</summary>
            <div class="menu-pop">
              <button id="exportAll" class="menu-item">Export all .lua</button>
            </div>
          </details>
        </div>

        <span id="oscPill" class="osc-pill offline" title="Click to reconnect to OSC proxy">○ OSC offline</span>
        <div class="spacer"></div>

        <details class="menu overflow">
          <summary class="ovf-btn" aria-label="More actions">⋯</summary>
          <div class="menu-pop menu-pop-right">
            <button id="saveProject" class="menu-item">Save Project (.json)</button>
            <button id="loadBtn" class="menu-item">Load Project</button>
            <input type="file" id="loadProject" accept=".json">
            <button id="importCsvBtn" class="menu-item">Import .csv (CuePoints)</button>
            <input type="file" id="importCsv" accept=".csv" style="display:none">
            <hr>
            <button id="clearAll" class="menu-item danger-item">Clear all</button>
          </div>
        </details>
      </div>
```

Note: every ID from the old toolbar (`storeMode`, `sendOscCurrent`, `sendOscAll`, `export`, `exportAll`, `oscPill`, `saveProject`, `loadBtn`, `loadProject`, `importCsvBtn`, `importCsv`, `clearAll`) is preserved, so existing `main.js` wiring binds unchanged.

- [ ] **Step 2: Replace the `#toolbar` CSS (current L351-360) with the action-bar styles**

```css
  #toolbar {
    display: flex; gap: 9px; margin-top: 20px; padding-top: 16px;
    border-top: 1px solid var(--border); flex-wrap: wrap; align-items: center;
  }
  #toolbar .spacer { flex: 1; }
  #loadProject { display: none; }

  .visually-hidden { position: absolute; width: 1px; height: 1px; padding: 0; margin: -1px; overflow: hidden; clip: rect(0 0 0 0); white-space: nowrap; border: 0; }

  .seg { display: inline-flex; background: var(--surface-2); border: 1px solid var(--border); border-radius: var(--radius-sm); padding: 2px; }
  .seg-btn { background: transparent; color: var(--text-dim); box-shadow: none; padding: 5px 12px; font-size: 0.82em; font-weight: 600; border-radius: 6px; }
  .seg-btn:hover { color: var(--text); filter: none; }
  .seg-btn.active { background: var(--surface-3); color: #fff; }

  .split { display: inline-flex; align-items: stretch; }
  .primary-send.osc-btn { border-top-right-radius: 0; border-bottom-right-radius: 0; }
  .split-menu { position: relative; }
  .split-caret { list-style: none; cursor: pointer; display: flex; align-items: center; padding: 0 8px;
    background: var(--surface-2); border: 1px solid var(--border); border-left: none;
    border-radius: 0 var(--radius-sm) var(--radius-sm) 0; color: var(--text-dim); font-size: 0.8em; height: 100%; }
  .split-caret::-webkit-details-marker { display: none; }

  .menu { position: relative; }
  .ovf-btn { list-style: none; cursor: pointer; display: inline-flex; align-items: center; justify-content: center;
    width: 34px; height: 32px; border-radius: var(--radius-sm); background: var(--surface-2);
    border: 1px solid var(--border); color: var(--text-dim); font-size: 1.1em; }
  .ovf-btn::-webkit-details-marker { display: none; }

  .menu-pop {
    position: absolute; bottom: calc(100% + 6px); left: 0; z-index: 150;
    min-width: 180px; padding: 6px; display: flex; flex-direction: column; gap: 2px;
    background: rgba(30,32,40,.96); border: 1px solid var(--border); border-radius: 10px;
    box-shadow: 0 14px 30px rgba(0,0,0,.5); backdrop-filter: var(--blur);
  }
  .menu-pop-right { left: auto; right: 0; }
  .menu-pop hr { border: none; border-top: 1px solid var(--border); margin: 4px 2px; }
  .menu-item { width: 100%; text-align: left; background: transparent; color: var(--text); box-shadow: none; font-weight: 500; padding: 7px 10px; border-radius: 6px; font-size: 0.85em; }
  .menu-item:hover { background: var(--surface-2); filter: none; }
  .menu-item.danger-item { color: var(--danger); }
  .menu-item.danger-item:hover { background: var(--danger-bg); }
  .menu-item:disabled { color: var(--text-faint); cursor: not-allowed; }
  .menu-pop input[type="file"] { font-size: 0.8em; color: var(--text-dim); }
```

- [ ] **Step 3: Add the segmented adapter to `web/js/main.js`**

Add this near the existing `storeMode` change listener (around L45). It mirrors the hidden `<select>` both ways and exposes a sync function on `window` so `render.js` can refresh the segment after it sets the select value programmatically.

```javascript
// Segmented control adapter for store mode — drives the hidden <select id="storeMode">
function syncStoreModeSegment() {
  const sel = document.getElementById('storeMode');
  const seg = document.getElementById('storeModeSeg');
  if (!sel || !seg) return;
  seg.querySelectorAll('.seg-btn').forEach(btn => {
    btn.classList.toggle('active', btn.dataset.mode === sel.value);
  });
}
window.syncStoreModeSegment = syncStoreModeSegment;

document.getElementById('storeModeSeg').addEventListener('click', e => {
  const btn = e.target.closest('.seg-btn');
  if (!btn) return;
  const sel = document.getElementById('storeMode');
  sel.value = btn.dataset.mode;
  sel.dispatchEvent(new Event('change'));   // existing handler updates state
  syncStoreModeSegment();
});

syncStoreModeSegment(); // initialise on load
```

- [ ] **Step 4: Add the sync call in `web/js/render.js` after line 119**

Current L119 is `document.getElementById('storeMode').value = state.storeMode || 'Overwrite';`. Immediately after it add:

```javascript
  if (window.syncStoreModeSegment) window.syncStoreModeSegment();
```

- [ ] **Step 5: Verify the action bar end-to-end**

Reload `web/index.html`. Confirm:
- The store-mode segmented control shows Overwrite active; clicking Merge moves the highlight.
- Clicking a segment then exporting compiles in that mode (open devtools, confirm no error; the compiled `.lua` store mode reflects the choice).
- The **⌄** on Send and Export opens a small frosted menu with "Send all" / "Export all".
- The **⋯** overflow opens a menu containing Save / Load / Import / Clear all (Clear all in red).
- Save a project, reload it (via Load) — the segment reflects the loaded store mode (proves the `render.js` sync line).
- No console errors.

- [ ] **Step 6: Commit**

```bash
git add web/index.html web/css/styles.css web/js/main.js web/js/render.js
git commit -m "feat(ui): grouped action bar with segmented store mode and overflow menus"
```

---

### Task 9: Full verification + Electron smoke

**Files:** none (verification only) — plus this plan/spec already committed.

- [ ] **Step 1: Run all existing test suites — they must stay green (we touched no logic)**

```bash
cd web && npm test 2>&1 | tail -20; cd ..
cd desktop && npm test 2>&1 | tail -20; cd ..
cd hub && npm test 2>&1 | tail -20; cd ..
```

Expected: web transport 3/3, desktop settings 7/7, hub 12/12 — all passing.

- [ ] **Step 2: Confirm the frozen contract is untouched**

```bash
git diff main -- hub/
```

Expected: empty output (no changes under `hub/`).

- [ ] **Step 3: Electron visual smoke**

```bash
cd desktop && npm install && npm start
```

In the window, confirm: gradient canvas, translucent sidebar/cards, gradient accent, grouped action bar with working menus, desk-status row + Settings dialog render correctly. Close the app.

- [ ] **Step 4: Final commit (only if any tweaks were made during verification)**

```bash
git add -A && git commit -m "chore(ui): verification tweaks for Tinted Vibrancy redesign"
```

---

## Self-Review

**Spec coverage:**
- Tokens (spec §Architecture 1) → Task 1. ✔
- Component restyle, every group listed in spec §Architecture 2 → Tasks 2–7 (sidebar/header T2, controls T3, cue cards/actions/presets T4, audio/timeline T5, modals/pools/popover/moods T6, status pills/add-cue/settings T7). ✔
- Action-bar tidy + segmented adapter + render.js sync (spec §Architecture 3) → Task 8. ✔
- Verification: existing suites green, `git diff hub/` empty, Electron + browser manual checks (spec §Testing) → per-task checks + Task 9. ✔
- Non-goals (no main.js, no logic, no light theme, no native vibrancy) → respected; no task touches `desktop/main.js` or `hub/`. ✔

**Placeholder scan:** No TBD/TODO; every CSS/JS/HTML step contains the actual code. Task 5 Step 2 and Task 6 Step 4 give explicit per-declaration value changes rather than full-block rewrites (to preserve geometry and inline custom-property hooks) — these are concrete, not placeholders. ✔

**Type/name consistency:** `syncStoreModeSegment` defined in Task 8 Step 3, exported on `window`, and called in Task 8 Step 4 (render.js) under the same name. Element IDs in the new toolbar markup (Task 8 Step 1) match the IDs the spec promises are preserved. CSS class names (`.seg`, `.seg-btn`, `.split`, `.split-menu`, `.menu-pop`, `.ovf-btn`) defined in Step 2 match the markup in Step 1. ✔

# Desktop "Amber HUD" Restyle — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restyle the shared `web/` UI (browser + Electron desktop) into a dark cyber-tech "Amber HUD" look matching the iOS Saetta app, at Full-HUD intensity, with a clean instrument zone for the audio timeline.

**Architecture:** CSS-only, token-driven. A `:root` block in `web/css/styles.css` is the single source of truth; every component references the tokens. Full-HUD ornament (corner brackets, tick-grids, scanlines, glow) is pure CSS (`background` layers + pseudo-elements), so markup is untouched except the wordmark text. Dynamic markup (cue cards, audio panel, console) is restyled via existing class hooks — no JS changes.

**Tech Stack:** Plain CSS3 (custom properties, `::before`/`::after`, layered gradients), HTML. Tests: `node:test` (built-in). No build step, no dependencies.

**Spec:** `docs/superpowers/specs/2026-06-11-desktop-amber-hud-design.md`

---

## Conventions for this plan

- **Test command (web):** `node --test web/test/*.test.js` — currently 46 pass. Use the **glob** form; the bare-directory form misreports.
- **Test command (desktop):** `cd desktop && npm test` (= `node --test test`).
- **Visual smoke (browser):** open `web/index.html` directly in a browser (`open web/index.html` on macOS).
- **Visual smoke (Electron):** `cd desktop && npm install && npm start`.
- `styles.css` is 2-space indented with no top-level wrapper. Keep that style. Add the `:root` block at the very top of the file.
- **Amber tokens are the only hue.** Never introduce a non-amber accent. Red is reserved for `.danger`/delete and the functional waveform marker. Lighting-color swatches (`.color-tile` fills) are DATA — never re-tone them.
- After each task: run the web test suite (must stay 46+ pass) and eyeball the relevant component before committing.

---

## File Structure

- **Modify:** `web/css/styles.css` — all visual changes live here (every task except the wordmark text).
- **Modify:** `web/index.html` — wordmark text only (`<title>` + `h1`), Task 8. All element IDs preserved.
- **Create:** `web/test/restyle-guard.test.js` — guard tests: element-ID preservation + token presence + balanced braces (Task 1).

No other files are created or modified. `git diff main -- hub/ web/js/` must remain empty at the end (sanity-checked in Task 9).

---

## Task 1: Guard tests + token foundation + base shell

**Files:**
- Create: `web/test/restyle-guard.test.js`
- Modify: `web/css/styles.css` (add `:root` at top; restyle `body`, `.wrap`, `h1`, `.sub`)

- [ ] **Step 1: Write the guard test**

Create `web/test/restyle-guard.test.js`:

```javascript
'use strict';
const { test } = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');

const html = fs.readFileSync(path.resolve(__dirname, '..', 'index.html'), 'utf8');
const css = fs.readFileSync(path.resolve(__dirname, '..', 'css', 'styles.css'), 'utf8');

// Every element ID main.js wires up. The restyle must NOT remove or rename any of these.
const REQUIRED_IDS = [
  'sidebar','songList','addSong','main','header','songName','sequence','headerActions',
  'manageMoodsBtn','manageDefaultsBtn','audioPanel','loadAudioBtn','loadAudio','collapseAll',
  'expandAll','cueCount','cues','addCue','toolbar','storeMode','oscPill','oscTargetInline',
  'sendOscCurrent','sendOscAll','sendTcOscCurrent','sendTcOscAll','export','exportAll','exportTc',
  'exportTcAll','saveProject','saveProjectBundle','loadBtn','loadProject','importCsvBtn',
  'managePoolsBtn','importCsv','clearAll','deskStatusRow','phonePill','openSettingsBtn',
  'settingsDialog','settingsForm','setMa3Host','setMa3Port','setMa3Prefix','setIntervalMs',
  'setHubEnabled','setHubPort','settingsError','saveSettingsBtn','moodModal','moodList','addMood',
  'defaultsModal','defaultsList','poolsModal','poolsPaste','poolsStatus','poolsImportBtn',
  'poolsLoadFileBtn','poolsLoadFile','poolsClearBtn','poolPickerModal','poolPickerTitle',
  'poolPickerSearch','poolPickerClear','poolPickerGrid',
];

test('restyle-guard: all wired element IDs still present in index.html', () => {
  for (const id of REQUIRED_IDS) {
    assert.ok(html.includes(`id="${id}"`), `missing id="${id}" — would break main.js wiring`);
  }
});

test('restyle-guard: :root defines the required Amber HUD tokens', () => {
  const required = [
    '--accent-start','--accent-end','--accent-solid','--accent-tint','--accent-border',
    '--capture','--capture-ink','--surface-1','--surface-2','--surface-3','--border',
    '--border-strong','--text','--text-dim','--text-faint','--ok','--warn','--danger',
    '--radius','--radius-sm','--radius-lg','--grid-line','--scanline','--font-mono',
  ];
  assert.ok(/:root\s*\{/.test(css), ':root block must exist');
  for (const tok of required) {
    assert.ok(css.includes(tok), `missing token ${tok}`);
  }
});

test('restyle-guard: stylesheet braces are balanced', () => {
  const open = (css.match(/\{/g) || []).length;
  const close = (css.match(/\}/g) || []).length;
  assert.strictEqual(open, close, `unbalanced braces: ${open} { vs ${close} }`);
});
```

- [ ] **Step 2: Run the guard test — token test must FAIL**

Run: `node --test web/test/restyle-guard.test.js`
Expected: the ID test PASSES and the braces test PASSES, but `:root defines the required Amber HUD tokens` FAILS (no `:root` block exists yet).

- [ ] **Step 3: Add the `:root` token block at the very top of `web/css/styles.css`**

Insert ABOVE the existing `* { box-sizing: border-box; }` line:

```css
:root {
  /* Amber HUD — single hue. Ported from iOS Theme.swift. */
  --accent-start:  #f0b860;
  --accent-end:    #e0913f;
  --accent-solid:  #eaa64f;
  --accent-tint:   rgba(240,184,96,0.12);
  --accent-border: rgba(240,184,96,0.22);

  --capture:       #f5d8a6;   /* pale-amber capture/voice tone */
  --capture-ink:   #2a1d07;   /* dark ink on light-amber surfaces */

  --surface-1: rgba(255,255,255,0.05);
  --surface-2: rgba(255,255,255,0.07);
  --surface-3: rgba(255,255,255,0.10);
  --border:        rgba(255,255,255,0.08);
  --border-strong: rgba(255,255,255,0.14);

  --text:       #f6ead6;
  --text-dim:   #c2a079;
  --text-faint: #94795e;

  --ok:     #f0c074;   /* live / success (bright amber) */
  --warn:   #d49a4a;   /* connecting / delay (mid amber) */
  --danger: #ff6b6b;   /* DESTRUCTIVE DELETE ONLY */

  --radius:    7px;
  --radius-sm: 4px;
  --radius-lg: 11px;

  --grid-line: rgba(240,184,96,0.05);   /* tick-grid */
  --scanline:  rgba(255,255,255,0.025); /* scanline overlay */

  --font-mono: ui-monospace, "SF Mono", Menlo, Consolas, monospace;

  /* canvas */
  --canvas-1: #1d160e;
  --canvas-2: #15110a;
  --canvas-3: #0f0c07;
}
```

- [ ] **Step 4: Restyle the base shell — aurora canvas, body, headings**

Replace the existing `body`, `.wrap`, `h1`, `.sub` rules with:

```css
body {
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
  color: var(--text);
  margin: 0;
  padding: 8px;
  min-height: 100vh;
  background:
    radial-gradient(620px at 0% 0%,   rgba(122,79,30,0.55), transparent),
    radial-gradient(620px at 100% 100%, rgba(92,58,22,0.50), transparent),
    linear-gradient(135deg, var(--canvas-1), var(--canvas-2) 55%, var(--canvas-3));
  background-attachment: fixed;
}
/* tick-grid + scanline overlay across the whole app, behind content */
body::before {
  content: ""; position: fixed; inset: 0; z-index: 0; pointer-events: none;
  background:
    repeating-linear-gradient(0deg,  var(--grid-line) 0 1px, transparent 1px 24px),
    repeating-linear-gradient(90deg, var(--grid-line) 0 1px, transparent 1px 24px),
    repeating-linear-gradient(0deg,  var(--scanline) 0 2px, transparent 2px 4px);
}
.wrap { max-width: 1600px; margin: 0; position: relative; z-index: 1; }
h1 {
  color: var(--text); margin: 0 0 4px 0; font-size: 1.35em;
  font-family: var(--font-mono); text-transform: uppercase; letter-spacing: 2.5px; font-weight: 600;
}
.sub { color: var(--text-faint); font-size: 0.9em; margin-bottom: 20px; }
```

- [ ] **Step 5: Run the guard test — all pass**

Run: `node --test web/test/restyle-guard.test.js`
Expected: all 3 tests PASS.

- [ ] **Step 6: Run the full web suite — still green**

Run: `node --test web/test/*.test.js`
Expected: 49 pass (46 existing + 3 guard), 0 fail.

- [ ] **Step 7: Commit**

```bash
git add web/css/styles.css web/test/restyle-guard.test.js
git commit -m "feat(web-ui): Amber HUD token foundation + aurora canvas + guard tests"
```

---

## Task 2: Reusable HUD ornament — glass/glow/label utilities + canonical bracket technique

**Files:**
- Modify: `web/css/styles.css`

This task defines the shared skin utilities and the **canonical corner-bracket snippet** that later tasks apply per-component (at component-specific opacities). It proves the glass surface on the sidebar.

**Canonical bracket technique (reference — applied per-component in Tasks 4–7):**
A panel gets two L-shaped brackets — top-left via `::before`, bottom-right via `::after` — using one border-corner each. This is reliable across browsers and matches the iOS "softened brackets" look. The opacity varies by emphasis (cue cards 0.35, toolbar 0.4, audio panel 0.5). Pattern:

```css
.SELECTOR { position: relative; }
.SELECTOR::before, .SELECTOR::after {
  content: ""; position: absolute; width: 10px; height: 10px; pointer-events: none;
  border: 1.5px solid rgba(234,166,79, VAR_OPACITY);
}
.SELECTOR::before { top: 6px; left: 6px;  border-right: none;  border-bottom: none; }
.SELECTOR::after  { bottom: 6px; right: 6px; border-left: none; border-top: none; }
```

- [ ] **Step 1: Add the shared skin utilities** (append in a clearly commented section)

```css
/* ---- HUD ornament primitives ---------------------------------------- */
/* Glass surface used by panels/cards. */
.hud-surface {
  background: var(--surface-2);
  border: 1px solid var(--accent-border);
  border-radius: var(--radius);
  box-shadow: 0 8px 22px rgba(0,0,0,0.35), inset 0 1px 0 rgba(255,255,255,0.06);
}
/* amber glow utility for hero elements */
.hud-glow { box-shadow: 0 0 14px rgba(234,166,79,0.5), 0 0 30px rgba(224,145,63,0.3); }
/* HUD label: uppercase mono, tracked */
.hud-label { font-family: var(--font-mono); text-transform: uppercase; letter-spacing: 1.4px; }
```

> Corner brackets are NOT a shared class — they are applied per-component via the canonical snippet above, because the opacity differs by emphasis. The sidebar deliberately gets NO brackets (a full-height column with brackets reads as noise).

- [ ] **Step 2: Apply the glass surface to the sidebar (no brackets)**

Find the existing `#sidebar` rule and replace its `background`/`border` declarations (keep all layout props — width, padding, grid) with:

```css
#sidebar {
  /* layout props unchanged — only the skin below */
  background: var(--surface-1);
  border: 1px solid var(--border);
  border-radius: var(--radius);
}
```

- [ ] **Step 3: Visual smoke**

Run: `open web/index.html`
Expected: dark amber aurora background with faint grid; sidebar reads as a translucent glass panel; no layout breakage.

- [ ] **Step 4: Run web suite**

Run: `node --test web/test/*.test.js`
Expected: 49 pass, 0 fail.

- [ ] **Step 5: Commit**

```bash
git add web/css/styles.css
git commit -m "feat(web-ui): HUD ornament primitives (glass surface, corner brackets, glow)"
```

---

## Task 3: Sidebar, song list, header, inputs, wordmark area

**Files:**
- Modify: `web/css/styles.css`

- [ ] **Step 1: Restyle song-list items** — map the hardcoded colors to tokens.

Replace the `.song-item`, `.song-item:hover`, `.song-item.active`, `.song-seq`, `.song-item.active .song-seq`, `.song-remove:hover` color/background declarations:

```css
.song-item {
  background: var(--surface-1);
  border: 1px solid var(--border);
  border-radius: var(--radius-sm);
  color: var(--text-dim);
}
.song-item:hover { background: var(--surface-2); color: var(--text); }
.song-item.active {
  background: var(--accent-tint);
  border-color: var(--accent-border);
  color: var(--text);
}
.song-seq { font-family: var(--font-mono); color: var(--text-faint); }
.song-item.active .song-seq { color: var(--ok); }
.song-item .song-remove:hover { background: var(--danger); color: #fff; }
```

- [ ] **Step 2: Restyle `#addSong`, `#addCue` (dashed add buttons)**

```css
#addSong, #addCue {
  background: transparent;
  border: 1px dashed var(--border-strong);
  color: var(--text-dim);
  border-radius: var(--radius);
  font-family: var(--font-mono);
  text-transform: uppercase; letter-spacing: 1px; font-size: 0.8em;
}
#addSong:hover, #addCue:hover { border-color: var(--accent-solid); color: var(--text); }
```

- [ ] **Step 3: Restyle the header `h2`, text/number inputs, labels**

```css
#sidebar h2 {
  font-family: var(--font-mono); text-transform: uppercase; letter-spacing: 1.4px;
  color: var(--text-faint); font-size: 0.85em;
}
input[type="text"], input[type="number"] {
  background: var(--surface-1);
  border: 1px solid var(--border);
  color: var(--text);
  border-radius: var(--radius-sm);
}
input[type="text"]:focus, input[type="number"]:focus {
  border-color: var(--accent-solid);
  outline: none;
  box-shadow: 0 0 0 2px var(--accent-tint);
}
#header label { font-family: var(--font-mono); text-transform: uppercase; letter-spacing: 1.2px; color: var(--text-faint); font-size: 0.8em; }
#sequence { font-family: var(--font-mono); color: var(--ok); }
```

- [ ] **Step 4: Restyle the generic `button` and `.ghost` button rules**

```css
button {
  background: var(--surface-2);
  color: var(--text);
  border: 1px solid var(--border);
  border-radius: var(--radius-sm);
}
button:hover { background: var(--surface-3); border-color: var(--accent-border); }
button.ghost {
  background: transparent;
  border: 1px solid var(--accent-border);
  color: var(--text-dim);
}
button.ghost:hover { color: var(--text); border-color: var(--accent-solid); }
```

> Note: `.danger` is handled in Task 5. Send→MA CTA (`.osc-btn`/`.send-big`) is handled in Task 5. This task is the generic baseline only.

- [ ] **Step 5: Visual smoke** — `open web/index.html`. Confirm sidebar, song items (active = amber tint), header inputs (amber focus ring), add buttons read as HUD.

- [ ] **Step 6: Run web suite** — `node --test web/test/*.test.js` → 49 pass.

- [ ] **Step 7: Commit**

```bash
git add web/css/styles.css
git commit -m "feat(web-ui): Amber HUD sidebar, song list, header inputs, add buttons"
```

---

## Task 4: Cue cards (badge, chips, mono numerics, brackets, action blocks, mood bar)

**Files:**
- Modify: `web/css/styles.css`

Class hooks (emitted by `render.js`): `cue-card`, `cue-header`, `cue-num`, `cue-name`, `cue-summary`, `cue-timing`, `cue-mood-bar`, `action-block`, `add-action`, `apply-mood`, `group-row`, `group-name`, `col-head`, `fade-input`, `delay-input`, `cue-tc-capture`, `chevron`.

- [ ] **Step 1: Cue card surface + corner brackets**

```css
.cue-card {
  background: var(--surface-1);
  border: 1px solid var(--accent-border);
  border-radius: var(--radius);
  box-shadow: 0 6px 18px rgba(0,0,0,0.30), inset 0 1px 0 rgba(255,255,255,0.05);
  position: relative;
}
/* softened corner brackets (top-left + bottom-right only — the iOS "softened" choice) */
.cue-card::before, .cue-card::after {
  content: ""; position: absolute; width: 10px; height: 10px; pointer-events: none;
  border: 1.5px solid rgba(234,166,79,0.35);
}
.cue-card::before { top: 6px; left: 6px; border-right: none; border-bottom: none; }
.cue-card::after  { bottom: 6px; right: 6px; border-left: none; border-top: none; }
```

- [ ] **Step 2: Cue number badge (amber circle, dark ink)**

```css
.cue-num {
  background: linear-gradient(135deg, var(--accent-start), var(--accent-end));
  color: var(--capture-ink);
  font-family: var(--font-mono); font-weight: 700;
  border-radius: 50%;
  box-shadow: 0 0 12px rgba(234,166,79,0.4);
}
```

- [ ] **Step 3: Cue name, summary, timing — mono numerics + warm text**

```css
.cue-name { color: var(--text); }
.cue-summary { color: var(--text-dim); }
.cue-timing, .fade-input, .delay-input { font-family: var(--font-mono); }
.cue-timing { color: var(--text-dim); }
.fade-input, .delay-input {
  background: var(--surface-1); border: 1px solid var(--border);
  color: var(--ok); border-radius: var(--radius-sm);
}
.col-head { font-family: var(--font-mono); text-transform: uppercase; letter-spacing: 1px; color: var(--text-faint); }
```

- [ ] **Step 4: Action blocks + attribute chips (amber tint), add-action / apply-mood**

```css
.action-block {
  background: var(--accent-tint);
  border: 1px solid var(--accent-border);
  border-left: 3px solid var(--accent-solid);
  border-radius: var(--radius-sm);
  color: var(--text);
}
.group-name { font-family: var(--font-mono); text-transform: uppercase; letter-spacing: 0.5px; color: var(--ok); }
.add-action, .apply-mood {
  background: transparent; border: 1px dashed var(--accent-border); color: var(--text-dim);
}
.add-action:hover, .apply-mood:hover { border-color: var(--accent-solid); color: var(--text); }
.cue-tc-capture { font-family: var(--font-mono); color: var(--ok); }
```

> NOTE: the existing `--action-color` runtime CSS hook (used by `color-mix` for per-action tint, ~line 172 of the original) MUST be preserved. Do not delete `var(--action-color, ...)` fallbacks — they carry per-attribute color data. Only adjust the surrounding neutral colors to tokens.

- [ ] **Step 5: Mood bar + chevron**

```css
.cue-mood-bar { border-top: 1px solid var(--border); }
.chevron { color: var(--text-faint); }
.cue-card[open] .chevron, .cue-header:hover .chevron { color: var(--accent-solid); }
```

- [ ] **Step 6: Visual smoke** — `open web/index.html`, add a song, add a cue, add an action, expand/collapse. Confirm: amber badge, softened brackets on cards, mono fade/delay in amber, action blocks tinted. Verify per-action color tiles still show their real color.

- [ ] **Step 7: Run web suite** — `node --test web/test/*.test.js` → 49 pass.

- [ ] **Step 8: Commit**

```bash
git add web/css/styles.css
git commit -m "feat(web-ui): Amber HUD cue cards — badge, chips, mono timing, action blocks"
```

---

## Task 5: Toolbar groups + Send→MA CTAs + OSC pill + Clear-all

**Files:**
- Modify: `web/css/styles.css`

Class/ID hooks: `#toolbar`, `.toolbar-group`, `.group-title`, `.group-row`, `.group-col`, `.send-subs`, `.send-sub`, `.sub-title`, `.osc-btn`, `.send-big`, `#storeMode`, `.osc-pill`/`#oscPill`, `.osc-target-inline`, `.store-label`, `#clearAll`/`.danger`.

- [ ] **Step 1: Toolbar group panels + HUD section labels + brackets**

```css
#toolbar { gap: 12px; }
.toolbar-group {
  background: var(--surface-1);
  border: 1px solid var(--accent-border);
  border-radius: var(--radius);
  position: relative;
}
.toolbar-group::before, .toolbar-group::after {
  content: ""; position: absolute; width: 10px; height: 10px; pointer-events: none;
  border: 1.5px solid rgba(234,166,79,0.4);
}
.toolbar-group::before { top: 5px; left: 5px; border-right: none; border-bottom: none; }
.toolbar-group::after  { bottom: 5px; right: 5px; border-left: none; border-top: none; }
.group-title, .sub-title, .store-label {
  font-family: var(--font-mono); text-transform: uppercase; letter-spacing: 1.4px;
  color: var(--text-faint);
}
```

- [ ] **Step 2: Send→MA commit CTAs (`.osc-btn.send-big`) — amber gradient + ▸ glyph + glow**

```css
.osc-btn.send-big {
  background: linear-gradient(135deg, var(--accent-start), var(--accent-end));
  color: var(--capture-ink);
  border: none;
  border-radius: var(--radius);
  font-family: var(--font-mono); font-weight: 600; letter-spacing: 0.5px;
  box-shadow: 0 0 14px rgba(234,166,79,0.45);
}
.osc-btn.send-big::before { content: "\25B8"; margin-right: 6px; font-size: 0.85em; } /* ▸ */
.osc-btn.send-big:hover:not(:disabled) { box-shadow: 0 0 20px rgba(234,166,79,0.65); }
.osc-btn.send-big:disabled { opacity: 0.4; box-shadow: none; cursor: not-allowed; }
```

> The `::before` ▸ glyph is decorative; it does not affect the button's accessible name (the text node remains). This mirrors the iOS `AmberCTAStyle` leading triangle.

- [ ] **Step 3: `#storeMode` select + OSC pill (brightness-coded status)**

```css
#storeMode {
  background: var(--surface-2); color: var(--text);
  border: 1px solid var(--border); border-radius: var(--radius-sm);
  font-family: var(--font-mono);
}
.osc-pill { font-family: var(--font-mono); letter-spacing: 1px; border-radius: var(--radius-lg); }
.osc-pill.offline { color: var(--text-faint); border: 1px solid var(--border); }
.osc-pill.online  { color: var(--ok); border: 1px solid var(--accent-border); box-shadow: 0 0 10px rgba(240,192,116,0.4); }
.osc-target-inline { font-family: var(--font-mono); color: var(--text-dim); }
```

> If the OSC pill's online/offline class names differ from `.online`/`.offline`, grep `web/js/osc.js` for the exact classList toggles and match them. Do not change the JS.

- [ ] **Step 4: `.danger` / Clear-all — red, the one non-amber affordance**

```css
button.danger {
  background: transparent;
  color: var(--danger);
  border: 1px solid rgba(255,107,107,0.4);
  border-radius: var(--radius-lg);
  font-family: var(--font-mono); text-transform: uppercase; letter-spacing: 1px;
}
button.danger:hover { background: rgba(255,107,107,0.12); border-color: var(--danger); }
```

- [ ] **Step 5: Visual smoke** — `open web/index.html`. Confirm: grouped toolbar panels with brackets + uppercase mono titles; Send→MA buttons are amber with a leading ▸ and glow; disabled state dims; Clear all is red.

- [ ] **Step 6: Run web suite** — `node --test web/test/*.test.js` → 49 pass.

- [ ] **Step 7: Commit**

```bash
git add web/css/styles.css
git commit -m "feat(web-ui): Amber HUD toolbar — Send-to-MA CTAs, OSC pill, Clear-all"
```

---

## Task 6: Audio panel / timeline — Full-HUD chrome + clean instrument zone

**Files:**
- Modify: `web/css/styles.css`

Class hooks (from `audio.js`/`transport.js`/`render.js`): `audio-body`, `channels`, `channel-wave`, `chan-label`, `channel-toggle`, `console-box`, `console-meta`, `console-sep`, `ltc-badge`, `ltc-status`, `led-amber`, `led-cyan`, `led-label`, `led-main`, `marker`, `filename`, `loop`, `lock`, plus the SMPTE reader and transport-bar elements (grep `transport.js` for exact classes — likely `transport`, `tc-read`/`smpte`, transport button classes).

- [ ] **Step 1: Audio panel frame — Full-HUD chrome (glass + brackets + scanlined header)**

```css
#audioPanel {
  background: var(--surface-1);
  border: 1px solid var(--accent-border);
  border-radius: var(--radius);
  position: relative;
}
#audioPanel::before, #audioPanel::after {
  content: ""; position: absolute; width: 11px; height: 11px; pointer-events: none;
  border: 1.5px solid rgba(234,166,79,0.5);
}
#audioPanel::before { top: 5px; left: 5px; border-right: none; border-bottom: none; }
#audioPanel::after  { bottom: 5px; right: 5px; border-left: none; border-top: none; }
#audioPanel.empty { color: var(--text-faint); }
.filename { font-family: var(--font-mono); color: var(--text-dim); }
```

- [ ] **Step 2: SMPTE reader + transport bar (mono, glow, amber play)**

Grep the exact classes first: `grep -nE "smpte|tc-read|transport|btn" web/js/transport.js | head`. Then style the SMPTE readout and transport buttons. Representative rules (adjust selectors to the grep results):

```css
/* big SMPTE time reader */
.smpte, .tc-read {
  font-family: var(--font-mono); letter-spacing: 2px;
  color: var(--ok); text-shadow: 0 0 10px rgba(240,192,116,0.55);
}
/* transport buttons */
.transport button { background: var(--surface-2); border: 1px solid var(--accent-border); color: var(--ok); border-radius: var(--radius-sm); }
.transport button.play, .transport .is-playing {
  background: linear-gradient(135deg, var(--accent-start), var(--accent-end));
  color: var(--capture-ink); box-shadow: 0 0 16px rgba(234,166,79,0.6);
}
```

- [ ] **Step 3: Console box (Reaper-style) — HUD chrome, NOT scanlined over text**

```css
.console-box {
  background: rgba(0,0,0,0.30);
  border: 1px solid var(--accent-border);
  border-radius: var(--radius-sm);
  font-family: var(--font-mono); color: var(--text-dim);
}
.console-meta { color: var(--text-faint); }
.console-sep { color: var(--accent-border); }
.console-box .ok, .ltc-status.locked { color: var(--ok); }
```

- [ ] **Step 4: CLEAN INSTRUMENT ZONE — waveform canvas stays un-ornamented**

This is the core spec decision. The grid/scanline overlay is on `body::before` (z-index 0, behind `.wrap` at z-index 1), so it already does NOT bleed over the waveform. Explicitly guarantee the waveform area has a solid (non-transparent) backing so no app-level grid shows through, and keep functional colors:

```css
.channels, .channel-wave {
  background: rgba(0,0,0,0.32);   /* solid-ish backing: app grid never shows through the signal */
  border-radius: var(--radius-sm);
}
/* waveform signal = bright amber; do NOT add decorative grid/scanline here */
.channel-wave canvas { display: block; }
.marker { background: var(--danger); }          /* cue markers stay functional RED */
.marker::after { border-top-color: var(--danger); }
.chan-label, .led-label { font-family: var(--font-mono); color: var(--text-faint); text-transform: uppercase; letter-spacing: 1px; }
```

> The white playhead is drawn on the canvas by `audio.js` (not CSS) — leave it. If the playhead is a DOM element with a class, ensure it is `#fff`; grep `transport.js`/`audio.js` for `playhead` and match. Do not change drawing logic.

- [ ] **Step 5: Re-tone `led-cyan` into the amber family (amber-only rule)**

```css
.led-cyan { color: var(--ok); }            /* was cyan — re-toned to bright amber */
.led-amber { color: var(--accent-solid); } /* keep amber */
.led-main, .ltc-badge { font-family: var(--font-mono); }
```

> Grep `grep -n "led-cyan\|#0\|cyan\|aqua\|#5b8dd6\|#3d6ec6" web/css/styles.css` and convert ANY remaining cyan/blue literals in the audio section to amber tokens. There must be zero non-amber UI accents after this task (lighting-color `.color-tile` swatches excluded).

- [ ] **Step 6: Visual smoke WITH AUDIO** — `open web/index.html`, load an audio file, scrub. Confirm: panel has HUD chrome + brackets; SMPTE reader glows amber; waveform is a clean bright-amber signal on a dark bed with NO decorative grid/scanlines over it; **white playhead and red markers clearly legible**; console reads amber-on-dark; no cyan anywhere.

- [ ] **Step 7: Run web suite** — `node --test web/test/*.test.js` → 49 pass.

- [ ] **Step 8: Commit**

```bash
git add web/css/styles.css
git commit -m "feat(web-ui): Amber HUD audio panel — chrome + clean instrument zone, led-cyan retone"
```

---

## Task 7: Modals, pool picker, color popover, status pills, settings dialog

**Files:**
- Modify: `web/css/styles.css`

Class/ID hooks: `.modal`, `.modal-backdrop`, `.modal-content`, `.modal-header`, `.close-modal`, `.pool-picker-toolbar`, `.pool-picker-grid`, `.color-tile`, `#poolsPaste`, `#settingsDialog`, `.settings-error`, `.phone-pill`/`#phonePill`, `.desk-status`, `.empty-hint`.

- [ ] **Step 1: Modal shell — glass content + backdrop + header**

```css
.modal-backdrop { background: rgba(8,6,3,0.6); backdrop-filter: blur(3px); }
.modal-content {
  background:
    radial-gradient(500px at 0% 0%, rgba(122,79,30,0.30), transparent),
    var(--canvas-2);
  border: 1px solid var(--accent-border);
  border-radius: var(--radius-lg);
  color: var(--text);
  box-shadow: 0 24px 60px rgba(0,0,0,0.6);
}
.modal-header { border-bottom: 1px solid var(--border); }
.modal-header h2 { font-family: var(--font-mono); text-transform: uppercase; letter-spacing: 1.6px; font-size: 1em; color: var(--text); }
.close-modal { background: transparent; border: none; color: var(--text-faint); }
.close-modal:hover { color: var(--danger); }
```

- [ ] **Step 2: Pool picker toolbar + grid + the paste textarea**

```css
.pool-picker-toolbar input { font-family: var(--font-mono); }
.pool-picker-grid { gap: 6px; }
#poolsPaste {
  background: rgba(0,0,0,0.30) !important;   /* override inline style */
  border: 1px solid var(--accent-border) !important;
  color: var(--text) !important;
  border-radius: var(--radius-sm);
}
```

> NOTE: `#poolsPaste` and several modal widths use INLINE styles in `index.html`. Do not edit the HTML; override only what's necessary in CSS with `!important` (used sparingly, only where an inline style must be overridden). Widths set inline can stay.

- [ ] **Step 3: Color tiles — keep real colors, only style the chrome**

```css
.color-tile { border: 1px solid var(--border); border-radius: var(--radius-sm); }
.color-tile.current { outline: 2px solid var(--accent-solid); outline-offset: 2px; }
```

> The tile FILL is set at runtime via `var(--swatch-color)` / inline background = real lighting color. DO NOT touch the fill. Only the border + the "current" outline (was `#f0a830`, now the accent token) are chrome.

- [ ] **Step 4: Status pills + settings dialog + desk status row**

```css
.desk-status { border-top: 1px solid var(--border); }
.phone-pill { font-family: var(--font-mono); letter-spacing: 0.5px; color: var(--text-dim); border: 1px solid var(--border); border-radius: var(--radius-lg); }
.phone-pill.connected { color: var(--ok); border-color: var(--accent-border); box-shadow: 0 0 10px rgba(240,192,116,0.35); }
#settingsDialog {
  background: var(--canvas-2); color: var(--text);
  border: 1px solid var(--accent-border); border-radius: var(--radius-lg);
}
#settingsDialog::backdrop { background: rgba(8,6,3,0.6); }
#settingsDialog label { font-family: var(--font-mono); color: var(--text-dim); font-size: 0.85em; }
.settings-error { color: var(--danger); font-family: var(--font-mono); }
.empty-hint { color: var(--text-faint); }
```

> Grep `web/js/main.js` for the phone-pill connected-state class (may be `.connected` or a toggled text/class). Match the real class; do not change JS.

- [ ] **Step 5: Visual smoke** — `open web/index.html`. Open Moods, Defaults, Pools, Pool-picker modals + color popover; open Settings dialog. Confirm glass modals, mono headers, amber chrome, color tiles still show real colors, red close-hover and error text.

- [ ] **Step 6: Run web suite** — `node --test web/test/*.test.js` → 49 pass.

- [ ] **Step 7: Commit**

```bash
git add web/css/styles.css
git commit -m "feat(web-ui): Amber HUD modals, pool picker, color popover, settings dialog"
```

---

## Task 8: Wordmark — rename to SAETTA

**Files:**
- Modify: `web/index.html` (text only — no ID changes)

- [ ] **Step 1: Update `<title>` and `h1`**

In `web/index.html`, change:

```html
<title>Cuelist Compiler</title>
```
to
```html
<title>Saetta</title>
```

and change:

```html
  <h1>Cuelist Compiler</h1>
```
to
```html
  <h1>&#9656; SAETTA</h1>
```

(`&#9656;` is the ▸ glyph; the `h1` is already styled uppercase mono in Task 1.)

- [ ] **Step 2: Run the guard test — IDs still intact**

Run: `node --test web/test/restyle-guard.test.js`
Expected: all 3 pass (the wordmark change touches no IDs).

- [ ] **Step 3: Visual smoke** — `open web/index.html`. Confirm the header reads `▸ SAETTA`.

- [ ] **Step 4: Commit**

```bash
git add web/index.html
git commit -m "feat(web-ui): rename desktop wordmark to SAETTA"
```

---

## Task 9: Final verification — full sweep + frozen-contract checks

**Files:** none (verification only)

- [ ] **Step 1: Full web suite green**

Run: `node --test web/test/*.test.js`
Expected: 49 pass, 0 fail.

- [ ] **Step 2: Desktop suite green**

Run: `cd desktop && npm test`
Expected: existing desktop tests pass (settings, hub), 0 fail. Then `cd ..`.

- [ ] **Step 3: Frozen-contract check — no logic touched**

Run: `git diff main --stat -- hub/ web/js/`
Expected: EMPTY output (no hub or web/js changes). If `web/js` shows changes, they are a mistake — revert them; all visual work is CSS.

Run: `git diff main --stat -- web/index.html`
Expected: only the two wordmark lines changed.

- [ ] **Step 4: No stray non-amber accents**

Run: `grep -nE "#5b8dd6|#3d6ec6|#2c3e62|#4d80d6|cyan|aqua|#0(ff|cf|af)" web/css/styles.css`
Expected: no matches in UI-chrome context. (Lighting-color literals tied to `.color-tile`/`--swatch-color`/`--action-color`/`--pool-color` data hooks are allowed; anything else is a leftover and must be tokenized.)

- [ ] **Step 5: Electron visual smoke**

Run: `cd desktop && npm install && npm start`
Expected: app launches; aurora canvas + grid/scanlines; cue cards + toolbar brackets; Send→MA CTAs glow with ▸; load audio → clean instrument zone (legible white playhead + red markers) under HUD chrome; Settings dialog renders; `▸ SAETTA` wordmark. Close the app.

- [ ] **Step 6: Browser click-through**

Run: `open web/index.html`
Expected: full pass of the spec's browser checklist — add song/cue, expand/collapse, open each modal + color popover, toggle store mode, load audio, confirm clean timeline.

- [ ] **Step 7: Final commit (if any verification tweaks were needed)**

```bash
git add -A
git commit -m "chore(web-ui): final Amber HUD verification fixes"
```

(Skip if Steps 1–6 needed no changes.)

---

## Self-Review (completed by plan author)

- **Spec coverage:** token system (T1), full canvas/ornament (T1–T2), sidebar/header/inputs (T3), cue cards (T4), toolbar + Send→MA CTAs (T5), audio timeline + clean instrument zone + led-cyan retone (T6), modals/pool-picker/color-popover/status/settings (T7), wordmark→SAETTA (T8), non-goals + frozen contracts + testing (T9). Every spec section maps to a task.
- **Placeholder scan:** all code steps contain concrete CSS/JS/HTML. The few "grep the exact class then match" notes (transport SMPTE, OSC pill state, phone-pill state, playhead) are deliberate — those classes are emitted by JS not visible in markup; the instruction is exact (grep target + what to match) and forbids changing JS. Not vague placeholders.
- **Type/selector consistency:** token names are identical between the `:root` definition (T1) and every consumer; guard-test token list (T1) matches the `:root` block exactly; CTA selector `.osc-btn.send-big` and `.danger` consistent across T3/T5.
- **Frozen contract:** T9 Step 3 enforces empty `git diff` on `hub/` and `web/js/`, matching the spec's non-goals.

# Design Spec — Desktop "Amber HUD" Restyle (web/)

**Date:** 2026-06-11
**Status:** Approved (brainstorming) — pending implementation plan
**Surface:** `web/` shared UI (browser build **and** Electron desktop, which packages `web/`)
**Supersedes:** PR #5 ("Tinted Vibrancy", violet→blue) — closed in favour of brand-aligned amber.

## Summary

Restyle the shared `web/` UI into a dark, cyber-tech **"Amber HUD"** look that matches the
iOS Saetta app's design language (the iOS "Balanced Amber HUD" that shipped 2026-06-11).
The desktop intentionally goes **one step more intense than iOS** — a **Full HUD** chrome
(tick-grids, corner brackets, scanlines, glow) — with **one deliberate exception**: the audio
timeline stays a **clean instrument zone** so the waveform/playhead/markers read precisely.

This is a **CSS-only restyle**. No app logic, OSC/UDP transport, compile, audio engine, LTC,
or hub code is touched. Element IDs are preserved so `main.js` event wiring is unchanged.
The only non-CSS edit is the wordmark text (`<title>` + `h1`).

## Why (context)

- PR #5 restyled `web/` to a violet→blue "Tinted Vibrancy" look on 2026-06-05. It is now
  **253 commits stale**, conflicts in `styles.css` + `index.html`, and — critically — never
  saw the ~12 feature areas added since (audio timeline, transport, SMPTE reader, Reaper-style
  console, LTC markers, per-cue TC, time-ruler). It also predates the project's convergence on
  **amber as the only brand hue** (iOS shipped Amber HUD).
- Mechanically merging PR #5 would produce a half-redesigned, off-brand UI. Instead we rebuild
  the restyle fresh on current `main`, aligned to amber, covering **all** current components.

## Design Decisions (validated via visual companion)

1. **Intensity = Full HUD** (chosen over Restrained / Balanced). Tick-grids behind panels,
   corner brackets on cards/panels/action groups, subtle scanline overlay, amber glow on
   commit CTAs and the live indicator.
2. **Audio timeline = clean instrument zone** (chosen over ornament-over-signal). HUD chrome
   frames it; the waveform canvas itself carries only functional ruler ticks, the bright amber
   signal, the **white playhead**, and **red cue markers** — no decorative grid/scanlines over
   the signal.
3. **Amber is the only hue.** Status is signalled by **brightness + glyph**, not by a second
   colour. The sole exception is **red (`#ff6b6b`), reserved for destructive delete** (and the
   functional red of cue markers on the waveform). The stray `led-cyan` accent is re-toned into
   the amber family.
4. **Wordmark → `▸ SAETTA`** (uppercase, letter-tracked, mono), replacing "Cuelist Compiler"
   in `<title>` and `h1`.
5. **Action bar = pure restyle.** `main`'s toolbar is already grouped into labelled sections
   (Send→MA / Export / Project / Import / Clear). Keep that structure and all element IDs
   exactly; apply Full-HUD styling only. No segmented-control / split-menu / overflow
   restructure (that was for PR #5's older flat toolbar and is out of scope).

## Approach

**CSS-only, token-driven.** Add a `:root` design-token block to `web/css/styles.css` as the
single source of truth, then restyle every component by referencing those tokens. Full-HUD
ornament is achieved entirely with CSS `background` layers and `::before`/`::after`
pseudo-elements (corner brackets drawn as positioned gradients/borders; tick-grids and
scanlines as layered repeating gradients), so there is **zero markup churn**. Dynamic markup
(cue cards, audio panel, console, markers) is restyled via its existing, stable class hooks —
no `render.js` / `audio.js` / `transport.js` changes.

*Alternative considered & rejected:* adding bracket/utility wrapper `<div>`s to `index.html`
and `render.js` for finer per-panel control — touches generated markup, adds risk, no real
gain over the pure-CSS technique.

## Token System (`:root`)

Port the iOS `Theme` palette into CSS custom properties:

| Token | Value | Role |
|---|---|---|
| `--accent-start` / `--accent-end` | `#f0b860` / `#e0913f` | commit-to-MA CTA gradient |
| `--accent-solid` | `#eaa64f` | solid amber, glow source |
| `--accent-tint` / `--accent-border` | `#f0b860`@12% / @22% | group-card fill / glass hairline |
| `--capture` | `#f5d8a6` | pale-amber "capture/voice" tone |
| `--capture-ink` | `#2a1d07` | dark ink on light-amber surfaces |
| `--surface-1/2/3` | white @ 5% / 7% / 10% | layered glass surfaces |
| `--border` / `--border-strong` | white @ 8% / 14% | hairlines |
| `--text` / `--text-dim` / `--text-faint` | `#f6ead6` / `#c2a079` / `#94795e` | warm off-white text hierarchy |
| `--ok` / `--warn` | `#f0c074` / `#d49a4a` | live/success / connecting (brightness-coded) |
| `--danger` | `#ff6b6b` | **destructive delete only** |
| `--radius` / `--radius-sm` / `--radius-lg` | 7px / 4px / 11px | tightened HUD radii |
| `--grid-line` / `--scanline` | amber @ ~5% / white @ ~2.5% | ornament opacities |
| `--font-mono` | `ui-monospace, "SF Mono", Menlo, monospace` | HUD numerics + labels |

Canvas: dark gradient `#1d160e → #15110a → #0f0c07` with two radial amber blooms (top-left,
bottom-right), matching the iOS aurora canvas.

## Component Coverage (all)

- **Canvas / body:** amber aurora background + tick-grid + scanline overlay.
- **Sidebar + song list:** glass surface, mono song sequence numerics, amber active-state.
- **Header / inputs:** glass fields, amber focus rings, mono `SEQ` numeric.
- **Cue cards** (`cue-card`/`cue-header`/`cue-num`/`cue-name`/`action-block`/`cue-timing`/
  `cue-summary`/`cue-mood-bar`): corner brackets, amber circular cue badge, mono fade/delay,
  amber attribute chips.
- **Toolbar groups:** HUD section labels (uppercase mono). **Send→MA** buttons become amber-CTA
  with leading `▸` glyph + glow; ghost buttons get amber hairline treatment; **Clear all** stays
  red (delete affordance).
- **Audio panel / timeline:** Full-HUD chrome (mono SMPTE reader with text-glow, transport
  buttons with amber play, scanlined panel frame, console box) **+ clean instrument zone** for
  the waveform (`channel-wave`/`marker`/playhead).
- **Modals** (moods / defaults / pools / pool-picker / color popover): glass content, amber
  hairlines, mono labels; `color-tile` swatches keep their functional colours (lighting colours,
  not UI chrome) — only the surrounding chrome is amber.
- **Status pills + settings dialog:** brightness-coded amber pills, glass dialog. `led-cyan`
  re-toned to amber; `led-amber` unchanged.

## Non-Goals (frozen)

- No changes to: app logic, OSC/UDP transport (`osc.js`), compile (`compile.js`), audio engine
  (`audio.js` logic), LTC (`ltc.js`), state (`state.js`), hub (`hub/`).
- `git diff main -- hub/` stays empty.
- All element IDs in `index.html` preserved → `main.js` wiring unchanged.
- No toolbar restructure (segmented control / split menus / overflow are out of scope).
- `color-tile` swatch fills (real lighting colours) are NOT re-toned — they are data, not chrome.

## Testing & Verification

- **Existing suites green** (no logic touched): web transport, desktop settings, hub.
- **Static checks:** CSS braces balanced; `node --check` on any touched JS (none expected
  beyond the wordmark, which is HTML); confirm every `index.html` element ID still present.
- **Electron visual smoke** (`cd desktop && npm install && npm start`): aurora canvas, Full-HUD
  panels, brackets/grid/scanlines render; Send→MA CTAs glow; Settings dialog renders.
- **Browser click-through:** add song/cue, expand/collapse, open each modal + color popover,
  toggle store mode, **load audio and confirm the clean instrument zone** (legible waveform,
  white playhead, red markers) under the HUD chrome.

## Out of Scope / Follow-ups

- Signed desktop builds, packaging.
- Any new toolbar information architecture.
- iOS parity audit beyond the shared visual language.

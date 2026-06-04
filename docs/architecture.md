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

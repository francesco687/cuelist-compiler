# Cuelist Compiler

Author per-song cuelists for grandMA3 and ship them as a runnable Lua plugin or
send them live over OSC.

## Repo layout

| Path | What |
|------|------|
| `web/` | The authoring web app (open `web/index.html` — no build). |
| `desktop/` | **Desktop app (Electron) — recommended for operators.** Packages the web UI, sends OSC/UDP directly to the desk, and embeds the hub so an iPhone can connect as a companion. |
| `ios/` | Native SwiftUI frontend (companion controller). |
| `proxy/` | WebSocket→OSC bridge for live send (browser/dev). |
| `hub/` | WebSocket→compile→OSC hub — used by the iPhone app and embedded in the desktop app. |
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

## Desktop app (recommended for operators)

For running a show on a laptop, the **desktop app** (`desktop/`) is the recommended
path. It wraps the same authoring UI in a native window, sends OSC/UDP **directly**
to the desk (no separate proxy to start), and **embeds the hub** so an iPhone can
connect to the laptop as a companion controller.

1. Run from source: `cd desktop && npm install && npm start`.
2. Build installers: `cd desktop && npm run dist` — macOS `.dmg` (signed + notarized)
   and Windows `.exe`.
3. In **⚙ Settings**: set the MA3 host / UDP port / OSC prefix, and toggle the
   embedded hub (default port `9000`) for the iPhone companion. The status row shows
   the live OSC target and whether a phone is connected.

This **supersedes the Raspberry Pi hub** (`hub/deploy/cuelist-hub.service`): the
laptop now does what the Pi did, so a dedicated Pi is no longer required. The systemd
unit remains for headless / always-on deployments but is no longer the recommended
setup.

## Features

- **Multi-song show**: each song has its own sequence number, cues, audio track.
- **CSV import**: drop a CuePoints `.csv` export — a new song appears with all the named cues already created.
- **MA3 pool autocomplete**: import groups + the 6 preset pools from MA via the included `export_pools.lua` plugin; pick items from a MA3-style popup grid (search by name or pool number).
- **Group color tagging**: color-code group blocks for visual organization across cues.
- **Mood library**: save reusable lighting "looks" and apply them to any cue with one click.
- **Defaults**: set global default Fade / Delay per pool; per-preset overrides only where needed.
- **Audio per song**: load an `.mp3` / `.wav` per song to see waveforms, play, and time cues against the track.
- **Two export paths**:
  - **`.lua` plugin** — paste into a gma3 plugin slot, Save, Run. Includes ClearAll before each cue (tracking on by default) and Store with Overwrite/Merge toggle.
  - **OSC live** — `Send → MA` buttons stream the same commands through the local WebSocket→OSC proxy. No paste required.

## OSC live mode

Send commands straight to MA without the paste step.

1. Start the proxy — **macOS/Linux:** `cd proxy && ./start.sh`; **Windows:** `cd proxy && start.bat`. First run installs `ws` via npm; subsequent runs just start the bridge on `ws://127.0.0.1:8765`.
2. In MA3: Menu → Network → MA Network Configuration → OSC. **Enable Input**. OSCData row: Destination `127.0.0.1`, UDP, Port `8000`, Prefix `gma3`, **Receive=Yes, Receive Command=Yes, Echo Input=Yes**. Echo Input is required for `/cmd` to actually dispatch — counterintuitive but verified on MA3 onPC.
3. In the compiler: `Send current → MA` (active song) or `Send all → MA` (entire show).

OSC address: `/gma3/cmd` with one string arg = the full MA command line.

## Requirements

- **Browser**: Chrome or Edge.
- **MA3 onPC**: tested on 2.3.2.
- **OSC live mode**: Node.js (any recent version; 24.x verified).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Two-person project; work on branches,
merge via PR.

## License

MIT — see [LICENSE](LICENSE).

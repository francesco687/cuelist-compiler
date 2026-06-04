# Cuelist Compiler

Single-file HTML app to author per-song cuelists for grandMA3 and ship them as a runnable Lua plugin or send them live over OSC.

## What it does

Build a multi-song show structurally — pick a Group, assign Color / Dimmer / Position / Gobo / Beam / Focus presets, set fade & delay per cue or per attribute — then emit a `.lua` plugin you paste into a gma3 plugin slot. Or stream the same commands live over OSC through a small WebSocket→OSC Node proxy.

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

## Quick start

1. Open `cuelist-compiler.html` in Chrome or Edge.
2. (Recommended) Run `plugins/export_pools.lua` once on your MA3 show to import groups + preset pool names — gives you autocomplete with the real names.
3. Import a CuePoints `.csv` (the `Import .csv` button), or create songs manually with `+ New Song`.
4. Fill in cues — Group + preset names + fade / delay.
5. Either **Export .lua** and paste into a gma3 plugin, or start the OSC proxy and click **Send → MA**.

## OSC live mode

Send commands straight to MA without the paste step.

1. `cd proxy && start.bat` — first run installs `ws` via npm; subsequent runs just start the bridge on `ws://127.0.0.1:8765`.
2. In MA3: Menu → Network → MA Network Configuration → OSC. **Enable Input**. OSCData row: Destination `127.0.0.1`, UDP, Port `8000`, Prefix `gma3`, **Receive=Yes, Receive Command=Yes, Echo Input=Yes**. Echo Input is required for `/cmd` to actually dispatch — counterintuitive but verified on MA3 onPC.
3. In the compiler: `Send current → MA` (active song) or `Send all → MA` (entire show).

OSC address: `/gma3/cmd` with one string arg = the full MA command line.

## File layout

```
cuelist-compiler/
├── cuelist-compiler.html   the app — open in a browser
├── examples/
│   ├── SONG_1.json         known-good project, loads via Load Project
│   └── SONG_1.lua          the matching generated plugin output
├── plugins/
│   └── export_pools.lua    run in MA to dump groups + preset names as JSON
└── proxy/
    ├── ws2osc.js           WebSocket → OSC/UDP bridge for live mode
    ├── package.json
    └── start.bat
```

## Requirements

- **Browser**: Chrome or Edge.
- **MA3 onPC**: tested on 2.3.2.
- **OSC live mode**: Node.js (any recent version; 24.x verified).

## License

MIT — see [LICENSE](LICENSE).

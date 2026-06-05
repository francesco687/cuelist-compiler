# Cuelist Compiler — Desktop App

A cross-platform **Electron** app for running a show from a laptop. It wraps the
existing `web/` authoring UI in a native window, sends OSC/UDP **directly** to the
grandMA3 desk (no separate proxy to start), and **embeds the hub** so an iPhone can
connect to the laptop as a companion controller — no Raspberry Pi required.

This is the **recommended path for operators**. (The browser + `proxy/` flow still
works and is kept for dev; the Pi hub in `hub/deploy/` is superseded.)

## How it fits together

```
┌─ desktop app (this folder) ──────────────────────────────┐
│  Electron window = web/index.html (the authoring UI)      │
│        │ per-line OSC command (IPC)                       │
│        ▼                                                  │
│  main process → OscSender ──UDP /gma3/cmd──►  grandMA3    │
│        │                                                  │
│        └─ embedded hub (ws://0.0.0.0:9000) ◄── iPhone app │
└───────────────────────────────────────────────────────────┘
```

`main.js` loads `../web/index.html` and reuses `../hub/src/*`, so the **whole repo**
must be checked out (not just this folder). A packaged build bundles `web/` and
`hub/src/` inside the app automatically.

## Prerequisites

- **Node.js** LTS (18 / 20 / 22) — includes `npm`. Only needed to install/build;
  the app itself runs on Electron's bundled Node.
- **Git**.
- A grandMA3 target: **onPC** (same machine is fine) or a real console.

## Run from source (fastest — best for a first test)

```sh
git clone https://github.com/francesco687/cuelist-compiler.git
cd cuelist-compiler/desktop
npm install      # one-time; downloads the Electron binary for your OS
npm start        # opens the Cuelist Compiler window
```

No build, no installer, no signing prompts. This is the reliable path on any OS.

## Build an installer

```sh
cd desktop
npm run dist
```

Output lands in `desktop/dist/`:

| OS | Artifact | Notes |
|----|----------|-------|
| **Windows** | `Cuelist Compiler Setup 0.1.0.exe` (NSIS) | **Unsigned (v1).** On launch, SmartScreen shows *"Windows protected your PC / unknown publisher"* → **More info → Run anyway**. A code-signing cert is deferred. |
| **macOS** | `Cuelist Compiler-0.1.0.dmg` | Signed + notarized **only if** you export `APPLE_ID`, `APPLE_APP_SPECIFIC_PASSWORD`, `APPLE_TEAM_ID=UWJSLFQDGL` before `npm run dist`. Without those, build with `CSC_IDENTITY_AUTO_DISCOVERY=false npx electron-builder --dir` for an unsigned local app. |

> Build on the OS you're targeting (build the Windows `.exe` on Windows, the `.dmg`
> on macOS). The Windows installer build is new — if `electron-builder` hiccups,
> **run from source** instead; it needs no installer.

## Using it

1. **⚙ Settings** — set the MA3 **host** (`127.0.0.1` for onPC on this machine, or the
   console's IP e.g. `10.0.0.2`), **UDP port** `8000`, **OSC prefix** `gma3`. Optionally
   toggle the **embedded hub** (default port `9000`) for the iPhone companion. The
   status row shows the live OSC target and whether a phone is connected.
2. On **MA3**: Menu → Network → MA Network Configuration → **OSC**. Enable Input.
   OSCData row: UDP, Port `8000`, Prefix `gma3`, **Receive = Yes, Receive Command = Yes,
   Echo Input = Yes**. *(Echo Input is required for `/cmd` to dispatch — verified on onPC.)*
3. Author a song + cues, then **Send current → MA** (active song) or **Send all → MA**.

Settings persist to your user data dir:
- **Windows:** `%APPDATA%\cuelist-compiler-desktop\settings.json`
- **macOS:** `~/Library/Application Support/cuelist-compiler-desktop/settings.json`

## iPhone companion (optional)

The embedded hub means an iPhone running the `ios/` app can drive the desk through
the laptop:

1. Put phone + laptop on the same network — **Windows:** Settings → Network →
   *Mobile hotspot* (phone joins it); **macOS:** System Settings → *Internet Sharing*;
   or simply the same Wi‑Fi.
2. In the iPhone app's settings, set hub **host = the laptop's IP**, **port = 9000**.
3. The desktop status row shows **📱 phone connected**; sends from the phone relay
   through the laptop to the desk.

(Installing the iOS app on a phone needs Xcode + your own signing — separate from
testing this desktop app.)

## Troubleshooting

- **Firewall prompt on first run** — allow Node/Electron through (Private networks at
  least). Needed for the embedded hub's `:9000` listener; outbound OSC usually works
  regardless.
- **Nothing reaches MA** — confirm **Echo Input = Yes** and that the app's MA3 host/port
  match the desk's OSC input. Sends are fire-and-forget UDP, so a wrong host fails
  silently.
- **Port 9000 already in use** — the app fails *soft*: the desktop OSC path still works,
  only the iPhone companion is unavailable. Close whatever else holds `:9000` (a leftover
  hub, a second app instance) and reopen Settings → Save to retry the hub.
- **Hub disabled** — if you don't need the phone, untick *Embedded hub* in Settings.

## Tests

```sh
cd desktop && npm test          # settings module unit tests
cd ../web   && node --test test/transport.test.js   # renderer transport seam
cd ../hub   && npm install && npm test               # hub contract
```

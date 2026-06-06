# Cuelist Compiler — Internet Hub (menubar)

A stripped-down, **hub-only** macOS menubar app. Use it when you just need the
laptop to act as a hub for the iPhone **over the internet** (cellular / different
WiFi). It pairs with the phone through the Fly relay and relays each command to
the desk over OSC/UDP. It reuses `hub/src/*` for compiling/OSC — so the whole
repo must be checked out. Separate from `desktop/` (the full authoring app).

## Run from source

```sh
cd menubar-hub
npm install
npm start
```

A glyph appears in the menubar (`○` offline · `◐` relay up, no phone · `●` phone
paired). Click it for status, the **pairing code**, a live activity log, and MA3
settings.

## Use it

1. Deploy/confirm the relay (`relay/README.md`) so `wss://cuelist-relay.fly.dev` is up.
2. Set MA3 **host/port/prefix** in the popover (e.g. `127.0.0.1` / `8000` / `gma3`
   for onPC on this Mac, or the desk's IP). On MA3: OSC input, **Echo Input = Yes**.
3. Copy the **pairing code** into the iPhone app (Settings → Relay).
4. The dot turns green when the phone pairs; GO+/GO-/PAUSE/Send/Pull from the
   phone now flow laptop → desk, and each shows in the Activity log.

## Gotchas

- **onPC on the same Mac → OSC echo loop.** `Echo Input = Yes` is required for
  `/cmd` to dispatch, but if that OSC entry's **Output destination** points back at
  the input (`127.0.0.1:8000`), the echoed command re-enters its own input and
  **every command runs twice** (one tap → two GOs). Fix: set the OSC row's Output
  **Destination IP off-loopback** (e.g. the Mac's LAN IP, or disable Output), and
  keep Input `8000` + Echo Input `Yes`. A real desk on the network doesn't hit this.
- **Pairing code is regenerated on every launch** and only persisted once you change
  a setting from the popover — so the displayed code is stable across a session, but
  a relaunch yields a new one. Copy the current code into the phone each session.
- **Packaging standalone** (not run-from-source) must bundle the sibling `hub/` and
  `web/` trees — this app `require`s `../../hub/src/*` and the compiler reads `web/js`.

## Test

```sh
cd menubar-hub && npm test
```

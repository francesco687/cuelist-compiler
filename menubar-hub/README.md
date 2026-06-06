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

## Test

```sh
cd menubar-hub && npm test
```

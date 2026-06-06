# Cuelist Compiler — Internet Relay

A tiny stateless WebSocket pairer on Fly.io. The laptop **menubar hub** and the
iPhone both dial out to it and present a shared **pairing code**; the relay
forwards JSON between the one hub and one phone in that room. It never parses OSC
and never sees your LAN.

```
iPhone  ──wss──►  cuelist-relay (this)  ◄──wss──  menubar hub (laptop) ──OSC──► grandMA3
```

## Protocol

First frame from each side:

```json
{ "type": "join", "room": "<pairingCode>", "role": "hub" | "phone" }
```

Relay replies `{ "type": "joined" }`, then `{ "type": "peer", "connected": true|false }`
whenever the other side connects/drops. Every later frame is forwarded verbatim
to the opposite role. A socket that doesn't `join` within 5s is closed; frames
are capped at 256 KB; rooms are capped.

## Deploy

```sh
cd relay
fly launch --no-deploy --name cuelist-relay   # first time: creates the app from fly.toml
fly deploy
```

Health: `GET https://cuelist-relay.fly.dev/healthz` → `ok`.
The phone/laptop connect to `wss://cuelist-relay.fly.dev`.

> One machine, `min_machines_running = 1` (the laptop holds a persistent
> connection — don't let Fly stop it). Never run two `fly deploy` at once.

## Test

```sh
cd relay && npm install && npm test
```

# Saetta Hub — "Disconnect all" (soft kick)

**Date:** 2026-06-11
**Status:** Approved

## Problem

The Saetta Hub operator has no way to clear the room. Phones stay paired until
they disconnect themselves, and the only blunt instrument — regenerating the
pairing code — revokes access permanently. We want a one-click "kick everyone
out" that drops every connected phone but lets anyone rejoin immediately with
the same pairing code (soft kick).

## Constraint that shapes the design

The hub holds no sockets to phones. Both sides dial the Fly.io relay
(`cuelist-relay`) and meet in a room keyed by the pairing code. The iPhone app
auto-reconnects with 1–15 s backoff after any socket drop, so closing sockets
at the relay alone cannot make a kick stick. The kick must be a message the
*phone app* honors by stopping its reconnect loop.

## Chosen approach

Phone-honored kick, zero relay changes. The hub broadcasts a bare
`{"type":"kicked"}` frame; the relay's existing legacy-broadcast path
(`relay/src/rooms.js` — any non-`to-phone` hub frame goes to every phone)
delivers it. The deployed Fly relay is untouched.

Rejected alternatives:
- **Relay-enforced kick** (relay closes phone sockets on a `kick-all`
  control message): still needs the iOS change for stickiness, plus a Fly
  redeploy — strictly more moving parts for the same end state.
- **Kick + code regen** (hard lock-out): different semantics than wanted;
  regen already exists for that.

## Design

### Hub side (menubar-hub)

- `src/relay-client.js`: new `kickAll()` on `RelayHubClient` — sends the bare
  frame `{"type":"kicked"}` over the relay socket. Safe no-op when the socket
  is absent or not open.
- `main.js`: `ipcMain.handle('hub:kickAll', ...)` calling `client.kickAll()`.
- `preload.js`: expose `kickAll` on the `window.hub` bridge.
- `renderer/`: a **Disconnect all** button next to the roster.
  - Confirm-gated like the regen button: "Disconnect all paired phones?\n\n
    They can rejoin with the same pairing code."
  - Disabled when the roster is empty.
  - No bespoke roster bookkeeping: the list empties on its own as the relay
    broadcasts each phone's departure.

### iOS side (SaettaKit)

- `HubMessages.swift`: `IncomingMessage` gains `.kicked`
  (envelope `type: "kicked"`).
- `HubClient.handle`: on `.kicked`, do what `disconnect()` does — set
  `stopped`, bump `generation`, close the connection, clear the roster — but
  land on `state = .error("disconnected by hub")` instead of `.offline`, so
  the existing error UI explains what happened with no new views.
- Tapping Connect rejoins normally: `connect()` already resets `stopped`.
- `.kicked` is honored in any mode (relay or direct) — harmless and
  consistent, though only the relay path ever produces it today.

## Edge cases

- **Old phone builds** ignore the unknown frame and stay connected. Accepted:
  the operator owns the whole fleet.
- **Phone mid-send when kicked**: the link drops; existing failure handling
  applies.
- **Direct/LAN mode** is unaffected; the kick lives in the relay path.
- **Hub socket down when the button is clicked**: `kickAll()` no-ops (the
  button is also disabled because the roster is empty when offline).

## Testing

Hermetic, matching the existing suites:

- `menubar-hub/test/relay-client.test.js`: `kickAll()` emits exactly
  `{"type":"kicked"}`; safe no-op with no socket.
- `ios/Tests/KitTests/HubClientTests.swift`: `.kicked` parses; receiving it
  stops the reconnect loop (observable via the injectable `scheduleAfter`),
  clears the roster, sets `state == .error("disconnected by hub")`; a manual
  `connect()` afterwards reconnects.

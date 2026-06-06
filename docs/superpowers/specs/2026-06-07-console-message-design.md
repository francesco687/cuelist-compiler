# Send Message to Console — Design

**Date:** 2026-06-07
**App:** Saetta (iOS), `ios/`
**Branch:** `feat/console-message`

## Goal

Let the operator on an iPhone send a free-text note that pops up as a visible
message on the grandMA3 desk during a live show. This is the first step in
turning the **Live** tab (currently three full-screen transport buttons) into a
broader "control screen": the transport buttons shrink to ~half the screen and a
control area opens below them, starting with this message feature.

## User flow

1. On the **Live** tab, the operator types a note into an inline text field.
2. Taps **Send**.
3. A `MessageBox` popup appears on the focused grandMA3 screen showing the note,
   titled **"Saetta"**, with a single **OK** button.
4. The desk operator reads the note and taps **OK** to dismiss it.

Sending is optimistic (haptic + brief "Sent" confirmation, field clears), matching
the existing GO+/PAUSE/GO− transport behavior. No desk acknowledgement is awaited.

## Layout (Live tab)

```
LIVE TAB
┌─────────────────────────┐
│ ● connection row        │  (unchanged, fixed height, top)
├─────────────────────────┤
│                         │
│   GO+   PAUSE   GO-      │  top half — transport (was full screen)
│                         │
├─────────────────────────┤
│ ┌─────────────────────┐ │
│ │ Message to console… │ │  bottom half — control area, top-aligned
│ └──────────────[Send]─┘ │  (reserves room for future controls)
│                         │
└─────────────────────────┘
```

- Connection row stays at the top, fixed height (unchanged).
- The area below the connection row splits into two roughly equal flexible halves
  (`.frame(maxHeight: .infinity)` each):
  - **Top half:** the existing three `TransportButton`s. They share the half and
    therefore render at ~half their current height.
  - **Bottom half:** a `controlSection`, top-aligned (`alignment: .top`), holding
    the message control now and reserving space for future control buttons.
- **Message control:** a `TextField` ("Message to console…") and a **Send** button.
  - Send is **disabled** when the hub is offline OR the (sanitized) text is empty.
  - On Send: fire optimistically — medium haptic (reuse the existing
    `sensoryFeedback` trigger pattern), show a transient "Sent" label, clear the field.

## Command path (no hub / protocol change)

The desk popup is grandMA3's `MessageBox` Lua function, triggered inline from the
command line via the `Lua` keyword. It travels over the **exact same `cmd` OSC
passthrough** that GO+/PAUSE/GO− already use and that is desk-proven — so there is
**no change to the hub, the WebSocket protocol, or `OutgoingMessage`**.

### New builder (SaettaKit, pure + testable)

`ConsoleMessage.line(text:title:)` returns one command-line string, or `nil` if the
text is empty after sanitization:

```
Lua "MessageBox({title=[[Saetta]], message=[[<sanitized text>]], commands={{value=1,name=[[OK]]}}})"
```

- `title` defaults to `"Saetta"`.
- Lua **long-bracket strings** `[[ … ]]` wrap both the title and the message so we
  never need single/double quotes inside the Lua — sidestepping nested-quote escaping
  across the two parsers (MA command line + Lua 5.4).

### Sanitization (the two-parser wrinkle)

User text passes through two parsers (the MA command-line `Lua "…"` wrapper, then
Lua's `[[ … ]]`). To keep both well-formed regardless of input:

1. Replace newlines and tabs with single spaces (the OSC `cmd` frame is one line).
2. Remove the `"` character (would close the outer command-line string).
3. Remove the `]]` sequence (would close the Lua long bracket).
4. Trim leading/trailing whitespace and collapse runs of spaces.
5. Cap length at **200 characters** (truncate).
6. If the result is empty, `line(...)` returns `nil` and no send occurs.

The same sanitization is applied to a non-default `title` (kept simple; the UI only
passes the fixed `"Saetta"` for now).

### New HubClient method

```swift
func sendConsoleMessage(_ text: String) {
    guard let line = ConsoleMessage.line(text: text) else { return }
    sendCommand(line)   // existing optimistic cmd passthrough
}
```

The Live view calls `sendConsoleMessage(_:)` and never builds command strings itself.

## Components & responsibilities

| Unit | Responsibility | Depends on |
| --- | --- | --- |
| `ConsoleMessage` (Kit) | Pure: sanitize text + build the `Lua "MessageBox(…)"` line, or `nil` | nothing |
| `HubClient.sendConsoleMessage` (Kit) | Thin: build line, forward via existing `sendCommand` | `ConsoleMessage`, `sendCommand` |
| `LiveView` (App) | Layout split + message field/Send + optimistic feedback | `HubClient` |

## Error handling

- **Offline:** Send disabled (matches transport buttons; `sendCommand` also no-ops
  when there is no connection).
- **Empty / whitespace-only / sanitizes-to-empty:** Send disabled / no-op.
- **No desk ack:** by design — optimistic, like the existing transport. The "Sent"
  label is a local confirmation that the frame was dispatched, not a desk receipt.

## Testing (TDD)

`ConsoleMessage` unit tests in the Kit test target (currently 35 tests):

- Normal text → exact `Lua "MessageBox({title=[[Saetta]], message=[[hello]], commands={{value=1,name=[[OK]]}}})"`.
- `"` in text → removed.
- `]]` in text → removed.
- Newline / tab → collapsed to space.
- Leading/trailing + doubled spaces → trimmed/collapsed.
- > 200 chars → truncated to 200.
- Empty / whitespace-only → `nil`.
- Custom title → appears in `title=[[ … ]]` and is sanitized too.

The view layer stays thin enough not to need new UI tests; manual device smoke on
jPhone (2) against the desk confirms the popup renders and dismisses.

## Out of scope (YAGNI)

- Message presets / quick-send buttons.
- Editable popup title (fixed "Saetta" for now).
- Auto-dismiss timer (operator taps OK).
- Send history / log.

The bottom-half control area is structured so presets and additional control buttons
can be added later without reworking the layout.

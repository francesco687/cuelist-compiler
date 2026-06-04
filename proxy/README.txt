Cuelist Compiler — OSC Proxy
============================

This is a small Node.js bridge that lets the cuelist-compiler.html browser app
talk to grandMA3 via OSC.

Browser  --(WebSocket)-->  this proxy  --(OSC over UDP)-->  gma3 onPC


ONE-TIME SETUP
--------------

1. Make sure Node.js is installed (already verified: v24.15.0).
2. Double-click `start.bat`. On first launch it runs `npm install` (~5 seconds).


gma3 SIDE (one-time per show file)
-----------------------------------

1. In gma3 onPC: Menu -> Network -> MA Network Configuration -> OSC
2. Click "Enable Input" toggle at the top.
3. Add an OSC Input row:
     Destination IP:    127.0.0.1
     Mode:              UDP
     Port:              8000
     Prefix:            gma3
     Receive:           Yes
     Receive Command:   Yes   <-- gates /cmd execution
     Echo Input:        Yes   <-- REQUIRED: without this MA silently
                                  ignores incoming /cmd messages even
                                  when Receive Command is Yes
4. Save show.

To verify it works: send a `Cmd` from the compiler ("Send current to MA" button).
The command should appear in the gma3 Command Line History.


EVERY SESSION
-------------

- Double-click `start.bat`. Leave the window open.
- Open cuelist-compiler.html — the OSC status pill goes green when the bridge is up.
- Close the bat window when you're done (Ctrl+C or just close it).


PROTOCOL (for reference)
------------------------

WebSocket address: ws://127.0.0.1:8765

Browser sends:
  { "type": "cmd", "line": "Store Sequence 666 Cue 1 \"INTRO\" /Overwrite /NoConfirmation", "id": 42 }
  { "type": "ping" }

Proxy responds:
  { "type": "status", "connected": true, "oscTarget": "127.0.0.1:8000", "oscAddress": "/gma3/cmd" }
  { "type": "sent",   "line": "...", "id": 42 }
  { "type": "error",  "msg": "...", "id": 42 }
  { "type": "pong" }

OSC packet sent to gma3:
  address: /gma3/cmd
  args:    [ <command-line string> ]


TROUBLESHOOTING
---------------

- "Address already in use" on port 8765: another instance of the proxy is
  already running. Check the taskbar.
- Browser shows OFFLINE pill: the proxy isn't running, or the browser was
  opened before the proxy started. Click the pill to reconnect.
- Commands go through but gma3 doesn't react: check the OSC input is enabled
  in gma3 and the prefix is "gma3" (not "GMA3" — case-sensitive in some builds).
- The proxy listens on 127.0.0.1 only (localhost). It is not reachable from
  other machines on the network — by design.

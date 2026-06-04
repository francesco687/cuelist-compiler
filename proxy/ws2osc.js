'use strict';

// Cuelist Compiler — WebSocket → OSC bridge for grandMA3.
//
// Listens for JSON messages from the compiler (browser) over WebSocket,
// converts each {type:"cmd", line:"..."} into an OSC packet and forwards it
// over UDP to gma3.
//
// gma3 side: configure Menu -> Network -> MA Network Configuration -> OSC
// to listen on UDP port 8000 with prefix "gma3".

const dgram = require('dgram');
const { WebSocketServer } = require('ws');

const WS_HOST = '127.0.0.1';
const WS_PORT = 8765;
const OSC_HOST = '127.0.0.1';
const OSC_PORT = 8000;
const OSC_ADDRESS = '/gma3/cmd';

// --- OSC encoding (no external lib) -----------------------------------------

function oscString(s) {
  const body = Buffer.from(s + '\0', 'binary');
  const padLen = (4 - (body.length % 4)) % 4;
  return padLen ? Buffer.concat([body, Buffer.alloc(padLen)]) : body;
}

function oscInt(n) {
  const b = Buffer.alloc(4);
  b.writeInt32BE(n | 0, 0);
  return b;
}

function oscFloat(n) {
  const b = Buffer.alloc(4);
  b.writeFloatBE(n, 0);
  return b;
}

function buildOscMessage(address, args) {
  let types = ',';
  const parts = [];
  for (const a of args) {
    if (typeof a === 'string') { types += 's'; parts.push(oscString(a)); }
    else if (typeof a === 'number' && Number.isInteger(a)) { types += 'i'; parts.push(oscInt(a)); }
    else if (typeof a === 'number') { types += 'f'; parts.push(oscFloat(a)); }
    else { throw new Error('unsupported OSC arg type: ' + typeof a); }
  }
  return Buffer.concat([oscString(address), oscString(types), ...parts]);
}

// --- UDP socket -------------------------------------------------------------

const udp = dgram.createSocket('udp4');

function sendOscCmd(line) {
  return new Promise((resolve, reject) => {
    let pkt;
    try { pkt = buildOscMessage(OSC_ADDRESS, [line]); }
    catch (e) { reject(e); return; }
    udp.send(pkt, OSC_PORT, OSC_HOST, err => err ? reject(err) : resolve());
  });
}

// --- WebSocket server -------------------------------------------------------

const wss = new WebSocketServer({ host: WS_HOST, port: WS_PORT });

console.log(`[ws2osc] WebSocket listening on ws://${WS_HOST}:${WS_PORT}`);
console.log(`[ws2osc] OSC target:        udp://${OSC_HOST}:${OSC_PORT}  address ${OSC_ADDRESS}`);
console.log(`[ws2osc] gma3 setup: Menu > Network > MA Network Configuration > OSC, input UDP ${OSC_PORT}, prefix "gma3"`);
console.log(`[ws2osc] Leave this window open. Close it to stop the bridge.`);

wss.on('connection', (ws, req) => {
  const peer = req.socket.remoteAddress + ':' + req.socket.remotePort;
  console.log(`[ws2osc] browser connected from ${peer}`);
  ws.send(JSON.stringify({
    type: 'status',
    connected: true,
    oscTarget: `${OSC_HOST}:${OSC_PORT}`,
    oscAddress: OSC_ADDRESS
  }));

  ws.on('message', async raw => {
    let msg;
    try { msg = JSON.parse(raw.toString()); }
    catch (e) { ws.send(JSON.stringify({ type: 'error', msg: 'invalid JSON' })); return; }

    if (msg.type === 'cmd' && typeof msg.line === 'string') {
      try {
        await sendOscCmd(msg.line);
        console.log('[osc>] ' + msg.line);
        ws.send(JSON.stringify({ type: 'sent', line: msg.line, id: msg.id }));
      } catch (err) {
        console.error('[ws2osc] send error:', err.message);
        ws.send(JSON.stringify({ type: 'error', msg: err.message, id: msg.id }));
      }
    } else if (msg.type === 'ping') {
      ws.send(JSON.stringify({ type: 'pong' }));
    } else {
      ws.send(JSON.stringify({ type: 'error', msg: 'unknown message: ' + JSON.stringify(msg) }));
    }
  });

  ws.on('close', () => console.log(`[ws2osc] browser ${peer} disconnected`));
  ws.on('error', err => console.error('[ws2osc] ws error:', err.message));
});

process.on('SIGINT', () => {
  console.log('\n[ws2osc] shutting down');
  wss.close();
  udp.close();
  process.exit(0);
});

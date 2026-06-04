'use strict';
// OSC 1.0 encoding + UDP sender. Port of proxy/ws2osc.js.
const dgram = require('node:dgram');

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

/** Holds one UDP socket and sends OSC `/prefix/cmd` messages to a target. */
class OscSender {
  constructor({ host, port, prefix }) {
    this.host = host;
    this.port = port;
    this.address = '/' + prefix + '/cmd';
    this.udp = dgram.createSocket('udp4');
  }

  send(line) {
    return new Promise((resolve, reject) => {
      let pkt;
      try { pkt = buildOscMessage(this.address, [line]); }
      catch (e) { reject(e); return; }
      this.udp.send(pkt, this.port, this.host, (err) => (err ? reject(err) : resolve()));
    });
  }

  close() { try { this.udp.close(); } catch { /* already closed */ } }
}

module.exports = { oscString, oscInt, oscFloat, buildOscMessage, OscSender };

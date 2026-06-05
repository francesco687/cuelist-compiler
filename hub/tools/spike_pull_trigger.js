'use strict';
// SPIKE: trigger dump_sequence.lua on the desk over OSC /cmd. Usage:
//   node hub/tools/spike_pull_trigger.js 666 [ma3Host] [ma3Port] [prefix]
const { OscSender } = require('../src/osc.js');

const seq = parseInt(process.argv[2] || '666', 10);
const host = process.argv[3] || '127.0.0.1';
const port = parseInt(process.argv[4] || '8000', 10);
const prefix = process.argv[5] || 'gma3';

const sender = new OscSender({ host, port, prefix });

async function main() {
  // Set the target sequence as a user var, then run the plugin by name.
  // Both lines go through /gma3/cmd. If user vars don't survive, the plugin
  // falls back to its own DEFAULT_SEQ — recorded as a finding.
  await sender.send(`SetUserVariable "pullseq" "${seq}"`);
  await sender.send(`Plugin "dump_sequence"`);
  console.log(`[trigger] sent SetUserVariable pullseq=${seq} + Plugin "dump_sequence" to ${host}:${port} /${prefix}/cmd`);
  sender.close();
}
main().catch((e) => { console.error('[trigger] failed:', e); process.exit(1); });

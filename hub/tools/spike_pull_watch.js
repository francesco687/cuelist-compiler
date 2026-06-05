'use strict';
// SPIKE: watch a folder for the cuelist-pull JSON the desk plugin writes,
// parse it, and print a summary. Usage:
//   node hub/tools/spike_pull_watch.js /Users/Shared/cuelist-pull/seq.json
const fs = require('node:fs');
const path = require('node:path');

const target = process.argv[2] || '/Users/Shared/cuelist-pull/seq.json';
const dir = path.dirname(target);
const base = path.basename(target);

function summarize(file) {
  let raw;
  try { raw = fs.readFileSync(file, 'utf8'); }
  catch (e) { console.log('[watch] read failed:', e.message); return; }
  let obj;
  try { obj = JSON.parse(raw); }
  catch (e) { console.log('[watch] JSON parse failed:', e.message, '\n--- raw ---\n', raw); return; }
  console.log('[watch] parsed OK:',
    'version=', obj.version,
    'sequence=', obj.sequence,
    'cues=', Array.isArray(obj.cues) ? obj.cues.length : '(none)',
    'error=', obj.error);
  if (Array.isArray(obj.cues) && obj.cues.length) {
    const c = obj.cues[0];
    console.log('[watch] first cue:', JSON.stringify(c, null, 2));
  }
}

console.log('[watch] watching', dir, 'for', base);
if (fs.existsSync(target)) summarize(target);
fs.watch(dir, (event, filename) => {
  if (filename === base) {
    // debounce: writes can fire multiple events
    setTimeout(() => summarize(target), 150);
  }
});

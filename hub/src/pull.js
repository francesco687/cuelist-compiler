'use strict';
// Pull side of the hub: trigger the desk's list_sequences plugin over OSC, then
// wait for it to (re)write the JSON file and return the parsed result.
//
// The plugin can't push data back over the wire (MA3 Lua writes a local file),
// so the contract is: hub fires the trigger, the plugin truncates+rewrites the
// file, hub notices the newer mtime, reads + parses, relays to the phone.
const fs = require('node:fs');

const delay = (ms) => new Promise((r) => setTimeout(r, ms));

/** mtime in ms, or 0 if the file doesn't exist yet. */
function mtimeMs(file) {
  try { return fs.statSync(file).mtimeMs; } catch { return 0; }
}

/** Read + parse + loosely validate the pull JSON. Throws on missing/partial/bad. */
function readPullFile(file) {
  const obj = JSON.parse(fs.readFileSync(file, 'utf8'));
  if (!obj || !Array.isArray(obj.sequences)) {
    throw new Error('pull file missing sequences[]');
  }
  return obj;
}

/**
 * Trigger the plugin and wait for a parseable file newer than the pre-trigger
 * mtime. Resolves with the parsed object; rejects on timeout.
 *
 * Polling (not fs.watch) on purpose: fs.watch is unreliable on network mounts,
 * and a partial read mid-write just fails to parse and we poll again.
 */
async function pullSequences({ sender, trigger, file, timeoutMs = 8000, pollMs = 150 }) {
  const before = mtimeMs(file);
  await sender.send(trigger);
  const start = Date.now();
  for (;;) {
    await delay(pollMs);
    if (mtimeMs(file) > before) {
      try { return readPullFile(file); }
      catch { /* mid-write or partial JSON — keep polling */ }
    }
    if (Date.now() - start > timeoutMs) {
      throw new Error(`timed out after ${timeoutMs}ms waiting for ${file}`);
    }
  }
}

module.exports = { mtimeMs, readPullFile, pullSequences };

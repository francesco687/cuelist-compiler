'use strict';
// Live smoke: start the hub, send one `pull-sequences` over WS, print what the
// desk returns. Triggers the real onPC plugin via OSC. Usage: node tools/smoke_pull.js
const { startServer } = require('../src/server');
const { loadConfig } = require('../src/config');

(async () => {
  const config = loadConfig();
  const handle = startServer({ ...config, host: '127.0.0.1', port: 0 });
  await new Promise((r) => handle.wss.on('listening', r));
  console.log(`[smoke] trigger="${config.pullTrigger}"  file=${config.pullFile}  ma3=${config.ma3Host}:${config.ma3Port}`);
  const ws = new WebSocket(`ws://127.0.0.1:${handle.wss.address().port}`);

  const done = new Promise((resolve) => {
    ws.addEventListener('message', (ev) => {
      const msg = JSON.parse(ev.data);
      if (msg.type === 'sequences') {
        console.log(`[smoke] OK — ${msg.sequences.length} sequences. First 5:`);
        for (const s of msg.sequences.slice(0, 5)) console.log(`   ${s.no}  ${JSON.stringify(s.name)}`);
        resolve();
      } else if (msg.type === 'pull-error' || msg.type === 'error') {
        console.log(`[smoke] FAIL — ${msg.type}: ${msg.message}`);
        resolve();
      }
    });
  });
  await new Promise((r) => ws.addEventListener('open', r));
  ws.send(JSON.stringify({ type: 'pull-sequences' }));
  await done;
  ws.close();
  await handle.close();
  process.exit(0);
})();

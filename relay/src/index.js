'use strict';
const { startRelay } = require('./server');

const port = parseInt(process.env.PORT || '8080', 10);
const relay = startRelay({ port });
relay.server.on('listening', () => {
  console.log(`[relay] listening on :${port} (ws upgrade + GET /healthz)`);
});

process.on('SIGINT', () => { console.log('\n[relay] shutting down'); relay.close().then(() => process.exit(0)); });
process.on('SIGTERM', () => { relay.close().then(() => process.exit(0)); });

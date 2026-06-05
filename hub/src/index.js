'use strict';
const { loadConfig } = require('./config');
const { startServer } = require('./server');

const config = loadConfig();
const { wss } = startServer(config);

wss.on('listening', () => {
  console.log(`[hub] WebSocket listening on ws://${config.host}:${config.port}`);
  console.log(`[hub] OSC target: udp://${config.ma3Host}:${config.ma3Port}  /${config.ma3Prefix}/cmd`);
  console.log('[hub] grandMA3: Menu > Network > MA Network Configuration > OSC, input UDP ' +
    `${config.ma3Port}, prefix "${config.ma3Prefix}", Echo Input = Yes`);
  console.log(`[hub] pull: trigger "${config.pullTrigger}" -> reads ${config.pullFile}`);
});

process.on('SIGINT', () => { console.log('\n[hub] shutting down'); wss.close(); process.exit(0); });

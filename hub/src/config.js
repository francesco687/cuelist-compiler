'use strict';

/** Reads hub configuration from an env-like object. */
function loadConfig(env = process.env) {
  const int = (v, d) => {
    const n = parseInt(v, 10);
    return Number.isFinite(n) ? n : d;
  };
  return {
    host: env.HUB_HOST || '0.0.0.0',
    port: int(env.HUB_PORT, 9000),
    ma3Host: env.MA3_HOST || '127.0.0.1',
    ma3Port: int(env.MA3_PORT, 8000),
    ma3Prefix: env.MA3_PREFIX || 'gma3',
    intervalMs: int(env.OSC_INTERVAL_MS, 20),
    webJsDir: env.WEB_JS_DIR || undefined, // defaults to ../web/js inside compile-bridge
  };
}

module.exports = { loadConfig };

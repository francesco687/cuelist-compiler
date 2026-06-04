// osc.js — WebSocket client to the proxy; throttled command send; status pill. Depends on: constants, compile (buildCmdLines), state.

// --- OSC client (WebSocket to local proxy) ---------------------------------
let oscWs = null;
let oscState = 'offline'; // offline | connecting | online | sending
let oscReconnectTimer = null;
let oscSending = false;

function setOscState(s, label) {
  oscState = s;
  const pill = document.getElementById('oscPill');
  pill.className = 'osc-pill ' + s;
  pill.textContent = label || ({
    offline: '○ OSC offline',
    connecting: '● connecting…',
    online: '● OSC online',
    sending: '● sending…'
  })[s];
  const canSend = (s === 'online');
  document.getElementById('sendOscCurrent').disabled = !canSend;
  document.getElementById('sendOscAll').disabled = !canSend;
}

function oscConnect() {
  if (oscWs && (oscWs.readyState === WebSocket.OPEN || oscWs.readyState === WebSocket.CONNECTING)) return;
  setOscState('connecting');
  try {
    oscWs = new WebSocket(OSC_PROXY_URL);
  } catch (e) {
    setOscState('offline');
    return;
  }
  oscWs.addEventListener('open', () => {
    setOscState('online');
    if (oscReconnectTimer) { clearTimeout(oscReconnectTimer); oscReconnectTimer = null; }
  });
  oscWs.addEventListener('close', () => {
    setOscState('offline');
    // Auto-retry every 3s when offline (but not while user is actively sending).
    if (!oscSending && !oscReconnectTimer) {
      oscReconnectTimer = setTimeout(() => { oscReconnectTimer = null; oscConnect(); }, 3000);
    }
  });
  oscWs.addEventListener('error', () => {
    // 'close' will fire after this; nothing to do here.
  });
  oscWs.addEventListener('message', ev => {
    let msg;
    try { msg = JSON.parse(ev.data); } catch (e) { return; }
    if (msg.type === 'status' && msg.oscTarget) {
      const pill = document.getElementById('oscPill');
      pill.title = `OSC → ${msg.oscTarget} ${msg.oscAddress}\nClick to reconnect`;
    } else if (msg.type === 'error') {
      console.error('[osc proxy]', msg.msg);
    }
  });
}

function oscSendLine(line) {
  return new Promise((resolve, reject) => {
    if (!oscWs || oscWs.readyState !== WebSocket.OPEN) { reject(new Error('OSC offline')); return; }
    try {
      oscWs.send(JSON.stringify({ type: 'cmd', line }));
      resolve();
    } catch (e) { reject(e); }
  });
}

async function sendCmdLinesViaOsc(lines, label) {
  if (!lines || lines.length === 0) { alert('Nothing to send.'); return; }
  if (oscState !== 'online') { alert('OSC proxy is offline. Start the bridge (proxy/start.bat) first.'); return; }
  if (oscSending) return;
  oscSending = true;
  setOscState('sending', `● sending… 0 / ${lines.length}`);
  try {
    for (let i = 0; i < lines.length; i++) {
      await oscSendLine(lines[i]);
      if (i % 5 === 4 || i === lines.length - 1) {
        setOscState('sending', `● sending… ${i + 1} / ${lines.length}`);
      }
      if (i < lines.length - 1) {
        await new Promise(r => setTimeout(r, OSC_SEND_INTERVAL_MS));
      }
    }
    setOscState('online');
    console.log(`[osc] ${label}: ${lines.length} commands sent.`);
  } catch (err) {
    setOscState('offline');
    alert('OSC send failed: ' + err.message + '\nProxy may have disconnected.');
  } finally {
    oscSending = false;
  }
}

function sendCurrentViaOsc() {
  const song = activeSong();
  if (!song || song.cues.length === 0) { alert('No cues in the active song.'); return; }
  const lines = buildCmdLines([song]);
  sendCmdLinesViaOsc(lines, `current song "${song.name || '(untitled)'}"`);
}

function sendAllViaOsc() {
  const songs = state.songs.filter(s => s.cues && s.cues.length > 0);
  if (songs.length === 0) { alert('No songs with cues to send.'); return; }
  const lines = buildCmdLines(songs);
  sendCmdLinesViaOsc(lines, `${songs.length} song(s)`);
}

// --- public surface
window.CC = window.CC || {};
CC.osc = { setOscState, oscConnect, sendCurrentViaOsc, sendAllViaOsc };

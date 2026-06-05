// osc.js — WebSocket client to the proxy; throttled command send; status pill. Depends on: constants, compile (buildCmdLines), state.

// --- OSC client (WebSocket to local proxy) ---------------------------------
let transport = null;
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
  if (!transport) {
    transport = CC.transport.make(window, { proxyUrl: OSC_PROXY_URL });
    transport.onStatus = (s) => {
      if (oscSending) return;            // don't clobber the sending label
      if (s === 'online') { setOscState('online'); if (oscReconnectTimer) { clearTimeout(oscReconnectTimer); oscReconnectTimer = null; } }
      else if (s === 'connecting') setOscState('connecting');
      else { setOscState('offline'); if (!oscReconnectTimer) oscReconnectTimer = setTimeout(() => { oscReconnectTimer = null; oscConnect(); }, 3000); }
    };
    // Proxy status/error messages (WebSocket transport only) → pill title + log.
    transport.onMessage = (msg) => {
      if (msg.type === 'status' && msg.oscTarget) {
        const pill = document.getElementById('oscPill');
        pill.title = `OSC → ${msg.oscTarget} ${msg.oscAddress}\nClick to reconnect`;
      } else if (msg.type === 'error') {
        console.error('[osc proxy]', msg.msg);
      }
    };
  }
  if (oscState === 'online' || oscState === 'connecting') return;
  transport.connect().catch(() => setOscState('offline'));
}

function oscSendLine(line) {
  if (!transport) return Promise.reject(new Error('OSC offline'));
  return transport.sendLine(line);
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

// --- Desktop settings + status (Electron only) -----------------------------
function initDesktopChrome() {
  if (!(window.cuelist && window.cuelist.isDesktop)) return; // browser: no native settings
  const row = document.getElementById('deskStatusRow');
  if (row) row.hidden = false;

  async function refreshStatus() {
    try {
      const st = await window.cuelist.getStatus();
      const tl = document.getElementById('oscTargetLabel');
      if (tl) tl.textContent = 'OSC → ' + st.oscTarget;
      const pp = document.getElementById('phonePill');
      if (pp) { pp.textContent = st.phoneConnected ? '📱 phone connected' : '📱 no phone'; pp.classList.toggle('connected', st.phoneConnected); }
    } catch { /* transient IPC error — next poll recovers */ }
  }
  refreshStatus();
  setInterval(refreshStatus, 2000);

  const dlg = document.getElementById('settingsDialog');
  const errEl = document.getElementById('settingsError');
  document.getElementById('openSettingsBtn').addEventListener('click', async () => {
    const s = await window.cuelist.getSettings();
    document.getElementById('setMa3Host').value = s.ma3Host;
    document.getElementById('setMa3Port').value = s.ma3Port;
    document.getElementById('setMa3Prefix').value = s.ma3Prefix;
    document.getElementById('setIntervalMs').value = s.intervalMs;
    document.getElementById('setHubEnabled').checked = s.hubEnabled;
    document.getElementById('setHubPort').value = s.hubPort;
    if (errEl) errEl.hidden = true; // clear any stale error from a prior attempt
    dlg.showModal();
  });
  // Save is type="button": validate via main, keep dialog open + show inline error on failure.
  document.getElementById('saveSettingsBtn').addEventListener('click', async () => {
    try {
      await window.cuelist.setSettings({
        ma3Host: document.getElementById('setMa3Host').value.trim(),
        ma3Port: parseInt(document.getElementById('setMa3Port').value, 10),
        ma3Prefix: document.getElementById('setMa3Prefix').value.trim(),
        intervalMs: parseInt(document.getElementById('setIntervalMs').value, 10),
        hubEnabled: document.getElementById('setHubEnabled').checked,
        hubPort: parseInt(document.getElementById('setHubPort').value, 10),
      });
      if (errEl) errEl.hidden = true;
      dlg.close();
      refreshStatus();
    } catch (e) {
      if (errEl) { errEl.textContent = (e && e.message) || 'Invalid settings'; errEl.hidden = false; }
    }
  });
}

// --- public surface
window.CC = window.CC || {};
CC.osc = { setOscState, oscConnect, sendCurrentViaOsc, sendAllViaOsc, initDesktopChrome };

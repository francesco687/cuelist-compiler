'use strict';
const $ = (id) => document.getElementById(id);

function setStatus(relay, peer) {
  const dot = $('dot');
  dot.className = 'dot ' + (peer ? 'paired' : relay === 'online' ? 'online'
    : String(relay).startsWith('error') ? 'error' : 'offline');
  $('status').textContent = peer ? 'phone paired' : relay === 'online' ? 'waiting for phone' : relay;
}

function pad(n) { return String(n).padStart(2, '0'); }
function hhmmss(ms) { const d = new Date(ms); return `${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`; }

function addLog(entry) {
  const li = document.createElement('li');
  const kindLabel = { cmd: 'CMD', send: 'SEND', pull: 'PULL', error: 'ERR' }[entry.kind] || entry.kind.toUpperCase();
  li.innerHTML =
    `<span class="ts">${hhmmss(entry.at)}</span>` +
    `<span class="kind ${entry.kind}">${kindLabel}</span>` +
    `<span class="summary"></span>`;
  const who = entry.name ? entry.name + ' · ' : '';
  li.querySelector('.summary').textContent = who + entry.summary;   // textContent = no HTML injection
  const feed = $('feed');
  feed.prepend(li);
  while (feed.childElementCount > 200) feed.removeChild(feed.lastChild);
}

function renderRoster(phones) {
  const ul = $('roster');
  ul.innerHTML = '';
  for (const p of phones) {
    const li = document.createElement('li');
    li.textContent = p.name;
    ul.appendChild(li);
  }
}

async function init() {
  const s = await window.hub.getSettings();
  $('relayUrl').value = s.relayUrl;
  $('ma3Host').value = s.ma3Host;
  $('ma3Port').value = s.ma3Port;
  $('ma3Prefix').value = s.ma3Prefix;
  $('code').value = s.pairingCode;

  const st = await window.hub.getState();
  setStatus(st.relay, st.peer);

  window.hub.onState((relay) => window.hub.getState().then((x) => setStatus(x.relay, x.peer)));
  window.hub.onRoster(renderRoster);
  window.hub.onLog(addLog);

  $('copy').onclick = () => navigator.clipboard.writeText($('code').value);
  $('regen').onclick = async () => {
    // Regenerating drops every phone currently paired — guard the accidental click.
    if (!confirm('Generate a new pairing code?\n\nEvery phone currently paired will go offline and must be re-paired with the new code.')) return;
    $('code').value = await window.hub.regenCode();
  };
  $('save').onclick = async () => {
    try {
      const updated = await window.hub.setSettings({
        relayUrl: $('relayUrl').value.trim(),
        ma3Host: $('ma3Host').value.trim(),
        ma3Port: parseInt($('ma3Port').value, 10),
        ma3Prefix: $('ma3Prefix').value.trim(),
        pairingCode: $('code').value.trim().toLowerCase(),
      });
      $('code').value = updated.pairingCode;
    } catch (e) {
      alert(e.message || 'Settings error');
    }
  };
}
init();

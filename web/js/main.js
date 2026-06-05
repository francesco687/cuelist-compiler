// main.js — boot + all event wiring. Loaded last so every function above exists. Depends on: every other module.

document.getElementById('songName').addEventListener('input', e => {
  const song = activeSong();
  if (!song) return;
  song.name = e.target.value;
  saveState();
  renderSidebar();
});
document.getElementById('sequence').addEventListener('input', e => {
  const song = activeSong();
  if (!song) return;
  song.sequence = parseInt(e.target.value) || 1;
  saveState();
  renderSidebar();
});
document.getElementById('addCue').addEventListener('click', () => {
  const song = activeSong();
  if (!song) return;
  song.cues.push(newCue());
  saveState();
  render();
});
document.getElementById('collapseAll').addEventListener('click', () => {
  const song = activeSong();
  if (!song) return;
  song.cues.forEach(c => c.collapsed = true);
  saveState();
  render();
});
document.getElementById('expandAll').addEventListener('click', () => {
  const song = activeSong();
  if (!song) return;
  song.cues.forEach(c => c.collapsed = false);
  saveState();
  render();
});
document.getElementById('addSong').addEventListener('click', () => {
  const s = newSong();
  state.songs.push(s);
  state.activeSongId = s.id;
  saveState();
  render();
});
document.getElementById('storeMode').addEventListener('change', e => {
  state.storeMode = e.target.value === 'Merge' ? 'Merge' : 'Overwrite';
  saveState();
});

// Segmented control adapter for store mode — drives the hidden <select id="storeMode">
function syncStoreModeSegment() {
  const sel = document.getElementById('storeMode');
  const seg = document.getElementById('storeModeSeg');
  if (!sel || !seg) return;
  seg.querySelectorAll('.seg-btn').forEach(btn => {
    btn.classList.toggle('active', btn.dataset.mode === sel.value);
  });
}
window.syncStoreModeSegment = syncStoreModeSegment;

document.getElementById('storeModeSeg').addEventListener('click', e => {
  const btn = e.target.closest('.seg-btn');
  if (!btn) return;
  const sel = document.getElementById('storeMode');
  sel.value = btn.dataset.mode;
  sel.dispatchEvent(new Event('change'));   // existing handler updates state
  syncStoreModeSegment();
});

syncStoreModeSegment(); // initialise on load
document.getElementById('export').addEventListener('click', exportLua);
document.getElementById('exportAll').addEventListener('click', exportAllLua);
document.getElementById('saveProject').addEventListener('click', saveProject);
document.getElementById('loadBtn').addEventListener('click', () => document.getElementById('loadProject').click());
document.getElementById('loadProject').addEventListener('change', e => {
  if (e.target.files[0]) loadProject(e.target.files[0]);
  e.target.value = '';
});
document.getElementById('importCsvBtn').addEventListener('click', () => document.getElementById('importCsv').click());
document.getElementById('importCsv').addEventListener('change', e => {
  if (e.target.files[0]) importCsv(e.target.files[0]);
  e.target.value = '';
});
document.getElementById('manageMoodsBtn').addEventListener('click', openMoodModal);
document.getElementById('addMood').addEventListener('click', () => {
  moods.push(newMood());
  saveMoods();
  renderMoodModal();
});
document.querySelector('#moodModal .close-modal').addEventListener('click', closeMoodModal);
document.querySelector('#moodModal .modal-backdrop').addEventListener('click', closeMoodModal);

document.getElementById('manageDefaultsBtn').addEventListener('click', openDefaultsModal);
document.querySelector('#defaultsModal .close-modal').addEventListener('click', closeDefaultsModal);
document.querySelector('#defaultsModal .modal-backdrop').addEventListener('click', closeDefaultsModal);

document.getElementById('managePoolsBtn').addEventListener('click', openPoolsModal);
document.querySelector('#poolsModal .close-modal').addEventListener('click', closePoolsModal);
document.querySelector('#poolsModal .modal-backdrop').addEventListener('click', closePoolsModal);
document.getElementById('poolsImportBtn').addEventListener('click', () => {
  const text = document.getElementById('poolsPaste').value;
  try {
    const parsed = parsePoolsPaste(text);
    pools = parsed;
    savePools();
    refreshPoolsStatus();
    document.getElementById('poolsPaste').value = '';
  } catch (err) {
    alert('Import failed: ' + err.message);
  }
});
document.getElementById('poolsClearBtn').addEventListener('click', () => {
  if (!confirm('Clear all loaded pool data? Autocomplete will go back to free-text only.')) return;
  pools = emptyPools();
  savePools();
  refreshPoolsStatus();
});
document.getElementById('poolsLoadFileBtn').addEventListener('click', () => document.getElementById('poolsLoadFile').click());
document.getElementById('poolsLoadFile').addEventListener('change', e => {
  const file = e.target.files[0];
  if (!file) return;
  const reader = new FileReader();
  reader.onload = ev => {
    try {
      pools = parsePoolsPaste(ev.target.result);
      savePools();
      refreshPoolsStatus();
    } catch (err) {
      alert('Load failed: ' + err.message);
    }
  };
  reader.readAsText(file);
  e.target.value = '';
});

document.getElementById('sendOscCurrent').addEventListener('click', sendCurrentViaOsc);
document.getElementById('sendOscAll').addEventListener('click', sendAllViaOsc);
document.getElementById('oscPill').addEventListener('click', () => {
  if (oscState === 'offline') oscConnect();
});

document.addEventListener('keydown', e => {
  if (e.key === 'Escape') {
    if (!document.getElementById('moodModal').classList.contains('hidden')) { closeMoodModal(); return; }
    if (!document.getElementById('defaultsModal').classList.contains('hidden')) { closeDefaultsModal(); return; }
    if (!document.getElementById('poolsModal').classList.contains('hidden')) { closePoolsModal(); return; }
  }
  if (e.code === 'Space' && audioEl) {
    const tag = (e.target.tagName || '').toUpperCase();
    if (tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT') return;
    e.preventDefault();
    togglePlay();
  }
});

wireLoadAudio();

window.addEventListener('resize', () => {
  if (!audioBuffer) return;
  const waveL = document.getElementById('waveL');
  const waveR = document.getElementById('waveR');
  if (waveL) drawWaveform(waveL, audioBuffer.getChannelData(0));
  if (waveR && audioBuffer.numberOfChannels >= 2) drawWaveform(waveR, audioBuffer.getChannelData(1));
  updatePlayhead();
});
document.getElementById('clearAll').addEventListener('click', () => {
  if (confirm('Clear the whole project (all songs)? This cannot be undone.')) {
    state = newProject();
    saveState();
    render();
  }
});

document.querySelector('#poolPickerModal .modal-backdrop').addEventListener('click', closePoolPicker);
document.querySelector('#poolPickerModal .close-modal').addEventListener('click', closePoolPicker);
document.getElementById('poolPickerSearch').addEventListener('input', e => renderPoolPickerGrid(e.target.value));
document.getElementById('poolPickerClear').addEventListener('click', () => pickPoolValue(''));
window.addEventListener('keydown', e => {
  if (e.key === 'Escape' && !document.getElementById('poolPickerModal').classList.contains('hidden')) {
    closePoolPicker();
  }
});

render();
oscConnect();
CC.osc.initDesktopChrome && CC.osc.initDesktopChrome();

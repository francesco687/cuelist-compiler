// audio.js — WebAudio decode/playback, channel gain, waveform, playhead, cue markers. Depends on: constants, util, state, render.

// Audio state (per-session, not persisted on disk)
// audioCache holds decoded audio per song id; the globals below mirror the
// entry for the currently-active song and get swapped on song switch.
let audioCtx = null;
let audioEl = null;
let audioBuffer = null;
let audioGainL = null, audioGainR = null;
let audioFileName = '';
let audioRAF = null;
const audioCache = new Map(); // songId -> { audioEl, audioBuffer, audioGainL, audioGainR, fileName }
let currentAudioSongId = null;
let selectedMarkerCueN = null;
let markerDragState = null; // { cueN, timelineRect, durationS, moved } during a drag, else null
const channelMute = { L: false, R: false };

// --- Pure helpers (no DOM, no globals — unit-tested in test/audio-helpers.test.js)

function fileToSongTime(currentTime, trim) {
  return currentTime - (trim && typeof trim.startS === 'number' ? trim.startS : 0);
}

function songToFileTime(songT, trim) {
  return songT + (trim && typeof trim.startS === 'number' ? trim.startS : 0);
}

function clampSeek(rawS, trim, duration) {
  const lo = trim && typeof trim.startS === 'number' ? trim.startS : 0;
  const hi = trim && trim.endS != null ? trim.endS : duration;
  return Math.max(lo, Math.min(hi, rawS));
}

function shouldAutoPause(currentTime, trim, alreadyPaused) {
  if (alreadyPaused) return false;
  if (!trim || trim.endS == null) return false;
  return currentTime >= trim.endS;
}

function pickTickInterval(duration) {
  if (duration <= 30)  return { interval: 1,  major: 5  };
  if (duration <= 120) return { interval: 5,  major: 30 };
  return { interval: 10, major: 60 };
}

function findPrevMarker(songTime, cues) {
  const PREV_TOL = 0.25;
  let best = null, bestT = -Infinity;
  for (const c of cues) {
    const t = timecodeToSeconds(c.position);
    if (isNaN(t)) continue;
    if (t < songTime - PREV_TOL && t > bestT) { best = c; bestT = t; }
  }
  return best;
}

function findNextMarker(songTime, cues) {
  const NEXT_TOL = 0.05;
  let best = null, bestT = Infinity;
  for (const c of cues) {
    const t = timecodeToSeconds(c.position);
    if (isNaN(t)) continue;
    if (t > songTime + NEXT_TOL && t < bestT) { best = c; bestT = t; }
  }
  return best;
}

async function loadAudioFile(file) {
  const targetSongId = state.activeSongId;
  try {
    if (!audioCtx) audioCtx = new (window.AudioContext || window.webkitAudioContext)();
    if (audioCtx.state === 'suspended') await audioCtx.resume();

    const buf = await file.arrayBuffer();
    const newBuffer = await audioCtx.decodeAudioData(buf.slice(0));

    // Tear down any existing cache entry for this song before replacing.
    const prev = audioCache.get(targetSongId);
    if (prev) {
      try { prev.audioEl.pause(); } catch (e) {}
      try { URL.revokeObjectURL(prev.audioEl.src); } catch (e) {}
    }

    const newEl = new Audio();
    newEl.src = URL.createObjectURL(file);
    newEl.preservesPitch = false;

    await new Promise((resolve, reject) => {
      newEl.addEventListener('loadedmetadata', resolve, { once: true });
      newEl.addEventListener('error', () => reject(new Error('audio load error')), { once: true });
    });

    const source = audioCtx.createMediaElementSource(newEl);
    const ch = newBuffer.numberOfChannels;
    let gL, gR;
    if (ch >= 2) {
      const splitter = audioCtx.createChannelSplitter(2);
      const merger = audioCtx.createChannelMerger(2);
      gL = audioCtx.createGain();
      gR = audioCtx.createGain();
      gL.gain.value = channelMute.L ? 0 : 1;
      gR.gain.value = channelMute.R ? 0 : 1;
      source.connect(splitter);
      splitter.connect(gL, 0);
      splitter.connect(gR, 1);
      gL.connect(merger, 0, 0);
      gR.connect(merger, 0, 1);
      merger.connect(audioCtx.destination);
    } else {
      gL = audioCtx.createGain();
      gR = null;
      source.connect(gL);
      gL.connect(audioCtx.destination);
    }

    newEl.addEventListener('play', startPlayheadLoop);
    newEl.addEventListener('pause', stopPlayheadLoop);
    newEl.addEventListener('ended', stopPlayheadLoop);

    audioCache.set(targetSongId, {
      audioEl: newEl,
      audioBuffer: newBuffer,
      audioGainL: gL,
      audioGainR: gR,
      fileName: file.name
    });

    const song = state.songs.find(s => s.id === targetSongId);
    if (song) {
      song.audioFileName = file.name;
      saveState();
    }

    if (state.activeSongId === targetSongId) {
      setActiveAudioFromCache(targetSongId);
      renderAudioPanel();
    }
  } catch (err) {
    alert('Audio load failed: ' + err.message);
  }
}

function setActiveAudioFromCache(songId) {
  // Pause whatever was active so it doesn't keep playing after the swap.
  if (audioEl && currentAudioSongId !== songId) {
    try { audioEl.pause(); } catch (e) {}
  }
  stopPlayheadLoop();
  const entry = audioCache.get(songId);
  if (entry) {
    audioEl = entry.audioEl;
    audioBuffer = entry.audioBuffer;
    audioGainL = entry.audioGainL;
    audioGainR = entry.audioGainR;
    audioFileName = entry.fileName;
    // Re-apply current channel mute settings to this song's gain nodes.
    if (audioGainL) audioGainL.gain.value = channelMute.L ? 0 : 1;
    if (audioGainR) audioGainR.gain.value = channelMute.R ? 0 : 1;
  } else {
    audioEl = null;
    audioBuffer = null;
    audioGainL = null;
    audioGainR = null;
    audioFileName = '';
  }
  currentAudioSongId = songId;
}

function setChannelMute(ch, muted) {
  channelMute[ch] = muted;
  if (ch === 'L' && audioGainL) audioGainL.gain.value = muted ? 0 : 1;
  if (ch === 'R' && audioGainR) audioGainR.gain.value = muted ? 0 : 1;
  document.querySelectorAll('.channel-toggle').forEach(btn => {
    const c = btn.dataset.ch;
    if (c) {
      btn.classList.toggle('active', !channelMute[c]);
      btn.classList.toggle('muted', channelMute[c]);
    }
  });
}

function drawWaveform(canvas, channelData) {
  const dpr = window.devicePixelRatio || 1;
  const w = canvas.clientWidth, h = canvas.clientHeight;
  canvas.width = Math.max(1, Math.floor(w * dpr));
  canvas.height = Math.max(1, Math.floor(h * dpr));
  const ctx = canvas.getContext('2d');
  ctx.scale(dpr, dpr);
  ctx.clearRect(0, 0, w, h);

  ctx.strokeStyle = '#1f1f23';
  ctx.beginPath();
  ctx.moveTo(0, h / 2);
  ctx.lineTo(w, h / 2);
  ctx.stroke();

  if (!channelData || channelData.length === 0) return;

  const samplesPerPixel = Math.max(1, Math.floor(channelData.length / w));
  ctx.fillStyle = '#5b8dd6';
  for (let x = 0; x < w; x++) {
    let min = 1, max = -1;
    const start = x * samplesPerPixel;
    const end = Math.min(channelData.length, start + samplesPerPixel);
    for (let i = start; i < end; i++) {
      const s = channelData[i];
      if (s < min) min = s;
      if (s > max) max = s;
    }
    const y1 = ((1 - max) / 2) * h;
    const y2 = ((1 - min) / 2) * h;
    ctx.fillRect(x, y1, 1, Math.max(1, y2 - y1));
  }
}

function renderAudioPanel() {
  const panel = document.getElementById('audioPanel');
  if (!audioEl || !audioBuffer) {
    const song = activeSong();
    const remembered = song && song.audioFileName ? song.audioFileName : '';
    panel.className = 'empty';
    panel.innerHTML = `
      <button id="loadAudioBtn" class="ghost">${remembered ? 'Load Audio…' : 'Load Audio…'}</button>
      <input type="file" id="loadAudio" accept="audio/*" style="display:none">
      <span style="margin-left:8px;font-size:0.85em;">${
        remembered
          ? '🎵 ' + escapeHtml(remembered) + ' <span style="color:#888;">— click Load Audio to re-select</span>'
          : 'no audio loaded'
      }</span>
    `;
    wireLoadAudio();
    return;
  }

  const ch = audioBuffer.numberOfChannels;
  const dur = audioBuffer.duration;
  panel.className = '';
  panel.innerHTML = `
    <div id="audioControls">
      <div class="transport">
        <button id="prevBtn"    title="Previous marker">⏮</button>
        <button id="stopBtn"    title="Stop (back to in-point)">⏹</button>
        <button id="playBtn"    title="Play / Pause">${audioEl.paused ? '▶' : '⏸'}</button>
        <button id="nextBtn"    title="Next marker">⏭</button>
        <button id="restartBtn" title="Restart from in-point">↻</button>
      </div>
      ${ch >= 2 ? `
        <button class="channel-toggle ${channelMute.L ? 'muted' : 'active'}" data-ch="L" title="Toggle Left channel">L</button>
        <button class="channel-toggle ${channelMute.R ? 'muted' : 'active'}" data-ch="R" title="Toggle Right channel">R</button>
      ` : ''}
      <span class="filename" title="${escapeHtml(audioFileName)}">${escapeHtml(audioFileName)}</span>
      <span class="time" id="audioTime">0:00 / ${secondsToMMSS(dur)}</span>
      <button id="reloadAudioBtn" class="ghost" title="Load a different file">Change</button>
      <input type="file" id="loadAudio" accept="audio/*" style="display:none">
    </div>
    <div id="timeline">
      ${ch >= 2 ? `
        <div class="channel-wave"><span class="chan-label">L</span><canvas id="waveL"></canvas></div>
        <div class="channel-wave"><span class="chan-label">R</span><canvas id="waveR"></canvas></div>
      ` : `
        <div class="channel-wave" style="height:90px;"><canvas id="waveL"></canvas></div>
      `}
      <div class="markers" id="markers"></div>
      <div class="playhead" id="playhead" style="left:0px"></div>
    </div>
  `;

  document.getElementById('playBtn').addEventListener('click', togglePlay);
  document.getElementById('prevBtn').addEventListener('click', skipPrevMarker);
  document.getElementById('stopBtn').addEventListener('click', stopAudio);
  document.getElementById('nextBtn').addEventListener('click', skipNextMarker);
  document.getElementById('restartBtn').addEventListener('click', restartAudio);
  document.getElementById('reloadAudioBtn').addEventListener('click', () => document.getElementById('loadAudio').click());
  document.getElementById('loadAudio').addEventListener('change', e => {
    if (e.target.files[0]) loadAudioFile(e.target.files[0]);
    e.target.value = '';
  });
  panel.querySelectorAll('.channel-toggle').forEach(btn => {
    btn.addEventListener('click', () => setChannelMute(btn.dataset.ch, !channelMute[btn.dataset.ch]));
  });

  const tl = document.getElementById('timeline');
  tl.addEventListener('click', e => {
    if (e.target.classList.contains('marker') || e.target.classList.contains('marker-label')) return;
    deselectAllMarkers();
    const rect = tl.getBoundingClientRect();
    const pct = (e.clientX - rect.left) / rect.width;
    audioEl.currentTime = Math.max(0, Math.min(dur, pct * dur));
    updatePlayhead();
  });

  // Draw waveforms once panel is in DOM (with proper width)
  requestAnimationFrame(() => {
    const waveL = document.getElementById('waveL');
    if (waveL) drawWaveform(waveL, audioBuffer.getChannelData(0));
    if (ch >= 2) {
      const waveR = document.getElementById('waveR');
      if (waveR) drawWaveform(waveR, audioBuffer.getChannelData(1));
    }
    renderMarkers();
    updatePlayhead();
  });
}

function wireLoadAudio() {
  const btn = document.getElementById('loadAudioBtn');
  const input = document.getElementById('loadAudio');
  if (!btn || !input) return;
  btn.addEventListener('click', () => input.click());
  input.addEventListener('change', e => {
    if (e.target.files[0]) loadAudioFile(e.target.files[0]);
    e.target.value = '';
  });
}

function togglePlay() {
  if (!audioEl) return;
  if (audioEl.paused) {
    if (audioCtx && audioCtx.state === 'suspended') audioCtx.resume();
    audioEl.play();
  } else {
    audioEl.pause();
  }
  const btn = document.getElementById('playBtn');
  if (btn) btn.textContent = audioEl.paused ? '▶' : '⏸';
}

function stopAudio() {
  if (!audioEl) return;
  audioEl.pause();
  const song = activeSong();
  const startS = (song && song.audioTrim) ? song.audioTrim.startS : 0;
  audioEl.currentTime = startS;
  updatePlayhead();
}

function restartAudio() {
  if (!audioEl) return;
  const wasPlaying = !audioEl.paused;
  const song = activeSong();
  const startS = (song && song.audioTrim) ? song.audioTrim.startS : 0;
  audioEl.currentTime = startS;
  if (wasPlaying && audioCtx && audioCtx.state === 'suspended') audioCtx.resume();
  if (wasPlaying) audioEl.play();
  updatePlayhead();
}

function skipPrevMarker() {
  const song = activeSong();
  if (!audioEl || !song) return;
  const trim = song.audioTrim || { startS: 0, endS: null };
  const songT = fileToSongTime(audioEl.currentTime, trim);
  const target = findPrevMarker(songT, song.cues);
  if (target) {
    const tS = timecodeToSeconds(target.position);
    audioEl.currentTime = songToFileTime(tS, trim);
  } else {
    audioEl.currentTime = trim.startS;
  }
  updatePlayhead();
}

function skipNextMarker() {
  const song = activeSong();
  if (!audioEl || !song) return;
  const trim = song.audioTrim || { startS: 0, endS: null };
  const songT = fileToSongTime(audioEl.currentTime, trim);
  const target = findNextMarker(songT, song.cues);
  if (!target) return;
  const tS = timecodeToSeconds(target.position);
  audioEl.currentTime = songToFileTime(tS, trim);
  updatePlayhead();
}

function startPlayheadLoop() {
  stopPlayheadLoop();
  const tick = () => {
    updatePlayhead();
    audioRAF = requestAnimationFrame(tick);
  };
  audioRAF = requestAnimationFrame(tick);
  const btn = document.getElementById('playBtn');
  if (btn) btn.textContent = '⏸';
}

function stopPlayheadLoop() {
  if (audioRAF != null) cancelAnimationFrame(audioRAF);
  audioRAF = null;
  updatePlayhead();
  const btn = document.getElementById('playBtn');
  if (btn) btn.textContent = '▶';
}

function updatePlayhead() {
  if (!audioEl || !audioBuffer) return;
  const tl = document.getElementById('timeline');
  const ph = document.getElementById('playhead');
  const timeEl = document.getElementById('audioTime');
  if (!tl || !ph) return;
  const dur = audioBuffer.duration;
  const t = audioEl.currentTime;
  const pct = dur > 0 ? t / dur : 0;
  ph.style.left = (pct * tl.clientWidth) + 'px';
  if (timeEl) timeEl.textContent = `${secondsToMMSS(t)} / ${secondsToMMSS(dur)}`;
  updateCurrentMarker(t);
}

function updateCurrentMarker(t) {
  const song = activeSong();
  if (!song) return;
  const positions = song.cues
    .map(c => ({ c, s: timecodeToSeconds(c.position) }))
    .filter(x => !isNaN(x.s));
  if (positions.length === 0) return;
  let currentId = null;
  for (const { c, s } of positions) {
    if (s <= t) currentId = c;
    else break;
  }
  document.querySelectorAll('#markers .marker').forEach(m => {
    m.classList.toggle('current', currentId && m.dataset.cueN === String(currentId.n));
  });
}

function renderMarkers() {
  const song = activeSong();
  const markers = document.getElementById('markers');
  if (!song || !markers || !audioBuffer) return;
  markers.innerHTML = '';
  const dur = audioBuffer.duration;
  if (dur <= 0) return;
  song.cues.forEach(cue => {
    const s = timecodeToSeconds(cue.position);
    if (isNaN(s)) return;
    const pct = s / dur;
    if (pct < 0 || pct > 1) return;
    const m = document.createElement('div');
    m.className = 'marker';
    m.style.left = (pct * 100) + '%';
    m.dataset.cueN = String(cue.n);
    m.title = `${cue.position} — Cue ${cue.n}${cue.name ? ' "' + cue.name + '"' : ''}`;
    const lbl = document.createElement('span');
    lbl.className = 'marker-label';
    lbl.textContent = cue.name || `Cue ${cue.n}`;
    m.appendChild(lbl);
    if (selectedMarkerCueN === cue.n) m.classList.add('selected');
    m.addEventListener('mousedown', e => {
      e.stopPropagation();
      startMarkerDrag(cue.n, e);
    });
    m.addEventListener('click', e => {
      e.stopPropagation();
      selectMarker(cue.n);
      audioEl.currentTime = s;
      song.cues.forEach(c => c.collapsed = (c.n !== cue.n));
      saveState();
      render();
    });
    markers.appendChild(m);
  });
  updateCurrentMarker(audioEl ? audioEl.currentTime : 0);
}

function captureCurrentPlayheadAsSmpte() {
  if (!audioEl || isNaN(audioEl.currentTime)) return null;
  return secondsToTimecode(audioEl.currentTime);
}

function dropMarkerAtPlayhead() {
  const song = activeSong();
  if (!song || !audioEl || !audioBuffer) return;
  const tc = captureCurrentPlayheadAsSmpte();
  if (!tc) return;
  CC.state.appendCueWithTcAndResort(song, tc);
  saveState();
  render();
}

function selectMarker(cueN) {
  selectedMarkerCueN = cueN;
  document.querySelectorAll('#markers .marker').forEach(m => {
    m.classList.toggle('selected', m.dataset.cueN === String(cueN));
  });
}

function deselectAllMarkers() {
  selectedMarkerCueN = null;
  document.querySelectorAll('#markers .marker.selected').forEach(m => m.classList.remove('selected'));
}

function getSelectedMarkerCueN() {
  return selectedMarkerCueN;
}

function deleteSelectedMarker() {
  if (selectedMarkerCueN == null) return false;
  const song = activeSong();
  if (!song) return false;
  const idx = song.cues.findIndex(c => c.n === selectedMarkerCueN);
  if (idx < 0) { selectedMarkerCueN = null; return false; }
  song.cues.splice(idx, 1);
  CC.state.resortAndRenumber(song);
  selectedMarkerCueN = null;
  saveState();
  render();
  return true;
}

function startMarkerDrag(cueN, evt) {
  if (!audioBuffer) return;
  const tl = document.getElementById('timeline');
  if (!tl) return;
  evt.preventDefault();
  selectMarker(cueN);
  markerDragState = {
    cueN,
    timelineRect: tl.getBoundingClientRect(),
    durationS: audioBuffer.duration,
    moved: false
  };
  document.body.style.cursor = 'grabbing';
  window.addEventListener('mousemove', onMarkerDragMove);
  window.addEventListener('mouseup', onMarkerDragEnd);
}

function onMarkerDragMove(evt) {
  if (!markerDragState) return;
  markerDragState.moved = true;
  const song = activeSong();
  if (!song) return;
  const { cueN, timelineRect, durationS } = markerDragState;
  const cue = song.cues.find(c => c.n === cueN);
  if (!cue) return;
  let pct = (evt.clientX - timelineRect.left) / timelineRect.width;
  pct = Math.max(0, Math.min(1, pct));
  const seconds = pct * durationS;
  cue.position = secondsToTimecode(seconds);
  const pin = document.querySelector(`#markers .marker[data-cue-n="${cueN}"]`);
  if (pin) pin.style.left = (pct * 100) + '%';
}

function onMarkerDragEnd() {
  if (!markerDragState) return;
  const song = activeSong();
  const moved = markerDragState.moved;
  markerDragState = null;
  document.body.style.cursor = '';
  window.removeEventListener('mousemove', onMarkerDragMove);
  window.removeEventListener('mouseup', onMarkerDragEnd);
  if (moved && song) {
    CC.state.resortAndRenumber(song);
    saveState();
    render();
  }
}

// --- public surface
window.CC = window.CC || {};
window.CC.audio = {
  loadAudioFile, setActiveAudioFromCache, setChannelMute, drawWaveform, renderAudioPanel,
  wireLoadAudio, togglePlay, stopAudio, restartAudio, skipPrevMarker, skipNextMarker,
  startPlayheadLoop, stopPlayheadLoop, updatePlayhead,
  updateCurrentMarker, renderMarkers, captureCurrentPlayheadAsSmpte, dropMarkerAtPlayhead,
  selectMarker, deselectAllMarkers, deleteSelectedMarker, getSelectedMarkerCueN,
  // new pure helpers (test surface)
  fileToSongTime, songToFileTime, clampSeek, shouldAutoPause, pickTickInterval,
  findPrevMarker, findNextMarker
};

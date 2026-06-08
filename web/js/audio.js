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
let trimDragState = null;  // { side, timelineRect, durationS } during a trim drag, else null
let resizeObserver = null;
const channelMute = { L: false, R: false };
const autoloadInFlight = new Set();   // songId set — in-flight autoload from disk path
const autoloadMissing = new Set();    // songId set — paths that already failed this session
// LTC decode state (active song; swapped in setActiveAudioFromCache).
let ltcFrames = null;       // decoded frame map | null
let ltcFramerate = null;    // detected fps | null
let ltcSampleRate = null;   // sample rate the decode was performed at
let ltcChannel = null;      // 'L'|'R'|null
let ltcError = null;        // null on success, else string code from decoder

// --- Viewport (zoom + pan) helpers --------------------------------------
const MIN_ZOOM = 1;
const MAX_ZOOM = 128;

function viewportOf(song, dur) {
  const zoom = song && typeof song.viewportZoom === 'number' ? song.viewportZoom : 1;
  let offsetS = song && typeof song.viewportOffsetS === 'number' ? song.viewportOffsetS : 0;
  const visibleDur = dur / Math.max(1, zoom);
  const maxOffset = Math.max(0, dur - visibleDur);
  offsetS = Math.max(0, Math.min(maxOffset, offsetS));
  return { zoom, offsetS, visibleDur, dur, maxOffset };
}

// Convert song-time (seconds) → x position on timeline (px), and vice versa.
function songTimeToX(t, w, vp) {
  return ((t - vp.offsetS) / vp.visibleDur) * w;
}
function xToSongTime(x, w, vp) {
  return vp.offsetS + (x / w) * vp.visibleDur;
}

function clampViewport(song, dur) {
  if (!song) return;
  song.viewportZoom = Math.max(MIN_ZOOM, Math.min(MAX_ZOOM, song.viewportZoom || 1));
  const visibleDur = dur / song.viewportZoom;
  const maxOffset = Math.max(0, dur - visibleDur);
  song.viewportOffsetS = Math.max(0, Math.min(maxOffset, song.viewportOffsetS || 0));
}

// Zoom by factor centered on the given song-time anchor (keeps that anchor fixed in viewport).
function zoomViewportAt(song, dur, factor, anchorSongT) {
  if (!song) return;
  const oldZoom = song.viewportZoom || 1;
  const newZoom = Math.max(MIN_ZOOM, Math.min(MAX_ZOOM, oldZoom * factor));
  if (newZoom === oldZoom) return;
  const oldVisible = dur / oldZoom;
  const newVisible = dur / newZoom;
  // anchor position as a fraction in current viewport
  const frac = (anchorSongT - (song.viewportOffsetS || 0)) / oldVisible;
  let newOffset = anchorSongT - frac * newVisible;
  song.viewportZoom = newZoom;
  song.viewportOffsetS = newOffset;
  clampViewport(song, dur);
}

function resetViewport(song) {
  if (!song) return;
  song.viewportZoom = 1;
  song.viewportOffsetS = 0;
}

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

// Adaptive SMPTE-style ruler label. Major ticks are on whole-second boundaries,
// so FF is always 00 — but we still show it for format consistency with the
// cue editor and the LTC / OFFSET TC LEDs.
function formatRulerLabel(t, totalDuration) {
  const ts = Math.max(0, Math.round(t));
  const hh = Math.floor(ts / 3600);
  const mm = Math.floor((ts % 3600) / 60);
  const ss = ts % 60;
  if (totalDuration > 3600) {
    return `${String(hh).padStart(2,'0')}:${String(mm).padStart(2,'0')}:${String(ss).padStart(2,'0')}`;
  }
  return `${String(mm).padStart(2,'0')}:${String(ss).padStart(2,'0')}:00`;
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

// Re-run the LTC decoder for the active song using its currently-set ltcChannel.
// Updates audioCache entry + globals + status badge.
function redecodeLtcCurrent() {
  const song = activeSong();
  if (!song || !audioBuffer) { refreshLtcStatusBadge(); return; }
  const entry = audioCache.get(song.id);
  if (!entry) return;
  const r = runLtcDecode(audioBuffer, song);
  entry.ltcFrames = r.frames; entry.ltcFramerate = r.framerate;
  entry.ltcChannel = r.channel; entry.ltcError = r.error;
  ltcFrames = r.frames; ltcFramerate = r.framerate;
  ltcChannel = r.channel; ltcError = r.error;
  refreshLtcStatusBadge();
  updatePlayhead();
}

// Show an inline editable TC popup anchored at clickX (px from timeline left)
// pre-filled with the song-time SMPTE at the clicked point. Confirming the input
// re-seeks the audio to the exact typed TC.
function showTimelineTcPopup(clickX, songT, dur, trim) {
  const tl = document.getElementById('timeline');
  if (!tl) return;
  // Remove any prior popup.
  const prior = tl.querySelector('.tl-tc-popup');
  if (prior) prior.remove();

  const popup = document.createElement('div');
  popup.className = 'tl-tc-popup';
  popup.style.left = clickX + 'px';
  popup.innerHTML = `
    <input type="text" class="tl-tc-input" value="${secondsToTimecode(Math.max(0, songT))}" spellcheck="false">
    <button class="tl-tc-ok" title="Seek to typed TC">✓</button>
    <button class="tl-tc-cancel" title="Close">✕</button>
  `;
  tl.appendChild(popup);
  // Clamp horizontal position so the popup doesn't overflow the timeline edges.
  const tlW = tl.clientWidth;
  const popW = popup.offsetWidth;
  const halfW = popW / 2;
  if (clickX - halfW < 4) popup.style.left = (halfW + 4) + 'px';
  else if (clickX + halfW > tlW - 4) popup.style.left = (tlW - halfW - 4) + 'px';

  const input = popup.querySelector('.tl-tc-input');
  const okBtn = popup.querySelector('.tl-tc-ok');
  const cancelBtn = popup.querySelector('.tl-tc-cancel');

  const commit = () => {
    const v = input.value.trim();
    const songSecs = timecodeToSeconds(v);
    if (!isFinite(songSecs) || isNaN(songSecs)) {
      input.classList.add('parse-error');
      return;
    }
    const fileT = clampSeek(songSecs + (trim.startS || 0), trim, dur);
    if (audioEl) { audioEl.currentTime = fileT; updatePlayhead(); }
    close();
  };
  const close = () => {
    popup.remove();
    document.removeEventListener('mousedown', onOutside, true);
  };
  const onOutside = ev => {
    if (!popup.contains(ev.target)) close();
  };

  input.addEventListener('keydown', e => {
    if (e.key === 'Enter') { e.preventDefault(); commit(); }
    else if (e.key === 'Escape') { e.preventDefault(); close(); }
  });
  input.addEventListener('input', () => input.classList.remove('parse-error'));
  okBtn.addEventListener('click', e => { e.stopPropagation(); commit(); });
  cancelBtn.addEventListener('click', e => { e.stopPropagation(); close(); });
  // Close popup on any mousedown outside it (capture phase so it fires before
  // the timeline's own click handler would re-open the popup).
  setTimeout(() => document.addEventListener('mousedown', onOutside, true), 0);

  input.focus();
  input.select();
}

// Recompute everything dependent on viewport: waveform pixels, ruler ticks,
// marker positions, playhead, trim handle, scrollbar thumb. Cheap to call —
// canvases are GPU-backed, marker math is O(N) for N cues.
function refreshTimelineViewport() {
  if (!audioBuffer) return;
  const song = activeSong();
  const trim = song && song.audioTrim ? song.audioTrim : { startS: 0, endS: null };
  const dur = audioBuffer.duration;
  const ruler = document.getElementById('ruler');
  const waveL = document.getElementById('waveL');
  const waveR = document.getElementById('waveR');
  if (ruler) drawRuler(ruler, dur, trim);
  if (waveL) drawWaveform(waveL, audioBuffer.getChannelData(0), dur, trim);
  if (waveR && audioBuffer.numberOfChannels >= 2) drawWaveform(waveR, audioBuffer.getChannelData(1), dur, trim);
  renderMarkers();
  positionEndHandle();
  updatePlayhead();
  updateViewportBar();
}

function updateViewportBar() {
  const thumb = document.getElementById('viewportThumb');
  if (!thumb || !audioBuffer) return;
  const song = activeSong();
  const dur = audioBuffer.duration;
  const vp = viewportOf(song, dur);
  const leftPct = (vp.offsetS / dur) * 100;
  const widthPct = (vp.visibleDur / dur) * 100;
  thumb.style.left = leftPct + '%';
  thumb.style.width = widthPct + '%';
}

function refreshLtcStatusBadge() {
  const el = document.getElementById('ltcStatusBadge');
  if (!el) return;
  if (!audioBuffer) { el.textContent = '— no audio'; el.className = 'ltc-badge none'; return; }
  if (ltcFrames && ltcFrames.length > 0) {
    el.textContent = `✓ ${ltcFramerate || '?'}fps · ${ltcChannel || '?'} · ${ltcFrames.length} frames`;
    el.className = 'ltc-badge ok';
  } else if (ltcError) {
    el.textContent = `✗ ${ltcError}`;
    el.className = 'ltc-badge err';
  } else {
    el.textContent = '…';
    el.className = 'ltc-badge';
  }
}

// Run the LTC decoder on the configured channel of an AudioBuffer.
// Returns { frames, framerate, channel, error }. Synchronous (Web Worker is a
// future optimization — typical 3-min track decodes in ~200ms on a modern CPU).
function runLtcDecode(audioBuffer, songObj) {
  if (!audioBuffer || !window.CC || !window.CC.ltc) {
    return { frames: [], framerate: null, channel: null, error: 'no-decoder' };
  }
  const ch = audioBuffer.numberOfChannels;
  const wanted = (songObj && songObj.ltcChannel) || 'auto';
  // Build the list of channels to try in order.
  const tryChannels = [];
  if (wanted === 'L') tryChannels.push(0);
  else if (wanted === 'R' && ch >= 2) tryChannels.push(1);
  else if (wanted === 'auto') {
    if (ch >= 2) tryChannels.push(1);   // try R first (most common for LTC)
    tryChannels.push(0);
  } else {
    tryChannels.push(0);
  }
  let lastError = 'no-signal';
  for (const ci of tryChannels) {
    const data = audioBuffer.getChannelData(ci);
    const res = window.CC.ltc.decodeLtc(data, audioBuffer.sampleRate);
    if (res.error === null && res.frames.length > 0) {
      return { frames: res.frames, framerate: res.framerate, channel: ci === 0 ? 'L' : 'R', error: null };
    }
    lastError = res.error;
  }
  return { frames: [], framerate: null, channel: null, error: lastError };
}

async function loadAudioFile(file, opts) {
  const { filePath = '', silent = false } = opts || {};
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

    // Decode LTC from the configured channel (default auto → try R, then L).
    const songObj = state.songs.find(s => s.id === targetSongId);
    const ltcResult = runLtcDecode(newBuffer, songObj);

    audioCache.set(targetSongId, {
      audioEl: newEl,
      audioBuffer: newBuffer,
      audioGainL: gL,
      audioGainR: gR,
      fileName: file.name,
      ltcFrames: ltcResult.frames,
      ltcFramerate: ltcResult.framerate,
      ltcSampleRate: newBuffer.sampleRate,
      ltcChannel: ltcResult.channel,
      ltcError: ltcResult.error,
    });

    const song = state.songs.find(s => s.id === targetSongId);
    if (song) {
      song.audioFileName = file.name;
      if (filePath) song.audioFilePath = filePath;
      saveState();
    }

    if (state.activeSongId === targetSongId) {
      setActiveAudioFromCache(targetSongId);
      renderAudioPanel();
    }
  } catch (err) {
    if (!silent) alert('Audio load failed: ' + err.message);
    throw err;
  }
}

// Desktop only: load audio from an absolute file path via the Electron IPC bridge.
// Returns { ok: true } or { ok: false, reason }. Never alerts — callers decide UX.
async function loadAudioFromPath(filePath) {
  if (!filePath) return { ok: false, reason: 'no-path' };
  if (!(window.cuelist && window.cuelist.readAudio)) return { ok: false, reason: 'not-desktop' };
  try {
    const exists = await window.cuelist.pathExists(filePath);
    if (!exists) return { ok: false, reason: 'missing' };
    const res = await window.cuelist.readAudio(filePath);
    if (res && res.error) return { ok: false, reason: res.error };
    const file = new File([res.buffer], res.name);
    await loadAudioFile(file, { filePath, silent: true });
    return { ok: true };
  } catch (e) {
    return { ok: false, reason: (e && e.message) || 'load-failed' };
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
    ltcFrames = entry.ltcFrames || null;
    ltcFramerate = entry.ltcFramerate || null;
    ltcSampleRate = entry.ltcSampleRate || null;
    ltcChannel = entry.ltcChannel || null;
    ltcError = entry.ltcError || null;
    // Re-apply current channel mute settings to this song's gain nodes.
    if (audioGainL) audioGainL.gain.value = channelMute.L ? 0 : 1;
    if (audioGainR) audioGainR.gain.value = channelMute.R ? 0 : 1;
  } else {
    audioEl = null;
    audioBuffer = null;
    audioGainL = null;
    audioGainR = null;
    audioFileName = '';
    ltcFrames = null; ltcFramerate = null; ltcSampleRate = null; ltcChannel = null; ltcError = null;
    // Desktop autoload: if this song has a remembered file path and the file is
    // still on disk, decode it in the background and re-render when ready.
    tryAutoloadAudioFromPath(songId);
  }
  currentAudioSongId = songId;
}

function tryAutoloadAudioFromPath(songId) {
  if (!(window.cuelist && window.cuelist.readAudio)) return;            // browser → no path access
  if (autoloadInFlight.has(songId) || autoloadMissing.has(songId)) return;
  const song = state.songs.find(s => s.id === songId);
  if (!song || !song.audioFilePath) return;
  autoloadInFlight.add(songId);
  loadAudioFromPath(song.audioFilePath).then(res => {
    autoloadInFlight.delete(songId);
    if (!res.ok) {
      autoloadMissing.add(songId);
      // Re-render so the panel shows the file-missing hint (handled in renderAudioPanel).
      if (state.activeSongId === songId) renderAudioPanel();
    }
  }).catch(() => {
    autoloadInFlight.delete(songId);
    autoloadMissing.add(songId);
  });
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

function drawWaveform(canvas, channelData, durationS, trim) {
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

  // audio-mobile + viewport: timeline x in [0,w] represents song-time
  // [vp.offsetS, vp.offsetS + vp.visibleDur]. For each pixel, sample audio at
  // file-time = songT + audioTrim.startS. Pixels whose file-time falls outside
  // [0, durationS] draw nothing; past trim.endS render dim.
  const trimStart = (trim && typeof trim.startS === 'number') ? trim.startS : 0;
  const trimEnd = (trim && trim.endS != null) ? trim.endS : Infinity;
  const song = activeSong();
  const vp = viewportOf(song, durationS);
  const sampleRate = channelData.length / durationS;
  for (let x = 0; x < w; x++) {
    const songT = vp.offsetS + (x / w) * vp.visibleDur;
    const fileT = songT + trimStart;
    if (fileT < 0 || fileT >= durationS) continue;
    ctx.fillStyle = (fileT >= trimEnd) ? '#2a3a52' : '#5b8dd6';
    const pxDur = vp.visibleDur / w;
    const i0 = Math.floor(fileT * sampleRate);
    const i1 = Math.min(channelData.length, Math.floor((fileT + pxDur) * sampleRate));
    let min = 1, max = -1;
    for (let i = i0; i < i1; i++) {
      const s = channelData[i];
      if (s < min) min = s;
      if (s > max) max = s;
    }
    const y1 = ((1 - max) / 2) * h;
    const y2 = ((1 - min) / 2) * h;
    ctx.fillRect(x, y1, 1, Math.max(1, y2 - y1));
  }
}

function drawRuler(canvas, duration, trim) {
  if (!canvas || !duration) return;
  const dpr = window.devicePixelRatio || 1;
  const w = canvas.clientWidth, h = canvas.clientHeight;
  canvas.width = Math.max(1, Math.floor(w * dpr));
  canvas.height = Math.max(1, Math.floor(h * dpr));
  const ctx = canvas.getContext('2d');
  ctx.scale(dpr, dpr);
  ctx.clearRect(0, 0, w, h);

  const song = activeSong();
  const vp = viewportOf(song, duration);
  // Tick density is based on what's currently visible, not total duration.
  const { interval, major } = pickTickInterval(vp.visibleDur);
  ctx.font = '10px ui-monospace, Consolas, monospace';
  ctx.textBaseline = 'alphabetic';
  const startS = trim ? trim.startS : 0;
  const endS = trim && trim.endS != null ? trim.endS : duration;

  // Snap iteration to a multiple of `interval` at/just-before the left edge.
  const tStart = Math.floor(vp.offsetS / interval) * interval;
  const tEnd = vp.offsetS + vp.visibleDur;
  for (let t = tStart; t <= tEnd + interval; t += interval) {
    if (t < 0 || t > duration) continue;
    const x = Math.round(((t - vp.offsetS) / vp.visibleDur) * w) + 0.5;
    if (x < 0 || x > w) continue;
    const isMajor = (Math.round(t) % major) === 0;
    const inWindow = t >= startS && t <= endS;
    const tickColour = inWindow ? '#888' : '#333';
    const labelColour = inWindow ? '#aaa' : '#444';
    ctx.strokeStyle = tickColour;
    ctx.beginPath();
    ctx.moveTo(x, 0);
    ctx.lineTo(x, isMajor ? 10 : 6);
    ctx.stroke();
    if (isMajor) {
      ctx.fillStyle = labelColour;
      const label = formatRulerLabel(t, vp.visibleDur);
      const labelW = ctx.measureText(label).width;
      if (x + 3 + labelW <= w) ctx.fillText(label, x + 3, h - 3);
    }
  }
}

function renderAudioPanel() {
  const panel = document.getElementById('audioPanel');
  if (!audioEl || !audioBuffer) {
    const song = activeSong();
    const remembered = song && song.audioFileName ? song.audioFileName : '';
    const songId = song ? song.id : null;
    const loading = songId && autoloadInFlight.has(songId);
    const missing = songId && autoloadMissing.has(songId);
    const rememberedPath = song && song.audioFilePath ? song.audioFilePath : '';
    panel.className = 'empty';
    let statusHtml;
    if (loading) {
      statusHtml = '⏳ <span style="color:#888;">loading ' + escapeHtml(remembered || rememberedPath) + '…</span>';
    } else if (missing && rememberedPath) {
      statusHtml = '🎵 ' + escapeHtml(remembered) +
        ' <span style="color:#e08060;">— file not found at ' + escapeHtml(rememberedPath) + '</span>';
    } else if (remembered) {
      statusHtml = '🎵 ' + escapeHtml(remembered) +
        ' <span style="color:#888;">— click Load Audio to re-select</span>';
    } else {
      statusHtml = 'no audio loaded';
    }
    panel.innerHTML = `
      <button id="loadAudioBtn" class="ghost">Load Audio…</button>
      <input type="file" id="loadAudio" accept="audio/*" style="display:none">
      <span style="margin-left:8px;font-size:0.85em;">${statusHtml}</span>
    `;
    wireLoadAudio();
    return;
  }

  const ch = audioBuffer.numberOfChannels;
  const dur = audioBuffer.duration;
  panel.className = '';
  panel.innerHTML = `
    <div id="audioControls" class="reaper-console">
      <div class="console-box transport">
        <button id="prevBtn"    title="Previous marker">⏮</button>
        <button id="stopBtn"    title="Stop (back to in-point)">⏹</button>
        <button id="playBtn"    class="play" title="Play / Pause">${audioEl.paused ? '▶' : '⏸'}</button>
        <button id="nextBtn"    title="Next marker">⏭</button>
        <button id="restartBtn" title="Restart from in-point">↻</button>
        <span class="console-sep"></span>
        <button id="loopBtn"    class="loop" title="Loop between cues (coming soon)">🔁</button>
        <button id="lockBtn"    class="lock ${activeSong()?.audioLocked ? 'on' : ''}" title="Lock the track: disable drag / trim / reset">${activeSong()?.audioLocked ? '🔒' : '🔓'}</button>
        <span class="console-sep"></span>
        <button id="zoomOutBtn" title="Zoom out (or wheel + Ctrl over timeline)">🔍−</button>
        <button id="zoomInBtn"  title="Zoom in (or wheel + Ctrl over timeline)">🔍+</button>
        <button id="zoomFitBtn" title="Reset zoom to fit whole track">↔</button>
      </div>
      <div class="console-box tc-ltc" title="Track LTC at playhead — decoded from the audio signal.">
        <span class="led-label">LTC</span>
        <span id="tcLtc" class="led-main led-cyan">--:--:--:--</span>
      </div>
      <div class="console-box tc-offset" title="LTC + offset = the TC value that will match the lighting console.">
        <span class="led-label">OFFSET TC</span>
        <span id="tcOffsetOut" class="led-main led-amber">--:--:--:--</span>
      </div>
      <div class="console-meta">
        ${ch >= 2 ? `
          <div class="channels">
            <button class="channel-toggle ${channelMute.L ? 'muted' : 'active'}" data-ch="L" title="Toggle Left channel">L</button>
            <button class="channel-toggle ${channelMute.R ? 'muted' : 'active'}" data-ch="R" title="Toggle Right channel">R</button>
          </div>
        ` : ''}
        <span class="filename" title="${escapeHtml(audioFileName)}">${escapeHtml(audioFileName)}</span>
        <button id="reloadAudioBtn" class="ghost" title="Load a different file">Change</button>
        <input type="file" id="loadAudio" accept="audio/*" style="display:none">
      </div>
    </div>
    <div id="audioTcConfig">
      <div class="ltc-status" title="LTC decoder status">
        <span id="ltcStatusBadge" class="ltc-badge">…</span>
      </div>
      <label title="Which audio channel carries the LTC signal. 'Auto' tries R then L.">
        <span class="tc-config-label">Channel</span>
        <select id="ltcChannelInput">
          <option value="auto">Auto (R, then L)</option>
          <option value="L">L</option>
          <option value="R">R</option>
        </select>
      </label>
      <label title="TC value the OFFSET TC reader shows at song start (then advances with playback).">
        <span class="tc-config-label">Start TC</span>
        <input id="tcOffsetInput" type="text" placeholder="01:00:00:00" value="${escapeHtml(activeSong()?.tcOffset || '')}">
      </label>
      <button id="ltcRedecodeBtn" class="ghost" title="Re-run decoder (e.g. after switching channel)">Re-decode</button>
    </div>
    <div id="timeline" class="${activeSong()?.audioLocked ? 'locked' : ''}">
      <canvas id="ruler"></canvas>
      ${ch >= 2 ? `
        <div class="channel-wave audio-body" title="Drag to shift audio. Double-click to reset."><span class="chan-label">L</span><canvas id="waveL"></canvas></div>
        <div class="channel-wave audio-body" title="Drag to shift audio. Double-click to reset."><span class="chan-label">R</span><canvas id="waveR"></canvas></div>
      ` : `
        <div class="channel-wave audio-body" style="height:90px;" title="Drag to shift audio. Double-click to reset."><canvas id="waveL"></canvas></div>
      `}
      <div class="markers" id="markers"></div>
      <div class="playhead" id="playhead" style="left:0px"></div>
      <div class="trim-handle" id="trimEndHandle" title="Audio end — drag to cut the tail"></div>
    </div>
    <div id="viewportBar" title="Visible portion of the track. Drag to pan; wheel + Ctrl over timeline to zoom.">
      <div id="viewportThumb"></div>
    </div>
  `;

  document.getElementById('playBtn').addEventListener('click', togglePlay);
  document.getElementById('prevBtn').addEventListener('click', skipPrevMarker);
  document.getElementById('stopBtn').addEventListener('click', stopAudio);
  document.getElementById('nextBtn').addEventListener('click', skipNextMarker);
  document.getElementById('restartBtn').addEventListener('click', restartAudio);
  const loopBtn = document.getElementById('loopBtn');
  if (loopBtn) loopBtn.addEventListener('click', () => showToast('Loop region — coming soon', { kind: 'info' }));
  const lockBtn = document.getElementById('lockBtn');
  if (lockBtn) lockBtn.addEventListener('click', () => {
    const song = activeSong(); if (!song) return;
    song.audioLocked = !song.audioLocked;
    saveState();
    renderAudioPanel();
    showToast(song.audioLocked ? 'Track locked 🔒' : 'Track unlocked 🔓', { kind: 'info', ms: 1500 });
  });

  const zoomInBtn = document.getElementById('zoomInBtn');
  const zoomOutBtn = document.getElementById('zoomOutBtn');
  const zoomFitBtn = document.getElementById('zoomFitBtn');
  const doZoom = factor => {
    const song = activeSong(); if (!song || !audioBuffer) return;
    const vp = viewportOf(song, audioBuffer.duration);
    const centerSongT = vp.offsetS + vp.visibleDur / 2;
    zoomViewportAt(song, audioBuffer.duration, factor, centerSongT);
    saveState();
    refreshTimelineViewport();
  };
  if (zoomInBtn) zoomInBtn.addEventListener('click', () => doZoom(1.5));
  if (zoomOutBtn) zoomOutBtn.addEventListener('click', () => doZoom(1 / 1.5));
  if (zoomFitBtn) zoomFitBtn.addEventListener('click', () => {
    const song = activeSong(); if (!song) return;
    resetViewport(song); saveState(); refreshTimelineViewport();
  });

  // Mouse wheel over the timeline: Ctrl+wheel zoom centered on cursor, plain wheel pan.
  const tlEl = document.getElementById('timeline');
  if (tlEl) tlEl.addEventListener('wheel', e => {
    if (!audioBuffer) return;
    const song = activeSong(); if (!song) return;
    e.preventDefault();
    const rect = tlEl.getBoundingClientRect();
    const w = rect.width;
    const x = e.clientX - rect.left;
    const vp = viewportOf(song, audioBuffer.duration);
    if (e.ctrlKey || e.metaKey) {
      const factor = e.deltaY < 0 ? 1.18 : 1 / 1.18;
      const anchor = xToSongTime(x, w, vp);
      zoomViewportAt(song, audioBuffer.duration, factor, anchor);
    } else {
      // Pan: deltaY (vertical wheel) drives horizontal pan — most laptops use it.
      const delta = (e.deltaX !== 0 ? e.deltaX : e.deltaY);
      const panAmt = (delta / w) * vp.visibleDur;
      song.viewportOffsetS = (song.viewportOffsetS || 0) + panAmt;
      clampViewport(song, audioBuffer.duration);
    }
    saveState();
    refreshTimelineViewport();
  }, { passive: false });

  // Mini scrollbar drag to pan.
  const sbThumb = document.getElementById('viewportThumb');
  if (sbThumb) {
    let dragState = null;
    sbThumb.addEventListener('mousedown', e => {
      const song = activeSong(); if (!song || !audioBuffer) return;
      e.preventDefault();
      const sb = sbThumb.parentElement;
      const sbW = sb.getBoundingClientRect().width;
      dragState = { startClientX: e.clientX, startOffsetS: song.viewportOffsetS || 0, sbW };
      document.body.style.cursor = 'grabbing';
      const move = ev => {
        if (!dragState) return;
        const dx = ev.clientX - dragState.startClientX;
        const dur = audioBuffer.duration;
        const dt = (dx / dragState.sbW) * dur;
        song.viewportOffsetS = dragState.startOffsetS + dt;
        clampViewport(song, dur);
        refreshTimelineViewport();
      };
      const up = () => {
        dragState = null;
        document.body.style.cursor = '';
        window.removeEventListener('mousemove', move);
        window.removeEventListener('mouseup', up);
        saveState();
      };
      window.addEventListener('mousemove', move);
      window.addEventListener('mouseup', up);
    });
  }

  const tcOffsetInput = document.getElementById('tcOffsetInput');
  if (tcOffsetInput) {
    const onOffsetEdit = e => {
      const song = activeSong(); if (!song) return;
      const v = e.target.value.trim();
      song.tcOffset = v;
      // Visual feedback: red border if the value can't be parsed (still saved).
      const parsed = signedTimecodeToSeconds(v);
      const invalid = v !== '' && isNaN(parsed);
      e.target.classList.toggle('parse-error', invalid);
      e.target.title = invalid
        ? 'Invalid format. Use HH:MM:SS:FF (e.g. 01:00:00:00)'
        : 'TC value the OFFSET TC reader shows at song start.';
      saveState();
      updatePlayhead();
    };
    // Live update as the user types AND on commit (blur / Enter).
    tcOffsetInput.addEventListener('input', onOffsetEdit);
    tcOffsetInput.addEventListener('change', onOffsetEdit);
  }
  const chanSel = document.getElementById('ltcChannelInput');
  if (chanSel) {
    const song = activeSong();
    chanSel.value = (song && song.ltcChannel) || 'auto';
    chanSel.addEventListener('change', e => {
      const s = activeSong(); if (!s) return;
      s.ltcChannel = e.target.value;
      saveState();
      redecodeLtcCurrent();
    });
  }
  const redecBtn = document.getElementById('ltcRedecodeBtn');
  if (redecBtn) redecBtn.addEventListener('click', redecodeLtcCurrent);
  refreshLtcStatusBadge();
  document.getElementById('reloadAudioBtn').addEventListener('click', pickAndLoadAudio);
  document.getElementById('loadAudio').addEventListener('change', e => {
    if (e.target.files[0]) loadAudioFile(e.target.files[0]);
    e.target.value = '';
  });
  panel.querySelectorAll('.channel-toggle').forEach(btn => {
    btn.addEventListener('click', () => setChannelMute(btn.dataset.ch, !channelMute[btn.dataset.ch]));
  });

  const endHandle = document.getElementById('trimEndHandle');
  if (endHandle) {
    endHandle.addEventListener('mousedown', startEndHandleDrag);
    endHandle.addEventListener('dblclick', () => {
      const song = activeSong();
      if (song && song.audioTrim) { song.audioTrim.endS = null; redrawAudioBody(); saveState(); }
    });
  }
  panel.querySelectorAll('.audio-body').forEach(body => {
    body.addEventListener('mousedown', startAudioBodyDrag);
    body.addEventListener('dblclick', resetAudioTrim);
  });

  const tl = document.getElementById('timeline');
  tl.addEventListener('click', e => {
    if (e.target.classList.contains('marker') || e.target.classList.contains('marker-label')) return;
    if (e.target.classList.contains('trim-handle')) return;
    if (e.target.closest('.tl-tc-popup')) return;        // ignore clicks INSIDE the popup
    if (trimDragState && trimDragState.moved) return;    // suppress click after audio body drag
    deselectAllMarkers();
    const rect = tl.getBoundingClientRect();
    const x = e.clientX - rect.left;
    const w = rect.width;
    const song = activeSong();
    const trim = (song && song.audioTrim) ? song.audioTrim : { startS: 0, endS: null };
    const vp = viewportOf(song, dur);
    // Click position in song-time uses viewport offset/zoom.
    const songT = xToSongTime(x, w, vp);
    audioEl.currentTime = clampSeek(songT + trim.startS, trim, dur);
    updatePlayhead();
    // Open an inline TC popup pre-filled with the song-time at click point.
    showTimelineTcPopup(x, songT, dur, trim);
  });

  // Draw waveforms once panel is in DOM (with proper width)
  requestAnimationFrame(() => {
    const ruler = document.getElementById('ruler');
    const song = activeSong();
    const trim = (song && song.audioTrim) ? song.audioTrim : { startS: 0, endS: null };
    if (ruler) drawRuler(ruler, audioBuffer.duration, trim);

    const waveL = document.getElementById('waveL');
    if (waveL) drawWaveform(waveL, audioBuffer.getChannelData(0), audioBuffer.duration, trim);
    if (ch >= 2) {
      const waveR = document.getElementById('waveR');
      if (waveR) drawWaveform(waveR, audioBuffer.getChannelData(1), audioBuffer.duration, trim);
    }
    renderMarkers();
    positionEndHandle();
    updatePlayhead();
  });

  if (resizeObserver) resizeObserver.disconnect();
  if (window.ResizeObserver && tlEl) {
    resizeObserver = new ResizeObserver(() => { refreshTimelineViewport(); });
    resizeObserver.observe(tlEl);
  }
  // First viewport bar paint right after the panel mounts.
  requestAnimationFrame(updateViewportBar);
}

async function pickAndLoadAudio() {
  // Desktop: native dialog → path → readAudio IPC → decode.
  if (window.cuelist && window.cuelist.pickAudio) {
    const picked = await window.cuelist.pickAudio();
    if (!picked) return;
    const res = await loadAudioFromPath(picked.path);
    if (!res.ok) alert('Audio load failed: ' + res.reason);
    return;
  }
  // Browser: trigger the hidden <input type="file"> (only path-less option).
  const input = document.getElementById('loadAudio');
  if (input) input.click();
}

function wireLoadAudio() {
  const btn = document.getElementById('loadAudioBtn');
  const input = document.getElementById('loadAudio');
  if (!btn || !input) return;
  btn.addEventListener('click', pickAndLoadAudio);
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
  const btn = document.getElementById('playBtn');
  if (btn) btn.textContent = '▶';
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
  const dur = audioBuffer ? audioBuffer.duration : Infinity;
  const endS = trim.endS != null ? trim.endS : dur;
  const inWindow = song.cues.filter(c => {
    const sSong = timecodeToSeconds(c.position);
    if (isNaN(sSong)) return false;
    const sFile = songToFileTime(sSong, trim);
    return sFile >= trim.startS && sFile <= endS;
  });
  const songT = fileToSongTime(audioEl.currentTime, trim);
  const target = findPrevMarker(songT, inWindow);
  if (target) {
    audioEl.currentTime = songToFileTime(timecodeToSeconds(target.position), trim);
  } else {
    audioEl.currentTime = trim.startS;
  }
  updatePlayhead();
}

function skipNextMarker() {
  const song = activeSong();
  if (!audioEl || !song) return;
  const trim = song.audioTrim || { startS: 0, endS: null };
  const dur = audioBuffer ? audioBuffer.duration : Infinity;
  const endS = trim.endS != null ? trim.endS : dur;
  const inWindow = song.cues.filter(c => {
    const sSong = timecodeToSeconds(c.position);
    if (isNaN(sSong)) return false;
    const sFile = songToFileTime(sSong, trim);
    return sFile >= trim.startS && sFile <= endS;
  });
  const songT = fileToSongTime(audioEl.currentTime, trim);
  const target = findNextMarker(songT, inWindow);
  if (!target) return;
  audioEl.currentTime = songToFileTime(timecodeToSeconds(target.position), trim);
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
  const song = activeSong();
  const trim = (song && song.audioTrim) ? song.audioTrim : { startS: 0, endS: null };

  if (shouldAutoPause(audioEl.currentTime, trim, audioEl.paused)) {
    audioEl.pause();
    audioEl.currentTime = trim.endS;
  }

  const tl = document.getElementById('timeline');
  const ph = document.getElementById('playhead');
  const tcEl = document.getElementById('tcReader');
  const subEl = document.getElementById('tcReaderSub');
  if (!tl || !ph) return;
  const dur = audioBuffer.duration;
  const t = audioEl.currentTime;
  const songT = fileToSongTime(t, trim);
  // audio-mobile + viewport: playhead x computed from current viewport. Hidden
  // (off-screen) if the playhead is outside the visible range.
  const vp = viewportOf(song, dur);
  const tlW = tl.clientWidth;
  if (songT < vp.offsetS || songT > vp.offsetS + vp.visibleDur) {
    ph.style.left = '-3px';
  } else {
    const pct = (songT - vp.offsetS) / vp.visibleDur;
    ph.style.left = (pct * tlW) + 'px';
  }

  if (tcEl) {
    tcEl.textContent = secondsToTimecode(Math.max(0, songT));
    tcEl.style.color =
      t < trim.startS ? '#888' :
      (trim.endS != null && t > trim.endS) ? '#ff5a5a' :
      '#fff';
  }
  if (subEl) {
    const segDur = (trim.endS != null ? trim.endS : dur) - trim.startS;
    subEl.textContent = `${secondsToMMSS(Math.max(0, songT))} / ${secondsToMMSS(Math.max(0, segDur))}`;
  }
  // LTC: from decoder cache. Uses file-time (audioEl.currentTime), ignores trim —
  // it's the actual signal recorded in the file.
  // OFFSET TC: independent of LTC. Starts at `offset` when the song is at time 0,
  // advances at real-time with songTime (= file-time − trim.startS).
  // Example: offset=01:00:00:00 → at song-time 0, OFFSET TC reads 01:00:00:00.
  const ltcEl = document.getElementById('tcLtc');
  const offsetEl = document.getElementById('tcOffsetOut');
  if (ltcEl || offsetEl) {
    const offsetStr = song ? song.tcOffset : '';
    const offsetSecs = signedTimecodeToSeconds(offsetStr);
    const hasOffset = !isNaN(offsetSecs);
    const hasLtc = ltcFrames && ltcFrames.length > 0 && ltcSampleRate;
    const ltcSecs = hasLtc ? window.CC.ltc.ltcAtSample(ltcFrames, Math.round(t * ltcSampleRate), ltcSampleRate) : NaN;
    if (ltcEl) ltcEl.textContent = hasLtc ? secondsToSignedTimecode(ltcSecs) : '--:--:--:--';
    if (offsetEl) {
      if (hasOffset) offsetEl.textContent = secondsToSignedTimecode(offsetSecs + Math.max(0, songT));
      else offsetEl.textContent = '--:--:--:--';
    }
  }
  updateCurrentMarker(songT);
}

function updateCurrentMarker(songT) {
  const song = activeSong();
  if (!song) return;
  const positions = song.cues
    .map(c => ({ c, s: timecodeToSeconds(c.position) }))
    .filter(x => !isNaN(x.s));
  if (positions.length === 0) return;
  let currentId = null;
  for (const { c, s } of positions) {
    if (s <= songT) currentId = c;
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
  const trim = song.audioTrim || { startS: 0, endS: null };
  const vp = viewportOf(song, dur);
  // audio-mobile model + viewport: markers anchored to SMPTE; x computed from
  // the visible time range. Markers outside the viewport aren't rendered.
  song.cues.forEach(cue => {
    const sSong = timecodeToSeconds(cue.position);
    if (isNaN(sSong)) return;
    if (sSong < vp.offsetS || sSong > vp.offsetS + vp.visibleDur) return;
    const pct = (sSong - vp.offsetS) / vp.visibleDur;
    const sFile = songToFileTime(sSong, trim);   // for the seek-on-click only
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
      audioEl.currentTime = sFile;
      song.cues.forEach(c => c.collapsed = (c.n !== cue.n));
      saveState();
      render();
    });
    markers.appendChild(m);
  });
  updateCurrentMarker(audioEl ? fileToSongTime(audioEl.currentTime, trim) : 0);
}

function captureCurrentPlayheadAsSmpte() {
  if (!audioEl || isNaN(audioEl.currentTime)) return null;
  const song = activeSong();
  const trim = (song && song.audioTrim) ? song.audioTrim : { startS: 0, endS: null };
  return secondsToTimecode(Math.max(0, fileToSongTime(audioEl.currentTime, trim)));
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
  let pxX = evt.clientX - timelineRect.left;
  pxX = Math.max(0, Math.min(timelineRect.width, pxX));
  // viewport-aware: x → song-time via active viewport.
  const vp = viewportOf(song, durationS);
  const songSeconds = vp.offsetS + (pxX / timelineRect.width) * vp.visibleDur;
  cue.position = secondsToTimecode(Math.max(0, songSeconds));
  const pin = document.querySelector(`#markers .marker[data-cue-n="${cueN}"]`);
  if (pin) pin.style.left = (pxX / timelineRect.width * 100) + '%';
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

// audio-mobile model: drag the waveform body to change `startS` (offset);
// drag the right-edge handle to change `endS` (audio end trim).

function redrawAudioBody() {
  if (!audioBuffer) return;
  const song = activeSong();
  const trim = (song && song.audioTrim) ? song.audioTrim : { startS: 0, endS: null };
  const dur = audioBuffer.duration;
  const wl = document.getElementById('waveL');
  if (wl) drawWaveform(wl, audioBuffer.getChannelData(0), dur, trim);
  if (audioBuffer.numberOfChannels >= 2) {
    const wr = document.getElementById('waveR');
    if (wr) drawWaveform(wr, audioBuffer.getChannelData(1), dur, trim);
  }
  positionEndHandle();
  updatePlayhead();
}

function positionEndHandle() {
  const song = activeSong();
  if (!song || !audioBuffer) return;
  const trim = song.audioTrim || { startS: 0, endS: null };
  const dur = audioBuffer.duration;
  const handle = document.getElementById('trimEndHandle');
  if (!handle) return;
  const vp = viewportOf(song, dur);
  const audioEndFile = trim.endS != null ? trim.endS : dur;
  const audioEndSong = audioEndFile - trim.startS;
  // Hide handle if outside the current viewport.
  if (audioEndSong < vp.offsetS || audioEndSong > vp.offsetS + vp.visibleDur) {
    handle.style.display = 'none';
    return;
  }
  handle.style.display = '';
  const pct = (audioEndSong - vp.offsetS) / vp.visibleDur;
  handle.style.left = (pct * 100) + '%';
}

function startAudioBodyDrag(evt) {
  if (!audioBuffer) return;
  if (evt.target.classList.contains('trim-handle')) return;  // let handle drag take over
  if (evt.target.classList.contains('marker') || evt.target.classList.contains('marker-label')) return;
  const song = activeSong();
  if (!song) return;
  if (song.audioLocked) return;       // 🔒 track is locked
  const tl = document.getElementById('timeline');
  if (!tl) return;
  evt.preventDefault();
  if (!song.audioTrim) song.audioTrim = { startS: 0, endS: null };
  trimDragState = {
    kind: 'body',
    timelineRect: tl.getBoundingClientRect(),
    durationS: audioBuffer.duration,
    initialClientX: evt.clientX,
    initialStartS: song.audioTrim.startS,
    initialEndS: song.audioTrim.endS,
    moved: false
  };
  document.body.style.cursor = 'grabbing';
  window.addEventListener('mousemove', onAudioBodyDragMove);
  window.addEventListener('mouseup', onAudioBodyDragEnd);
}

function onAudioBodyDragMove(evt) {
  if (!trimDragState || trimDragState.kind !== 'body') return;
  trimDragState.moved = true;
  const song = activeSong();
  if (!song) return;
  const { timelineRect, durationS, initialClientX, initialStartS, initialEndS } = trimDragState;
  // viewport-aware: a pixel of drag corresponds to vp.visibleDur/w seconds of shift.
  const vp = viewportOf(song, durationS);
  const dxPx = evt.clientX - initialClientX;
  const dxS = (dxPx / timelineRect.width) * vp.visibleDur;
  song.audioTrim.startS = initialStartS - dxS;
  if (initialEndS != null) song.audioTrim.endS = initialEndS - dxS;
  // No hard clamp on startS — operator can shift audio fully off either side if they want.
  // Practical limit: don't let audio disappear entirely.
  const minStartS = -(durationS - 0.5);
  const maxStartS = durationS - 0.5;
  song.audioTrim.startS = Math.max(minStartS, Math.min(maxStartS, song.audioTrim.startS));
  redrawAudioBody();
}

function onAudioBodyDragEnd() {
  if (!trimDragState || trimDragState.kind !== 'body') return;
  const moved = trimDragState.moved;
  trimDragState = null;
  document.body.style.cursor = '';
  window.removeEventListener('mousemove', onAudioBodyDragMove);
  window.removeEventListener('mouseup', onAudioBodyDragEnd);
  if (moved) saveState();
}

function startEndHandleDrag(evt) {
  if (!audioBuffer) return;
  const song = activeSong();
  if (song && song.audioLocked) return;       // 🔒 track is locked
  const tl = document.getElementById('timeline');
  if (!tl) return;
  evt.preventDefault();
  evt.stopPropagation();
  trimDragState = {
    kind: 'end',
    timelineRect: tl.getBoundingClientRect(),
    durationS: audioBuffer.duration
  };
  document.body.style.cursor = 'ew-resize';
  window.addEventListener('mousemove', onEndHandleDragMove);
  window.addEventListener('mouseup', onEndHandleDragEnd);
}

function onEndHandleDragMove(evt) {
  if (!trimDragState || trimDragState.kind !== 'end') return;
  const song = activeSong();
  if (!song) return;
  if (!song.audioTrim) song.audioTrim = { startS: 0, endS: null };
  const { timelineRect, durationS } = trimDragState;
  const vp = viewportOf(song, durationS);
  let pxX = evt.clientX - timelineRect.left;
  pxX = Math.max(0, Math.min(timelineRect.width, pxX));
  const songT = vp.offsetS + (pxX / timelineRect.width) * vp.visibleDur;
  const fileT = songT + song.audioTrim.startS;
  const leftBound = song.audioTrim.startS + 0.5;
  song.audioTrim.endS = Math.max(leftBound, Math.min(durationS, fileT));
  redrawAudioBody();
}

function onEndHandleDragEnd() {
  if (!trimDragState || trimDragState.kind !== 'end') return;
  trimDragState = null;
  document.body.style.cursor = '';
  window.removeEventListener('mousemove', onEndHandleDragMove);
  window.removeEventListener('mouseup', onEndHandleDragEnd);
  saveState();
}

function resetAudioTrim() {
  const song = activeSong();
  if (!song) return;
  if (song.audioLocked) return;             // 🔒 track is locked
  song.audioTrim = { startS: 0, endS: null };
  redrawAudioBody();
  saveState();
}

// --- public surface
window.CC = window.CC || {};
window.CC.audio = {
  loadAudioFile, loadAudioFromPath, pickAndLoadAudio, tryAutoloadAudioFromPath,
  setActiveAudioFromCache, setChannelMute, drawWaveform, renderAudioPanel,
  wireLoadAudio, togglePlay, stopAudio, restartAudio, skipPrevMarker, skipNextMarker,
  startPlayheadLoop, stopPlayheadLoop, updatePlayhead,
  updateCurrentMarker, renderMarkers, captureCurrentPlayheadAsSmpte, dropMarkerAtPlayhead,
  selectMarker, deselectAllMarkers, deleteSelectedMarker, getSelectedMarkerCueN,
  // audio-mobile trim model
  redrawAudioBody, positionEndHandle, startAudioBodyDrag, startEndHandleDrag, resetAudioTrim,
  // pure helpers (test surface)
  fileToSongTime, songToFileTime, clampSeek, shouldAutoPause, pickTickInterval,
  findPrevMarker, findNextMarker
};

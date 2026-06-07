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

  // audio-mobile model: timeline x in [0,w] represents song-time [0, durationS].
  // For each pixel, sample audio at file-time = songT + startS (= x/w * durationS + startS).
  // Pixels whose file-time falls outside [0, audio_dur] draw nothing.
  const offsetS = (trim && typeof trim.startS === 'number') ? trim.startS : 0;
  const endS = (trim && trim.endS != null) ? trim.endS : Infinity;
  const sampleRate = channelData.length / durationS;
  ctx.fillStyle = '#5b8dd6';
  for (let x = 0; x < w; x++) {
    const songT = (x / w) * durationS;
    const fileT = songT + offsetS;
    if (fileT < 0 || fileT >= durationS) continue;       // outside audio file
    if (fileT >= endS) {                                  // past end trim — render dim
      ctx.fillStyle = '#2a3a52';
    } else {
      ctx.fillStyle = '#5b8dd6';
    }
    const i0 = Math.floor(fileT * sampleRate);
    const i1 = Math.min(channelData.length, Math.floor((fileT + durationS / w) * sampleRate));
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

  const { interval, major } = pickTickInterval(duration);
  ctx.font = '10px ui-monospace, Consolas, monospace';
  ctx.textBaseline = 'alphabetic';
  const startS = trim ? trim.startS : 0;
  const endS = trim && trim.endS != null ? trim.endS : duration;

  for (let t = 0; t <= duration; t += interval) {
    const x = Math.round((t / duration) * w) + 0.5;
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
      const mins = Math.floor(t / 60);
      const secs = Math.floor(t % 60);
      const label = `${mins}:${secs.toString().padStart(2, '0')}`;
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
      <div class="tc-reader">
        <span id="tcReader">00:00:00:00</span>
        <span id="tcReaderSub">0:00 / ${secondsToMMSS(dur)}</span>
      </div>
      <button id="reloadAudioBtn" class="ghost" title="Load a different file">Change</button>
      <input type="file" id="loadAudio" accept="audio/*" style="display:none">
    </div>
    <div id="timeline">
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
    if (trimDragState && trimDragState.moved) return;  // suppress click after audio body drag
    deselectAllMarkers();
    const rect = tl.getBoundingClientRect();
    const pct = (e.clientX - rect.left) / rect.width;
    const song = activeSong();
    const trim = (song && song.audioTrim) ? song.audioTrim : { startS: 0, endS: null };
    // Click position is song-time; convert to file-time for audioEl.
    const songT = pct * dur;
    audioEl.currentTime = clampSeek(songT + trim.startS, trim, dur);
    updatePlayhead();
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

  const tlEl = document.getElementById('timeline');
  if (resizeObserver) resizeObserver.disconnect();
  if (window.ResizeObserver && tlEl) {
    resizeObserver = new ResizeObserver(() => {
      const ruler2 = document.getElementById('ruler');
      const song2 = activeSong();
      const trim2 = (song2 && song2.audioTrim) ? song2.audioTrim : { startS: 0, endS: null };
      if (ruler2 && audioBuffer) drawRuler(ruler2, audioBuffer.duration, trim2);
      const wl = document.getElementById('waveL');
      if (wl && audioBuffer) drawWaveform(wl, audioBuffer.getChannelData(0), audioBuffer.duration, trim2);
      if (audioBuffer && audioBuffer.numberOfChannels >= 2) {
        const wr = document.getElementById('waveR');
        if (wr) drawWaveform(wr, audioBuffer.getChannelData(1), audioBuffer.duration, trim2);
      }
      positionEndHandle();
      updatePlayhead();
    });
    resizeObserver.observe(tlEl);
  }
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
  // audio-mobile: playhead position is song-time, not file-time
  const pct = dur > 0 ? songT / dur : 0;
  ph.style.left = (Math.max(0, Math.min(1, pct)) * tl.clientWidth) + 'px';

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
  // audio-mobile model: markers are anchored to SMPTE timeline directly.
  song.cues.forEach(cue => {
    const sSong = timecodeToSeconds(cue.position);
    if (isNaN(sSong)) return;
    const pct = sSong / dur;
    if (pct < 0 || pct > 1) return;
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
  let pct = (evt.clientX - timelineRect.left) / timelineRect.width;
  pct = Math.max(0, Math.min(1, pct));
  // audio-mobile model: timeline coord = song-time directly.
  const songSeconds = pct * durationS;
  cue.position = secondsToTimecode(Math.max(0, songSeconds));
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
  const audioEndFile = trim.endS != null ? trim.endS : dur;
  const audioEndSong = audioEndFile - trim.startS;          // song-time position of audio end
  const pct = Math.max(0, Math.min(1, audioEndSong / dur));
  handle.style.left = (pct * 100) + '%';
}

function startAudioBodyDrag(evt) {
  if (!audioBuffer) return;
  if (evt.target.classList.contains('trim-handle')) return;  // let handle drag take over
  if (evt.target.classList.contains('marker') || evt.target.classList.contains('marker-label')) return;
  const tl = document.getElementById('timeline');
  if (!tl) return;
  evt.preventDefault();
  const song = activeSong();
  if (!song) return;
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
  // dragging right = audio moves right = startS decreases (audio's file-t=0 lines up later on timeline)
  const dxPx = evt.clientX - initialClientX;
  const dxS = (dxPx / timelineRect.width) * durationS;
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
  let pct = (evt.clientX - timelineRect.left) / timelineRect.width;
  pct = Math.max(0, Math.min(1, pct));
  const songT = pct * durationS;
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
  song.audioTrim = { startS: 0, endS: null };
  redrawAudioBody();
  saveState();
}

// --- public surface
window.CC = window.CC || {};
window.CC.audio = {
  loadAudioFile, setActiveAudioFromCache, setChannelMute, drawWaveform, renderAudioPanel,
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

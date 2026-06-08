// state.js — data model, persistence, migration, project/CSV IO. Depends on: constants, util. Defines global state, moods, defaults, pools.

function newSong() {
  const maxSeq = (state && state.songs)
    ? state.songs.reduce((m, s) => Math.max(m, parseInt(s.sequence) || 0), 0)
    : 0;
  return {
    id: genId(),
    name: '',
    sequence: maxSeq > 0 ? maxSeq + 1 : 1,
    cues: [],
    audioFileName: '',
    audioTrim: { startS: 0, endS: null }
  };
}

function newProject() {
  const song = { id: genId(), name: '', sequence: 1, cues: [], audioFileName: '', audioFilePath: '', audioTrim: { startS: 0, endS: null }, audioLocked: false, viewportZoom: 1, viewportOffsetS: 0, ltcChannel: 'auto', tcOffset: '' };
  return { songs: [song], activeSongId: song.id, storeMode: 'Overwrite' };
}

function activeSong() {
  if (!state.songs || state.songs.length === 0) return null;
  return state.songs.find(s => s.id === state.activeSongId) || state.songs[0];
}

function newCue() {
  const song = activeSong();
  const maxN = song ? song.cues.reduce((m, c) => Math.max(m, parseFloat(c.n) || 0), 0) : 0;
  return {
    n: maxN + 1,
    name: '',
    actions: [newAction()],
    fade: '',
    delay: '',
    collapsed: false
  };
}

function appendCueWithTcAndResort(song, tc) {
  if (!song || !Array.isArray(song.cues)) return;
  song.cues.push({
    n: 0,
    position: tc,
    name: '',
    actions: [newAction()],
    fade: '',
    delay: '',
    collapsed: false
  });
  resortAndRenumber(song);
}

function resortAndRenumber(song) {
  if (!song || !Array.isArray(song.cues)) return;
  song.cues.sort((a, b) => {
    const sa = timecodeToSeconds(a.position);
    const sb = timecodeToSeconds(b.position);
    if (isNaN(sa) && isNaN(sb)) return 0;
    if (isNaN(sa)) return 1;   // invalid TCs sink to the end
    if (isNaN(sb)) return -1;
    return sa - sb;
  });
  song.cues.forEach((c, i) => { c.n = i + 1; });
}

function newAction() {
  const presets = {};
  POOLS.forEach(p => presets[p] = { name: '', fade: '', delay: '' });
  return { group: '', presets };
}

function migrateActions(actions) {
  (actions || []).forEach(action => {
    if (!action.presets) action.presets = {};
    POOLS.forEach(p => {
      const v = action.presets[p];
      if (v == null || v === '') {
        action.presets[p] = { name: '', fade: '', delay: '' };
      } else if (typeof v === 'string') {
        action.presets[p] = { name: v, fade: '', delay: '' };
      } else if (typeof v === 'object') {
        action.presets[p] = {
          name: v.name || '',
          fade: v.fade != null ? v.fade : '',
          delay: v.delay != null ? v.delay : ''
        };
      }
    });
  });
}

function migrateCues(cues) {
  (cues || []).forEach(cue => {
    if (typeof cue.collapsed !== 'boolean') cue.collapsed = false;
    if (cue.position == null) cue.position = '';
    migrateActions(cue.actions);
  });
}

function migrateState(s) {
  if (!s) return s;
  // Old single-song format: { songName, sequence, cues }
  if (!Array.isArray(s.songs)) {
    if (Array.isArray(s.cues)) {
      const song = {
        id: genId(),
        name: s.songName || '',
        sequence: s.sequence || 1,
        cues: s.cues
      };
      s = { songs: [song], activeSongId: song.id };
    } else {
      return null;
    }
  }
  // Ensure each song has the expected shape
  s.songs.forEach(song => {
    if (!song.id) song.id = genId();
    if (!Array.isArray(song.cues)) song.cues = [];
    if (typeof song.audioFileName !== 'string') song.audioFileName = '';
    if (typeof song.audioFilePath !== 'string') song.audioFilePath = '';
    if (typeof song.trackTcStart === 'string') delete song.trackTcStart;  // obsoleted by LTC decoder
    if (typeof song.audioLocked !== 'boolean') song.audioLocked = false;
    if (typeof song.viewportZoom !== 'number' || song.viewportZoom < 1) song.viewportZoom = 1;
    if (typeof song.viewportOffsetS !== 'number' || song.viewportOffsetS < 0) song.viewportOffsetS = 0;
    if (typeof song.ltcChannel !== 'string' || !['auto','L','R'].includes(song.ltcChannel)) song.ltcChannel = 'auto';
    if (typeof song.tcOffset !== 'string') song.tcOffset = '';
    if (!song.audioTrim || typeof song.audioTrim !== 'object') {
      song.audioTrim = { startS: 0, endS: null };
    } else {
      if (typeof song.audioTrim.startS !== 'number' || song.audioTrim.startS < 0) song.audioTrim.startS = 0;
      if (song.audioTrim.endS != null && typeof song.audioTrim.endS !== 'number') song.audioTrim.endS = null;
    }
    migrateCues(song.cues);
  });
  if (s.songs.length === 0) {
    const song = { id: genId(), name: '', sequence: 1, cues: [], audioFileName: '', audioFilePath: '', audioTrim: { startS: 0, endS: null }, audioLocked: false, viewportZoom: 1, viewportOffsetS: 0, ltcChannel: 'auto', tcOffset: '' };
    s.songs.push(song);
  }
  if (!s.songs.find(x => x.id === s.activeSongId)) {
    s.activeSongId = s.songs[0].id;
  }
  if (s.storeMode !== 'Merge') s.storeMode = 'Overwrite';
  return s;
}

function loadState() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    return raw ? migrateState(JSON.parse(raw)) : null;
  } catch (e) { return null; }
}

function saveState() {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
}

function loadMoods() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY_MOODS);
    if (!raw) return [];
    const arr = JSON.parse(raw);
    if (!Array.isArray(arr)) return [];
    arr.forEach(m => {
      if (!m.id) m.id = genId();
      if (typeof m.name !== 'string') m.name = '';
      if (!Array.isArray(m.actions)) m.actions = [newAction()];
      migrateActions(m.actions);
    });
    return arr;
  } catch (e) { return []; }
}

function saveMoods() {
  localStorage.setItem(STORAGE_KEY_MOODS, JSON.stringify(moods));
}

function newMood() {
  return { id: genId(), name: '', actions: [newAction()] };
}

function makeDefaults() {
  const d = {};
  POOLS.forEach(p => d[p] = { fade: '', delay: '' });
  return d;
}

function loadDefaults() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY_DEFAULTS);
    if (!raw) return makeDefaults();
    const d = JSON.parse(raw) || {};
    const out = makeDefaults();
    POOLS.forEach(p => {
      if (d[p]) {
        out[p].fade  = d[p].fade  != null ? d[p].fade  : '';
        out[p].delay = d[p].delay != null ? d[p].delay : '';
      }
    });
    return out;
  } catch (e) { return makeDefaults(); }
}

function saveDefaults() {
  localStorage.setItem(STORAGE_KEY_DEFAULTS, JSON.stringify(defaults));
}

function emptyPools() {
  return { groups: [], dimmer: [], position: [], gobo: [], color: [], beam: [], focus: [] };
}

function loadPools() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY_POOLS);
    if (!raw) return emptyPools();
    const p = JSON.parse(raw);
    const out = emptyPools();
    Object.keys(out).forEach(k => {
      if (Array.isArray(p[k])) {
        out[k] = p[k]
          .filter(x => x && x.name && String(x.name).trim())
          .map(x => ({ no: parseInt(x.no) || 0, name: String(x.name) }));
      }
    });
    return out;
  } catch (e) { return emptyPools(); }
}

function savePools() {
  localStorage.setItem(STORAGE_KEY_POOLS, JSON.stringify(pools));
}

function parsePoolsPaste(text) {
  if (!text) throw new Error('empty input');
  const begin = text.indexOf('CUELIST_POOLS_BEGIN');
  const end = text.indexOf('CUELIST_POOLS_END');
  let json;
  if (begin !== -1 && end !== -1 && end > begin) {
    const slice = text.substring(begin, end);
    const firstBrace = slice.indexOf('{');
    const lastBrace = slice.lastIndexOf('}');
    if (firstBrace === -1 || lastBrace === -1) throw new Error('no JSON object found between markers');
    json = slice.substring(firstBrace, lastBrace + 1);
  } else {
    const firstBrace = text.indexOf('{');
    const lastBrace = text.lastIndexOf('}');
    if (firstBrace === -1 || lastBrace === -1) throw new Error('no JSON object found');
    json = text.substring(firstBrace, lastBrace + 1);
  }
  let parsed;
  try { parsed = JSON.parse(json); }
  catch (e) { throw new Error('JSON parse failed: ' + e.message); }
  if (!parsed.pools || typeof parsed.pools !== 'object') throw new Error('missing "pools" object');
  const out = emptyPools();
  Object.keys(out).forEach(k => {
    const src = parsed.pools[k];
    if (src && Array.isArray(src.items)) {
      out[k] = src.items
        .filter(x => x && x.name && String(x.name).trim())
        .map(x => ({ no: parseInt(x.no) || 0, name: String(x.name) }));
    }
  });
  return out;
}

function cloneActions(actions) {
  return actions.map(a => {
    const presets = {};
    POOLS.forEach(p => {
      const v = a.presets[p] || {};
      presets[p] = { name: v.name || '', fade: v.fade != null ? v.fade : '', delay: v.delay != null ? v.delay : '' };
    });
    return { group: a.group || '', presets };
  });
}

function actionIsEmpty(action) {
  if (action.group && action.group.trim()) return false;
  return !POOLS.some(p => action.presets[p] && action.presets[p].name && action.presets[p].name.trim());
}

// Session-only project file path tracking (NEVER serialized into the JSON).
// Set when the user loads a project from disk or saves to a known location.
let projectFilePath = '';

function getProjectFilePath() { return projectFilePath; }
function setProjectFilePath(p) { projectFilePath = p || ''; }

// Strip "./" or ".\" prefix.
function stripDotSlash(p) {
  return p.replace(/^\.[\\/]+/, '');
}

// Heuristic absolute-path detector for both Windows and POSIX (fallback for browser).
function looksAbsolute(p) {
  if (!p) return false;
  return /^[A-Za-z]:[\\/]/.test(p) || p.startsWith('\\\\') || p.startsWith('/');
}

async function resolveAudioPath(rawPath, projectDir) {
  if (!rawPath) return '';
  // Desktop: use Node's path.resolve for correct Windows semantics.
  if (window.cuelist && window.cuelist.isAbsolutePath) {
    const abs = await window.cuelist.isAbsolutePath(rawPath);
    if (abs) return rawPath;
    if (!projectDir) return rawPath;  // can't resolve without context
    return await window.cuelist.resolvePath(projectDir, stripDotSlash(rawPath));
  }
  // Browser fallback (no fs anyway, but keep the math sensible).
  if (looksAbsolute(rawPath)) return rawPath;
  return rawPath;
}

async function applyLoadedProject(jsonText, sourceFilePath) {
  let loaded;
  try { loaded = JSON.parse(jsonText); }
  catch (err) { showToast('Invalid project file: ' + err.message, { kind: 'error', ms: 4000 }); return; }
  const isOldFormat = loaded && Array.isArray(loaded.cues);
  const isNewFormat = loaded && Array.isArray(loaded.songs);
  if (!isOldFormat && !isNewFormat) { showToast('Invalid project file: not a project', { kind: 'error', ms: 4000 }); return; }
  // Drop any cached audio from the previous project — ids may collide and files are stale.
  audioCache.forEach(entry => {
    try { entry.audioEl.pause(); } catch (e) {}
    try { URL.revokeObjectURL(entry.audioEl.src); } catch (e) {}
  });
  audioCache.clear();
  currentAudioSongId = null;
  audioEl = null; audioBuffer = null; audioGainL = null; audioGainR = null; audioFileName = '';
  // Reset autoload session sets so re-loaded songs get a fresh chance.
  if (typeof autoloadInFlight !== 'undefined') autoloadInFlight.clear();
  if (typeof autoloadMissing !== 'undefined') autoloadMissing.clear();
  state = migrateState(loaded);
  // Resolve relative audio paths against the project's directory.
  if (sourceFilePath && window.cuelist && window.cuelist.resolvePath) {
    const projectDir = await window.cuelist.resolvePath(sourceFilePath, '..');
    for (const song of state.songs) {
      if (song.audioFilePath) {
        song.audioFilePath = await resolveAudioPath(song.audioFilePath, projectDir);
      }
    }
  }
  setProjectFilePath(sourceFilePath || '');
  saveState();
  render();
  if (sourceFilePath) showToast('Loaded → ' + sourceFilePath, { kind: 'success' });
}

async function saveProject() {
  const content = JSON.stringify(state, null, 2);
  if (window.cuelist && window.cuelist.saveProjectAt) {
    // Desktop. Save in place if we know the path; else dialog.
    if (projectFilePath) {
      const res = await window.cuelist.saveProjectAt(projectFilePath, content);
      if (res && res.error) { showToast('Save failed: ' + res.error, { kind: 'error', ms: 4000 }); return; }
      showToast('Saved → ' + projectFilePath, { kind: 'success' });
      return;
    }
    const suggested = suggestedSaveName();
    const res = await window.cuelist.saveProjectAs(content, suggested);
    if (!res) return;
    if (res.error) { showToast('Save failed: ' + res.error, { kind: 'error', ms: 4000 }); return; }
    setProjectFilePath(res.path);
    showToast('Saved → ' + res.path, { kind: 'success' });
    return;
  }
  // Browser fallback (download).
  download(content, 'show.json', 'application/json');
  showToast('Project downloaded', { kind: 'success' });
}

function suggestedSaveName() {
  if (projectFilePath) {
    // basename without extension can't be derived in renderer trivially on Windows;
    // delegate via IPC. Best-effort fallback: just use 'show.json'.
    return projectFilePath;
  }
  const first = state.songs && state.songs[0];
  const slug = (first && first.name ? first.name : 'show').replace(/[^A-Za-z0-9_-]+/g, '_').slice(0, 32) || 'show';
  return slug + '.json';
}

async function loadProjectViaPicker() {
  if (window.cuelist && window.cuelist.openProject) {
    const res = await window.cuelist.openProject();
    if (!res) return;
    if (res.error) { showToast('Open failed: ' + res.error, { kind: 'error', ms: 4000 }); return; }
    await applyLoadedProject(res.content, res.path);
    return;
  }
  // Browser: trigger the hidden <input type="file">
  const input = document.getElementById('loadProject');
  if (input) input.click();
}

// Browser-only path: <input type="file"> → FileReader.
function loadProject(file) {
  const reader = new FileReader();
  reader.onload = e => { applyLoadedProject(e.target.result, ''); };
  reader.readAsText(file);
}

// Save Project + Assets: pick destination .json, create sibling _assets/ dir,
// copy each song's audio file in, write JSON with paths relative to the .json.
// In-memory state is NOT mutated to relative — only the on-disk JSON has relative paths.
async function saveProjectAsBundle() {
  if (!(window.cuelist && window.cuelist.pickBundleDir)) {
    alert('Save + Assets is only available in the desktop app.');
    return;
  }
  const suggested = suggestedSaveName();
  const pick = await window.cuelist.pickBundleDir(suggested);
  if (!pick) return;
  if (pick.error) { alert('Save failed: ' + pick.error); return; }
  const { jsonPath, assetsDir, baseName } = pick;
  const assetsDirName = baseName + '_assets';

  // Build a deep-copy of state for serialization with relative paths.
  const out = JSON.parse(JSON.stringify(state));
  const songsToCopy = [];
  for (let i = 0; i < out.songs.length; i++) {
    const song = out.songs[i];
    const src = song.audioFilePath;
    if (!src) continue;
    // Only copy absolute paths that exist on disk.
    const isAbs = await window.cuelist.isAbsolutePath(src);
    if (!isAbs) continue;
    const exists = await window.cuelist.pathExists(src);
    if (!exists) {
      console.warn('[bundle] audio missing, leaving path as-is:', src);
      continue;
    }
    // Build a unique dst filename: <NN>_<originalName>.
    const origName = song.audioFileName || ('track_' + (i + 1) + '.bin');
    const safe = origName.replace(/[^A-Za-z0-9._-]+/g, '_');
    const dstName = String(i + 1).padStart(2, '0') + '_' + safe;
    songsToCopy.push({ srcIndex: i, src, dstName });
  }

  // Execute copies.
  for (const job of songsToCopy) {
    const res = await window.cuelist.copyAudioToAssets(job.src, assetsDir, job.dstName);
    if (res && res.error) {
      alert(`Failed to copy "${job.src}":\n${res.error}\n\nAborting bundle save.`);
      return;
    }
    out.songs[job.srcIndex].audioFilePath = './' + assetsDirName + '/' + job.dstName;
  }

  // Write the JSON.
  const content = JSON.stringify(out, null, 2);
  const wr = await window.cuelist.saveProjectAt(jsonPath, content);
  if (wr && wr.error) { showToast('Write failed: ' + wr.error, { kind: 'error', ms: 4000 }); return; }
  setProjectFilePath(jsonPath);
  const audioMsg = songsToCopy.length === 0
    ? ''
    : ` (${songsToCopy.length} audio file${songsToCopy.length === 1 ? '' : 's'} copied)`;
  showToast(`Bundle saved → ${jsonPath}${audioMsg}`, { kind: 'success', ms: 3500 });
}

function parseCsv(text) {
  const rows = [];
  let row = [], field = '', inQuotes = false, i = 0;
  while (i < text.length) {
    const ch = text[i];
    if (inQuotes) {
      if (ch === '"') {
        if (text[i+1] === '"') { field += '"'; i += 2; continue; }
        inQuotes = false; i++;
      } else { field += ch; i++; }
    } else {
      if (ch === '"') { inQuotes = true; i++; }
      else if (ch === ',') { row.push(field); field = ''; i++; }
      else if (ch === '\r') { i++; }
      else if (ch === '\n') { row.push(field); rows.push(row); row = []; field = ''; i++; }
      else { field += ch; i++; }
    }
  }
  if (field.length > 0 || row.length > 0) { row.push(field); rows.push(row); }
  return rows;
}

function importCsv(file) {
  const reader = new FileReader();
  reader.onload = e => {
    try {
      const rows = parseCsv(e.target.result);
      if (rows.length < 2) throw new Error('Empty CSV');
      const header = rows[0].map(h => h.trim());
      const trackIdx = header.indexOf('Track');
      const cueNoIdx = header.indexOf('Cue No');
      const labelIdx = header.indexOf('Label');
      const posIdx = header.indexOf('Position');
      if (trackIdx < 0 || labelIdx < 0) {
        throw new Error('Missing required columns "Track" or "Label"');
      }

      const songsByTrack = new Map();
      for (let r = 1; r < rows.length; r++) {
        const row = rows[r];
        if (!row.length || row.every(c => c === '')) continue;
        const track = (row[trackIdx] || '').trim();
        const label = (row[labelIdx] || '').trim();
        if (!track || !label) continue;
        if (!songsByTrack.has(track)) songsByTrack.set(track, []);
        const cueList = songsByTrack.get(track);
        const cueN = cueNoIdx >= 0 ? parseFloat(row[cueNoIdx]) : NaN;
        const position = posIdx >= 0 ? (row[posIdx] || '').trim() : '';
        cueList.push({
          n: isNaN(cueN) ? cueList.length + 1 : cueN,
          name: label,
          actions: [newAction()],
          fade: '',
          delay: '',
          collapsed: true,
          position
        });
      }

      if (songsByTrack.size === 0) {
        alert('No valid rows (need non-empty Track and Label).');
        return;
      }

      // Prune the initial empty placeholder song if it's still pristine
      state.songs = state.songs.filter(s => (s.name && s.name.trim()) || s.cues.length > 0);

      let added = 0, totalCues = 0, lastId = null;
      songsByTrack.forEach((cues, trackName) => {
        const leadNum = trackName.match(/^(\d+)/);
        const maxSeq = state.songs.reduce((m, s) => Math.max(m, parseInt(s.sequence) || 0), 0);
        const sequence = leadNum ? parseInt(leadNum[1]) : maxSeq + 1;
        const song = {
          id: genId(),
          name: trackName,
          sequence,
          cues,
          audioFileName: '',
          audioFilePath: '',
          audioTrim: { startS: 0, endS: null },
          audioLocked: false,
          viewportZoom: 1,
          viewportOffsetS: 0,
          ltcChannel: 'auto',
          tcOffset: ''
        };
        state.songs.push(song);
        added++;
        totalCues += cues.length;
        lastId = song.id;
      });

      if (state.songs.length === 0) {
        const ns = { id: genId(), name: '', sequence: 1, cues: [], audioFileName: '', audioFilePath: '', audioTrim: { startS: 0, endS: null }, audioLocked: false, viewportZoom: 1, viewportOffsetS: 0, ltcChannel: 'auto', tcOffset: '' };
        state.songs.push(ns);
        state.activeSongId = ns.id;
      } else if (lastId) {
        state.activeSongId = lastId;
      }
      saveState();
      render();
      alert(`Imported ${added} song(s), ${totalCues} cue(s) total.`);
    } catch (err) {
      alert('CSV import failed: ' + err.message);
    }
  };
  reader.readAsText(file);
}

let state = loadState() || newProject();
let moods = loadMoods();
let defaults = loadDefaults();
let pools = loadPools();

// --- public surface
window.CC = window.CC || {};
CC.state = { newSong, newProject, activeSong, newCue, newAction, migrateActions, migrateCues, migrateState, loadState, saveState, loadMoods, saveMoods, newMood, makeDefaults, loadDefaults, saveDefaults, emptyPools, loadPools, savePools, cloneActions, actionIsEmpty, parsePoolsPaste, saveProject, loadProject, loadProjectViaPicker, saveProjectAsBundle, getProjectFilePath, setProjectFilePath, applyLoadedProject, parseCsv, importCsv, appendCueWithTcAndResort, resortAndRenumber };

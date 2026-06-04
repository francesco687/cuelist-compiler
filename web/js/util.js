// util.js — pure helpers (timecode, ids, escaping, download). Depends on: constants (FPS).

function timecodeToSeconds(tc) {
  if (!tc) return NaN;
  const parts = String(tc).split(':');
  if (parts.length !== 4) return NaN;
  const [hh, mm, ss, ff] = parts.map(Number);
  if ([hh, mm, ss, ff].some(isNaN)) return NaN;
  return hh * 3600 + mm * 60 + ss + ff / FPS;
}

function secondsToTimecode(s) {
  if (!isFinite(s) || s < 0) return '00:00:00:00';
  const hh = Math.floor(s / 3600);
  const mm = Math.floor((s % 3600) / 60);
  const ss = Math.floor(s % 60);
  const ff = Math.floor((s - Math.floor(s)) * FPS);
  return `${String(hh).padStart(2,'0')}:${String(mm).padStart(2,'0')}:${String(ss).padStart(2,'0')}:${String(ff).padStart(2,'0')}`;
}

function secondsToMMSS(s) {
  if (!isFinite(s) || s < 0) return '0:00';
  const mm = Math.floor(s / 60);
  const ss = Math.floor(s % 60);
  return `${mm}:${String(ss).padStart(2,'0')}`;
}

function genId() {
  return 's_' + Date.now().toString(36) + '_' + Math.random().toString(36).slice(2, 8);
}

function escapeHtml(s) {
  return String(s == null ? '' : s).replace(/[<>&"]/g, c => (
    { '<': '&lt;', '>': '&gt;', '&': '&amp;', '"': '&quot;' }[c]
  ));
}

function download(content, filename, mime) {
  const blob = new Blob([content], { type: mime });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  setTimeout(() => URL.revokeObjectURL(url), 0);
}

// --- public surface
window.CC = window.CC || {};
CC.util = { timecodeToSeconds, secondsToTimecode, secondsToMMSS, genId, escapeHtml, download };

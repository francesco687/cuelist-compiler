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

// Parse signed SMPTE: "-01:00:00:00", "+00:30:00:00", or unsigned "01:00:00:00".
// Empty / invalid → NaN.
function signedTimecodeToSeconds(tc) {
  if (tc == null || tc === '') return NaN;
  let s = String(tc).trim();
  let sign = 1;
  if (s[0] === '-') { sign = -1; s = s.slice(1); }
  else if (s[0] === '+') { s = s.slice(1); }
  const parts = s.split(':');
  if (parts.length !== 4) return NaN;
  const [hh, mm, ss, ff] = parts.map(Number);
  if ([hh, mm, ss, ff].some(isNaN)) return NaN;
  return sign * (hh * 3600 + mm * 60 + ss + ff / FPS);
}

// Format seconds as signed SMPTE: positive → "01:00:00:00", negative → "-01:00:00:00".
function secondsToSignedTimecode(s) {
  if (!isFinite(s)) return '00:00:00:00';
  const sign = s < 0 ? '-' : '';
  const abs = Math.abs(s);
  const hh = Math.floor(abs / 3600);
  const mm = Math.floor((abs % 3600) / 60);
  const ss = Math.floor(abs % 60);
  const ff = Math.floor((abs - Math.floor(abs)) * FPS);
  return `${sign}${String(hh).padStart(2,'0')}:${String(mm).padStart(2,'0')}:${String(ss).padStart(2,'0')}:${String(ff).padStart(2,'0')}`;
}

function secondsToMMSS(s) {
  if (!isFinite(s) || s < 0) return '0:00';
  const mm = Math.floor(s / 60);
  const ss = Math.floor(s % 60);
  return `${mm}:${String(ss).padStart(2,'0')}`;
}

function isValidSmpte(s) {
  if (typeof s !== 'string') return false;
  const m = /^(\d{2}):(\d{2}):(\d{2}):(\d{2})$/.exec(s);
  if (!m) return false;
  const [, , mm, ss, ff] = m;
  return Number(mm) < 60 && Number(ss) < 60 && Number(ff) < FPS;
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

// Lightweight toast notification. kind: 'success'|'error'|'info'. Auto-dismisses after ms.
let _toastTimer = null;
function showToast(message, opts) {
  if (typeof document === 'undefined') return; // safe in test sandbox
  const kind = (opts && opts.kind) || 'info';
  const ms = (opts && typeof opts.ms === 'number') ? opts.ms : 2500;
  let el = document.getElementById('toast');
  if (!el) {
    el = document.createElement('div');
    el.id = 'toast';
    document.body.appendChild(el);
  }
  el.className = 'toast ' + kind + ' show';
  el.textContent = message;
  if (_toastTimer) { clearTimeout(_toastTimer); _toastTimer = null; }
  _toastTimer = setTimeout(() => {
    el.classList.remove('show');
    _toastTimer = null;
  }, ms);
}

// --- public surface
window.CC = window.CC || {};
window.CC.util = { timecodeToSeconds, secondsToTimecode, secondsToMMSS, isValidSmpte, signedTimecodeToSeconds, secondsToSignedTimecode, genId, escapeHtml, download, showToast };

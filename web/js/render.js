// render.js — all DOM rendering: sidebar, cues, actions, modals, popovers, pickers. Depends on: constants, util, state, audio. Provides render().

let _colorPopoverOnPick = null;
function openColorPopover(anchorEl, current, onPick) {
  let pop = document.getElementById('colorPopover');
  if (!pop) {
    pop = document.createElement('div');
    pop.id = 'colorPopover';
    pop.className = 'hidden';
    document.body.appendChild(pop);
  }
  _colorPopoverOnPick = onPick;
  const tiles = [`<div class="color-tile no-color${!current ? ' current' : ''}" data-color="" title="No color"></div>`]
    .concat(ACTION_COLORS.map(c =>
      `<div class="color-tile${c === current ? ' current' : ''}" style="--c:${c}" data-color="${c}" title="${c}"></div>`
    ))
    .join('');
  pop.innerHTML = tiles;
  pop.classList.remove('hidden');
  const rect = anchorEl.getBoundingClientRect();
  pop.style.top = (rect.bottom + window.scrollY + 4) + 'px';
  pop.style.left = (rect.left + window.scrollX) + 'px';
  pop.querySelectorAll('.color-tile').forEach(t => {
    t.addEventListener('click', e => {
      e.stopPropagation();
      const c = t.getAttribute('data-color');
      const cb = _colorPopoverOnPick;
      closeColorPopover();
      if (cb) cb(c);
    });
  });
  setTimeout(() => {
    document.addEventListener('mousedown', colorPopoverOutsideClick);
  }, 0);
}
function closeColorPopover() {
  const pop = document.getElementById('colorPopover');
  if (pop) pop.classList.add('hidden');
  _colorPopoverOnPick = null;
  document.removeEventListener('mousedown', colorPopoverOutsideClick);
}
function colorPopoverOutsideClick(e) {
  const pop = document.getElementById('colorPopover');
  if (pop && !pop.contains(e.target)) closeColorPopover();
}

let _poolPickerState = { kind: null, current: '', onPick: null };

function openPoolPicker(kind, currentValue, onPick) {
  _poolPickerState = { kind, current: currentValue || '', onPick };
  document.getElementById('poolPickerTitle').textContent = POOL_TITLE[kind] || kind;
  const search = document.getElementById('poolPickerSearch');
  search.value = '';
  renderPoolPickerGrid('');
  document.getElementById('poolPickerModal').classList.remove('hidden');
  setTimeout(() => search.focus(), 0);
}

function closePoolPicker() {
  document.getElementById('poolPickerModal').classList.add('hidden');
  _poolPickerState = { kind: null, current: '', onPick: null };
}

function pickPoolValue(name) {
  const cb = _poolPickerState.onPick;
  closePoolPicker();
  if (cb) cb(name);
}

function renderPoolPickerGrid(filter) {
  const grid = document.getElementById('poolPickerGrid');
  const kind = _poolPickerState.kind;
  if (!kind) return;
  const items = pools[kind] || [];
  const accent = POOL_ACCENT[kind] || '#5b8dd6';
  const f = String(filter || '').trim().toLowerCase();
  const filtered = f
    ? items.filter(x =>
        String(x.name).toLowerCase().includes(f) ||
        String(x.no).includes(f))
    : items;

  if (items.length === 0) {
    grid.innerHTML = `<div class="pool-empty">No items loaded for <code>${kind}</code>.<br>Import from MA via the <b>Pools</b> button.</div>`;
    return;
  }
  if (filtered.length === 0) {
    grid.innerHTML = `<div class="pool-empty">No matches for "<code>${escapeHtml(filter)}</code>".</div>`;
    return;
  }

  const current = (_poolPickerState.current || '').trim();
  grid.innerHTML = filtered.map(x => {
    const isCurrent = current && current === String(x.name).trim();
    return `
      <div class="pool-tile${isCurrent ? ' current' : ''}" data-name="${escapeHtml(x.name)}">
        <span class="pool-tile-accent" style="background:${accent}"></span>
        <span class="pool-tile-no">${x.no}</span>
        <span>${escapeHtml(x.name)}</span>
      </div>
    `;
  }).join('');
  grid.querySelectorAll('.pool-tile').forEach(t => {
    t.addEventListener('click', () => pickPoolValue(t.getAttribute('data-name')));
  });
}

function render() {
  renderSidebar();
  const song = activeSong();

  if (currentAudioSongId !== state.activeSongId) {
    setActiveAudioFromCache(state.activeSongId);
    renderAudioPanel();
  }

  document.getElementById('songName').value = song.name || '';
  document.getElementById('sequence').value = song.sequence || 1;
  document.getElementById('storeMode').value = state.storeMode || 'Overwrite';
  if (window.syncStoreModeSegment) window.syncStoreModeSegment();
  document.getElementById('cueCount').textContent = song.cues.length
    ? `${song.cues.length} cue${song.cues.length > 1 ? 's' : ''}`
    : '';

  const container = document.getElementById('cues');
  container.innerHTML = '';

  if (song.cues.length === 0) {
    const hint = document.createElement('div');
    hint.className = 'empty-hint';
    hint.textContent = 'No cues yet. Click "+ Add Cue" below to start.';
    container.appendChild(hint);
    return;
  }

  song.cues.sort((a, b) => (parseFloat(a.n) || 0) - (parseFloat(b.n) || 0));
  song.cues.forEach((cue, ci) => container.appendChild(renderCue(song, cue, ci)));

  if (audioBuffer) renderMarkers();
}

function renderSidebar() {
  const list = document.getElementById('songList');
  list.innerHTML = '';
  state.songs.forEach(song => {
    const li = document.createElement('li');
    li.className = 'song-item' + (song.id === state.activeSongId ? ' active' : '');
    li.innerHTML = `
      <span class="song-label">${escapeHtml(song.name || '(untitled)')}</span>
      <span class="song-seq">S${escapeHtml(song.sequence)}</span>
      <button class="song-remove" title="Remove song">&times;</button>
    `;
    li.addEventListener('click', e => {
      if (e.target.classList.contains('song-remove')) return;
      state.activeSongId = song.id;
      saveState();
      render();
    });
    li.querySelector('.song-remove').addEventListener('click', e => {
      e.stopPropagation();
      const label = song.name || '(untitled)';
      const cueCount = song.cues.length;
      const msg = `Remove song "${label}"${cueCount ? ' with ' + cueCount + ' cue(s)' : ''}?`;
      if (!confirm(msg)) return;
      const idx = state.songs.findIndex(s => s.id === song.id);
      state.songs.splice(idx, 1);
      audioCache.delete(song.id);
      if (state.songs.length === 0) {
        const ns = { id: genId(), name: '', sequence: 1, cues: [], audioFileName: '' };
        state.songs.push(ns);
        state.activeSongId = ns.id;
      } else if (song.id === state.activeSongId) {
        state.activeSongId = state.songs[Math.max(0, idx - 1)].id;
      }
      saveState();
      render();
    });
    list.appendChild(li);
  });
}

function cueSummary(cue) {
  const groups = cue.actions.filter(a => a.group && a.group.trim()).length;
  const parts = [];
  if (cue.position) parts.push(cue.position);
  if (groups) parts.push(`${groups} group${groups > 1 ? 's' : ''}`);
  if (cue.fade && String(cue.fade).trim()) parts.push(`fade ${cue.fade}`);
  if (cue.delay && String(cue.delay).trim()) parts.push(`delay ${cue.delay}`);
  return parts.join(' · ');
}

function renderCue(song, cue, ci) {
  const card = document.createElement('div');
  card.className = 'cue-card' + (cue.collapsed ? ' collapsed' : '');

  const hdr = document.createElement('div');
  hdr.className = 'cue-header';
  const chev = cue.collapsed ? '▶' : '▼';
  hdr.innerHTML = `
    <button class="chevron" title="${cue.collapsed ? 'Expand' : 'Collapse'}">${chev}</button>
    <input type="number" step="0.1" class="cue-num" value="${escapeHtml(cue.n)}" title="Cue number">
    <input type="text" class="cue-name" placeholder="Cue name (Intro, Verse, Chorus...)" value="${escapeHtml(cue.name)}">
    ${cue.collapsed ? `<span class="cue-summary">${escapeHtml(cueSummary(cue))}</span>` : ''}
    <button class="icon-btn danger" title="Remove cue">&times;</button>
  `;
  hdr.querySelector('.chevron').addEventListener('click', () => {
    cue.collapsed = !cue.collapsed;
    saveState();
    render();
  });
  const numInput = hdr.querySelector('.cue-num');
  numInput.addEventListener('input', e => {
    cue.n = parseFloat(e.target.value);
    saveState();
  });
  numInput.addEventListener('change', () => {
    saveState();
    render();
  });
  hdr.querySelector('.cue-name').addEventListener('input', e => {
    cue.name = e.target.value;
    saveState();
  });
  hdr.querySelector('.icon-btn.danger').addEventListener('click', () => {
    if (confirm(`Remove cue ${cue.n}${cue.name ? ' "' + cue.name + '"' : ''}?`)) {
      song.cues.splice(ci, 1);
      saveState();
      render();
    }
  });
  card.appendChild(hdr);

  if (cue.collapsed) return card;

  const moodBar = document.createElement('div');
  moodBar.className = 'cue-mood-bar';
  const moodOpts = moods.length
    ? moods.map(m => `<option value="${escapeHtml(m.id)}">${escapeHtml(m.name || '(unnamed)')}</option>`).join('')
    : '<option value="" disabled>(no moods saved)</option>';
  const otherCues = song.cues
    .map((c, idx) => ({ c, idx }))
    .filter(x => x.idx !== ci && !actionIsEmpty(x.c.actions[0] || {}));
  const copyOpts = otherCues.length
    ? otherCues.map(({ c, idx }) =>
        `<option value="${idx}">Cue ${escapeHtml(c.n)}${c.name ? ' — ' + escapeHtml(c.name) : ''}</option>`
      ).join('')
    : '<option value="" disabled>(no other compiled cues)</option>';
  moodBar.innerHTML = `
    <label>Mood:</label>
    <select class="apply-mood">
      <option value="">— Apply mood —</option>
      ${moodOpts}
    </select>
    <select class="copy-from">
      <option value="">— Copy from cue —</option>
      ${copyOpts}
    </select>
    <button class="ghost save-as-mood" title="Save current actions as a new mood">Save as mood</button>
  `;
  moodBar.querySelector('.copy-from').addEventListener('change', e => {
    const idx = e.target.value;
    e.target.value = '';
    if (idx === '') return;
    const src = song.cues[parseInt(idx)];
    if (!src) return;
    const cloned = cloneActions(src.actions);
    if (cue.actions.length === 1 && actionIsEmpty(cue.actions[0])) {
      cue.actions = cloned;
    } else {
      if (!confirm(`This cue already has actions. Replace with values from cue ${src.n}${src.name ? ' "' + src.name + '"' : ''}?`)) return;
      cue.actions = cloned;
    }
    saveState();
    render();
  });
  moodBar.querySelector('.apply-mood').addEventListener('change', e => {
    const mid = e.target.value;
    e.target.value = '';
    if (!mid) return;
    const mood = moods.find(m => m.id === mid);
    if (!mood) return;
    const cloned = cloneActions(mood.actions);
    if (cue.actions.length === 1 && actionIsEmpty(cue.actions[0])) {
      cue.actions = cloned;
    } else {
      cue.actions.push(...cloned);
    }
    saveState();
    render();
  });
  moodBar.querySelector('.save-as-mood').addEventListener('click', () => {
    const nonEmpty = cue.actions.filter(a => !actionIsEmpty(a));
    if (nonEmpty.length === 0) {
      alert('Cue is empty — nothing to save as mood.');
      return;
    }
    const suggested = cue.name ? cue.name.trim() : '';
    const name = prompt('Mood name:', suggested);
    if (name == null) return;
    moods.push({ id: genId(), name: name.trim(), actions: cloneActions(nonEmpty) });
    saveMoods();
    render();
    alert(`Saved mood "${name.trim()}".`);
  });
  card.appendChild(moodBar);

  cue.actions.forEach((action, ai) => card.appendChild(
    renderAction(cue, action, ai, saveState, () => { saveState(); render(); })
  ));

  const addBtn = document.createElement('button');
  addBtn.className = 'ghost add-action';
  addBtn.textContent = '+ Add Group block';
  addBtn.addEventListener('click', () => {
    cue.actions.push(newAction());
    saveState();
    render();
  });
  card.appendChild(addBtn);

  const timing = document.createElement('div');
  timing.className = 'cue-timing';
  timing.innerHTML = `
    <label>Fade:</label>
    <input type="number" step="0.1" min="0" class="fade-input" value="${escapeHtml(cue.fade)}" placeholder="">
    <label>Delay:</label>
    <input type="number" step="0.1" min="0" class="delay-input" value="${escapeHtml(cue.delay)}" placeholder="">
  `;
  timing.querySelector('.fade-input').addEventListener('input', e => {
    cue.fade = e.target.value;
    saveState();
  });
  timing.querySelector('.delay-input').addEventListener('input', e => {
    cue.delay = e.target.value;
    saveState();
  });
  card.appendChild(timing);

  return card;
}

function renderAction(parent, action, ai, save, refresh) {
  const block = document.createElement('div');
  block.className = 'action-block';
  if (action.color) block.style.setProperty('--action-color', action.color);

  const groupRow = document.createElement('div');
  groupRow.className = 'group-row';
  const swatchColorAttr = action.color ? `style="--swatch-color:${action.color}"` : '';
  const swatchClass = action.color ? 'color-swatch' : 'color-swatch no-color';
  groupRow.innerHTML = `
    <button class="${swatchClass}" type="button" title="Color group block" ${swatchColorAttr}></button>
    <label>Group:</label>
    <div class="input-with-picker">
      <input type="text" class="group-name" value="${escapeHtml(action.group)}" placeholder='Group name (e.g. "Wash Side")'>
      <button class="pick-btn" type="button" title="Pick from Groups pool">&#9638;</button>
    </div>
    <button class="icon-btn danger" title="Remove group block">&times;</button>
  `;
  const groupInput = groupRow.querySelector('.group-name');
  groupInput.addEventListener('input', e => {
    action.group = e.target.value;
    save();
  });
  groupRow.querySelector('.pick-btn').addEventListener('click', () => {
    openPoolPicker('groups', action.group, (name) => {
      action.group = name;
      groupInput.value = name;
      save();
    });
  });
  const swatchBtn = groupRow.querySelector('.color-swatch');
  swatchBtn.addEventListener('click', e => {
    e.stopPropagation();
    openColorPopover(swatchBtn, action.color || '', (color) => {
      action.color = color;
      save();
      if (color) {
        block.style.setProperty('--action-color', color);
        swatchBtn.classList.remove('no-color');
        swatchBtn.style.setProperty('--swatch-color', color);
      } else {
        block.style.removeProperty('--action-color');
        swatchBtn.classList.add('no-color');
        swatchBtn.style.removeProperty('--swatch-color');
      }
    });
  });
  groupRow.querySelector('.icon-btn').addEventListener('click', () => {
    parent.actions.splice(ai, 1);
    if (parent.actions.length === 0) parent.actions.push(newAction());
    refresh();
  });
  block.appendChild(groupRow);

  const grid = document.createElement('div');
  grid.className = 'presets-grid';
  POOLS.forEach(pool => {
    const p = action.presets[pool];
    const def = defaults[pool] || { fade: '', delay: '' };
    const row = document.createElement('div');
    row.className = 'preset-row';
    row.style.setProperty('--pool-color', POOL_ACCENT[pool] || '#444');
    row.innerHTML = `
      <label title="${pool} — click to pick from pool">${POOL_ABBR[pool] || pool}</label>
      <input type="text" class="preset-name" value="${escapeHtml(p.name)}" placeholder="(none)">
      <div class="ptime">
        <input type="number" step="0.1" min="0" class="preset-fade" value="${escapeHtml(p.fade)}" placeholder="${escapeHtml(def.fade)}" title="Fade">
        <input type="number" step="0.1" min="0" class="preset-delay" value="${escapeHtml(p.delay)}" placeholder="${escapeHtml(def.delay)}" title="Delay">
      </div>
    `;
    const presetInput = row.querySelector('.preset-name');
    presetInput.addEventListener('input', e => {
      p.name = e.target.value;
      save();
    });
    row.querySelector('label').addEventListener('click', () => {
      openPoolPicker(pool, p.name, (name) => {
        p.name = name;
        presetInput.value = name;
        save();
      });
    });
    row.querySelector('.preset-fade').addEventListener('input', e => {
      p.fade = e.target.value;
      save();
    });
    row.querySelector('.preset-delay').addEventListener('input', e => {
      p.delay = e.target.value;
      save();
    });
    grid.appendChild(row);
  });
  block.appendChild(grid);

  return block;
}

function openMoodModal() {
  document.getElementById('moodModal').classList.remove('hidden');
  renderMoodModal();
}

function closeMoodModal() {
  document.getElementById('moodModal').classList.add('hidden');
  render();
}

function openDefaultsModal() {
  document.getElementById('defaultsModal').classList.remove('hidden');
  renderDefaultsModal();
}

function closeDefaultsModal() {
  document.getElementById('defaultsModal').classList.add('hidden');
  render();
}

function renderDefaultsModal() {
  const list = document.getElementById('defaultsList');
  list.innerHTML = '';

  const head = document.createElement('div');
  head.className = 'defaults-row';
  head.innerHTML = `<span></span><span class="col-head">Fade</span><span class="col-head">Delay</span>`;
  list.appendChild(head);

  POOLS.forEach(pool => {
    const d = defaults[pool];
    const row = document.createElement('div');
    row.className = 'defaults-row';
    row.innerHTML = `
      <label>${pool}</label>
      <input type="number" step="0.1" min="0" class="def-fade" value="${escapeHtml(d.fade)}" placeholder="—">
      <input type="number" step="0.1" min="0" class="def-delay" value="${escapeHtml(d.delay)}" placeholder="—">
    `;
    row.querySelector('.def-fade').addEventListener('input', e => {
      d.fade = e.target.value;
      saveDefaults();
    });
    row.querySelector('.def-delay').addEventListener('input', e => {
      d.delay = e.target.value;
      saveDefaults();
    });
    list.appendChild(row);
  });
}

function renderMoodModal() {
  const list = document.getElementById('moodList');
  list.innerHTML = '';
  if (moods.length === 0) {
    const hint = document.createElement('div');
    hint.className = 'mood-empty';
    hint.textContent = 'No moods yet. Click "+ New Mood" to create one, or use "Save as mood" inside a cue.';
    list.appendChild(hint);
    return;
  }
  moods.forEach((mood, mi) => list.appendChild(renderMoodCard(mood, mi)));
}

function renderMoodCard(mood, mi) {
  const card = document.createElement('div');
  card.className = 'mood-card';

  const hdr = document.createElement('div');
  hdr.className = 'mood-header';
  hdr.innerHTML = `
    <input type="text" class="mood-name" value="${escapeHtml(mood.name)}" placeholder="Mood name (e.g. Intimate Red Floor)">
    <button class="icon-btn danger" title="Delete mood">&times;</button>
  `;
  hdr.querySelector('.mood-name').addEventListener('input', e => {
    mood.name = e.target.value;
    saveMoods();
  });
  hdr.querySelector('.icon-btn').addEventListener('click', () => {
    if (confirm(`Delete mood "${mood.name || '(unnamed)'}"?`)) {
      moods.splice(mi, 1);
      saveMoods();
      renderMoodModal();
    }
  });
  card.appendChild(hdr);

  mood.actions.forEach((action, ai) => card.appendChild(
    renderAction(mood, action, ai, saveMoods, () => { saveMoods(); renderMoodModal(); })
  ));

  const addBtn = document.createElement('button');
  addBtn.className = 'ghost add-action';
  addBtn.textContent = '+ Add Group block';
  addBtn.addEventListener('click', () => {
    mood.actions.push(newAction());
    saveMoods();
    renderMoodModal();
  });
  card.appendChild(addBtn);

  return card;
}

function openPoolsModal() {
  document.getElementById('poolsModal').classList.remove('hidden');
  refreshPoolsStatus();
  document.getElementById('poolsPaste').value = '';
  document.getElementById('poolsPaste').focus();
}
function closePoolsModal() {
  document.getElementById('poolsModal').classList.add('hidden');
}
function refreshPoolsStatus() {
  const totals = ['groups', ...POOLS].map(k => `${k}=${pools[k].length}`).join(', ');
  const total = ['groups', ...POOLS].reduce((s, k) => s + pools[k].length, 0);
  document.getElementById('poolsStatus').textContent = total === 0
    ? 'No pools loaded yet.'
    : `Loaded ${total} items (${totals}).`;
}

// --- public surface
window.CC = window.CC || {};
CC.render = { render, renderSidebar, renderCue, renderAction, openColorPopover, openPoolPicker, openMoodModal, closeMoodModal, openDefaultsModal, closeDefaultsModal, renderMoodModal, renderDefaultsModal, openPoolsModal, closePoolsModal, refreshPoolsStatus };

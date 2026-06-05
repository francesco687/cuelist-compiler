// constants.js — shared constants. No dependencies. Load first.
'use strict';

const STORAGE_KEY = 'cuelistCompilerProject';
const STORAGE_KEY_MOODS = 'cuelistCompilerMoods';
const STORAGE_KEY_DEFAULTS = 'cuelistCompilerDefaults';
const STORAGE_KEY_POOLS = 'cuelistCompilerPools';
const POOLS = ['color', 'dimmer', 'position', 'gobo', 'beam', 'focus'];
const POOL_NUM = { dimmer: 1, position: 2, gobo: 3, color: 4, beam: 5, focus: 6 };
const FPS = 25;
const OSC_PROXY_URL = 'ws://127.0.0.1:8765';
const OSC_SEND_INTERVAL_MS = 20;

const POOL_ACCENT = {
  groups:   '#5b8dd6',
  dimmer:   '#d8d8d8',
  position: '#5fb86a',
  gobo:     '#e8a23a',
  color:    '#c44d8f',
  beam:     '#56c2d6',
  focus:    '#a574d6'
};
const POOL_TITLE = {
  groups:   'Groups',
  dimmer:   'Pool 1 — Dimmer',
  position: 'Pool 2 — Position',
  gobo:     'Pool 3 — Gobo',
  color:    'Pool 4 — Color',
  beam:     'Pool 5 — Beam',
  focus:    'Pool 6 — Focus'
};
const POOL_ABBR = {
  dimmer:   'DIM',
  position: 'POS',
  gobo:     'GOB',
  color:    'COL',
  beam:     'BEM',
  focus:    'FOC'
};
const ACTION_COLORS = [
  '#d63a3a', '#e8552d', '#e88332', '#f0a830', '#e8c83a',
  '#d8d83a', '#b8d83a', '#6fc850', '#3aa860', '#2c8470',
  '#3ac8c8', '#56b0e0', '#4a7ed6', '#3a5ad8', '#6a52d6',
  '#a050d6', '#d650b8', '#e85a8e', '#d8d8d8'
];

// --- public surface
window.CC = window.CC || {};
window.CC.constants = { POOLS, POOL_NUM, FPS, POOL_ACCENT, POOL_TITLE, POOL_ABBR, ACTION_COLORS };

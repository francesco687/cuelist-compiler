'use strict';
const { test } = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');

const html = fs.readFileSync(path.resolve(__dirname, '..', 'index.html'), 'utf8');
const css = fs.readFileSync(path.resolve(__dirname, '..', 'css', 'styles.css'), 'utf8');

// Every element ID main.js wires up. The restyle must NOT remove or rename any of these.
const REQUIRED_IDS = [
  'sidebar','songList','addSong','main','header','songName','sequence','headerActions',
  'manageMoodsBtn','manageDefaultsBtn','audioPanel','loadAudioBtn','loadAudio','collapseAll',
  'expandAll','cueCount','cues','addCue','toolbar','storeMode','oscPill','oscTargetInline',
  'sendOscCurrent','sendOscAll','sendTcOscCurrent','sendTcOscAll','export','exportAll','exportTc',
  'exportTcAll','saveProject','saveProjectBundle','loadBtn','loadProject','importCsvBtn',
  'managePoolsBtn','importCsv','clearAll','deskStatusRow','phonePill','openSettingsBtn',
  'settingsDialog','settingsForm','setMa3Host','setMa3Port','setMa3Prefix','setIntervalMs',
  'setHubEnabled','setHubPort','settingsError','saveSettingsBtn','moodModal','moodList','addMood',
  'defaultsModal','defaultsList','poolsModal','poolsPaste','poolsStatus','poolsImportBtn',
  'poolsLoadFileBtn','poolsLoadFile','poolsClearBtn','poolPickerModal','poolPickerTitle',
  'poolPickerSearch','poolPickerClear','poolPickerGrid',
];

test('restyle-guard: all wired element IDs still present in index.html', () => {
  for (const id of REQUIRED_IDS) {
    assert.ok(html.includes(`id="${id}"`), `missing id="${id}" — would break main.js wiring`);
  }
});

test('restyle-guard: :root defines the required Amber HUD tokens', () => {
  const required = [
    '--accent-start','--accent-end','--accent-solid','--accent-tint','--accent-border',
    '--capture','--capture-ink','--surface-1','--surface-2','--surface-3','--border',
    '--border-strong','--text','--text-dim','--text-faint','--ok','--warn','--danger',
    '--radius','--radius-sm','--radius-lg','--grid-line','--scanline','--font-mono',
    '--canvas-1','--canvas-2','--canvas-3',
  ];
  assert.ok(/:root\s*\{/.test(css), ':root block must exist');
  for (const tok of required) {
    assert.ok(css.includes(tok), `missing token ${tok}`);
  }
});

test('restyle-guard: stylesheet braces are balanced', () => {
  const open = (css.match(/\{/g) || []).length;
  const close = (css.match(/\}/g) || []).length;
  assert.strictEqual(open, close, `unbalanced braces: ${open} { vs ${close} }`);
});

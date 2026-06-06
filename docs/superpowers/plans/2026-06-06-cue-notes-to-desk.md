# Cue Notes → grandMA3 cue Note column — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make each cue's already-captured `notes` text appear in that cue's Note column on the grandMA3, on both the live OSC send and the exported `.lua` plugin.

**Architecture:** `web/js/compile.js` is the single source of truth the hub runs in a Node VM. Add one sanitization helper and emit `Set Sequence <seq> Cue <n> "Note" "<note>"` right after each cue's `Store`, in both `buildCmdLines()` (live OSC) and `buildLua()`/`songToLuaEntry()` (plugin). Document it in `shared/ma3-command-spec.md`. No iOS/web UI change — notes already travel in the `Project` JSON.

**Tech Stack:** Plain ES5-style JS (browser globals run via `vm`), Node's built-in test runner (`node --test`) in `hub/`.

---

## File Structure

- **Modify** `web/js/compile.js` — add `sanitizeNote()`; emit the Note line in `buildCmdLines()` and in `buildLua()`+`songToLuaEntry()`.
- **Modify** `hub/src/compile-bridge.js` — expose `buildLua` on the VM api so the plugin path is testable.
- **Modify** `hub/test/compile-bridge.test.js` — add focused tests for the live-OSC note line and the Lua note emission.
- **Modify** `shared/ma3-command-spec.md` — document the new step + Note escaping.

Notes on existing behavior (verified, do not change):
- `compile-bridge.compileShow()` runs `migrateState()` first; `migrateCues()` leaves unknown fields like `notes` untouched, so `cue.notes` survives to `buildCmdLines`.
- The `examples/SONG_1.*` golden fixtures contain **no** notes, so the existing golden tests stay green with zero fixture edits.

---

### Task 1: Sanitize + emit the Note line on the live-OSC path

**Files:**
- Modify: `web/js/compile.js` (add helper near top; edit `buildCmdLines()` ~line 126-127)
- Test: `hub/test/compile-bridge.test.js`

- [ ] **Step 1: Write the failing test**

Add to `hub/test/compile-bridge.test.js`:

```js
test('cue note emits a Set "Note" line after Store on the OSC path', () => {
  const api = createCompiler();
  const project = {
    songs: [{ id: 's1', name: 'S', sequence: 7, cues: [
      { n: 1, name: 'Q1', fade: '', delay: '',
        notes: 'tighten on the "hot" spot\nsecond line',
        actions: [{ group: 'G', presets: { color: { name: 'C', fade: '', delay: '' } } }] },
      { n: 2, name: 'Q2', fade: '', delay: '', notes: '   ',
        actions: [{ group: 'G', presets: { color: { name: 'C', fade: '', delay: '' } } }] },
    ] }],
    activeSongId: 's1', storeMode: 'Overwrite',
  };
  const lines = compileShow(api, { project, selection: 'all' });

  const noteLine = 'Set Sequence 7 Cue 1 "Note" "tighten on the \\"hot\\" spot second line"';
  const storeIdx = lines.indexOf('Store Sequence 7 Cue 1 "Q1" /Overwrite /NoConfirmation');
  const noteIdx = lines.indexOf(noteLine);
  assert.ok(storeIdx !== -1, 'store line present');
  assert.ok(noteIdx === storeIdx + 1, 'note line immediately after its Store');
  // whitespace-only note emits nothing
  assert.ok(!lines.some((l) => l.startsWith('Set Sequence 7 Cue 2 "Note"')), 'empty note emits no line');
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd hub && node --test test/compile-bridge.test.js`
Expected: FAIL — the `Set … "Note" …` line is not produced (`noteIdx === -1`).

- [ ] **Step 3: Add the `sanitizeNote` helper**

In `web/js/compile.js`, immediately after the header comment block (before `function songToLuaEntry`), add:

```js
// Collapse a free-text (often voice-captured, multi-line) note into one safe
// command-line token: newlines/tabs/runs of whitespace → single space, trimmed,
// then " escaped to \". Returns '' for null/empty/whitespace-only input.
function sanitizeNote(raw) {
  return String(raw == null ? '' : raw)
    .replace(/[\r\n\t]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .replace(/"/g, '\\"');
}
```

- [ ] **Step 4: Emit the Note line in `buildCmdLines()`**

In `web/js/compile.js`, in `buildCmdLines()`, find the cue-level fade/delay block (currently lines ~126-127):

```js
      if (cue.fade  && String(cue.fade).trim())  out.push(`Set Sequence ${seq} Cue ${cue.n} Fade ${cue.fade}`);
      if (cue.delay && String(cue.delay).trim()) out.push(`Set Sequence ${seq} Cue ${cue.n} Delay ${cue.delay}`);
```

Add a third line right after them:

```js
      const note = sanitizeNote(cue.notes);
      if (note) out.push(`Set Sequence ${seq} Cue ${cue.n} "Note" "${note}"`);
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd hub && node --test test/compile-bridge.test.js`
Expected: PASS (new test green; existing golden tests still green).

- [ ] **Step 6: Commit**

```bash
git add web/js/compile.js hub/test/compile-bridge.test.js
git commit -m "feat(compile): emit cue Note on the live-OSC path"
```

---

### Task 2: Emit the matching Note line in the exported `.lua` plugin

**Files:**
- Modify: `web/js/compile.js` (`songToLuaEntry()` ~line 30-32 and `buildLua()` main loop ~line 81-82)
- Modify: `hub/src/compile-bridge.js` (expose `buildLua`)
- Test: `hub/test/compile-bridge.test.js`

- [ ] **Step 1: Expose `buildLua` on the VM api**

In `hub/src/compile-bridge.js`, find the `globalThis.__api = { ... }` assignment and add `buildLua`:

```js
    'globalThis.__api = { buildCmdLines, buildLua, migrateState, makeDefaults,' +
    '  setState: (s) => { state = s; }, setDefaults: (d) => { defaults = d; } };',
```

- [ ] **Step 2: Write the failing test**

Add to `hub/test/compile-bridge.test.js`:

```js
test('cue note appears in the exported Lua plugin (data + emitter)', () => {
  const api = createCompiler();
  const project = {
    songs: [{ id: 's1', name: 'S', sequence: 7, cues: [
      { n: 1, name: 'Q1', fade: '', delay: '', notes: 'tighten on the "hot" spot',
        actions: [{ group: 'G', presets: { color: { name: 'C', fade: '', delay: '' } } }] },
    ] }],
    activeSongId: 's1', storeMode: 'Overwrite',
  };
  const migrated = api.migrateState(project);
  const lua = String(api.buildLua(migrated.songs, 'T'));

  // data table carries the sanitized + escaped note
  assert.ok(lua.includes('note="tighten on the \\"hot\\" spot"'), 'note in SONGS table');
  // main loop emits the Set "Note" command when c.note is present
  assert.ok(
    lua.includes('Cmd(\'Set Sequence \'..song.seq..\' Cue \'..c.n..\' "Note" "\'..c.note..\'"\')'),
    'note emitter in main loop'
  );
});
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `cd hub && node --test test/compile-bridge.test.js`
Expected: FAIL — neither the `note="…"` table entry nor the emitter line exists yet.

- [ ] **Step 4: Add the note to the Lua cue data table**

In `web/js/compile.js`, in `songToLuaEntry()`, find the cue header block (currently lines ~30-32):

```js
    let header = `    {n=${cue.n}, name="${(cue.name || '').trim().replace(/"/g, '\\"')}"`;
    if (cue.fade && String(cue.fade).trim()) header += `, fade=${cue.fade}`;
    if (cue.delay && String(cue.delay).trim()) header += `, delay=${cue.delay}`;
```

Add a line right after the `delay` line:

```js
    const note = sanitizeNote(cue.notes);
    if (note) header += `, note="${note}"`;
```

- [ ] **Step 5: Add the note emitter to `buildLua()`'s main loop**

In `web/js/compile.js`, in `buildLua()`, find the cue-level fade/delay emitter (currently lines ~81-82):

```js
  lines.push('      if c.fade  then Cmd(\'Set Sequence \'..song.seq..\' Cue \'..c.n..\' Fade \'..c.fade)   end');
  lines.push('      if c.delay then Cmd(\'Set Sequence \'..song.seq..\' Cue \'..c.n..\' Delay \'..c.delay) end');
```

Add right after them:

```js
  lines.push('      if c.note  then Cmd(\'Set Sequence \'..song.seq..\' Cue \'..c.n..\' "Note" "\'..c.note..\'"\') end');
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `cd hub && node --test test/compile-bridge.test.js`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add web/js/compile.js hub/src/compile-bridge.js hub/test/compile-bridge.test.js
git commit -m "feat(compile): emit cue Note in exported Lua plugin"
```

---

### Task 3: Document the new command in the MA3 contract

**Files:**
- Modify: `shared/ma3-command-spec.md` (numbered per-cue list ~line 43-49; String escaping ~line 62-64)

- [ ] **Step 1: Add the Note step to the per-cue sequence**

In `shared/ma3-command-spec.md`, after the cue-delay step (currently item 5, line ~49):

```
5. If the cue has a delay: `Set Sequence <seq> Cue <n> Delay <d>`
```

add:

```
6. If the cue has a non-empty note: `Set Sequence <seq> Cue <n> "Note" "<note>"`
```

- [ ] **Step 2: Document Note sanitization in the escaping section**

In the `## String escaping` section, after the existing line about names, add:

```
Cue notes are collapsed to a single line (newlines/tabs/whitespace runs → one
space), trimmed, and `"` replaced with `\"`. A note that is empty or
whitespace-only emits no command, leaving the desk's existing Note field
untouched.
```

- [ ] **Step 3: Commit**

```bash
git add shared/ma3-command-spec.md
git commit -m "docs(spec): document cue Note command + escaping"
```

---

### Task 4: Full suite + handoff

- [ ] **Step 1: Run the full hub test suite**

Run: `cd hub && npm test`
Expected: all tests pass, including the untouched `SONG_1` golden tests.

- [ ] **Step 2: Run the web transport test (sanity, unrelated but cheap)**

Run: `cd web && node --test test/transport.test.js`
Expected: PASS (no change expected here; confirms nothing regressed).

- [ ] **Step 3: Confirm `compile.js` ↔ spec parity by eye**

Open `web/js/compile.js` and `shared/ma3-command-spec.md`; confirm the per-cue order matches: ClearAll → group/preset blocks → Store → cue Fade → cue Delay → cue **Note** → (final ClearAll). Fix either file if they diverge.

---

## Verify on hardware (post-merge, next desk smoke)

`Set Sequence X Cue Y "Note" "…"` assumes the cue Note column's property keyword is `Note`. If the grandMA3 rejects it or the text lands in the wrong column, the fix is the single literal `"Note"` token in both `buildCmdLines()` and the `buildLua()` emitter (e.g. `CueNote`), plus the spec. Confirm a captured note shows in the Sequence Sheet's Note column for the right cue, and that an empty note leaves an existing Note untouched.
```

'use strict';
const { test } = require('node:test');
const assert = require('node:assert');
const path = require('node:path');
const ltc = require(path.resolve(__dirname, '..', 'js', 'ltc.js'));

// ---------------------------------------------------------------------------
// LTC signal synthesizer (for testing decoder roundtrip)
// ---------------------------------------------------------------------------
// Produces a Float32Array of biphase-mark-encoded LTC at the given sample rate
// and framerate, starting at the given SMPTE timecode, for `nFrames` frames.

function bitsForFrame(tc) {
  // SMPTE 12M-1 frame layout: 80 bits total. Build the 64 data bits + 16 sync.
  const bits = new Array(80).fill(0);
  const writeNibble = (value, start, len) => {
    for (let i = 0; i < len; i++) bits[start + i] = (value >> i) & 1;
  };
  writeNibble(tc.ff % 10, 0, 4);             // frame units
  writeNibble(Math.floor(tc.ff / 10), 8, 2); // frame tens
  writeNibble(tc.ss % 10, 16, 4);
  writeNibble(Math.floor(tc.ss / 10), 24, 3);
  writeNibble(tc.mm % 10, 32, 4);
  writeNibble(Math.floor(tc.mm / 10), 40, 3);
  writeNibble(tc.hh % 10, 48, 4);
  writeNibble(Math.floor(tc.hh / 10), 56, 2);
  // Sync word at bits 64..79 — must match decoder SYNC_PATTERN.
  for (let i = 0; i < ltc.SYNC_PATTERN.length; i++) bits[64 + i] = ltc.SYNC_PATTERN[i];
  return bits;
}

function synthLtc(startTc, nFrames, framerate, sampleRate) {
  const bitsPerFrame = 80;
  const samplesPerFrame = sampleRate / framerate;
  const samplesPerBit = samplesPerFrame / bitsPerFrame;
  const total = Math.floor(nFrames * samplesPerFrame);
  const out = new Float32Array(total);

  // Biphase mark: always transition at the start of each bit; for a "1" bit,
  // also transition in the middle. So the signal toggles every half-bit on "1",
  // every full-bit on "0".
  let polarity = 1;
  let writeIdx = 0;
  let tc = { ...startTc };
  for (let f = 0; f < nFrames; f++) {
    const bits = bitsForFrame(tc);
    for (let b = 0; b < bitsPerFrame; b++) {
      const bit = bits[b];
      // Start of bit: transition.
      polarity = -polarity;
      const startSample = Math.round(f * samplesPerFrame + b * samplesPerBit);
      const endSample = Math.round(f * samplesPerFrame + (b + 1) * samplesPerBit);
      if (bit === 0) {
        // No mid-bit transition: hold polarity for the whole bit.
        for (let s = startSample; s < endSample && s < total; s++) out[s] = polarity * 0.8;
      } else {
        // Mid-bit transition.
        const mid = Math.round(f * samplesPerFrame + (b + 0.5) * samplesPerBit);
        for (let s = startSample; s < mid && s < total; s++) out[s] = polarity * 0.8;
        polarity = -polarity;
        for (let s = mid; s < endSample && s < total; s++) out[s] = polarity * 0.8;
      }
    }
    // Advance TC by one frame.
    tc.ff++;
    if (tc.ff >= framerate) { tc.ff = 0; tc.ss++; }
    if (tc.ss >= 60) { tc.ss = 0; tc.mm++; }
    if (tc.mm >= 60) { tc.mm = 0; tc.hh++; }
    if (tc.hh >= 24) tc.hh = 0;
  }
  return { signal: out, samplesPerFrame };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test('synthLtc produces a finite signal of expected length', () => {
  const { signal } = synthLtc({ hh: 1, mm: 0, ss: 0, ff: 0 }, 10, 25, 48000);
  assert.strictEqual(signal.length, 10 * (48000 / 25));
  for (let i = 0; i < signal.length; i++) {
    assert.ok(Math.abs(signal[i]) <= 1, 'sample within [-1, 1]');
  }
});

test('decodeLtc: roundtrip 25fps starting at 01:00:00:00 over 50 frames', () => {
  const { signal } = synthLtc({ hh: 1, mm: 0, ss: 0, ff: 0 }, 50, 25, 48000);
  const res = ltc.decodeLtc(signal, 48000);
  assert.strictEqual(res.error, null);
  assert.ok(res.frames.length >= 40, `got ${res.frames.length} frames (expected ~50)`);
  assert.strictEqual(res.framerate, 25);
  // The first decoded frame should be 01:00:00:00 (allowing a small offset
  // if the decoder dropped a leading frame while it found bit-sync).
  const first = res.frames[0].tc;
  assert.strictEqual(first.hh, 1);
  assert.strictEqual(first.mm, 0);
  assert.strictEqual(first.ss, 0);
  assert.ok(first.ff <= 3, `first ff was ${first.ff}`);
});

test('decodeLtc: roundtrip 30fps starting at 00:30:15:20 over 40 frames', () => {
  const { signal } = synthLtc({ hh: 0, mm: 30, ss: 15, ff: 20 }, 40, 30, 48000);
  const res = ltc.decodeLtc(signal, 48000);
  assert.strictEqual(res.error, null);
  assert.ok(res.frames.length >= 30, `got ${res.frames.length} frames`);
  assert.strictEqual(res.framerate, 30);
  const first = res.frames[0].tc;
  assert.strictEqual(first.hh, 0);
  assert.strictEqual(first.mm, 30);
  // ss/ff may have advanced by a frame or two depending on sync acquisition.
  assert.ok(first.ss === 15 || first.ss === 16, `first ss was ${first.ss}`);
});

test('decodeLtc: returns no-signal on silence', () => {
  const silence = new Float32Array(48000 * 2);
  const res = ltc.decodeLtc(silence, 48000);
  assert.notStrictEqual(res.error, null);
  assert.strictEqual(res.frames.length, 0);
});

test('decodeLtc: returns no-signal on white noise', () => {
  const noise = new Float32Array(48000);
  for (let i = 0; i < noise.length; i++) noise[i] = (Math.random() - 0.5) * 0.05;
  const res = ltc.decodeLtc(noise, 48000);
  assert.notStrictEqual(res.error, null);
});

test('ltcAtSample: extrapolates linearly between detected frames', () => {
  const { signal } = synthLtc({ hh: 1, mm: 0, ss: 0, ff: 0 }, 30, 25, 48000);
  const res = ltc.decodeLtc(signal, 48000);
  // 1 second into the signal = sample 48000. LTC should be ~01:00:01.0xx.
  const v = ltc.ltcAtSample(res.frames, 48000, 48000);
  // 01:00:00 = 3600 seconds. So LTC at +1s = 3601 ± a small offset.
  assert.ok(Math.abs(v - 3601) < 0.05, `expected ~3601, got ${v}`);
});

test('decodeFrameBits: rejects out-of-range BCD', () => {
  // Frame tens = 4 (invalid for 25/30 fps).
  const badBits = new Array(64).fill(0);
  badBits[8] = 0; badBits[9] = 1; badBits[10] = 0;  // ft = 0b010 → but only 2 bits used → ft = 2. Make it actually invalid:
  // Set ft bits (8,9) to value 4 — but they're only 2 bits so max is 3 anyway.
  // Set hour tens to 3 → 30+ hours → invalid.
  badBits[56] = 1; badBits[57] = 1;   // ht = 3
  badBits[48] = 1;                    // hu = 1 → total = 31 hours. Invalid.
  const r = ltc._decodeFrameBits(badBits);
  assert.strictEqual(r, null);
});

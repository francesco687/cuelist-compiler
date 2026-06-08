// ltc.js — Linear Timecode (LTC) decoder.
// Reads SMPTE timecode embedded as biphase-mark-code audio on one channel.
// Pure function: takes a Float32Array channel + sample rate, returns frames.
// No DOM, no globals — testable in isolation.

(function () {
  'use strict';

  // --- Bit-level helpers --------------------------------------------------

  // Find zero crossings with hysteresis to ignore micro-noise around zero.
  // Returns an array of sample indices where the signal crosses zero.
  function findZeroCrossings(data, hysteresis) {
    const h = typeof hysteresis === 'number' ? hysteresis : 0.03;
    const out = [];
    if (!data || data.length === 0) return out;
    let state = data[0] >= 0 ? 1 : -1;     // current "side" of zero
    for (let i = 1; i < data.length; i++) {
      const v = data[i];
      if (state > 0 && v < -h) { out.push(i); state = -1; }
      else if (state < 0 && v > h) { out.push(i); state = 1; }
    }
    return out;
  }

  // Histogram-based estimation of the short (half-bit) and long (full-bit) periods.
  // LTC biphase-mark code uses two consecutive short transitions for a "1",
  // one long transition for a "0". So intervals between zero-crossings cluster
  // bimodally around T/2 (short) and T (long).
  function estimateBitPeriod(intervals) {
    if (intervals.length < 40) return null;
    // Look at the first ~2000 intervals — enough to see the distribution and
    // robust against weak signal in later parts of the file.
    const sample = intervals.slice(0, Math.min(intervals.length, 4000));
    const sorted = sample.slice().sort((a, b) => a - b);
    // Lower-quartile median is the short period; upper-quartile median is the long.
    const shortIdx = Math.floor(sorted.length * 0.25);
    const longIdx = Math.floor(sorted.length * 0.75);
    const shortPeriod = sorted[shortIdx];
    const longPeriod = sorted[longIdx];
    if (shortPeriod <= 0 || longPeriod <= 0) return null;
    // Sanity: long should be ~2x short. Allow generous tolerance.
    const ratio = longPeriod / shortPeriod;
    if (ratio < 1.4 || ratio > 2.6) return null;
    return { shortPeriod, longPeriod };
  }

  // Biphase mark decode. Given consecutive zero-crossing intervals and the
  // estimated periods, walk through and emit bits with their sample positions.
  // intervals[i] = crossings[i+1] - crossings[i].
  function biphaseDecode(intervals, crossings, periods) {
    const { shortPeriod, longPeriod } = periods;
    const threshold = (shortPeriod + longPeriod) / 2;
    const bits = [];
    const bitSample = [];        // sample index where this bit starts
    let i = 0;
    while (i < intervals.length) {
      const len = intervals[i];
      if (len >= threshold) {
        // Long → bit "0"
        bits.push(0);
        bitSample.push(crossings[i]);
        i++;
      } else {
        // Short → expect another short for bit "1"
        if (i + 1 < intervals.length && intervals[i + 1] < threshold) {
          bits.push(1);
          bitSample.push(crossings[i]);
          i += 2;
        } else {
          // Lone short — phase glitch. Skip and let next interval re-sync.
          i++;
        }
      }
    }
    return { bits, bitSample };
  }

  // --- Frame extraction ---------------------------------------------------

  // SMPTE 12M LTC sync word: 16 bits at the END of each frame.
  // Bit sequence (in transmission order, LSB-first per byte but conceptually
  // a contiguous run): `0011 1111 1111 1101`.
  // We scan the bit stream for this pattern; positions of a sync indicate the
  // last bit of one frame (= bit 79). The 64 data bits are bits 0..63 before it.
  // Pattern length = 16. We treat as MSB-first array of 0/1 in transmission order.
  const SYNC_PATTERN = [0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 1];

  function findSyncEndPositions(bits) {
    const out = [];
    const N = bits.length;
    const SL = SYNC_PATTERN.length;
    // i = index of the FIRST bit of the sync (= bit 64 of the frame).
    for (let i = 0; i + SL <= N; i++) {
      let ok = true;
      for (let k = 0; k < SL; k++) {
        if (bits[i + k] !== SYNC_PATTERN[k]) { ok = false; break; }
      }
      if (ok) out.push(i + SL - 1);   // position of the LAST bit of the sync
    }
    return out;
  }

  // Decode the 64 data bits of a frame into a SMPTE timecode { hh, mm, ss, ff }.
  // Returns null if the BCD digits are out of range.
  // Bit layout per SMPTE 12M-1 (data bits 0..63):
  //   0-3   frame units (BCD)
  //   8-9   frame tens (BCD, 2 bits = 0..3)
  //   16-19 second units (BCD)
  //   24-26 second tens (BCD, 3 bits = 0..7)
  //   32-35 minute units (BCD)
  //   40-42 minute tens (BCD, 3 bits = 0..7)
  //   48-51 hour units (BCD)
  //   56-57 hour tens (BCD, 2 bits = 0..3)
  // BCD digit bits are little-endian within their nibble (bit 0 = LSB).
  function decodeFrameBits(frameBits) {
    if (frameBits.length < 64) return null;
    const nibble = (start, len) => {
      let v = 0;
      for (let i = 0; i < len; i++) v |= (frameBits[start + i] & 1) << i;
      return v;
    };
    const fu = nibble(0, 4);
    const ft = nibble(8, 2);
    const su = nibble(16, 4);
    const st = nibble(24, 3);
    const mu = nibble(32, 4);
    const mt = nibble(40, 3);
    const hu = nibble(48, 4);
    const ht = nibble(56, 2);
    if (fu > 9 || ft > 3 || su > 9 || st > 5 || mu > 9 || mt > 5 || hu > 9 || ht > 2) return null;
    const hh = ht * 10 + hu;
    const mm = mt * 10 + mu;
    const ss = st * 10 + su;
    const ff = ft * 10 + fu;
    if (hh > 23 || mm > 59 || ss > 59 || ff > 39) return null;
    return { hh, mm, ss, ff };
  }

  // Convert a SMPTE TC + assumed framerate to seconds (ignoring drop-frame).
  function tcToSeconds(tc, framerate) {
    if (!tc || !framerate) return NaN;
    return tc.hh * 3600 + tc.mm * 60 + tc.ss + tc.ff / framerate;
  }

  // Estimate framerate from a sequence of frames. The frame number resets
  // each second, so max(ff) + 1 is the framerate (24/25/30/etc.).
  function estimateFramerate(frames) {
    let maxFf = 0;
    for (const f of frames) if (f.tc.ff > maxFf) maxFf = f.tc.ff;
    // Round up to nearest standard framerate.
    if (maxFf <= 23) return 24;
    if (maxFf <= 24) return 25;
    if (maxFf <= 29) return 30;
    return maxFf + 1;
  }

  // --- Top-level API ------------------------------------------------------

  // decodeLtc(channelData, sampleRate, opts?) →
  //   { frames: [{sample, tc:{hh,mm,ss,ff}, ltcSeconds}], framerate, error }
  // On failure, frames = [] and error is one of:
  //   'no-signal' | 'no-bit-clock' | 'no-sync' | 'no-valid-frames'
  function decodeLtc(channelData, sampleRate, opts) {
    if (!channelData || channelData.length < sampleRate / 10) {
      return { frames: [], framerate: null, error: 'no-signal' };
    }
    const hysteresis = (opts && typeof opts.hysteresis === 'number') ? opts.hysteresis : 0.03;
    const crossings = findZeroCrossings(channelData, hysteresis);
    if (crossings.length < 200) return { frames: [], framerate: null, error: 'no-signal' };

    const intervals = new Array(crossings.length - 1);
    for (let i = 0; i < intervals.length; i++) intervals[i] = crossings[i + 1] - crossings[i];

    const periods = estimateBitPeriod(intervals);
    if (!periods) return { frames: [], framerate: null, error: 'no-bit-clock' };

    const { bits, bitSample } = biphaseDecode(intervals, crossings, periods);
    if (bits.length < 80) return { frames: [], framerate: null, error: 'no-sync' };

    const syncEnds = findSyncEndPositions(bits);
    if (syncEnds.length < 2) return { frames: [], framerate: null, error: 'no-sync' };

    // Each sync ends at frame bit 79. Bits 0..63 are at positions syncEnd-79 .. syncEnd-16.
    const rawFrames = [];
    for (const e of syncEnds) {
      const frameStart = e - 79;
      if (frameStart < 0) continue;
      const fb = bits.slice(frameStart, frameStart + 64);
      const tc = decodeFrameBits(fb);
      if (!tc) continue;
      rawFrames.push({ sample: bitSample[frameStart], tc });
    }
    if (rawFrames.length < 2) return { frames: [], framerate: null, error: 'no-valid-frames' };

    const framerate = estimateFramerate(rawFrames);
    const frames = rawFrames.map(f => ({
      sample: f.sample,
      tc: f.tc,
      ltcSeconds: tcToSeconds(f.tc, framerate),
    }));
    return { frames, framerate, error: null };
  }

  // Look up the LTC seconds value at a given sample index using the frames map.
  // Uses linear extrapolation from the nearest frame (LTC advances continuously
  // at sampleRate samples per second).
  function ltcAtSample(frames, targetSample, sampleRate) {
    if (!frames || frames.length === 0 || !sampleRate) return NaN;
    // Binary search for the largest frame.sample <= targetSample.
    let lo = 0, hi = frames.length - 1, best = -1;
    while (lo <= hi) {
      const mid = (lo + hi) >> 1;
      if (frames[mid].sample <= targetSample) { best = mid; lo = mid + 1; }
      else hi = mid - 1;
    }
    if (best < 0) {
      // Before first detected frame — extrapolate backward.
      const f = frames[0];
      return f.ltcSeconds + (targetSample - f.sample) / sampleRate;
    }
    const f = frames[best];
    return f.ltcSeconds + (targetSample - f.sample) / sampleRate;
  }

  // --- Public surface -----------------------------------------------------
  const api = {
    decodeLtc,
    ltcAtSample,
    // exposed for unit tests
    _findZeroCrossings: findZeroCrossings,
    _estimateBitPeriod: estimateBitPeriod,
    _biphaseDecode: biphaseDecode,
    _findSyncEndPositions: findSyncEndPositions,
    _decodeFrameBits: decodeFrameBits,
    _estimateFramerate: estimateFramerate,
    _tcToSeconds: tcToSeconds,
    SYNC_PATTERN,
  };

  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  if (typeof window !== 'undefined') {
    window.CC = window.CC || {};
    window.CC.ltc = api;
  }
})();

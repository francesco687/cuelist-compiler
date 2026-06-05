-- Cuelist Compiler — Sequence Dumper (SPIKE PROBE)
-- Reads ONE sequence's cues and (a) prints a structural probe to the System
-- Monitor, (b) writes best-effort JSON (the pull contract) to OUT_PATH.
-- Defensive on purpose: we do not yet know the exact object-model paths — that
-- is what this spike is for. Modelled on export_pools.lua.

-- ── Config (edit for a manual run; the hub trigger overrides SEQ via user var) ──
local OUT_PATH    = "/Users/Shared/cuelist-pull/seq.json"  -- a Mac-mounted share path on the desk
local DEFAULT_SEQ = 666                                     -- target sequence number
local MAX_CUES    = 200                                     -- safety cap
local PROBE_DEPTH = 3                                       -- how deep to walk children when probing

-- ── Helpers (mirrors export_pools.lua style) ───────────────────────────────────
local function tryGet(t, key)
  if t == nil then return nil end
  local ok, v = pcall(function() return t[key] end)
  if ok then return v end
  return nil
end

local function tryCall(obj, method, ...)
  if obj == nil then return nil end
  local args = { ... }
  local ok, v = pcall(function() return obj[method](obj, table.unpack(args)) end)
  if ok then return v end
  return nil
end

local function escape(s)
  if s == nil then return "" end
  return tostring(s):gsub('\\', '\\\\'):gsub('"', '\\"')
end

-- Read the target sequence number from a user variable if set (hub trigger path),
-- else DEFAULT_SEQ. We try a few API shapes since this is unconfirmed.
local function targetSeq()
  local attempts = {
    function() return tonumber(GetVar(UserVars(), "pullseq")) end,
    function() return tonumber(GetVar(GlobalVars(), "pullseq")) end,
  }
  for _, fn in ipairs(attempts) do
    local ok, v = pcall(fn)
    if ok and v then return v end
  end
  return DEFAULT_SEQ
end

local function findDataPool()
  local R = Root()
  local sd  = tryGet(R, "ShowData")
  local dps = tryGet(sd, "DataPools")
  local dp  = tryGet(dps, "Default") or tryGet(dps, 1)
  return dp
end

local function findSequence(dp, no)
  local seqs = tryGet(dp, "Sequences")
  if seqs == nil then return nil end
  return tryGet(seqs, no) or tryGet(seqs, tostring(no))
end

-- Iterate an object's children across the API shapes MA3 might expose.
local function childrenOf(obj)
  local kids = tryCall(obj, "Children")
  if type(kids) == "table" then return kids end
  local count = tryCall(obj, "Count") or tryGet(obj, "count")
  if type(count) == "number" then
    local out = {}
    for i = 1, count do out[#out + 1] = tryGet(obj, i) end
    return out
  end
  return {}
end

-- ── Probe: print everything readable about the sequence's cues ──────────────────
local PROP_GUESSES = {
  "name", "no", "number", "index",
  "CueFade", "Fade", "fade", "CueDelay", "Delay", "delay",
  "object", "Object", "TargetObject", "Group", "group",
  "preset", "Preset", "value", "Value", "Cue",
}

local function probeObj(label, obj, depth)
  if obj == nil or depth < 0 then return end
  local line = "[probe] " .. label .. " {"
  for _, k in ipairs(PROP_GUESSES) do
    local v = tryGet(obj, k)
    if v ~= nil and type(v) ~= "table" and type(v) ~= "userdata" then
      line = line .. string.format(' %s=%q', k, tostring(v))
    end
  end
  line = line .. " }"
  Printf(line)
  if depth > 0 then
    local kids = childrenOf(obj)
    for i, kid in ipairs(kids) do
      probeObj(label .. "/" .. i, kid, depth - 1)
    end
  end
end

-- ── Best-effort structured extraction (the pull-contract shape) ─────────────────
-- These property names are GUESSES; the probe output tells us the real ones, and
-- we refine in a later iteration of this same spike.
local POOL_KEYS = { "color", "dimmer", "position", "gobo", "beam", "focus" }

local function emptyPresets()
  local parts = {}
  for _, k in ipairs(POOL_KEYS) do
    parts[#parts + 1] = string.format('"%s":{"name":"","fade":"","delay":""}', k)
  end
  return "{" .. table.concat(parts, ",") .. "}"
end

local function cueToJson(cue)
  local no    = tryGet(cue, "no") or tryGet(cue, "number") or 0
  local name  = tryGet(cue, "name") or ""
  local fade  = tryGet(cue, "CueFade") or tryGet(cue, "Fade") or ""
  local delay = tryGet(cue, "CueDelay") or tryGet(cue, "Delay") or ""
  -- Actions left empty in the probe; the probe dump shows us where group/preset
  -- live so the next iteration fills `actions` for real.
  return string.format(
    '{"no":%s,"name":"%s","fade":"%s","delay":"%s","actions":[]}',
    tostring(tonumber(no) or 0), escape(name), escape(tostring(fade)), escape(tostring(delay)))
end

-- ── Write JSON to a file, fallback to monitor ───────────────────────────────────
local function writeFile(path, text)
  local f = io.open(path, "w")
  if f == nil then return false end
  f:write(text); f:close()
  return true
end

-- ── Main ────────────────────────────────────────────────────────────────────────
return function()
  local seqNo = targetSeq()
  local dp = findDataPool()
  if dp == nil then Printf("[dump_sequence] ERROR: no DataPool"); return end
  local seq = findSequence(dp, seqNo)
  if seq == nil then
    local err = string.format('{"version":1,"sequence":%d,"cues":[],"error":"sequence %d not found"}', seqNo, seqNo)
    writeFile(OUT_PATH, err)
    Printf("[dump_sequence] sequence " .. seqNo .. " not found")
    return
  end

  Printf("=== CUELIST_PULL_PROBE_BEGIN seq=" .. seqNo .. " ===")
  probeObj("seq", seq, PROBE_DEPTH)
  Printf("=== CUELIST_PULL_PROBE_END ===")

  local cues = childrenOf(seq)
  local jsonCues = {}
  for i, cue in ipairs(cues) do
    if i > MAX_CUES then break end
    jsonCues[#jsonCues + 1] = cueToJson(cue)
  end
  local json = string.format(
    '{"version":1,"sequence":%d,"cues":[%s],"error":null}',
    seqNo, table.concat(jsonCues, ","))

  local wrote = writeFile(OUT_PATH, json)
  Printf("=== CUELIST_PULL_BEGIN ===")
  Printf(json)
  Printf("=== CUELIST_PULL_END ===")
  Printf(string.format("[dump_sequence] seq=%d cues=%d wroteFile=%s path=%s",
    seqNo, #jsonCues, tostring(wrote), OUT_PATH))
end

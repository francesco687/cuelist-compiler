-- Cuelist Compiler — List Sequences (minimal v0)
-- The simplest possible "what's in the showfile": prints every sequence's
-- number + name to the System Monitor as JSON, between markers. No file write,
-- no network share — this proves the READ before we wire any transport.
-- Modelled on export_pools.lua's defensive helper style.

local function tryGet(t, k)
  if t == nil then return nil end
  local ok, v = pcall(function() return t[k] end)
  if ok then return v end
  return nil
end

-- onPC is running on the Mac, so write to a local macOS path the hub reads directly.
-- (For a Windows onPC desk, change this to e.g. "C:/cuelist-pull/sequences.json".)
local OUT_PATH = "/Users/Shared/cuelist-pull/sequences.json"

local function escape(s)
  return tostring(s or ""):gsub('\\', '\\\\'):gsub('"', '\\"')
end

local function writeFile(path, text)
  local f = io.open(path, "w")
  if f == nil then return false end
  f:write(text); f:close()
  return true
end

-- Find the Sequences pool of the loaded showfile, tolerant of API shape.
local function findSequences()
  local R   = Root()
  local sd  = tryGet(R, "ShowData")
  local dps = tryGet(sd, "DataPools")
  local dp  = tryGet(dps, "Default") or tryGet(dps, 1)
  return tryGet(dp, "Sequences")
end

local function countOf(obj)
  local c = tryGet(obj, "Count")
  if type(c) == "number" then return c end
  local ok, v = pcall(function() return obj:Count() end)   -- Count may be a method
  if ok and type(v) == "number" then return v end
  return 0
end

return function()
  local seqs = findSequences()
  if seqs == nil then
    Printf("[list_sequences] ERROR: could not reach the Sequences pool")
    return
  end

  local n = countOf(seqs)
  local items = {}
  for i = 1, n do
    local s = tryGet(seqs, i)
    if s ~= nil then
      local no   = tryGet(s, "no") or tryGet(s, "index") or i
      local name = tryGet(s, "name") or ""
      items[#items + 1] = string.format('{"no":%s,"name":"%s"}',
        tostring(tonumber(no) or i), escape(name))
    end
  end

  local json = string.format('{"version":1,"sequences":[%s]}', table.concat(items, ","))
  local wrote = writeFile(OUT_PATH, json)

  Printf("=== CUELIST_SEQUENCES_BEGIN ===")
  Printf(json)
  Printf("=== CUELIST_SEQUENCES_END ===")
  Printf(string.format("[list_sequences] found %d sequences  wroteFile=%s  path=%s",
    #items, tostring(wrote), OUT_PATH))
end

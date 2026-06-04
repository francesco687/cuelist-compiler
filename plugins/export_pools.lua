-- Cuelist Compiler — Pool Exporter
-- Walks Groups + the 6 standard preset pools (Dimmer, Position, Gobo, Color, Beam, Focus)
-- and either (a) writes a .json file to a path the user picks, or (b) prints the JSON to
-- the System Monitor as a fallback. Either output is accepted by the compiler's
-- "Import pools" dialog (Load .json file, or Paste).

local DEFAULT_PATH = "C:\\Users\\frank\\OneDrive\\Desktop\\cuelist-compiler\\pools.json"

-- Default pool index ranges shown in the popup. You can override these for
-- a single run by editing the values in the dialog when the plugin runs.
-- Format: "from-to" (e.g. "6301-6402") or a single number "42".
local DEFAULT_RANGES = {
  groups   = "1-100",
  dimmer   = "1-30",
  position = "1-50",
  gobo     = "1-60",
  color    = "1-100",
  beam     = "1-100",
  focus    = "1-80",
}

local function escape(s)
  if s == nil then return "" end
  return tostring(s):gsub('\\', '\\\\'):gsub('"', '\\"')
end

local function tryGet(t, key)
  local ok, v = pcall(function() return t[key] end)
  if ok then return v end
  return nil
end

local function dumpPool(pool, fromIdx, toIdx)
  local items = {}
  if pool == nil then return items end
  for i = fromIdx, toIdx do
    local ok, obj = pcall(function() return pool[i] end)
    if ok and obj ~= nil then
      local nameOk, name = pcall(function() return obj.name end)
      if nameOk and name and name ~= "" then
        items[#items + 1] = string.format('{"no":%d,"name":"%s"}', i, escape(name))
      end
    end
  end
  return items
end

local function findDataPool()
  local R = Root()
  local sd = tryGet(R, "ShowData")
  if sd == nil then return nil end
  local dps = tryGet(sd, "DataPools")
  if dps == nil then return nil end
  local dp = tryGet(dps, "Default")
  if dp == nil then dp = tryGet(dps, 1) end
  return dp
end

local function findPresetPool(dp, featureGroupNum)
  local attempts = {
    function() return dp.Presets[featureGroupNum] end,
    function() return dp.PresetPool[featureGroupNum] end,
    function() return dp.PresetPools[featureGroupNum] end,
  }
  for _, fn in ipairs(attempts) do
    local ok, p = pcall(fn)
    if ok and p ~= nil then return p end
  end
  return nil
end

local function parseRange(s, fallback)
  if s == nil or s == "" then return fallback[1], fallback[2] end
  local from, to = string.match(tostring(s), "^%s*(%d+)%s*%-%s*(%d+)%s*$")
  if from and to then return tonumber(from), tonumber(to) end
  local single = string.match(tostring(s), "^%s*(%d+)%s*$")
  if single then return tonumber(single), tonumber(single) end
  return fallback[1], fallback[2]
end

local function buildJson(ranges)
  local dp = findDataPool()
  if dp == nil then
    return nil, "cannot locate DataPool", 0, ""
  end

  local poolDefs = {
    { key = "groups",   no = 0, pool = tryGet(dp, "Groups") },
    { key = "dimmer",   no = 1, pool = findPresetPool(dp, 1) },
    { key = "position", no = 2, pool = findPresetPool(dp, 2) },
    { key = "gobo",     no = 3, pool = findPresetPool(dp, 3) },
    { key = "color",    no = 4, pool = findPresetPool(dp, 4) },
    { key = "beam",     no = 5, pool = findPresetPool(dp, 5) },
    { key = "focus",    no = 6, pool = findPresetPool(dp, 6) },
  }

  local parts = { '{"version":1,"pools":{' }
  local first = true
  local total = 0
  local perPool = {}
  for _, pd in ipairs(poolDefs) do
    local from, to = 1, 50
    if ranges and ranges[pd.key] then from, to = ranges[pd.key][1], ranges[pd.key][2] end
    local items = dumpPool(pd.pool, from, to)
    if not first then parts[#parts + 1] = ',' end
    first = false
    parts[#parts + 1] = string.format('"%s":{"no":%d,"items":[%s]}', pd.key, pd.no, table.concat(items, ','))
    total = total + #items
    perPool[#perPool + 1] = string.format("%s[%d-%d]=%d", pd.key, from, to, #items)
  end
  parts[#parts + 1] = '}}'
  return table.concat(parts), nil, total, table.concat(perPool, ", ")
end

local function writeToMonitor(json, total, perPool)
  Printf("=== CUELIST_POOLS_BEGIN ===")
  Printf(json)
  Printf("=== CUELIST_POOLS_END ===")
  Printf(string.format("[export_pools] %d items (%s) printed to System Monitor.", total, perPool))
end

local function tryWriteFile(path, json)
  local f, err = io.open(path, "w")
  if not f then return false, tostring(err) end
  local ok, writeErr = pcall(function() f:write(json) end)
  f:close()
  if not ok then return false, tostring(writeErr) end
  return true, nil
end

local function askForOptions(defaultPath, defaultRanges)
  -- Try the MessageBox dialog API. If it's not available on this MA build,
  -- caller will fall through to monitor-only output.
  local ok, result = pcall(function()
    return MessageBox({
      title    = "Export Pools to JSON",
      message  = "Pool index ranges (format: from-to, e.g. 6301-6402) and save path.",
      commands = { { name = "Save",   value = 1 },
                   { name = "Monitor only", value = 2 },
                   { name = "Cancel", value = 0 } },
      -- Names are prefixed with a digit because MA sorts dialog inputs
      -- alphabetically: "0. Groups" < "1. Dimmer" < ... < "7. Path".
      inputs   = {
        { name = "0. Groups",   value = defaultRanges.groups,   maxTextLength = 30 },
        { name = "1. Dimmer",   value = defaultRanges.dimmer,   maxTextLength = 30 },
        { name = "2. Position", value = defaultRanges.position, maxTextLength = 30 },
        { name = "3. Gobo",     value = defaultRanges.gobo,     maxTextLength = 30 },
        { name = "4. Color",    value = defaultRanges.color,    maxTextLength = 30 },
        { name = "5. Beam",     value = defaultRanges.beam,     maxTextLength = 30 },
        { name = "6. Focus",    value = defaultRanges.focus,    maxTextLength = 30 },
        { name = "7. Path",     value = defaultPath,            maxTextLength = 400 },
      }
    })
  end)
  if not ok or result == nil then return nil end
  return result
end

local function rangesFromInputs(inputs, defaults)
  local function pick(key, dlt)
    local v = inputs and inputs[key]
    local from, to = parseRange(v, { 1, 50 })
    -- Fall back to defaults only if the input was completely missing.
    if v == nil then
      from, to = parseRange(dlt, { 1, 50 })
    end
    return { from, to }
  end
  return {
    groups   = pick("0. Groups",   defaults.groups),
    dimmer   = pick("1. Dimmer",   defaults.dimmer),
    position = pick("2. Position", defaults.position),
    gobo     = pick("3. Gobo",     defaults.gobo),
    color    = pick("4. Color",    defaults.color),
    beam     = pick("5. Beam",     defaults.beam),
    focus    = pick("6. Focus",    defaults.focus),
  }
end

local function main()
  -- Ask first, scan after — so the user can pick the right ranges per show.
  local dialog = askForOptions(DEFAULT_PATH, DEFAULT_RANGES)

  if dialog == nil then
    -- MessageBox unavailable on this build: scan with defaults and dump to monitor.
    local defRanges = rangesFromInputs(nil, DEFAULT_RANGES)
    local json, jsonErr, total, perPool = buildJson(defRanges)
    if json == nil then
      Printf("[export_pools] ERROR: " .. tostring(jsonErr))
      return
    end
    writeToMonitor(json, total, perPool)
    return
  end

  local pressed = dialog.result or dialog.value or 0
  if pressed == 0 then
    Printf("[export_pools] cancelled by user.")
    return
  end

  local ranges = rangesFromInputs(dialog.inputs or {}, DEFAULT_RANGES)
  local json, jsonErr, total, perPool = buildJson(ranges)
  if json == nil then
    Printf("[export_pools] ERROR: " .. tostring(jsonErr))
    pcall(function()
      MessageBox({ title="Export failed", message=tostring(jsonErr),
                   commands={ { name="OK", value=0 } } })
    end)
    return
  end

  if pressed == 2 then
    writeToMonitor(json, total, perPool)
    return
  end

  -- pressed == 1 → save to file
  local inputs = dialog.inputs or {}
  local path = inputs.Path or DEFAULT_PATH
  if path == nil or path == "" then path = DEFAULT_PATH end

  local ok, err = tryWriteFile(path, json)
  if ok then
    Printf(string.format("[export_pools] %d items saved to %s", total, path))
    pcall(function()
      MessageBox({
        title    = "Pools exported",
        message  = string.format("%d items (%s)\nsaved to:\n%s", total, perPool, path),
        commands = { { name = "OK", value = 0 } }
      })
    end)
  else
    Printf("[export_pools] file write failed: " .. tostring(err) .. "  — falling back to System Monitor.")
    writeToMonitor(json, total, perPool)
    pcall(function()
      MessageBox({
        title    = "File save failed",
        message  = "Could not write to:\n" .. path .. "\n\n" .. tostring(err) ..
                   "\n\nThe JSON has been printed to the System Monitor instead.",
        commands = { { name = "OK", value = 0 } }
      })
    end)
  end
end

return main

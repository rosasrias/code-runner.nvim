local config = require "code-runner.config"

local M = {}

-- Sobrescribible en tests (M._data_file). Por defecto persiste en data/state.
local function data_file()
  return M._data_file or (vim.fn.stdpath("data") .. "/code-runner/history.json")
end

local function load()
  local f = io.open(data_file(), "r")

  if not f then
    return {}
  end

  local raw = f:read "*a"
  f:close()
  local ok, decoded = pcall(vim.json.decode, raw)

  if not ok or type(decoded) ~= "table" then
    return {}
  end

  return decoded
end

local function save(items)
  local file = data_file()
  local dir = vim.fn.fnamemodify(file, ":h")

  if vim.fn.isdirectory(dir) == 0 then
    vim.fn.mkdir(dir, "p")
  end

  local f = io.open(file, "w")

  if f then
    f:write(vim.json.encode(items))
    f:close()
  end
end

-- Registra una ejecución. cmd repetido + mismo cwd no duplica: sube al
-- frente e incrementa count (para ver qué se ejecuta más).
function M.add(cmd, cwd, key)
  if not config.options.history.enabled then
    return
  end

  local items = load()
  cwd = cwd or ""
  local prev_count = 0

  for i, it in ipairs(items) do
    if it.cmd == cmd and (it.cwd or "") == cwd then
      prev_count = tonumber(it.count) or 1
      table.remove(items, i)
      break
    end
  end

  table.insert(items, 1, {
    cmd = cmd,
    cwd = cwd,
    key = key or "",
    count = prev_count + 1,
    ts = os.time(),
  })

  local max = config.options.history.max

  if #items > max then
    for i = #items, max + 1, -1 do
      items[i] = nil
    end
  end

  save(items)
end

-- Historial completo, del más reciente al más antiguo. Normaliza count (no
-- confiar en valores viejos del archivo).
function M.list()
  local items = load()

  for i, it in ipairs(items) do
    it.count = tonumber(it.count) or 1
    items[i] = it
  end

  return items
end

-- Vacía el historial
function M.clear()
  save({})
end

return M
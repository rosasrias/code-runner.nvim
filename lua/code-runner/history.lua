local config = require "code-runner.config"
local command = require "code-runner.command"

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

local function clone(tbl)
  if type(tbl) ~= "table" then
    return tbl
  end

  local out = {}

  for k, v in pairs(tbl) do
    out[k] = clone(v)
  end

  return out
end

-- Entrada canónica derivada de una Execution (EXEC-008, CONTRACTS §24):
--   { version=1, task_id, execution_id, status, cmd, command, cwd, key,
--     context, result, ts }
-- `cmd`/`cwd`/`key` se conservan por compat con la UI legacy
-- (`run_history` re-ejecuta `choice.cmd`). Puro, sin I/O.
-- Devuelve (entry, nil) o (nil, error).
function M.from_execution(exec, now)
  if type(exec) ~= "table" then
    return nil, "history: Execution debe ser una tabla"
  end

  if type(exec.task_id) ~= "string" or exec.task_id == "" then
    return nil, "history: Execution requiere 'task_id'"
  end

  if exec.command == nil or command.valid(exec.command) == false then
    return nil, "history: Execution requiere 'command' válido"
  end

  local ctx = exec.context
  if ctx ~= nil and type(ctx) ~= "table" then
    return nil, "history: Execution 'context' debe ser tabla o nil"
  end

  local cmd_str = command.build(exec.command) or exec.command.executable
  local cwd = exec.command.cwd or ""
  local key = (type(ctx) == "table" and ctx.filetype) or ""

  return {
    version = 1,
    task_id = exec.task_id,
    execution_id = exec.id,
    status = exec.status,
    cmd = cmd_str,
    command = clone(exec.command),
    cwd = cwd,
    key = key,
    context = clone(ctx),
    result = clone(exec.result),
    ts = now or os.time(),
  }, nil
end

local function trim(items)
  local max = config.options.history.max

  if #items > max then
    for i = #items, max + 1, -1 do
      items[i] = nil
    end
  end
end

-- Copia plana de vars (strings): el historial nunca comparte referencias con
-- el llamador (precedente EXEC-008: entradas desacopladas).
local function clone_vars(vars)
  if type(vars) ~= "table" then
    return nil
  end

  local out = {}

  for k, v in pairs(vars) do
    if type(k) == "string" and (type(v) == "string" or type(v) == "number") then
      out[k] = tostring(v)
    end
  end

  if next(out) == nil then
    return nil
  end

  return out
end

-- Registra una ejecución. cmd repetido + mismo cwd no duplica: sube al
-- frente e incrementa count (para ver qué se ejecuta más).
-- `opts` (opcional, EXEC-009 slice 2): `{ task_id, execution_id, status }`
-- con la identidad del tracking cuando el job corre como Execution. Sin
-- opts se registra legacy (sin identidad), como antes.
-- `vars` (opcional, slice 3): parámetros de invocación (`$testName`, ...)
-- necesarios para reconstruir la intención de ejecución al resolver por
-- task_id. Sin vars, la entrada solo admite replay del comando guardado.
function M.add(cmd, cwd, key, opts)
  if not config.options.history.enabled then
    return
  end

  opts = opts or {}
  local items = load()
  cwd = cwd or ""
  local prev_count = 0
  -- Si la nueva llamada no trae identidad pero la entrada existente sí,
  -- se hereda task_id/status (un relanzamiento legacy no degrada una entrada
  -- canónica). execution_id NO se hereda: identifica una invocación concreta
  -- y un id viejo sería peor que ninguno (el historial nunca lo usa en guards).
  local inherit = nil

  for i, it in ipairs(items) do
    if it.cmd == cmd and (it.cwd or "") == cwd then
      prev_count = tonumber(it.count) or 1
      inherit = it
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
    task_id = opts.task_id or (inherit and inherit.task_id) or nil,
    execution_id = opts.execution_id or nil,
    status = opts.status or (inherit and inherit.status) or nil,
    vars = clone_vars(opts.vars) or (inherit and inherit.vars) or nil,
  })

  trim(items)

  save(items)
end

-- Registra una Execution terminada o relevante (EXEC-008). Dedup por
-- (task_id + cmd + cwd): repetir la misma task sube al frente e incrementa
-- count en vez de duplicar. Legacy sin task_id sigue visible para la UI.
-- Devuelve (entry, nil) o (nil, error) sin escribir en caso de error.
function M.add_execution(exec, opts)
  if not config.options.history.enabled then
    return nil, "history deshabilitado"
  end

  opts = opts or {}
  local entry, err = M.from_execution(exec, opts.now)

  if not entry then
    return nil, err
  end

  local items = load()
  local prev_count = 0

  for i, it in ipairs(items) do
    local same_task = it.task_id ~= nil and it.task_id == entry.task_id
    local same_legacy = it.task_id == nil and it.cmd == entry.cmd

    if (same_task or same_legacy) and (it.cwd or "") == entry.cwd and it.cmd == entry.cmd then
      prev_count = tonumber(it.count) or 1
      table.remove(items, i)
      break
    end
  end

  entry.count = prev_count + 1
  table.insert(items, 1, entry)
  trim(items)
  save(items)

  return entry, nil
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
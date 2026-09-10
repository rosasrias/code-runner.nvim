-- Lifecycle Events (EXEC-007): nombres de evento por transición de Execution.
--
-- Capa pura que traduce el ciclo de vida del Execution Engine (engine.lua + la
-- snapshot que emite el `listener`, EXEC-001) a los nombres de evento públicos
-- del plugin. Paridad con la API existente `CodeRunner*` usada por los usuarios:
--
--   running   -> CodeRunnerStart
--   success   -> CodeRunnerSuccess  (+ CodeRunnerExit)
--   failed    -> CodeRunnerFailed   (+ CodeRunnerExit)
--   cancelled -> CodeRunnerCancelled(+ CodeRunnerExit)
--
-- created/starting no emiten (paridad con events.lua legacy).
--
-- Este módulo NO dispara nada (Core puro, BOUNDARIES §7). El adapter de Neovim
-- (EXEC-009) tomará el resultado de `for_transition` y hará el
-- `nvim_exec_autocmds` sobre el events.lua legacy, que sigue siendo privado.
local M = {}

-- Estado alcanzado -> evento primario (paridad con events.lua legacy).
local MAP = {
  starting = nil,
  running = "CodeRunnerStart",
  success = "CodeRunnerSuccess",
  failed = "CodeRunnerFailed",
  cancelled = "CodeRunnerCancelled",
}

-- Estados terminales que además disparan CodeRunnerExit.
local EXIT = { success = true, failed = true, cancelled = true }

-- Nombre del evento primario para un estado alcanzado (nil si no emite).
function M.event_for(status)
  return MAP[status]
end

-- True si el estado alcanzado emite también CodeRunnerExit.
function M.exits(status)
  return EXIT[status] == true
end

-- Nombres de evento (en orden de emisión) para el estado alcanzado.
function M.names(status)
  local names = {}

  local primary = MAP[status]

  if primary then
    names[#names + 1] = primary
  end

  if EXIT[status] then
    names[#names + 1] = "CodeRunnerExit"
  end

  return names
end

-- Payload canónico derivado de una Execution (paridad de campos con la API
-- pública: status/action/cwd/filetype/buf/code). `buf` no tiene equivalente de
-- Execution (la terminal la decide, EXEC-009); se omite aquí.
function M.data(exec)
  local ctx = exec.context or {}
  return {
    status = exec.status,
    action = exec.task_id,
    task_id = exec.task_id,
    command = exec.command and exec.command.executable or nil,
    cwd = ctx.cwd,
    filetype = ctx.filetype,
    code = exec.result and exec.result.code,
  }
end

-- Descriptores de evento para una snapshot de Execution (tras su transición):
--   { { name = "CodeRunnerSuccess", data = {...} },
--     { name = "CodeRunnerExit",    data = {...} } }
-- En orden de emisión. El adapter de vim (EXEC-009) los despacha.
function M.for_transition(exec)
  if not exec or not exec.status then
    return {}
  end

  local data = M.data(exec)
  local out = {}

  for _, name in ipairs(M.names(exec.status)) do
    out[#out + 1] = { name = name, data = data }
  end

  return out
end

-- Nombre de la familia de un descriptor (para tests/introspección).
function M.event_names(transitions)
  local names = {}

  for _, t in ipairs(transitions) do
    names[#names + 1] = t.name
  end

  return names
end

return M
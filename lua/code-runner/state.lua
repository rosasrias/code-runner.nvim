-- Estado central de ejecución del plugin: qué está corriendo y cómo terminó.
-- Estados: idle | running | success | failed | cancelled
--
-- API pública: state.get() (copia; nunca se muta el interno).
-- Interno (lo usa terminal.lua): state.set(status, { action, cwd, filetype, code }).
local M = {}

M.STATUSES = { "idle", "running", "success", "failed", "cancelled" }

local function fresh(status)
  return {
    status = status or "idle",
    action = nil,   -- label de la acción elegida ("Run", "Run test · TestAdd", ...)
    cwd = nil,      -- directorio del job
    filetype = nil, -- key resuelta (java, py, go, ...)
    code = nil,     -- exit code (success/failed)
    started_at = nil,
    ended_at = nil,
    run_id = 0,     -- generación: identifica el job actual (crece en cada run)
  }
end

local current = fresh()

-- Cambia el estado. `running` crea un registro fresco (información del nuevo
-- job) e incrementa run_id: así un on_exit asíncrono de un job anterior nunca
-- pisa el estado del job actual. Los estados finales conservan acción/cwd/
-- filetype/run_id del job que terminó y guardan info.code. Devuelve false si
-- el status no es válido (no-op).
function M.set(status, info)
  if not vim.tbl_contains(M.STATUSES, status) then
    return false
  end

  info = info or {}

  if status == "running" then
    local next_run = (current.run_id or 0) + 1
    current = fresh "running"
    current.action = info.action
    current.cwd = info.cwd
    current.filetype = info.filetype
    current.started_at = os.time()
    current.run_id = next_run
    return true
  end

  current.status = status
  current.ended_at = os.time()

  if info.code ~= nil then
    current.code = info.code
  end

  return true
end

-- Copia del estado actual (los consumidores no deben mutar el interno).
function M.get()
  return vim.deepcopy(current)
end

return M
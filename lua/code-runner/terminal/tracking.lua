-- Tracking de Execution sobre el job real de la terminal (EXEC-009).
--
-- La terminal consume el Engine y lanza por el puerto `process` (adapter PTY,
-- slice 5). Todo es best-effort: si el comando no normaliza (p.ej. chain
-- `&&`), el tracking se omite y el path legacy (state/quickfix/buffer)
-- sigue mandando.
--
-- Este módulo es el único dueño de `current_exec`; `terminal.lua` solo delega.
-- No registra historial al salir: el registro vive al lanzar
-- (`init.execute_action → history.add` con identidad desde slice 2);
-- registrar también al salir contaría doble.
--
-- Core-adapters: depende de engine/task/execution/result_handler/
-- lifecycle_events (contratos Core), nunca de buffer/UI/quickfix.
local engine = require "code-runner.engine"
local task = require "code-runner.task"
local execution = require "code-runner.execution"
local result_handler = require "code-runner.result_handler"
local lifecycle_events = require "code-runner.lifecycle_events"

local M = {}

local current = nil
local last_events = {}
local last_skip = nil

-- Inicia el seguimiento de un job real. Devuelve el exec_id o nil si el
-- comando no pudo modelarse como Execution (se sigue con legacy; ver
-- `skip_reason()` — el fallback es explícito y observable, nunca un error
-- de ejecución ni una Execution a medio inicializar).
-- Cada llamada crea una Execution NUEVA (id fresco): la identidad de la
-- tarea (`task_id`, estable por key+label) nunca se confunde con la
-- identidad de la invocación (`id`, única por lanzamiento). Si había una
-- Execution running anterior (reemplazo), se cancela primero: ninguna queda
-- colgada en running.
function M.start(cmd, entry_key, label)
  local tid = task.id(entry_key or "", label or "")

  if tid == "" then
    tid = "misc.run"
  end

  local created, cerr = engine.create { task_id = tid, context = { filetype = entry_key }, command = cmd }

  if not created then
    last_skip = { reason = "command-no-normaliza", detail = tostring(cerr), cmd = type(cmd) == "string" and cmd or nil }
    return nil
  end

  local started = engine.start(created)
  local running = started and engine.running(started) or nil

  if not running then
    last_skip = { reason = "lifecycle-no-avanza", cmd = type(cmd) == "string" and cmd or nil }
    return nil
  end

  -- Reemplazo: la anterior deja de ser la actual y se cierra como cancelled
  -- para que nunca quede una Execution running huérfana en seguimiento.
  if current ~= nil and current.status == "running" then
    local prev = engine.cancel(current)

    if prev then
      local ok, events = pcall(lifecycle_events.for_transition, prev)

      if ok then
        last_events = events
      end
    end
  end

  current = running
  last_events = {}
  last_skip = nil

  return running.id
end

-- Finaliza la Execution en seguimiento con el exit code del job.
-- Solo acepta el `expected` del job actual: un on_exit tardío de un job
-- reemplazado se ignora (criterio 4). Devuelve la Execution finalizada o nil.
function M.finish(code, expected)
  if expected == nil or current == nil then
    return nil
  end

  if not execution.matches(current, expected) or current.status ~= "running" then
    return nil
  end

  local done = result_handler.complete(current, { code = code, expected = expected })

  if done then
    current = done
    local ok, events = pcall(lifecycle_events.for_transition, done)

    if ok then
      last_events = events
    end
  end

  return done
end

-- Cancela la Execution en seguimiento (cierre por el usuario). Best-effort.
function M.cancel()
  if current == nil or current.status ~= "running" then
    return nil
  end

  local done = engine.cancel(current)

  if done then
    current = done
    local ok, events = pcall(lifecycle_events.for_transition, done)

    if ok then
      last_events = events
    end
  end

  return done
end

-- Marca una Execution fallida de lanzamiento (termopen == -1). Best-effort.
function M.fail_launch(expected)
  if expected == nil or current == nil then
    return nil
  end

  if not execution.matches(current, expected) or current.status ~= "running" then
    return nil
  end

  local done = result_handler.complete(current, { code = -1, expected = expected })

  if done then
    current = done
    local ok, events = pcall(lifecycle_events.for_transition, done)

    if ok then
      last_events = events
    end
  end

  return done
end

-- Execution en seguimiento (copia) o nil.
function M.get()
  if current == nil then
    return nil
  end

  return vim.deepcopy(current)
end

-- Descriptores de evento del último finish/cancel (introspección/tests).
function M.events()
  return vim.deepcopy(last_events)
end

-- Despacha los descriptores del último finish/cancel como autocmds `User`
-- (slice 4: el Engine es la única fuente de eventos). Respeta
-- `config.events.enabled` y aísla cada autocmd con pcall: un listener de
-- usuario que lanza nunca rompe el path de salida. Devuelve cuántos disparó.
-- El llamador espeja el estado legacy con `state.set(..., { emit = false })`
-- para no duplicar: una sola emisión por transición.
function M.dispatch()
  local config = require "code-runner.config"

  if not config.options.events.enabled then
    return 0
  end

  local n = 0

  for _, e in ipairs(last_events) do
    pcall(vim.api.nvim_exec_autocmds, "User", {
      pattern = e.name,
      modeline = false,
      data = e.data,
    })
    n = n + 1
  end

  return n
end

-- Limpia el seguimiento (tests).
function M.reset()
  current = nil
  last_events = {}
  last_skip = nil
end

-- Motivo del último fallback a legacy (nil si el último start trackeó).
-- Forma: `{ reason = "command-no-normaliza"|"lifecycle-no-avanza",
-- detail?, cmd? }`. Solo introspección/tests: nunca es error de ejecución.
function M.skip_reason()
  return last_skip and vim.deepcopy(last_skip) or nil
end

return M

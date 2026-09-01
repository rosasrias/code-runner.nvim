-- Workflow: tasks con varios pasos secuenciales (P3). Es un engine mínimo,
-- deliberadamente sin scheduler: corre una lista de comandos en orden, cada
-- uno en "headless" (captura el exit code sin abrir terminal a la vista) y con
-- stop-si-falla opcional.
--
-- Una task se registra con steps (lista de comandos a sustituir) y es distinta
-- de una acción del picker (registry): no aparece en build_run, se invoca por
-- nombre con require("code-runner").run_task("nombre") o :CodeRunTask.
--
-- Núcleo: `execute(spec, run_step)` es síncrono y testeable (run_step inyectado).
-- `run(name)` es la envoltura async real basada en jobstart.
local shell = require "code-runner.shell"

local M = {}

local tasks = {}

-- register{ name, steps = { "cmd1", "cmd2" }, stop_on_fail = true|false, cwd, key }
--   name          obligatorio, único (re-registrar el mismo reemplaza).
--   steps         lista NO vacía de comandos (se sustituyen con shell.substitute).
--   stop_on_fail  true (default): detener en el primer paso con exit != 0.
--   cwd           directorio de trabajo de los pasos (raíz del proyecto).
--   key           para resolver $project en substitute.
function M.register(spec)
  assert(type(spec) == "table", "workflow.register: se espera una tabla")
  assert(type(spec.name) == "string" and spec.name ~= "", "workflow.register: falta 'name'")
  assert(type(spec.steps) == "table" and #spec.steps > 0, "workflow.register: 'steps' no puede estar vacío")

  spec.stop_on_fail = spec.stop_on_fail ~= false
  tasks[spec.name] = spec
  return true
end

-- Lista de tasks registradas (name -> spec).
function M.list()
  return tasks
end

-- Núcleo síncrono: corre cada paso llamando a `run_step(cmd, cwd)` que devuelve
-- el exit code (siempre síncrono; para tests o wrappers). Con stop_on_fail se
-- detiene en el primer error. Devuelve { ok, results = { { cmd, code } } }.
function M.execute(spec, run_step)
  local results = {}
  local ok = true

  for i, step in ipairs(spec.steps) do
    local cmd = shell.substitute(step, nil, spec.key)
    local code = run_step(cmd, spec.cwd)
    results[i] = { cmd = cmd, code = code }

    if code ~= 0 then
      ok = false

      if spec.stop_on_fail then
        break
      end
    end
  end

  return { ok = ok, results = results }
end

-- Ejecuta un paso con jobstart (headless, sin buffer de terminal) y llama a
-- on_exit(code) al terminar. Devuelve el job id (para tests con jobwait).
function M.run_step(cmd, cwd, on_exit)
  local opts = { on_exit = function(_, code)
    on_exit(code)
  end }

  if cwd and cwd ~= "" then
    opts.cwd = cwd
  end

  return vim.fn.jobstart(shell.wrap_command(cmd), opts)
end

-- Corre una task por nombre (async) encadenando los pasos vía jobstart.
-- on_done(result) se llama al terminar (o al fallar con stop_on_fail).
-- Devuelve false si la task no existe.
function M.run(name, on_done)
  local spec = tasks[name]

  if not spec then
    return false
  end

  local idx = 1
  local results = {}

  local function done(ok)
    if on_done then
      on_done({ ok = ok, results = results })
    end
  end

  local function next_step()
    if idx > #spec.steps then
      local all_ok = true

      for _, r in ipairs(results) do
        if r.code ~= 0 then
          all_ok = false
          break
        end
      end

      done(all_ok)
      return
    end

    local step = spec.steps[idx]
    local cmd = shell.substitute(step, nil, spec.key)

    M.run_step(cmd, spec.cwd, function(code)
      results[idx] = { cmd = cmd, code = code }

      if code ~= 0 and spec.stop_on_fail then
        done(false)
        return
      end

      idx = idx + 1
      next_step()
    end)
  end

  next_step()
  return true
end

-- Limpia las tasks (tests / recarga).
function M.reset()
  tasks = {}
end

return M

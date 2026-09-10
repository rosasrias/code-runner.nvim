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

-- register{ name, steps = { "cmd1", "cmd2" }, stop_on_fail = true|false,
--           parallel = true|N, cwd, key }
--   name          obligatorio, único (re-registrar el mismo reemplaza).
--   steps         lista NO vacía de comandos (se sustituyen con shell.substitute).
--   stop_on_fail  true (default): detener en el primer paso con exit != 0.
--   parallel      false (default): secuencial.  true: todos en paralelo.
--                 N (number > 0): máximo N pasos concurrentes.
--   cwd           directorio de trabajo de los pasos (raíz del proyecto).
--   key           para resolver $project en substitute.
function M.register(spec)
  assert(type(spec) == "table", "workflow.register: se espera una tabla")
  assert(type(spec.name) == "string" and spec.name ~= "", "workflow.register: falta 'name'")
  assert(type(spec.steps) == "table" and #spec.steps > 0, "workflow.register: 'steps' no puede estar vacío")

  spec.stop_on_fail = spec.stop_on_fail ~= false

  if spec.parallel == true then
    spec.parallel = #spec.steps
  elseif type(spec.parallel) == "number" and spec.parallel > 0 then
    spec.parallel = math.floor(spec.parallel)
  else
    spec.parallel = false
  end

  tasks[spec.name] = spec
  return true
end

-- Lista de tasks registradas (name -> spec).
function M.list()
  return tasks
end

-- Ejecuta un paso individual: sustituye variables y llama a run_step.
-- Devuelve { cmd, code }.
local function run_single(spec, run_step, idx)
  local cmd = shell.substitute(spec.steps[idx], nil, spec.key)
  local code = run_step(cmd, spec.cwd)
  return { cmd = cmd, code = code }
end

-- Núcleo síncrono: corre cada paso llamando a `run_step(cmd, cwd)` que devuelve
-- el exit code (siempre síncrono; para tests o wrappers).
-- Si spec.parallel está seteado, lanza todos los pasos en paralelo
-- (simulado: el run_step inyectado se llama en orden, pero se comporta como
-- si fueran concurrentes — para tests reales usa `run()` con jobstart).
-- Con stop_on_fail se detiene en el primer error. Devuelve { ok, results }.
function M.execute(spec, run_step)
  if spec.parallel then
    return M.execute_parallel(spec, run_step)
  end

  local results = {}
  local ok = true

  for i, step in ipairs(spec.steps) do
    local r = run_single(spec, run_step, i)
    results[i] = r

    if r.code ~= 0 then
      ok = false

      if spec.stop_on_fail then
        break
      end
    end
  end

  return { ok = ok, results = results }
end

-- Núcleo síncrono para tareas paralelas: ejecuta todos los pasos usando
-- run_step inyectado y espera a que terminen todos antes de evaluar.
-- Con stop_on_fail, si algún paso falla, se reporta al final (no interrumpe
-- los demás porque ya están corriendo).
function M.execute_parallel(spec, run_step)
  local n = #spec.steps
  local pending = n
  local results = {}
  local any_failed = false

  for i = 1, n do
    vim.schedule(function()
      local r = run_single(spec, run_step, i)
      results[i] = r

      if r.code ~= 0 then
        any_failed = true
      end

      pending = pending - 1
    end)
  end

  -- Espera a que todos los pasos terminen (bloquea el test runner).
  vim.wait(n * 5000, function()
    return pending == 0
  end, 50)

  local ok = not any_failed

  if not ok and spec.stop_on_fail then
    -- En paralelo con stop_on_fail: reportamos los pasos que fallaron.
    -- Todos los pasos ya corrieron (estaban lanzados); simplemente marcamos
    -- ok = false. Los pasos posteriores al primer fallo en el orden original
    -- pudieron lanzarse antes de que el primero terminara — eso es correcto
    -- en ejecución paralela (no hay "orden" estricto).
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
-- Si spec.parallel está seteado, lanza los pasos en paralelo con concurrencia
-- acotada. on_done(result) se llama al terminar. Devuelve false si no existe.
function M.run(name, on_done)
  local spec = tasks[name]

  if not spec then
    return false
  end

  if spec.parallel then
    return M.run_parallel(spec, on_done)
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

-- Ejecuta los pasos de una task en paralelo con concurrencia acotada.
-- Lanza hasta `limit` jobs simultáneos; cuando uno termina lanza el siguiente
-- (si quedan y stop_on_fail no ha detenido el lanzamiento). on_done(result).
function M.run_parallel(spec, on_done)
  local n = #spec.steps
  local limit = spec.parallel
  local results = {}
  local launched = 0
  local finished = 0
  local stop_launching = false

  local function done(ok)
    if on_done then
      on_done({ ok = ok, results = results })
    end
  end

  local function try_launch()

    while launched < n and launched - finished < limit do
      if stop_launching then
        return
      end

      local i = launched + 1
      launched = i

      local step = spec.steps[i]
      local cmd = shell.substitute(step, nil, spec.key)

      M.run_step(cmd, spec.cwd, function(code)
        results[i] = { cmd = cmd, code = code }
        finished = finished + 1

        if code ~= 0 and spec.stop_on_fail then
          stop_launching = true
        end

        if finished == n then
          local all_ok = true

          for _, r in ipairs(results) do
            if r.code ~= 0 then
              all_ok = false
              break
            end
          end

          done(all_ok)
        else
          try_launch()
        end
      end)
    end
  end

  try_launch()
  return true
end

-- Limpia las tasks (tests / recarga).
function M.reset()
  tasks = {}
end

return M

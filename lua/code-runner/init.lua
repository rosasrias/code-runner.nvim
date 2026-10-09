local config = require("code-runner.config")

local M = {}

local last_choice = nil

-- Pone la última elección y la persiste (para :CodeRunLast en la próxima
-- sesión). También la usamos como cache en memoria.
local function remember_choice(entry)
	last_choice = entry
	require("code-runner.last").set(entry)
end

M.setup = function(opts)
	config.setup(opts)

	-- Recuperamos la última ejecución persistida al cargar (solo si no hay
	-- una en memoria, que tendría prioridad).
	if not last_choice then
		last_choice = require("code-runner.last").get()
	end

	require("code-runner.highlight").setup()
	require("code-runner.terminal")._hook_exitmsg()
end

local function autosave()
	if not config.options.autosave then
		return
	end

	if vim.bo.buftype == "" and vim.bo.modified then
		pcall(vim.cmd, "silent write")
	end
end

local function execute_action(action, vars, cwd, key, label)
	local shell = require("code-runner.shell")
	local terminal = require("code-runner.terminal")

	if type(action) == "function" then
		local ok, err = pcall(action)
		if not ok then
			terminal.notify(err, vim.log.levels.ERROR)
		end
		return nil
	end

	local cmd = shell.substitute(action, vars, key)
	local exec_id = terminal.open(cmd, nil, cwd, label)
	-- Identidad (EXEC-009 slice 2): el open devuelve el exec_id que trackeó.
	-- Se usa el id devuelto (no el global) para no leer tracking obsoleto
	-- cuando open está stubbeado o el comando no normalizó.
	local exec = terminal.get_execution()

	if exec == nil or exec.id ~= exec_id then
		exec = nil
	end

	local idopts = nil

	if exec ~= nil and exec.task_id ~= nil then
		idopts = { task_id = exec.task_id, execution_id = exec.id, status = exec.status, vars = vars }
	end

	require("code-runner.history").add(cmd, cwd, key, idopts)

	return exec
end

-- Variables de contexto disponibles para cualquier acción (y task): derivadas
-- del cctx detectado. Permiten que una task use $testName / $entry / $entryLine
-- aunque no sea la acción contextual de test.
--   cctx: { test = { name }, entry = { name, line, fqcn } } (o nil)
local function context_vars(cctx)
	local vars = {}

	if cctx and cctx.test and cctx.test.name then
		vars["$testName"] = cctx.test.name
	end

	if cctx and cctx.entry then
		vars["$entry"] = cctx.entry.fqcn or cctx.entry.name

		if cctx.entry.line then
			vars["$entryLine"] = tostring(cctx.entry.line)
		end
	end

	return vars
end

-- Directorio de trabajo para ejecutar: raíz del proyecto si se detecta
local function project_cwd(key)
	if not config.options.project.enabled then
		return nil
	end

	return require("code-runner.project").resolve(key)
end

local function build_entry(actions, terminal)
	-- Busca acciones por extensión; si no hay, por filetype (ej: Makefile)
	local key = vim.fn.expand("%:e")

	if key == "" or not actions[key] then
		local ft = vim.bo.filetype
		if ft ~= "" and actions[ft] then
			key = ft
		end
	end

	local entry = actions[key]

	if not entry then
		terminal.notify(
			"Tipo de archivo no soportado: ." .. (key == "" and "(sin extensión)" or key),
			vim.log.levels.WARN
		)
		return nil, nil
	end

	return entry, key
end

function M.build_run()
	autosave()

	if vim.bo.buftype ~= "" then
		return
	end

	local actions = require("code-runner.actions")
	local picker = require("code-runner.picker")
	local terminal = require("code-runner.terminal")
	local context = require("code-runner.context")

	-- Carga `.code-runner.lua` del proyecto (tasks) ANTES de construir el
	-- catálogo, para que sus acciones estén disponibles en el picker.
	local rc_key = vim.fn.expand("%:e")
	if rc_key == "" then
		rc_key = vim.bo.filetype
	end
	require("code-runner.projectrc").load(rc_key)

	local entry, key = build_entry(actions.get_actions(), terminal)

	if not entry then
		return
	end

	local cctx = context.detect(key)
	local test_item = context.decorate(entry, key, cctx)
	local cwd = project_cwd(key)

	-- Título contextual: "⚡ CodeRunner · App.java" (+ · main:nn si hay entry)
	local fname = vim.fn.expand("%:t")

	if fname == "" then
		fname = vim.fn.expand("%:e") ~= "" and ("." .. vim.fn.expand("%:e")) or "sin archivo"
	end

	local title = config.options.picker.title .. " · " .. fname

	if cctx.entry and cctx.entry.line then
		title = title .. (" · main:%d"):format(cctx.entry.line)
	end

	picker.select(entry.__order, {
		prompt = config.options.picker.title,
		title = title,
	}, function(choice)
		if not choice then
			return
		end

		local vars = context_vars(cctx)

		last_choice = {
			lang = key,
			choice = choice,
			test = vars["$testName"],
			cmd = test_item and choice == test_item.label and test_item.cmd or nil,
			cwd = cwd,
			vars = vars,
		}

		remember_choice(last_choice)
		local exec = execute_action(entry[choice], vars, cwd, key, choice)

		-- Identidad (slice 2): si el job corre como Execution, last lleva su
		-- task_id. `run_last` sigue re-ejecutando el comando (comportamiento
		-- intacto); la resolución por task_id es slice 3.
		if exec ~= nil and exec.task_id ~= nil then
			last_choice.task_id = exec.task_id
			remember_choice(last_choice)
		end
	end)
end

-- Resuelve una identidad persistida a su definición vigente.
-- `vars_or_nil`/`test_or_nil` aportan el $testName para reconstruir la acción
-- contextual de test. Devuelve def o nil (fallback legacy explícito).
local function resolve_stored(task_id, lang, vars_or_nil, test_or_nil)
	local test_name = (vars_or_nil or {})["$testName"] or test_or_nil
	local ok, mod = pcall(require, "code-runner.task_resolve")

	if not ok then
		return nil
	end

	local def = mod.resolve(task_id, { lang = lang, test_name = test_name })

	return def
end

-- Repite la última acción ejecutada sin abrir el selector
--
-- Slice 3: si hay task_id, se resuelve la definición VIGENTE y se
-- re-sustituye su plantilla con los parámetros persistidos (`vars`): la
-- plantilla puede haber evolucionado desde el lanzamiento guardado. Si la
-- tarea ya no se resuelve (motivo explícito en `task_resolve`), fallback
-- legacy: replay del comando guardado. Nunca falla duro.
function M.run_last()
	autosave()

	local terminal = require("code-runner.terminal")

	if not last_choice then
		terminal.notify("No hay una ejecución anterior", vim.log.levels.WARN)
		return
	end

	if last_choice.task_id ~= nil then
		local def = resolve_stored(last_choice.task_id, last_choice.lang, last_choice.vars, last_choice.test)

		if def ~= nil then
			execute_action(
				def.template,
				last_choice.vars or { ["$testName"] = last_choice.test },
				last_choice.cwd,
				last_choice.lang,
				def.label
			)
			return
		end
	end
	-- Repetición fiel de un "Run test": el comando quedó guardado con su contexto
	if last_choice.cmd then
		local exec = execute_action(
			last_choice.cmd,
			last_choice.vars or { ["$testName"] = last_choice.test },
			last_choice.cwd,
			last_choice.lang,
			last_choice.choice
		)

		if last_choice.task_id == nil and exec ~= nil and exec.task_id ~= nil then
			last_choice.task_id = exec.task_id
			remember_choice(last_choice)
		end
		return
	end

	local entry = require("code-runner.actions").get_actions()[last_choice.lang]
	local action = entry and entry[last_choice.choice]

	if not action then
		terminal.notify("La acción anterior ya no está disponible", vim.log.levels.WARN)
		return
	end

	local exec = execute_action(action, last_choice.vars, last_choice.cwd, last_choice.lang, last_choice.choice)

	if last_choice.task_id == nil and exec ~= nil and exec.task_id ~= nil then
		last_choice.task_id = exec.task_id
		remember_choice(last_choice)
	end
end

-- Selector del historial: re-ejecuta una entrada guardada
function M.run_history()
	local terminal = require("code-runner.terminal")
	local picker = require("code-runner.picker")

	local history = require("code-runner.history")
	local items = history.list()

	if #items == 0 then
		terminal.notify("El historial está vacío", vim.log.levels.WARN)
		return
	end

	picker.select(items, {
		prompt = config.options.picker.title,
		title = "Historial",
		format_item = function(it)
			local cwd = it.cwd ~= "" and ("  (en " .. it.cwd .. ")") or ""
			return ("%dx %s%s"):format(it.count or 1, it.cmd, cwd)
		end,
	}, function(choice)
		if not choice then
			return
		end

		last_choice = {
			lang = choice.key,
			choice = nil,
			test = nil,
			cmd = choice.cmd,
			cwd = choice.cwd,
			vars = choice.vars,
			-- La entrada ya puede traer identidad (slice 2 / EXEC-008).
			task_id = choice.task_id,
		}

		remember_choice(last_choice)

		-- Slice 3: con identidad + parámetros persistidos se resuelve la
		-- plantilla vigente. Sin task_id, sin vars o sin resolución,
		-- fallback legacy explícito: replay del comando guardado (siempre
		-- persistido como compat). El status registrado nunca decide: el
		-- historial no es autoridad sobre el estado vivo (invariante 3).
		if choice.task_id ~= nil and choice.vars ~= nil then
			local def = resolve_stored(choice.task_id, choice.key, choice.vars, nil)

			if def ~= nil then
				execute_action(def.template, choice.vars, choice.cwd, choice.key, def.label)
				return
			end
		end

		local exec = execute_action(choice.cmd, nil, choice.cwd, choice.key)

		-- Si el historial no traía identidad, toma la del tracking nuevo.
		-- Nunca degrada una existente (label nil deriva solo la key).
		if last_choice.task_id == nil and exec ~= nil and exec.task_id ~= nil then
			last_choice.task_id = exec.task_id
			remember_choice(last_choice)
		end
	end)
end

-- Expuesto para tests
M._build_entry = build_entry
M._project_cwd = project_cwd
M._context_vars = context_vars

-- Ejecuta una task de workflow registrada (`.code-runner.lua` con `steps` o
-- register_task()): corre sus pasos en secuencia (headless) y notifica el
-- resultado por etapa. `name` es el nombre de la task.
function M.run_task(name)
	local workflow = require("code-runner.workflow")
	local terminal = require("code-runner.terminal")

	if not workflow.list()[name] then
		terminal.notify("No existe la task de workflow: " .. tostring(name), vim.log.levels.ERROR)
		return
	end

	local started = os.time()

	workflow.run(name, function(result)
		local failed = 0

		for _, r in ipairs(result.results) do
			if r.code ~= 0 then
				failed = failed + 1
			end
		end

		local secs = os.time() - started

		if result.ok then
			terminal.notify(
				("Task '%s' OK — %d paso(s) · %ds"):format(name, #result.results, secs),
				vim.log.levels.INFO
			)
			return
		end

		terminal.notify(
			("Task '%s' falló — %d error(es) en %d paso(s) · %ds"):format(name, failed, #result.results, secs),
			vim.log.levels.ERROR
		)
	end)
end

-- Detiene SOLO el job del plugin en marcha (el buffer registrado en el
-- estado). Cerrar/eliminar ese buffer también mata el job de terminal.
-- Cualquier otra terminal/proceso del usuario queda intacta.
function M.stop()
	M._stop_silent()
end

-- Como stop(), sin notificar: para :CodeRunRestart, que re-ejecuta y no
-- quiere el aviso intermedio de "cancelado". Expuesto para tests.
function M._stop_silent()
	local terminal = require("code-runner.terminal")
	local state = require("code-runner.state")
	local s = state.get()

	if s.status ~= "running" then
		return
	end

	local buf = s.buf

	if buf and vim.api.nvim_buf_is_valid(buf) then
		terminal._close_current(buf)
		return
	end

	-- job registrado pero su buffer ya no existe: no hay nada que matar
	state.set("cancelled")
end

-- Detiene la ejecución en marcha (si la hay) y repite la última acción.
function M.restart()
	M._stop_silent()
	M.run_last()
end

-- Estado de la ejecución actual/última del plugin (copia inmutable):
-- { status = "idle|running|success|failed|cancelled", action, cwd,
--   filetype, buf, code, started_at, ended_at }
function M.state()
	return require("code-runner.state").get()
end

-- Abre el selector para ejecutar una acción del archivo actual (alias de
-- build_run, que es la función usada por :CodeRun).
M.run = M.build_run

-- Detecta el contexto del archivo actual (o del key dado): orientado a
-- integraciones. Devuelve cctx { key, test, entry }.
--   key (opcional): extensión; por default se infiere del buffer actual.
function M.context(key)
	key = key or vim.fn.expand("%:e")
	if key == "" then
		key = vim.bo.filetype
	end
	return require("code-runner.context").detect(key)
end

-- Registra una acción programática para uno o varios lenguajes (P1).
--   register_action{
--     id = "mytool", filetypes = {"py"}, kind = "run", command = "mytool %"
--   }
--   kind: run|build|test|misc (icono del label). command o run (función).
--   Sobrescribir el mismo id reemplaza; `disable=true` elimina el lenguaje.
function M.register_action(spec)
	return require("code-runner.actions.registry").register(spec)
end

-- Desregistra una acción registrada con register_action().
function M.unregister_action(id)
	require("code-runner.actions.registry").unregister(id)
end

-- Lista las acciones del registry (id -> spec).
function M.list_registered_actions()
	return require("code-runner.actions.registry").list()
end

return M

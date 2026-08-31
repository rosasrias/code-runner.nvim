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
		return
	end

	local cmd = shell.substitute(action, vars, key)
	terminal.open(cmd, nil, cwd, label)
	require("code-runner.history").add(cmd, cwd, key)
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

		last_choice = {
			lang = key,
			choice = choice,
			test = test_item and cctx.test.name,
			cmd = test_item and choice == test_item.label and test_item.cmd or nil,
			cwd = cwd,
		}

		remember_choice(last_choice)
		execute_action(entry[choice], { ["$testName"] = last_choice.test }, cwd, key, choice)
	end)
end

-- Repite la última acción ejecutada sin abrir el selector
function M.run_last()
	autosave()

	local terminal = require("code-runner.terminal")

	if not last_choice then
		terminal.notify("No hay una ejecución anterior", vim.log.levels.WARN)
		return
	end

	-- Repetición fiel de un "Run test": el comando quedó guardado con su contexto
	if last_choice.cmd then
		execute_action(last_choice.cmd, { ["$testName"] = last_choice.test }, last_choice.cwd, last_choice.lang, last_choice.choice)
		return
	end

	local entry = require("code-runner.actions").get_actions()[last_choice.lang]
	local action = entry and entry[last_choice.choice]

	if not action then
		terminal.notify("La acción anterior ya no está disponible", vim.log.levels.WARN)
		return
	end

	execute_action(action, nil, last_choice.cwd, last_choice.lang, last_choice.choice)
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
		}

		remember_choice(last_choice)
		execute_action(choice.cmd, nil, choice.cwd, choice.key)
	end)
end

-- Expuesto para tests
M._build_entry = build_entry
M._project_cwd = project_cwd

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

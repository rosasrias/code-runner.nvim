local config = require("code-runner.config")

local M = {}

local last_choice = nil

M.setup = function(opts)
	config.setup(opts)
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

		execute_action(choice.cmd, nil, choice.cwd, choice.key)
	end)
end

-- Expuesto para tests
M._build_entry = build_entry
M._project_cwd = project_cwd

return M

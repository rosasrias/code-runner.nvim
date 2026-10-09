local picker = require "code-runner.picker"
local config = require "code-runner.config"

T.section("picker: fallback vim.ui.select")

T.it("ui='select' delega en vim.ui.select con items y prompt", function()
  config.setup { ui = "select" }

  local captured_items, captured_prompt, user_cb
  local original = vim.ui.select
  vim.ui.select = function(items, opts, cb)
    captured_items = items
    captured_prompt = opts.prompt
    user_cb = cb
  end

  local chosen
  picker.select({ "a", "b" }, { prompt = "Prueba" }, function(choice)
    chosen = choice
  end)

  vim.ui.select = original

  T.eq(2, #captured_items)
  T.eq("Prueba", captured_prompt)

  -- simula la elección del usuario
  user_cb "b"
  T.eq("b", chosen)
end)

T.it("format_item se respeta", function()
  config.setup { ui = "select" }

  local seen
  local original = vim.ui.select
  vim.ui.select = function(_, opts)
    seen = opts.format_item "x"
  end

  picker.select({ "x" }, { format_item = function(it)
    return "[" .. it .. "]"
  end }, function() end)

  vim.ui.select = original
  T.eq("[x]", seen)
end)

T.it("lista vacía llama on_choice(nil) sin abrir nada", function()
  config.setup { ui = "select" }

  local opened = false
  local original = vim.ui.select
  vim.ui.select = function()
    opened = true
  end

  local got_nil = false
  picker.select({}, {}, function(choice)
    got_nil = choice == nil
  end)

  vim.ui.select = original
  T.falsy(opened, "no debe invocar ui.select")
  T.truthy(got_nil)
end)

T.section("picker: items no-string (historial)")

T.it("_display formatea items tabela con format_item", function()
  local out = picker._display({ cmd = "go test ./..." }, function(it)
    return it.cmd .. "  (en C:/p)"
  end)

  T.eq("go test ./...  (en C:/p)", out)
end)

T.it("_display pasa strings sin format_item intactas", function()
  T.eq("hola", picker._display("hola", nil))
end)

T.it("el ancho del picker no se rompe con items en tabla (nvim_strwidth)", function()
  -- reproduce el bug: nvim_strwidth(item) con item = tabla
  local display = picker._display({ cmd = "pytest -q" }, function(it)
    return it.cmd
  end)

  T.truthy(vim.api.nvim_strwidth(display) >= #"pytest -q")
end)

T.section("picker: ventana volt")

local has_volt = vim.fn.isdirectory(vim.fn.stdpath "data" .. "/lazy/volt") == 1

if has_volt then
  T.it("abre ventana flotante con título contextual", function()
    config.setup { ui = "volt" }

    picker.select({ "run", "build" }, { title = "CodeRunner · test.lua" }, function() end)

    local found_title = nil
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local cfg = vim.api.nvim_win_get_config(win)
      if cfg.relative ~= "" and cfg.title then
        local title = vim.inspect(cfg.title) -- tolera string o segmentos {texto, hl}
        if title:find("CodeRunner · test.lua", 1, true) then
          found_title = title
          break
        end
      end
    end

    T.truthy(found_title, "debe existir una ventana con el título contextual")

    -- limpieza: cerrar floats de volt
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local buf = vim.api.nvim_win_get_buf(win)
      if vim.bo[buf].filetype == "VoltWindow" then
        pcall(vim.api.nvim_win_close, win, true)
      end
    end
    vim.schedule(function() end)
    vim.wait(50)
  end)

  T.it("acepta items en tabla (historial) con format_item", function()
    config.setup { ui = "volt" }

    -- reproducción del bug: el cálculo de ancho llamaba nvim_strwidth(item)
    -- con item = tabla y solo el render usaba format_item
    picker.select({
      { cmd = "pytest -q", cwd = "C:/p" },
      { cmd = "go test ./...", cwd = "C:/proj" },
    }, {
      format_item = function(it)
        return it.cmd .. "  (en " .. it.cwd .. ")"
      end,
    }, function() end)

    -- si llegó aquí sin error, el picker calculó ancho y colores con el label
    T.truthy(true)

    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local buf = vim.api.nvim_win_get_buf(win)
      if vim.bo[buf].filetype == "VoltWindow" then
        pcall(vim.api.nvim_win_close, win, true)
      end
    end
    vim.schedule(function() end)
    vim.wait(50)
  end)

  T.it("el ancho incluye el titulo: no se trunca con items cortos", function()
    config.setup { ui = "volt" }

    local long_title = "CodeRunner - un-nombre-de-archivo-muy-largo.py"
    picker.select({ "a" }, { title = long_title }, function() end)

    local win_w = nil
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local cfg = vim.api.nvim_win_get_config(win)
      if cfg.relative ~= "" and cfg.title then
        if vim.inspect(cfg.title):find("un-nombre-de-archivo-muy-largo", 1, true) then
          win_w = cfg.width
          break
        end
      end
    end

    T.truthy(win_w, "ventana del picker encontrada")
    T.truthy(win_w >= vim.api.nvim_strwidth(long_title), "el titulo cabe en la ventana")

    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local buf = vim.api.nvim_win_get_buf(win)
      if vim.bo[buf].filetype == "VoltWindow" then
        pcall(vim.api.nvim_win_close, win, true)
      end
    end
    vim.schedule(function() end)
    vim.wait(50)
  end)
else
  T.skip("ventana volt", "volt no está disponible")
end

config.options = vim.deepcopy(config.defaults)

local config = require "code-runner.config"

local M = {}

local function fallback(items, opts, on_choice)
  vim.ui.select(items, {
    prompt = opts.prompt,
    format_item = opts.format_item,
  }, on_choice)
end

local function volt_pick(items, opts, on_choice, volt)
  local api = vim.api
  local events_ok, events = pcall(require, "volt.events")

  if not events_ok then
    return fallback(items, opts, on_choice)
  end

  local buf = api.nvim_create_buf(false, true)
  local ns = api.nvim_create_namespace "CodeRunnerPicker"
  local selected = 1
  local closed = false
  local confirm
  local close

  ---------------------------------------------------------
  -- Dimensiones
  ---------------------------------------------------------
  local content_w = api.nvim_strwidth(opts.prompt or "")

  for _, item in ipairs(items) do
    content_w = math.max(content_w, api.nvim_strwidth(item))
  end

  local width = math.min(content_w + 12, vim.o.columns - 4)
  local height = math.min(#items + 3, vim.o.lines - 6)

  if height < #items + 3 then
    -- Demasiados items para la pantalla: usar el selector nativo
    return fallback(items, opts, on_choice)
  end

  local hl_sel = opts.hl_selected or config.options.picker.hl_selected
  local hl_hint = opts.hl_hint or config.options.picker.hl_hint

  local icons = config.options.icons
  local hl_run = config.options.picker.hl_run
  local hl_build = config.options.picker.hl_build
  local hl_misc = config.options.picker.hl_misc

  -- Color según el tipo de acción (por su icono)
  local function item_hl(label)
    if icons.run ~= "" and label:find(icons.run, 1, true) then
      return hl_run
    end
    if icons.build ~= "" and label:find(icons.build, 1, true) then
      return hl_build
    end
    return hl_misc
  end

  ---------------------------------------------------------
  -- Layout volt
  ---------------------------------------------------------
  local function padded(text, target_w)
    local pad = target_w - api.nvim_strwidth(text)
    return pad > 0 and (text .. string.rep(" ", pad)) or text
  end

  local inner_w = width - 4

  local layout = {
    {
      name = "list",
      lines = function()
        local lines = {}

        for i, item in ipairs(items) do
          local sel = i == selected
          local label = (sel and "▸ " or "  ") .. (opts.format_item and opts.format_item(item) or item)

          table.insert(lines, {
            {
              padded(label, inner_w),
              sel and hl_sel or item_hl(item),
              {
                click = function()
                  if not closed then
                    confirm(i)
                  end
                end,
              },
            },
          })
        end

        table.insert(lines, {})
        table.insert(lines, { { padded(" j/k · número · <CR> · q", inner_w), hl_hint } })

        return lines
      end,
    },
  }

  volt.gen_data { { buf = buf, xpad = 2, layout = layout, ns = ns } }
  volt.mappings { bufs = { buf }, winclosed_event = true }
  events.add(buf)

  ---------------------------------------------------------
  -- Confirmar / cerrar
  ---------------------------------------------------------
  close = function()
    if closed then
      return
    end
    closed = true

    local win = vim.fn.bufwinid(buf)
    if win ~= -1 then
      pcall(api.nvim_win_close, win, true)
    end

    if api.nvim_buf_is_valid(buf) then
      pcall(api.nvim_buf_delete, buf, { force = true })
    end
  end

  confirm = function(i)
    local choice = items[i]
    close()

    if choice then
      vim.schedule(function()
        on_choice(choice)
      end)
    end
  end

  -- Si la ventana se cierra por otra vía (:q, q de volt, etc.)
  api.nvim_create_autocmd("WinClosed", {
    buffer = buf,
    callback = function()
      vim.schedule(function()
        if not closed then
          closed = true
          if api.nvim_buf_is_valid(buf) then
            pcall(api.nvim_buf_delete, buf, { force = true })
          end
        end
      end)
    end,
  })

  ---------------------------------------------------------
  -- Keymaps de navegación
  ---------------------------------------------------------
  local function move(d)
    selected = ((selected - 1 + d) % #items) + 1
    volt.redraw(buf, "list")
  end

  local function map(lhs, rhs)
    vim.keymap.set("n", lhs, rhs, { buffer = buf, silent = true, nowait = true })
  end

  map("j", function()
    move(1)
  end)
  map("<Down>", function()
    move(1)
  end)
  map("k", function()
    move(-1)
  end)
  map("<Up>", function()
    move(-1)
  end)
  map("<CR>", function()
    confirm(selected)
  end)

  for i = 1, math.min(9, #items) do
    map(tostring(i), function()
      confirm(i)
    end)
  end

  ---------------------------------------------------------
  -- Render y ventana centrada
  ---------------------------------------------------------
  volt.run(buf, { h = height, w = width })

  local title = opts.title or "CodeRunner"

  api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    border = "rounded",
    title = "  " .. title .. " ",
    title_pos = "center",
    style = "minimal",
    zindex = 60,
  })
end

function M.select(items, opts, on_choice)
  opts = opts or {}

  if #items == 0 then
    on_choice(nil)
    return
  end

  local mode = config.options.ui

  if mode == "select" then
    return fallback(items, opts, on_choice)
  end

  local ok, volt = pcall(require, "volt")

  if mode == "volt" and not ok then
    vim.notify("[code-runner] ui='volt' pero nvzone/volt no está disponible, usando vim.ui.select", vim.log.levels.WARN)
  end

  if not ok then
    return fallback(items, opts, on_choice)
  end

  volt_pick(items, opts, on_choice, volt)
end

return M

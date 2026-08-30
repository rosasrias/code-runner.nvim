-- Parsea la salida de build/test y la vuelca a la lista quickfix para
-- navegar a los errores desde el compilador.
local config = require "code-runner.config"

local M = {}

local ANSI = "\27%[[%d;]*m"

-- El orden importa (el primero que encaje gana):
--   1/2. Maven/javac: [ERROR] path:[line,col]
--   3.   MSVC: path(line,col) : error CODE: msg
--   4.   gcc/clang/rustc/go: path:line:col: msg
--   5.   camino:line: msg (sin columna)
--   6.   go test: "--- FAIL: TestX"
local RULES = {
  { pattern = "^%[ERROR%]%s+(.-):%[(%d+),%s*(%d+)%]%s*(.*)$" },
  { pattern = "^%[ERROR%]%s+(.-):%[(%d+)%]%s*(.*)$" },
  {
    pattern = "^(.-)%((%d+),(%d+)%)%s*:%s*(.-)%s*:%s*(.*)$",
    msvc = true,
  },
  { pattern = "^(.-):(%d+):(%d+)%s*:%s*(.*)$" },
  { pattern = "^(.-):(%d+)%s*:%s*(.*)$" },
  { pattern = "^%-%-%-%s*(FAIL:%s*.*)$", fail = true },
}

-- Normaliza el nombre de archivo del error. Los relativos se resuelven
-- contra el cwd del job (raíz del proyecto), no contra el cwd de nvim.
function M.normalize(fname, cwd)
  fname = fname:gsub("^%s+", ""):gsub("^%.[/\\]", "")

  local is_abs = fname:match "^%a:[/\\]" or fname:sub(1, 1) == "/" or fname:sub(1, 1) == "\\"

  if not is_abs and cwd and cwd ~= "" then
    fname = cwd .. "/" .. fname
  end

  return vim.fn.fnamemodify(fname, ":p")
end

-- Convierte líneas de salida bruta en entradas de quickfix.
function M.parse(lines, cwd)
  local out = {}

  for _, raw in ipairs(lines) do
    local line = raw:gsub(ANSI, "")

    for _, rule in ipairs(RULES) do
      local g = { line:match(rule.pattern) }

      if g[1] then
        local entry = { type = "E" }

        if rule.fail then
          entry.text = g[1]
        elseif rule.msvc then
          entry.filename = M.normalize(g[1], cwd)
          entry.lnum = tonumber(g[2])
          entry.col = tonumber(g[3])
          entry.text = (g[4] ~= "" and (g[4] .. ": ") or "") .. g[5]
        else
          entry.filename = M.normalize(g[1], cwd)
          entry.lnum = tonumber(g[2])

          if #g == 4 then
            entry.col = tonumber(g[3])
            entry.text = g[4]
          else
            entry.text = g[3]
          end
        end

        if entry.text and entry.text:lower():find "warning" then
          entry.type = "W"
        end

        table.insert(out, entry)
        break
      end
    end
  end

  return out
end

-- Lee el buffer de terminal, parsea y llena la lista quickfix.
function M.handle(buf, code, cwd)
  if not config.options.quickfix.enabled then
    return
  end

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local entries = M.parse(lines, cwd)

  if #entries == 0 then
    return
  end

  vim.fn.setqflist(entries, "r")

  local cfg = config.options.quickfix

  if cfg.open and code ~= 0 then
    pcall(vim.cmd, "silent copen " .. cfg.height)
    vim.cmd "wincmd p"
  end

  vim.notify(
    ("%d problema(s) encontrados, ver la lista quickfix (:cl / :cn)"):format(#entries),
    vim.log.levels.WARN,
    { title = "code-runner.nvim" }
  )
end

-- Expuesto para tests
M._rules = RULES

return M
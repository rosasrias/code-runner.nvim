-- Parsea la salida de build/test y la vuelca a la lista quickfix para
-- navegar a los errores desde el compilador (o a vim.diagnostic si está
-- configurado `quickfix.style = "diagnostic"`/`"both"`).
local config = require "code-runner.config"
local diagnostics = require "code-runner.diagnostics"

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
  { pattern = '^%s*File%s+"([^"]+)",%s+line%s+(%d+)(.*)$' },
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

-- Lee el buffer de terminal, parsea y llena el canal de errores configurado
-- (quickfix y/o diagnostic). Devuelve cuántas entradas quedaron
-- (0 = nada parseable), que es lo que usa el hint de la terminal.
function M.handle(buf, code, cwd)
  if not config.options.quickfix.enabled then
    return 0
  end

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local entries = M.parse(lines, cwd)
  local count = #entries
  local cfg = config.options.quickfix

  local use_qf = cfg.style ~= "diagnostic"
  local use_diag = cfg.style == "diagnostic" or cfg.style == "both"

  -- Canal diagnostic (solo o en paralelo): se actualiza siempre, tanto en
  -- éxit como en error; se limpia solo al terminar con código 0.
  if use_diag then
    diagnostics.handle(entries, code)
  end

  -- Éxito: los errores ya se corrigieron, la lista anterior es basura.
  if code == 0 then
    if use_qf then
      if count == 0 and cfg.close_on_success then
        pcall(vim.cmd, "silent cclose")
        vim.fn.setqflist({}, "r")
      elseif count > 0 then
        -- El éxito con warnings: refresca la lista pero no fuerza a abrir.
        vim.fn.setqflist(entries, "r")
      end
    end

    return 0
  end

  if count == 0 then
    return 0
  end

  if use_qf then
    vim.fn.setqflist(entries, "r")

    if cfg.open then
      pcall(vim.cmd, "silent copen " .. cfg.height)
      vim.cmd "wincmd p"
    end
  end

  local canal = use_qf and (use_diag and "quickfix y vim.diagnostic" or "lista quickfix") or "vim.diagnostic"
  vim.notify(
    ("%d problema(s) encontrados, ver %s (:cl / :cn)"):format(count, canal),
    vim.log.levels.WARN,
    { title = "code-runner.nvim" }
  )

  return count
end

-- Expuesto para tests
M._rules = RULES

return M
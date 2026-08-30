-- Compatibilidad con shell (Windows PowerShell / POSIX bash)
local M = {}

M.IS_WIN = vim.fn.has "win32" == 1

-- EXE_SUFFIX / BIN_PREFIX responden al IS_WIN actual (los tests lo someten a
-- prueba con valores simulados), no al valor de carga del módulo.
local PLATFORM = {
  [true] = { suffix = ".exe", prefix = ".\\" },
  [false] = { suffix = "", prefix = "./" },
}

setmetatable(M, {
  __index = function(_, key)
    if key == "EXE_SUFFIX" then
      return PLATFORM[M.IS_WIN].suffix
    elseif key == "BIN_PREFIX" then
      return PLATFORM[M.IS_WIN].prefix
    end
    return nil
  end,
})

-- PowerShell evalúa rutas entre comillas como strings (las imprime);
-- necesita el operador & para ejecutarlas. Bash no.
function M.quoted_run(path)
  return M.IS_WIN and ("& " .. '"' .. path .. '"') or ('"' .. path .. '"')
end

local SUBSTITUTIONS = {
  ["$filePath"] = function()
    return vim.fn.expand "%:p"
  end,
  ["$fileBase"] = function()
    return vim.fn.expand "%:r"
  end,
  ["$dir"] = function()
    return vim.fn.expand "%:p:h"
  end,
  ["$altFile"] = function()
    return vim.fn.expand "#"
  end,
  ["$file"] = function()
    return vim.fn.expand "%"
  end,
  ["$stem"] = function()
    return vim.fn.expand "%:t:r"
  end,
}

-- Invocación correcta del binario de $fileBase en cualquier plataforma y
-- tanto con rutas relativas como absolutas ($fileBase puede ser absoluta
-- si el buffer está fuera del cwd).
function M.bin_run()
  local base = vim.fn.expand "%:r"
  local target = base .. M.EXE_SUFFIX

  -- ¿ruta absoluta? (C:/..., C:\... o /unix)
  local is_abs = base:match "^%a:[/\\]" or base:sub(1, 1) == "/"
  local prefix = (not is_abs) and M.BIN_PREFIX or ""

  return M.quoted_run(prefix .. target)
end

SUBSTITUTIONS["$binRun"] = function()
  return M.bin_run()
end

-- % y tokens $var en una sola pasada; los desconocidos se dejan intactos.
-- vars permite inyectar valores por token (ej: { ["$testName"] = "TestFoo" }).
-- key (opcional) se usa para resolver $project con los marcadores del lenguaje.
function M.substitute(cmd, vars, key)
  vars = vars or {}

  local out = cmd:gsub("%%l", tostring(vim.api.nvim_win_get_cursor(0)[1]))
  out = out:gsub("%%", SUBSTITUTIONS["$file"]())

  return (out:gsub("%$%w+", function(token)
    if token == "$project" then
      return require("code-runner.project").resolve(key)
    end

    local expand_fn = SUBSTITUTIONS[token]

    if expand_fn then
      return expand_fn()
    end

    local val = vars[token]

    return val ~= nil and tostring(val) or token
  end))
end

function M.wrap_command(cmd)
  if M.IS_WIN then
    if cmd:find("&&", 1, true) then
      local parts = vim.split(cmd, "&&", { plain = true })
      local chained = vim.trim(parts[#parts])

      for i = #parts - 1, 1, -1 do
        chained = string.format("%s; if ($?) { %s }", vim.trim(parts[i]), chained)
      end

      cmd = chained
    end

    return {
      "powershell",
      "-NoLogo",
      "-NoProfile",
      "-ExecutionPolicy",
      "Bypass",
      "-Command",
      cmd,
    }
  end

  return { "bash", "-lc", cmd }
end

return M

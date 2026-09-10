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
    return vim.fn.expand "%:p:r"
  end,
  ["$dir"] = function()
    return vim.fn.expand "%:p:h"
  end,
  ["$altFile"] = function()
    return vim.fn.expand "#"
  end,
  ["$file"] = function()
    return vim.fn.expand "%:p"
  end,
  ["$stem"] = function()
    return vim.fn.expand "%:t:r"
  end,
}

-- Invocación correcta del binario de $fileBase en cualquier plataforma y
-- tanto con rutas relativas como absolutas ($fileBase puede ser absoluta
-- si el buffer está fuera del cwd). Siempre absoluto para que el cwd del
-- proyecto (project.resolve) no rompa rutas relativas tipo 01_data_types/main.c
-- cuando nvim se abre desde una carpeta padre (Windows).
function M.bin_run()
  local base = vim.fn.expand "%:p:r"
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
  -- % siempre absoluto: evita cc1.exe: ...\01_data_types\main.c: No such file
  -- cuando el buffer se abrió relativo (01_data_types\main.c) pero el job
  -- corre con cwd = file_dir() (C:\...\01_data_types) via project.resolve.
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

-- Divide por el operador `&&` SOLO cuando está fuera de comillas. vim.split
-- naive corta también un `&&` literal dentro de "..." o '...' (p.ej. el
-- argumento de un comando), rompiendo la reescritura para PowerShell.
-- Devuelve la lista de trozos (sin los separadores).
local function split_and_outside_quotes(cmd)
  local parts = {}
  local buf = {}
  local quote = nil -- nil | "'" | '"'
  local i = 1
  local n = #cmd

  local function flush()
    table.insert(parts, table.concat(buf))
    buf = {}
  end

  while i <= n do
    local c = cmd:sub(i, i)

    if quote then
      if c == "\\" and quote == '"' then
        table.insert(buf, c)
        table.insert(buf, cmd:sub(i + 1, i + 1))
        i = i + 1
      elseif c == quote then
        quote = nil
        table.insert(buf, c)
      else
        table.insert(buf, c)
      end
      i = i + 1
    elseif c == "'" or c == '"' then
      quote = c
      table.insert(buf, c)
      i = i + 1
    elseif c == "&" and cmd:sub(i + 1, i + 1) == "&" then
      flush()
      i = i + 2
    else
      table.insert(buf, c)
      i = i + 1
    end
  end

  flush()
  return parts
end

function M.wrap_command(cmd)
  if M.IS_WIN then
    if cmd:find("&&", 1, true) then
      local parts = split_and_outside_quotes(cmd)
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

-- Maven/Gradle Wrapper: `mvn`/`gradle` como primer token → `mvnw`/`gradlew`
-- del proyecto, si el wrapper existe en `cwd`. Es independente de la shell:
-- en Windows los wrappers son `mvnw.cmd`/`gradlew.bat`; en POSIX `mvnw`/
-- `gradlew`. Si no hay wrapper (o no es el primer token) devuelve el comando
-- intacto.
local WRAPPERS = {
  mvn = {
    [true] = { file = "mvnw.cmd", invoke = ".\\mvnw.cmd" },
    [false] = { file = "mvnw", invoke = "./mvnw" },
  },
  gradle = {
    [true] = { file = "gradlew.bat", invoke = ".\\gradlew.bat" },
    [false] = { file = "gradlew", invoke = "./gradlew" },
  },
}

function M.use_wrappers(cmd, cwd)
  if type(cmd) ~= "string" then
    return cmd
  end

  local first = cmd:match "^%s*([^%s]+)"

  if not first then
    return cmd
  end

  local spec = WRAPPERS[first]

  if not spec or not cwd or cwd == "" then
    return cmd
  end

  local plat = spec[M.IS_WIN]

  if vim.fn.filereadable(cwd .. "/" .. plat.file) ~= 1 then
    return cmd
  end

  return cmd:gsub("^%s*" .. first .. "%s*", plat.invoke .. " ", 1)
end

return M

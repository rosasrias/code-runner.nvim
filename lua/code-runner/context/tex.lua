-- Detector del archivo principal de LaTeX (migración latex, solo detección).
--
-- Extracción pura de `actions/latex.lua:detect_main_tex`: dada la ruta actual
-- y las primeras líneas, resuelve la directiva `% !TEX root = ...`.
-- No lee buffers ni filesystem: el llamador aporta `current` y `lines`
-- (precedente: `context/test.lua`, detectores puros sobre líneas).
-- `latex.lua` legacy sigue intacto y mandando en producción.
--
--   M.main_file({ current = "/abs/dir/cap.tex", lines = {...} })
--     -> "/abs/dir/main.tex" (o `current` si no hay directiva)
--
-- La normalización (`:p` del legacy: separadores + segmentos `.`/`..`
-- resueltos léxicamente) se hace aquí para paridad SEMÁNTICA sin vim, con
-- una diferencia intencional y documentada: la forma canónica usa SIEMPRE
-- barras normales (incluso en Windows, donde `:p` devuelve backslashes).
-- Es determinista en toda plataforma y más segura entrecomillada en shell;
-- los tests comparan insensitive a separadores + fijan la forma canónica.
local M = {}

local function normalize(path)
  if type(path) ~= "string" then
    return path
  end

  local p = path:gsub("\\", "/")
  local out = {}

  for seg in p:gmatch("[^/]+") do
    if seg == ".." and #out > 0 and out[#out] ~= ".." then
      table.remove(out)
    elseif seg ~= "." then
      out[#out + 1] = seg
    end
  end

  local prefix = p:sub(1, 1) == "/" and "/" or ""

  return prefix .. table.concat(out, "/")
end

-- Directiva en una línea, o nil. Misma pattern que el legacy.
local function root_of(line)
  if type(line) ~= "string" then
    return nil
  end

  return line:match("^%%%s*!TEX%s+root%s*=%s*(.+)")
end

-- Archivo principal. `opts.current` (absoluto) obligatorio; `opts.lines`
-- (primeras líneas) opcional — sin líneas no hay directiva que buscar.
-- Devuelve string siempre (nunca nil ni error).
function M.main_file(opts)
  opts = opts or {}
  local current = opts.current

  if type(current) ~= "string" or current == "" then
    return current
  end

  if type(opts.lines) ~= "table" then
    return current
  end

  for _, line in ipairs(opts.lines) do
    local root = root_of(line)

    if root then
      local dir = current:gsub("\\", "/"):match("^(.*)/[^/]*$") or ""
      return normalize(dir .. "/" .. root)
    end
  end

  return current
end

return M

-- CommandSpec: la representación estructurada interna de un comando (ADR-008).
--
-- Un CommandSpec es:
--   { executable = string, args = string[], cwd = string|nil, env = table|nil }
--
-- Las cadenas de comando del usuario ("go run $file") son shorthand: se
-- normalizan a CommandSpec para uso interno (CONTRACTS §8-§9). Los tokens de
-- contexto ($file, $dir, $stem...) se preservan tal cual: son sintaxis de
-- entrada, no se resuelven acá (resolución de contexto vive en Application).
--
-- Este módulo es Core puro: nada de vim, shell ni UI.
local M = {}

local function is_space(c)
  return c == " " or c == "\t" or c == "\r" or c == "\n"
end

-- Divide una cadena en tokens, respetando comillas simples/dobles y escapado
-- de backslash dentro de comillas dobles (rutas Windows). Las comillas no se
-- incluyen en el token. Ej: `gcc "%" -o "$base.exe"` ->
-- { "gcc", "%", "-o", "$base.exe" }.
local function split_tokens(cmd)
  local tokens = {}
  local i, n = 1, #cmd

  while i <= n do
    while i <= n and is_space(cmd:sub(i, i)) do
      i = i + 1
    end

    if i > n then
      break
    end

    local buf = {}
    local quote

    while i <= n do
      local c = cmd:sub(i, i)

      if quote == nil then
        if c == "'" or c == '"' then
          quote = c
          i = i + 1
        elseif is_space(c) then
          break
        else
          buf[#buf + 1] = c
          i = i + 1
        end
      elseif c == "\\" and quote == '"' then
        buf[#buf + 1] = c

        if i < n then
          i = i + 1
          buf[#buf + 1] = cmd:sub(i, i)
        end

        i = i + 1
      elseif c == quote then
        quote = nil
        i = i + 1
      else
        buf[#buf + 1] = c
        i = i + 1
      end
    end

    tokens[#tokens + 1] = table.concat(buf)
  end

  return tokens
end

-- Divide en las sentencias separadas por `&&` (solo fuera de comillas).
-- Devuelve array de cadenas sin los separadores. Es el primer paso para
-- representar una cadena multi-comando como N CommandSpec.
function M.split_chain(cmd)
  local parts = {}
  local buf = {}
  local i, n = 1, #cmd
  local quote

  while i <= n do
    local c = cmd:sub(i, i)

    if quote == nil and c == "&" and cmd:sub(i + 1, i + 1) == "&" then
      parts[#parts + 1] = (table.concat(buf)):gsub("^%s+", ""):gsub("%s+$", "")
      buf = {}
      i = i + 2
    else
      if quote == nil and (c == "'" or c == '"') then
        quote = c
      elseif quote ~= nil and c == quote and not (c == '"' and cmd:sub(i - 1, i - 1) == "\\") then
        quote = nil
      end

      buf[#buf + 1] = c
      i = i + 1
    end
  end

  parts[#parts + 1] = (table.concat(buf)):gsub("^%s+", ""):gsub("%s+$", "")
  return parts
end

-- Parsea una cadena a un único CommandSpec. Devuelve (spec, nil) o
-- (nil, error). Una cadena con `&&` fuera de comillas NO es un único comando:
-- usá split_chain + parse por sentencia.
function M.parse(cmd)
  if type(cmd) ~= "string" then
    return nil, "CommandSpec: debe ser un string, obtuvimos " .. type(cmd)
  end

  if #M.split_chain(cmd) > 1 then
    return nil, "CommandSpec: cadena multi-comando (&&); usá split_chain"
  end

  local tokens = split_tokens(cmd)

  if #tokens == 0 then
    return nil, "CommandSpec: cadena vacía"
  end

  local spec = { executable = tokens[1], args = {} }

  for i = 2, #tokens do
    spec.args[i - 1] = tokens[i]
  end

  return spec
end

local function needs_quoting(tok)
  return tok:match "%s" ~= nil or tok == ""
end

-- Reconstruye la cadena shorthand desde un CommandSpec (round-trip con parse).
-- Solo comilla tokens que lo necesitan (espacios); los placeholders quedan
-- intactos.
function M.build(spec)
  if type(spec) ~= "table" or type(spec.executable) ~= "string" then
    return nil
  end

  local parts = {}

  for i, tok in ipairs(spec.args or {}) do
    parts[i] = needs_quoting(tok) and ('"%s"'):format(tok) or tok
  end

  local exe = needs_quoting(spec.executable) and ('"%s"'):format(spec.executable) or spec.executable

  if #parts == 0 then
    return exe
  end

  return exe .. " " .. table.concat(parts, " ")
end

-- Valida un CommandSpec (tabla). Devuelve nil si es válido o un string de
-- error. Acepta `cwd` string y `env` tabla; el resto de campos no se tocan.
function M.validate(spec)
  if type(spec) ~= "table" then
    return "CommandSpec debe ser una tabla"
  end

  if type(spec.executable) ~= "string" or spec.executable == "" then
    return "CommandSpec requiere 'executable' (string no vacío)"
  end

  if spec.args ~= nil then
    if type(spec.args) ~= "table" then
      return "CommandSpec 'args' debe ser tabla o nil"
    end

    for _, a in ipairs(spec.args) do
      if type(a) ~= "string" then
        return "CommandSpec 'args' debe contener strings"
      end
    end
  end

  if spec.cwd ~= nil and type(spec.cwd) ~= "string" then
    return "CommandSpec 'cwd' debe ser string o nil"
  end

  if spec.env ~= nil and type(spec.env) ~= "table" then
    return "CommandSpec 'env' debe ser tabla o nil"
  end

  return nil
end

-- True si el spec es un CommandSpec válido.
function M.valid(spec)
  return M.validate(spec) == nil
end

-- Normaliza a un CommandSpec canónico y desacoplado (copia) desde:
--   - un string shorthand ("go run $file")
--   - una tabla CommandSpec ({ executable = ..., args = ... })
-- Devuelve (spec, nil) o (nil, error). Una cadena con `&&` devuelve error:
-- primero split_chain.
function M.normalize(input)
  local spec

  if type(input) == "string" then
    local parsed, err = M.parse(input)

    if not parsed then
      return nil, err
    end

    spec = parsed
  elseif type(input) == "table" then
    spec = input
  else
    return nil, "CommandSpec: entrada debe ser string o tabla"
  end

  local err = M.validate(spec)

  if err then
    return nil, err
  end

  local args = {}

  for i, a in ipairs(spec.args or {}) do
    args[i] = a
  end

  local env

  if spec.env then
    env = {}

    for k, v in pairs(spec.env) do
      env[k] = v
    end
  end

  return {
    executable = spec.executable,
    args = args,
    cwd = spec.cwd,
    env = env,
  }
end

M._internals = {
  split_tokens = split_tokens,
}

return M
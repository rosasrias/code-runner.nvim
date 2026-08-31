-- Persistencia de la última ejecución, para que :CodeRunLast y :CodeRunRestart
-- sigan funcionando tras reiniciar Neovim (last_choice en init.lua solo vive en
-- memoria).
local config = require "code-runner.config"

local M = {}

-- Sobrescribible en tests (M._data_file). Persiste junto al historial.
local function data_file()
  return M._data_file or (vim.fn.stdpath("data") .. "/code-runner/last.json")
end

local function load()
  local f = io.open(data_file(), "r")

  if not f then
    return nil
  end

  local raw = f:read "*a"
  f:close()
  local ok, decoded = pcall(vim.json.decode, raw)

  if not ok or type(decoded) ~= "table" then
    return nil
  end

  return decoded
end

local function save(entry)
  local file = data_file()
  local dir = vim.fn.fnamemodify(file, ":h")

  if vim.fn.isdirectory(dir) == 0 then
    vim.fn.mkdir(dir, "p")
  end

  local f = io.open(file, "w")

  if f then
    f:write(vim.json.encode(entry))
    f:close()
  end
end

-- Guarda la última ejecución elegida (la misma forma que last_choice).
function M.set(entry)
  if not config.options.last_run.persist then
    return
  end

  save(entry)
end

-- Lee la última ejecución persistida, o nil si no hubo / archivo corrupto.
function M.get()
  return load()
end

-- Borra la última ejecución persistida (:CodeRunHistory/clear u otros).
function M.clear()
  local f = io.open(data_file(), "w")

  if f then
    f:write("null")
    f:close()
  end
end

return M
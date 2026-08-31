-- Acciones de LaTeX: detectar el archivo principal y abrir compilar/ver PDF.
local terminal = require "code-runner.terminal"
local shell = require "code-runner.shell"

local M = {}

-- Detecta el archivo principal: si el actual tiene directoriva % !TEX root = ...
-- devuelve ese; si no, el archivo actual.
function M.detect_main_tex()
  local current = vim.fn.expand "%:p"
  local lines = vim.fn.readfile(current, "", 15)

  for _, line in ipairs(lines) do
    local root = line:match "^%%%s*!TEX%s+root%s*=%s*(.+)"

    if root then
      local dir = vim.fn.fnamemodify(current, ":h")
      return vim.fn.fnamemodify(dir .. "/" .. root, ":p")
    end
  end

  return current
end

function M.build_pdf()
  local texfile = M.detect_main_tex()
  terminal.open(string.format('latexmk -lualatex -interaction=nonstopmode -synctex=1 "%s"', texfile))
end

function M.continuous_build()
  local texfile = M.detect_main_tex()
  terminal.open(string.format('latexmk -pvc -lualatex -interaction=nonstopmode -synctex=1 "%s"', texfile))
end

function M.open_pdf()
  local texfile = M.detect_main_tex()
  local pdf = vim.fn.fnamemodify(texfile, ":r") .. ".pdf"

  if shell.IS_WIN then
    vim.fn.jobstart({ "cmd", "/c", "start", pdf }, { detach = true })
  else
    vim.fn.jobstart({ "xdg-open", pdf }, { detach = true })
  end
end

function M.clean_aux()
  local texfile = M.detect_main_tex()
  terminal.open(string.format('latexmk -c "%s"', texfile))
end

return M

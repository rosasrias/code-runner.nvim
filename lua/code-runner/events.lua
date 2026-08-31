-- Events `CodeRunner*`: autocmds User que se emiten cuando cambia el estado
-- central de ejecución. Así el usuario puede reaccionar (notificaciones,
-- linters, statusline...) sin acoplar su código a los internos del plugin.
--
-- Escucha con:
--   vim.api.nvim_create_autocmd("User", { pattern = "CodeRunnerSuccess", callback = fn })
-- Los callbacks reciben un objeto con status/action/cwd/filetype/buf/code.
--
-- Emitidos (mapean a `state.lua`):
--   CodeRunnerStart     → estado "running"
--   CodeRunnerExit      → cualquier estado final (success/failed/cancelled)
--   CodeRunnerSuccess   → "success"
--   CodeRunnerFailed    → "failed"
--   CodeRunnerCancelled → "cancelled"
local config = require "code-runner.config"

local M = {}

local MAP = {
  running = "CodeRunnerStart",
  cancelled = "CodeRunnerCancelled",
  failed = "CodeRunnerFailed",
  success = "CodeRunnerSuccess",
}

-- Estados terminales que además disparan CodeRunnerExit.
local EXIT = { cancelled = true, failed = true, success = true }

function M.emit(status, s)
  if not config.options.events.enabled then
    return
  end

  local data = {
    status = status,
    action = s.action,
    cwd = s.cwd,
    filetype = s.filetype,
    buf = s.buf,
    code = s.code,
  }

  local name = MAP[status]

  if name then
    vim.api.nvim_exec_autocmds("User", {
      pattern = name,
      modeline = false,
      data = data,
    })
  end

  if EXIT[status] then
    vim.api.nvim_exec_autocmds("User", {
      pattern = "CodeRunnerExit",
      modeline = false,
      data = data,
    })
  end
end

return M

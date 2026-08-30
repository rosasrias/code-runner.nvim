local config = require "code-runner.config"

local M = {}

-- Grupos propios del plugin (defaults): se enlazan a las opciones del tema
-- (config.options.picker/terminal). Al definirlos con `default = true` no
-- pisan lo que el usuario ya haya definido (base46 / highlights override).
-- Así el picker y la terminal comparten el mismo color.
local GROUPS = {
  CodeRunnerActionRun = function()
    return config.options.picker.hl_run
  end,
  CodeRunnerActionBuild = function()
    return config.options.picker.hl_build
  end,
  CodeRunnerActionMisc = function()
    return config.options.picker.hl_misc
  end,
  CodeRunnerTermTitle = function()
    return config.options.terminal.hl_title or config.options.picker.hl_misc
  end,
  CodeRunnerTermOk = function()
    return config.options.terminal.hl_status_ok
  end,
  CodeRunnerTermErr = function()
    return config.options.terminal.hl_status_err
  end,
}

-- Define (o reasocia) los grupos de resaltado del plugin. No sobreescribe
-- una definición previa del usuario.
function M.setup()
  for name, target in pairs(GROUPS) do
    local link = target()

    if link and link ~= "" then
      vim.api.nvim_set_hl(0, name, { link = link, default = true })
    end
  end
end

-- Grupos que el plugin expone (para documentarlos y consultarlos)
M.names = vim.tbl_keys(GROUPS)

return M
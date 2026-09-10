-- Punto de entrada: nvim --headless -l tests/run.lua
local here = debug.getinfo(1, "S").source:sub(2)
local plug_root = vim.fn.fnamemodify(here, ":h:h")

vim.opt.rtp:prepend(plug_root)

local volt_dir = vim.fn.stdpath "data" .. "/lazy/volt"
if vim.fn.isdirectory(volt_dir) == 1 then
  vim.opt.rtp:append(volt_dir)
end

_G.T = dofile(plug_root .. "/tests/runner.lua")
_G.PLUG_ROOT = plug_root

require("code-runner").setup {}

dofile(plug_root .. "/tests/config_spec.lua")
dofile(plug_root .. "/tests/shell_spec.lua")
dofile(plug_root .. "/tests/command_spec.lua")
dofile(plug_root .. "/tests/result_spec.lua")
dofile(plug_root .. "/tests/execution_spec.lua")
dofile(plug_root .. "/tests/task_registry_spec.lua")
dofile(plug_root .. "/tests/engine_spec.lua")
dofile(plug_root .. "/tests/process_spec.lua")
dofile(plug_root .. "/tests/stream_spec.lua")
dofile(plug_root .. "/tests/cancel_spec.lua")
dofile(plug_root .. "/tests/restart_spec.lua")
dofile(plug_root .. "/tests/result_handler_spec.lua")
dofile(plug_root .. "/tests/lifecycle_events_spec.lua")
dofile(plug_root .. "/tests/actions_spec.lua")
dofile(plug_root .. "/tests/registry_spec.lua")
dofile(plug_root .. "/tests/profiles_spec.lua")
dofile(plug_root .. "/tests/task_spec.lua")
dofile(plug_root .. "/tests/projectrc_spec.lua")
dofile(plug_root .. "/tests/init_spec.lua")
dofile(plug_root .. "/tests/picker_spec.lua")
dofile(plug_root .. "/tests/context_spec.lua")
dofile(plug_root .. "/tests/project_spec.lua")
dofile(plug_root .. "/tests/quickfix_spec.lua")
dofile(plug_root .. "/tests/diagnostics_spec.lua")
dofile(plug_root .. "/tests/health_spec.lua")
dofile(plug_root .. "/tests/events_spec.lua")
dofile(plug_root .. "/tests/terminal_spec.lua")
dofile(plug_root .. "/tests/history_spec.lua")
dofile(plug_root .. "/tests/last_spec.lua")
dofile(plug_root .. "/tests/workflow_spec.lua")
dofile(plug_root .. "/tests/state_spec.lua")
dofile(plug_root .. "/tests/characterization_spec.lua")
dofile(plug_root .. "/tests/e2e_spec.lua")

T.summary()

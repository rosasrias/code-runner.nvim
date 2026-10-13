-- Seed built-in del Runner Registry (RUN-002, solo registro).
--
-- Proyecta un catálogo legacy `{ key -> entry }` a RunnerSpecs y los registra.
-- Puro respecto a sus inputs: el llamador aporta `catalog`, `markers_for` e
-- `icons`; este módulo NO requiere actions/terminal/proyecto (cero
-- infraestructura). Lo usan `build_run` (poblar antes de resolver identidad)
-- y el re-seed de `task_resolve`; la presentación del picker sigue leyendo
-- el catálogo legacy hasta su migración.
--
-- Todo es explícito y contabilizado: entradas omitidas (alias, sin __order)
-- y acciones-función omitidas se reportan en el resumen, nada en silencio.
-- Orden determinista: las keys se procesan ordenadas (pairs es aleatorio).
local runner = require "code-runner.runner"
local registry = require "code-runner.runner_registry"

local M = {}

-- Pobla el registry desde un catálogo legacy. `opts = {
--   markers_for = fn(key) -> string[]|nil,
--   icons = { run, build }|nil,
-- }`.
-- Devuelve (summary, nil) o (nil, error). summary = {
--   registered = string[] (ids, ordenados),
--   skipped_entries = { [key] = reason },
--   skipped_actions = number (funciones omitidas con reporte),
-- }.
function M.seed(catalog, opts)
  if type(catalog) ~= "table" then
    return nil, "runners.seed: catalog debe ser tabla"
  end

  opts = opts or {}
  local markers_for = opts.markers_for or function()
    return nil
  end
  local icons = opts.icons

  local keys = {}

  for key in pairs(catalog) do
    keys[#keys + 1] = key
  end

  table.sort(keys, function(a, b)
    return tostring(a) < tostring(b)
  end)

  local summary = { registered = {}, skipped_entries = {}, skipped_actions = 0 }

  for _, key in ipairs(keys) do
    local entry = catalog[key]
    local markers = markers_for(key)
    local spec, info = runner.from_catalog_entry(key, entry, markers, icons)

    if spec == nil then
      summary.skipped_entries[key] = info
    else
      local norm, nerr = runner.new(spec)

      if not norm then
        summary.skipped_entries[key] = tostring(nerr)
      else
        local _, rerr = registry.register(norm)

        if not rerr then
          summary.registered[#summary.registered + 1] = norm.id
          summary.skipped_actions = summary.skipped_actions + #(info.skipped or {})
        else
          summary.skipped_entries[key] = tostring(rerr)
        end
      end
    end
  end

  return summary, nil
end

return M

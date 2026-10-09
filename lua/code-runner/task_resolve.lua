-- Resolución operativa por Task ID (EXEC-009 slice 3).
--
-- Convierte un `task_id` persistido (historial/last) en la definición ACTUAL
-- de la tarea: `{ label, template, key }`. Así `run_last`/`run_history`
-- re-sustituyen la plantilla vigente con los parámetros persistidos, en vez
-- de reejecutar a ciegas el comando sustituido en su día.
--
-- Dos fuentes, en orden:
--   1. Catálogo (acciones normales y custom): se busca el label cuyo
--      `task.id(lang, label)` coincide. La comparación es por identidad
--      estable, nunca por etiqueta cruda (un cambio de iconos no rompe).
--   2. Acción contextual de test: no vive en el catálogo; se reconstruye con
--      `context.test_action(lang, { test = { name } })` desde el `$testName`
--      persistido y se VERIFICA que su id coincide. Sin verificación no hay
--      resolución (nunca resolución silenciosa por etiqueta).
--
-- Fallbacks explícitos con motivo (nunca error duro: el llamador reejecuta
-- el comando guardado, que siempre se persiste como compat):
--   "no-catalog-entry"   sin acciones para esa key
--   "task-desconocida"   ningún label ni test reconstruido coincide
--   "command-funcion"    la plantilla es función (se ejecuta directo, no se
--                        sustituye; el path legacy la invoca)
--   "test-no-aplica"     hay $testName pero el test no aplica hoy (contexto
--                        desactivado o sin plantilla para la key)
--
-- Capa Application: puede depender del catálogo y del contexto. No ejecuta,
-- no toca terminal/historial/UI.
local task = require "code-runner.task"

local M = {}

-- Resuelve. `opts = { lang = key, test_name = string|nil }`.
-- Devuelve (def, nil) o (nil, reason).
function M.resolve(task_id, opts)
  opts = opts or {}

  if type(task_id) ~= "string" or task_id == "" then
    return nil, "task-desconocida"
  end

  local lang = opts.lang or ""

  local catalog_ok, actions_mod = pcall(require, "code-runner.actions")
  local entry = catalog_ok and actions_mod.get_actions()[lang] or nil

  if entry == nil then
    return nil, "no-catalog-entry"
  end

  -- 1. Catálogo: identidad estable contra cada label vigente.
  for _, label in ipairs(entry.__order or {}) do
    if task.id(lang, label) == task_id then
      local template = entry[label]

      if type(template) == "function" then
        return nil, "command-funcion"
      end

      return { label = label, template = template, key = lang }, nil
    end
  end

  -- 2. Test contextual reconstruido desde el $testName persistido.
  if opts.test_name ~= nil and opts.test_name ~= "" then
    local ctx_ok, context_mod = pcall(require, "code-runner.context")

    if ctx_ok then
      local label, cmd = context_mod.test_action(lang, { test = { name = opts.test_name } })

      if label == nil then
        return nil, "test-no-aplica"
      end

      if task.id(lang, label) == task_id then
        return { label = label, template = cmd, key = lang }, nil
      end
    end
  end

  return nil, "task-desconocida"
end

return M

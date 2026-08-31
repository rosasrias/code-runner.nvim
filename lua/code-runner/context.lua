-- Contexto inteligente: API pública + cache de detección.
-- La detección de tests vive en `context/test.lua` y los entry points (main)
-- en `context/entry.lua`. Este módulo orquesta: resuelve la key, analiza el
-- buffer con cache (bufnr+changedtick+cursor+key) y monta la acción "Run test".
local config = require "code-runner.config"
local testdetect = require "code-runner.context.test"
local entrypoint = require "code-runner.context.entry"

local M = {}

---------------------------------------------------------
-- API
---------------------------------------------------------
local EXT_ALIASES = { rs = "rust" }

function M._resolve_key()
  local ext = vim.fn.expand "%:e"

  if ext ~= "" then
    return EXT_ALIASES[ext] or ext
  end

  return vim.bo.filetype
end

-- Analiza el buffer actual. Devuelve { key, test = {name,line}, entry = {name,line,[fqcn]} }
--
-- Con cache: el parseo del buffer (TS/regex) es caro y se dispara en cada
-- :CodeRun. Si el buffer no cambió (changedtick) y el cursor sigue en la misma
-- línea, se reutiliza el resultado anterior. La clave incluye bufnr y key,
-- así buffers/idiomas distintos no se pisan.
local detect_cache = {}

function M.detect(key)
  key = key or M._resolve_key()
  local lang = testdetect.for_key(key)

  if not lang then
    return { key = key }
  end

  local buf = vim.api.nvim_get_current_buf()
  local changed = vim.b[buf].changedtick
  local cur = vim.api.nvim_win_get_cursor(0)[1]

  local cached = detect_cache[buf]

  if cached and cached.changed == changed and cached.cursor == cur and cached.key == key then
    return cached.result
  end

  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local result = {
    key = key,
    test = testdetect.enclosing_test(lang, lines, cur),
    entry = entrypoint.find_entry(key, lines),
  }

  detect_cache[buf] = {
    changed = changed,
    cursor = cur,
    key = key,
    result = result,
  }

  return result
end

-- Expuesto para tests: permite invalidar el cache entre casos.
function M._clear_cache()
  detect_cache = {}
end

---------------------------------------------------------
-- Acción contextual "Run test"
---------------------------------------------------------
local DEFAULT_TEST_CMDS = {
  go = 'go test -run "^$testName$" -v',
  py = 'python -m pytest "$dir" -k "$testName" -v',
  js = 'npx jest "$filePath" -t "$testName"',
  ts = 'npx jest "$filePath" -t "$testName"',
  lua = 'busted "$filePath" --filter "$testName"',
  java = 'mvn -q test "-Dtest=$stem#$testName"',
  rust = 'cargo test "$testName" -- --nocapture',
  php = 'vendor/bin/phpunit --filter "$testName" "$filePath"',
  rb = 'ruby -Itest "$filePath" -n "/$testName/"',
}

-- Devuelve (label, cmd) de la acción contextual o nil si no aplica.
function M.test_action(key, ctx)
  local cfg = config.options.context

  if not cfg.enabled then
    return nil
  end

  local test = ctx and ctx.test

  if not test or not test.name then
    return nil
  end

  local cmd = cfg.test[key]

  if cmd == false then
    return nil
  end

  cmd = cmd or DEFAULT_TEST_CMDS[key]

  if not cmd then
    return nil
  end

  local name = test.name

  if #name > 50 then
    name = name:sub(1, 47) .. "…"
  end

  local label = config.options.icons.run .. " Test · " .. name

  return label, cmd
end

-- Inserta la acción contextual al frente del entry y devuelve la acción.
function M.decorate(entry, key, ctx)
  local label, cmd = M.test_action(key, ctx)

  if not label then
    return nil
  end

  table.insert(entry.__order, 1, label)
  entry[label] = cmd

  return { label = label, cmd = cmd }
end

M._internals = {
  enclosing_test = testdetect.enclosing_test,
  detect_header = testdetect.detect_header,
  is_test_for = testdetect.is_test_for,
  regex_entry = entrypoint.regex_entry,
}

return M

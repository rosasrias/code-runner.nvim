-- Contexto inteligente: detecta si el cursor está dentro de un test y
-- encuentra el entry point (main) del archivo. Usa treesitter cuando el
-- parser está disponible y cae a heurísticas por línea en caso contrario.
local config = require "code-runner.config"

local M = {}

---------------------------------------------------------
-- Helpers
---------------------------------------------------------
local function count_char(text, ch)
  return select(2, text:gsub("%" .. ch, ""))
end

local function name_starts_test(name)
  return name:sub(1, 4):lower() == "test"
end

-- Extrae el nombre de un header_line por lista de patrones.
local function detect_header(lang, text)
  for _, p in ipairs(lang.patterns) do
    local groups = { text:match(p.pat) }
    if groups[1] then
      return { name = groups[p.name_group or 1], pattern = p }
    end
  end
  return nil
end

---------------------------------------------------------
-- Registro por lenguaje (clave = key usada por build_entry)
---------------------------------------------------------
-- Ojo: Lua patterns no hacen backtracking; hay que evitar alternación
-- (a|b) y grupos opcionales `(...)?`. Se definen patrones explícitos por
-- forma y se construye la familia it/test/describe programáticamente.
local ALWAYS_TEST = function()
  return true
end

-- Genera patrones tipo it("desc") / test('desc') para un conjunto de palabras
local function describe_patterns(...)
  local words = { ... }
  local out = {}

  for _, w in ipairs(words) do
    table.insert(out, {
      pat = "^%s*" .. w .. "%s*%(%s*[\"']([^\"']+)[\"']",
      name_group = 1,
      test = ALWAYS_TEST,
    })
  end

  return out
end

local LANGS = {
  go = {
    patterns = { { pat = "^%s*func%s+([%w_]+)%s*%(" } },
    test = name_starts_test,
  },

  py = {
    patterns = {
      { pat = "^%s*def%s+([%w_]+)%s*%(", name_group = 1 },
      { pat = "^%s*async%s+def%s+([%w_]+)%s*%(", name_group = 1 },
    },
    comment = "^%s*#",
    test = name_starts_test,
  },

  js = {
    patterns = describe_patterns("it", "test", "describe"),
    comment = "^%s*//",
    test = ALWAYS_TEST,
  },

  ts = {
    patterns = describe_patterns("it", "test", "describe"),
    comment = "^%s*//",
    test = ALWAYS_TEST,
  },

  lua = {
    patterns = vim.list_extend({
      { pat = "^%s*function%s+([%w%._%-]+)%s*%(", name_group = 1, test = name_starts_test },
      { pat = "^%s*local%s+function%s+([%w%._%-]+)%s*%(", name_group = 1, test = name_starts_test },
    }, describe_patterns("it", "describe", "context", "test")),
    comment = "^%s*%-%-",
  },

  java = {
    patterns = { { pat = "^%s*[^%(%c%s][^%(%c]-%s+([%w_]+)%s*%(", name_group = 1 } },
    comment = "^%s*//",
    annotations = { "@Test" },
    test = name_starts_test,
  },

  rust = {
    patterns = {
      { pat = "^%s*fn%s+([%w_]+)%s*%(", name_group = 1 },
      { pat = "^%s*pub%s+fn%s+([%w_]+)%s*%(", name_group = 1 },
    },
    comment = "^%s*//",
    annotations = { "#[test]", "#[cfg(test)]" },
    test = name_starts_test,
  },

  php = {
    patterns = {
      { pat = "^%s*function%s+([%w_]+)%s*%(", name_group = 1 },
      { pat = "^%s*[^%(%c]-function%s+([%w_]+)%s*%(", name_group = 1 },
    },
    comment = "^%s*//",
    annotations = { "@test", "@Test", "#[" },
    test = name_starts_test,
  },

  rb = {
    patterns = vim.list_extend({
      { pat = "^%s*def%s+([%w_?!]+)%s*", name_group = 1, test = name_starts_test },
      { pat = "^%s*it%s+[\"']([^\"']+)[\"']", name_group = 1, test = ALWAYS_TEST },
    }, describe_patterns "it"),
    comment = "^%s*#",
  },
}

-- ¿El header en la línea ln es un test? Nombre con prefijo 'test', patrón
-- marcado como test (ej: it/describe) o bien anotación (JUnit @Test, Rust
-- #[test], PHP @test/attribute) cerca arriba.
local function is_test_for(lang, lines, ln, name, pattern)
  local pred = (pattern and pattern.test) or lang.test

  if pred and pred(name) then
    return true
  end

  if lang.annotations then
    for i = math.max(1, ln - 3), ln - 1 do
      local t = vim.trim(lines[i] or "")

      for _, a in ipairs(lang.annotations) do
        if t:sub(1, #a) == a then
          return true
        end
      end
    end
  end

  return false
end

-- Encuentra el header que ENCIERRA al cursor y devuelve { name, line } si
-- es un test (nil si el cursor está dentro de una función que no es test).
local function enclosing_test(lang, lines, cur)
  local pending = 0

  for ln = cur, 1, -1 do
    local text = lines[ln] or ""
    local trimmed = text:match("^%s+(.*)$") or text

    if trimmed ~= "" and not (lang.comment and trimmed:match(lang.comment)) then
      local o = count_char(text, "{")
      local c = count_char(text, "}")

      if c > 0 then
        pending = pending + c
      end

      local candidate

      if o > 0 then
        pending = pending - o

        if pending <= 0 then
          pending = 0
          candidate = detect_header(lang, text)
        end
      elseif c == 0 and pending == 0 then
        candidate = detect_header(lang, text)
      end

      if candidate then
        if is_test_for(lang, lines, ln, candidate.name, candidate.pattern) then
          return { name = candidate.name, line = ln }
        end

        return nil -- dentro de una función no-test: no rastrear más arriba
      end
    end
  end

  return nil
end

---------------------------------------------------------
-- Entry points (main): treesitter con fallback regex
---------------------------------------------------------
local MAIN_RULES = {
  { "^%s*int%s+main%s*%(", "main" },
  { "^%s*void%s+main%s*%(", "main" },
}

local ENTRY_FINDERS = {
  go = {
    ts = "go",
    regex = { { "^%s*func%s+main%s*%(", "main" } },
  },

  py = {
    ts = "python",
    regex = function(lines)
      for i, line in ipairs(lines) do
        if line:match "if%s+__name__" and line:find("__main__", 1, true) then
          return { name = "__main__", line = i }
        end
      end

      for i, line in ipairs(lines) do
        if line:match "^%s*def%s+main%s*%(" then
          return { name = "main", line = i }
        end
      end

      return nil
    end,
  },

  java = {
    ts = "java",
    regex = function(lines)
      for i, line in ipairs(lines) do
        if line:match "public%s+static%s+void%s+main%s*%(" then
          return { name = "main", line = i }
        end
      end

      return nil
    end,
  },

  rust = {
    ts = "rust",
    regex = {
      { "^%s*fn%s+main%s*%(", "main" },
      { "^%s*pub%s+fn%s+main%s*%(", "main" },
    },
  },

  c = { ts = "c", regex = MAIN_RULES },
  cpp = { ts = "cpp", regex = MAIN_RULES },
}

local TS_QUERIES = {
  go = { "(function_declaration name: (identifier) @name)" },
  python = {
    "(function_definition name: (identifier) @name)",
    "(string) @main_str",
  },
  java = { "(method_declaration name: (identifier) @name)" },
  rust = { "(function_item name: (identifier) @name)" },
  c = { "(function_definition declarator: (function_declarator declarator: (identifier) @name))" },
  cpp = { "(function_definition declarator: (function_declarator declarator: (identifier) @name))" },
}

local function ts_entry(lang, buf)
  local queries = TS_QUERIES[lang]

  if not queries then
    return nil
  end

  local okp, parser = pcall(vim.treesitter.get_parser, buf, lang)

  if not okp then
    return nil
  end

  local okt, trees = pcall(function()
    return parser:parse()
  end)

  if not okt then
    return nil
  end

  local root = trees[1] and trees[1]:root()

  if not root then
    return nil
  end

  local main_found, main_if_found

  for _, qs in ipairs(queries) do
    local okq, q = pcall(vim.treesitter.query.parse, lang, qs)

    if okq then
      for id, node in q:iter_captures(root, buf) do
        local cap = q.captures[id]
        local txt = vim.treesitter.get_node_text(node, buf)

        if cap == "name" and (txt == "main" or txt == "__main__") and not main_if_found then
          if txt == "__main__" then
            main_if_found = { name = "__main__", line = node:start() + 1 }
          elseif not main_found then
            main_found = { name = "main", line = node:start() + 1 }
          end
        end

        if cap == "main_str" and txt:find("__main__", 1, true) then
          -- Sube hasta el if_statement que contiene el string (guard multilinea)
          local line_node = node
          local p = node:parent()

          while p do
            if p:type() == "if_statement" then
              line_node = p
              break
            end
            p = p:parent()
          end

          main_if_found = { name = "__main__", line = line_node:start() + 1 }
        end
      end
    end
  end

  return main_if_found or main_found
end

local function regex_entry(key, lines)
  local ef = ENTRY_FINDERS[key]

  if not ef then
    return nil
  end

  if type(ef.regex) == "function" then
    return ef.regex(lines)
  end

  for _, rule in ipairs(ef.regex) do
    for i, line in ipairs(lines) do
      if line:match(rule[1]) then
        return { name = rule[2], line = i }
      end
    end
  end

  return nil
end

local function java_fqcn(lines)
  local pkg, cls

  for _, line in ipairs(lines) do
    local m = line:match "^%s*package%s+([%w%.]+)%s*;"

    if m then
      pkg = m
    end

    local a = ({ line:match "^%s*class%s+([%w_]+)" })[1]
    local b = ({ line:match "^%s*[%w_%.<>]+%s+class%s+([%w_]+)" })[1]

    if a or b then
      cls = a or b
    end
  end

  if pkg and cls then
    return pkg .. "." .. cls
  end
end

local function find_entry(key, lines)
  local ef = ENTRY_FINDERS[key]

  if not ef then
    return nil
  end

  local entry

  if ef.ts then
    entry = ts_entry(ef.ts, 0)
  end

  entry = entry or regex_entry(key, lines)

  if entry and key == "java" and not entry.fqcn then
    entry.fqcn = java_fqcn(lines)
  end

  return entry
end

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
  local lang = LANGS[key]

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
    test = enclosing_test(lang, lines, cur),
    entry = find_entry(key, lines),
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
  enclosing_test = enclosing_test,
  detect_header = detect_header,
  is_test_for = is_test_for,
  regex_entry = regex_entry,
}

return M
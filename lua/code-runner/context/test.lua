-- Detección de tests: ¿el cursor está dentro de un test en el buffer?
-- Usa heurísticas por línea (regex por lenguaje). El entry point (main) vive en
-- `context/entry.lua`; la API y el cache en `context.lua`.
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
function M.detect_header(lang, text)
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
function M.is_test_for(lang, lines, ln, name, pattern)
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
function M.enclosing_test(lang, lines, cur)
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
          candidate = M.detect_header(lang, text)
        end
      elseif c == 0 and pending == 0 then
        candidate = M.detect_header(lang, text)
      end

      if candidate then
        if M.is_test_for(lang, lines, ln, candidate.name, candidate.pattern) then
          return { name = candidate.name, line = ln }
        end

        return nil -- dentro de una función no-test: no rastrear más arriba
      end
    end
  end

  return nil
end

-- Expuesto para que context.detect() obtenga el registro del lenguaje.
function M.for_key(key)
  return LANGS[key]
end

return M

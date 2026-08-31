-- Entry points (main) del archivo: treesitter con fallback regex.
-- Detección de tests vive en `context/test.lua`; la API en `context.lua`.
local M = {}

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

function M.regex_entry(key, lines)
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

function M.find_entry(key, lines)
  local ef = ENTRY_FINDERS[key]

  if not ef then
    return nil
  end

  local entry

  if ef.ts then
    entry = ts_entry(ef.ts, 0)
  end

  entry = entry or M.regex_entry(key, lines)

  if entry and key == "java" and not entry.fqcn then
    entry.fqcn = java_fqcn(lines)
  end

  return entry
end

return M

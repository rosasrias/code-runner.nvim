local context = require "code-runner.context"
local shell = require "code-runner.shell"
local actions = require "code-runner.actions"
local config = require "code-runner.config"

local tmpdir = vim.fn.tempname() .. "/cr_ctx_test"
vim.fn.mkdir(tmpdir, "p")

local function open(name, lines)
  local f = tmpdir .. "/" .. name
  vim.fn.writefile(lines, f)
  vim.cmd("edit " .. vim.fn.fnameescape(f))
end

local function cursor(line)
  vim.api.nvim_win_set_cursor(0, { line, 0 })
end

local detect -- lee el buffer actual sin pasar key (igual que build_run)
detect = function()
  return context.detect()
end

T.section("context: cache de detección")

T.it("misma línea y buffer: reutiliza el mismo resultado (identity)", function()
  open("cacheable.go", {
    "package demo",
    "",
    "func TestAlpha() {}",
  })
  cursor(3)
  local a = context.detect("go")
  local b = context.detect("go")
  T.truthy(a == b, "el cache devuelve el mismo objeto (sin re-parsear)")
end)

T.it("cambiar de línea invalida el cache (re-parsea)", function()
  cursor(3)
  local a = context.detect("go")
  cursor(1) -- otra línea => resultado distinto
  local b = context.detect("go")
  T.falsy(a == b, "distinto cursor => resultado nuevo")
end)

T.it("editar el buffer (changedtick) invalida el cache", function()
  cursor(3)
  local a = context.detect("go")
  vim.api.nvim_buf_set_lines(0, 0, 0, false, { "-- comentario nuevo" })
  -- changedtick sube con el cambio; forzamos re-parse aunque la línea siga igual
  local b = context.detect("go")
  T.falsy(a == b, "buffer modificado => resultado nuevo")
end)

T.it("cambiar de key invalida el cache (no comparte entre idiomas)", function()
  cursor(3)
  local a = context.detect("go")
  local b = context.detect("py") -- otro lenguaje sobre el mismo buffer
  T.falsy(a == b, "distinta key => resultado nuevo")
end)

T.it("_clear_cache fuerza una recomputación", function()
  cursor(3)
  local a = context.detect("go")
  context._clear_cache()
  local b = context.detect("go")
  T.falsy(a == b, "cache vaciado => resultado nuevo")
end)

T.section("context: detección de tests bajo el cursor")

T.it("go: cursor dentro de un Test* devuelve el nombre", function()
  open("calc_test.go", {
    "package demo",
    "",
    "func Helper() { _ = 1 }",
    "",
    "func TestAdd(t *testing.T) {",
    "  result := 1 + 1",
    "}",
  })
  cursor(6)

  local r = detect()
  T.eq("go", r.key)
  T.eq("TestAdd", r.test and r.test.name)
  T.eq(5, r.test.line)
end)

T.it("go: cursor dentro de una función que no es test devuelve nil", function()
  open("other.go", {
    "package demo",
    "",
    "func TestA() { _ = 1 }",
    "",
    "func Helper() {",
    "  _ = 2",
    "}",
  })
  cursor(6)

  T.falsy(detect().test)
end)

T.it("python: cursor dentro de def test_* devuelve el nombre", function()
  open("mod_test.py", {
    "x = 1",
    "",
    "def test_add():",
    "  a = 1",
    "  return a",
    "",
    "def helper():",
    "  b = 2",
    "  return b",
  })
  cursor(4)

  T.eq("test_add", detect().test.name)
end)

T.it("python: cursor dentro de un helper devuelve nil (no hereda el test de arriba)", function()
  -- mismo fixture del caso anterior
  cursor(8)

  T.falsy(detect().test)
end)

T.it("python: cursor encima del test devuelve nil", function()
  cursor(1)

  T.falsy(detect().test)
end)

T.it("javascript: it/test captura la descripción", function()
  open("sum.test.js", {
    'import { test } from "node:test"',
    "",
    'test("suma dos numeros", () => {',
    "  expect(1 + 1).toBe(2)",
    "})",
  })
  cursor(4)

  T.eq("suma dos numeros", detect().test.name)
end)

T.it("java: método anotado con @Test", function()
  open("CalcTest.java", {
    "import org.junit.jupiter.api.Test;",
    "",
    "class CalcTest {",
    "  @Test",
    "  void suma() {",
    "    assertTrue(true);",
    "  }",
    "}",
  })
  cursor(6)

  T.eq("suma", detect().test.name)
end)

T.it("rust: fn test_* o #[test] cuentan como test", function()
  open("inc.rs", {
    "#[cfg(test)]",
    "mod tests {",
    "  #[test]",
    "  fn test_increment() {",
    "    assert_eq!(1 + 1, 2);",
    "  }",
    "}",
  })
  cursor(5)

  T.eq("test_increment", detect().test.name)
end)

T.it("lua/busted: describe + it captura la descripción", function()
  open("spec.lua", {
    'describe("grupo", function()',
    '  it("suma", function()',
    "    local x = 1",
    "  end)",
    "end)",
  })
  cursor(3)

  T.eq("suma", detect().test.name)
end)

T.it("ruby: RSpec it captura la descripción", function()
  open("calc_spec.rb", {
    'RSpec.describe "Calc" do',
    '  it "suma" do',
    "    expect(1 + 1).to eq(2)",
    "  end",
    "end",
  })
  cursor(3)

  T.eq("suma", detect().test.name)
end)

T.it("extensión no soportada: devuelve solo la key", function()
  open("raro.xyz123", { "algo" })
  vim.bo.filetype = ""

  local r = detect()
  T.eq("xyz123", r.key)
  T.falsy(r.test)
  T.falsy(r.entry)
end)

T.section("context: entry points (main)")

T.it("python: if __name__ == __main__", function()
  open("app.py", {
    "import os",
    "",
    "def main():",
    "  pass",
    "",
    'if __name__ == "__main__":',
    "  main()",
  })

  local entry = detect().entry
  T.truthy(entry)
  T.eq("__main__", entry.name)
  T.eq(6, entry.line)
end)

T.it("python: def main()", function()
  open("app2.py", {
    "def main():",
    "  pass",
    "",
    "main()",
  })

  local entry = detect().entry
  T.eq("main", entry.name)
  T.eq(1, entry.line)
end)

T.it("go: func main", function()
  open("main.go", {
    "package main",
    "",
    "func main() {",
    "  println(1)",
    "}",
  })

  local entry = detect().entry
  T.eq("main", entry.name)
  T.eq(3, entry.line)
end)

T.it("java: package + clase + main => fqcn", function()
  open("App.java", {
    "package com.demo;",
    "",
    "public class App {",
    "",
    "  public static void main(String[] args) {",
    "  }",
    "}",
  })

  local entry = detect().entry
  T.eq("main", entry.name)
  T.eq("com.demo.App", entry.fqcn)
  T.eq(5, entry.line)
end)

T.it("lua no tiene entry (el script completo es el programa)", function()
  open("script.lua", { "print(1)" })
  T.falsy(detect().entry)
end)

T.it("regression: ts_entry no explota cuando node:start() devuelve (row, col)", function()
  -- Node real de tree-sitter: node:start() retorna row, col (numeros).
  -- Antes se usaba node:start()[1] -> 'attempt to index a number value'.
  open("mock_app.py", { "x = 1" })

  local orig_get_parser = vim.treesitter.get_parser
  local orig_parse = vim.treesitter.query.parse
  local orig_get_text = vim.treesitter.get_node_text

  local fake_query = {
    captures = { [1] = "name" },
    iter_captures = function()
      local i = 0
      return function()
        i = i + 1
        if i > 1 then
          return nil
        end
        local node = {
          start = function()
            return 3, 0 -- row, col
          end,
        }
        return 1, node
      end
    end,
  }

  vim.treesitter.query.parse = function()
    return vim.deepcopy(fake_query)
  end
  vim.treesitter.get_node_text = function()
    return "main"
  end
  vim.treesitter.get_parser = function()
    return {
      parse = function()
        return {
          {
            root = function()
              return {}
            end,
          },
        }
      end,
    }
  end

  local entry
  local ok = not not pcall(function()
    entry = detect().entry
  end)

  vim.treesitter.get_parser = orig_get_parser
  vim.treesitter.query.parse = orig_parse
  vim.treesitter.get_node_text = orig_get_text

  T.truthy(ok, "detect() sobrevive al ts_entry con node:start() numerico")
  T.truthy(entry)
  T.eq("main", entry.name)
  T.eq(4, entry.line)
end)

T.it("regression: main_str usa la linea del if_statement no del string", function()
  open("mock_guard.py", { "x = 1" })

  local orig_get_parser = vim.treesitter.get_parser
  local orig_parse = vim.treesitter.query.parse
  local orig_get_text = vim.treesitter.get_node_text

  vim.treesitter.query.parse = function()
    return {
      captures = { [1] = "main_str" },
      iter_captures = function()
        local i = 0
        return function()
          i = i + 1
          if i > 1 then
            return nil
          end
          local string_node = {
            start = function()
              return 7, 15
            end,
            parent = function()
              return {
                type = function()
                  return "comparison_operator"
                end,
                parent = function()
                  return {
                    type = function()
                      return "if_statement"
                    end,
                    start = function()
                      return 5, 0
                    end,
                  }
                end,
              }
            end,
          }
          return 1, string_node
        end
      end,
    }
  end
  vim.treesitter.get_node_text = function()
    return '"__main__"'
  end
  vim.treesitter.get_parser = function()
    return {
      parse = function()
        return {
          {
            root = function()
              return {}
            end,
          },
        }
      end,
    }
  end

  local entry
  local ok = not not pcall(function()
    entry = detect().entry
  end)

  vim.treesitter.get_parser = orig_get_parser
  vim.treesitter.query.parse = orig_parse
  vim.treesitter.get_node_text = orig_get_text

  T.truthy(ok, "detect() sobrevive al main_str")
  T.truthy(entry)
  T.eq("__main__", entry.name)
  T.eq(6, entry.line)
end)

T.section("context: acción contextual Run test")

T.it("test_action devuelve label y cmd con $testName", function()
  local label, cmd = context.test_action("go", { test = { name = "TestAdd" } })
  T.truthy(label and label:find(config.options.icons.run, 1, true), "label con icono de run")
  T.truthy(label:find("TestAdd", 1, true), "label con el nombre del test")
  T.truthy(cmd:find("$testName", 1, true), "cmd con plantilla")
end)

T.it("test_action: sin test (nil) -> nil", function()
  local label = context.test_action("go", {})
  T.falsy(label)
end)

T.it("test_action: comando propio por lenguaje (override)", function()
  config.options = vim.tbl_deep_extend("force", vim.deepcopy(config.defaults), {
    context = { test = { go = "gotestsum -- -run \"^$testName$\"" } },
  })

  local _, cmd = context.test_action("go", { test = { name = "TestAdd" } })
  T.contains(cmd, "gotestsum")

  config.options = vim.deepcopy(config.defaults)
end)

T.it("test_action: cmd=false desactiva ese lenguaje", function()
  config.options = vim.tbl_deep_extend("force", vim.deepcopy(config.defaults), {
    context = { test = { go = false } },
  })

  T.falsy(context.test_action("go", { test = { name = "TestAdd" } }))

  config.options = vim.deepcopy(config.defaults)
end)

T.it("test_action: context.enabled=false desactiva todo", function()
  config.options = vim.tbl_deep_extend("force", vim.deepcopy(config.defaults), {
    context = { enabled = false },
  })

  T.falsy(context.test_action("go", { test = { name = "TestAdd" } }))

  config.options = vim.deepcopy(config.defaults)
end)

T.it("decorate inserta el test primero y preserva el resto", function()
  local before = actions.get_actions().go
  local count_before = #before.__order

  local entry = actions.get_actions().go
  local item = context.decorate(entry, "go", { test = { name = "TestAdd" } })

  T.truthy(item, "devolvió la acción contextual")
  T.eq(item.label, entry.__order[1], "el test va primero")
  T.eq(item.cmd, entry[item.label], "cmd registrado")
  T.eq(count_before + 1, #entry.__order, "una acción nueva")
  T.truthy(entry[" ▶ Run"] or entry[config.options.icons.run .. " Run"], "acciones default intactas")
end)

T.section("shell: variables de contexto")

T.it("$testName se inyecta por vars", function()
  T.eq('go test -run "^TestAdd$" -v', shell.substitute('go test -run "^$testName$" -v', { ["$testName"] = "TestAdd" }))
end)

T.it("$stem expande al nombre sin extensión", function()
  open("App.java", { "class App {}", "public static void main" })
  T.eq("App", shell.substitute("$stem"))
end)

T.it("%l expande al número de línea del cursor", function()
  cursor(2)
  T.eq("2", shell.substitute("%l"))
end)

T.it("tokens desconocidos siguen intactos con vars presentes", function()
  T.eq('"$PATH"', shell.substitute('"$PATH"', { ["$testName"] = "x" }))
end)
local shell = require "code-runner.shell"
local actions = require "code-runner.actions"
local config = require "code-runner.config"

-- Blindaje: los E2E siempre corren con el valor real de la plataforma,
-- aunque otros tests hayan tocado shell.IS_WIN
local PLATFORM_WIN = vim.fn.has "win32" == 1

T.section("e2e: C (compile & run real)")

if vim.fn.executable "gcc" == 1 then
  T.it("plantilla nativa de C compila y ejecuta", function()
    local dir = vim.fn.tempname() .. "/cr_e2e_c"
    vim.fn.mkdir(dir, "p")
    local marker = "C_E2E_OK_" .. os.time()

    local src = dir .. "/prog.c"
    vim.fn.writefile({ "#include <stdio.h>", "int main(void) {", '  printf("' .. marker .. '\\n");', "  return 0;", "}" }, src)
    vim.cmd("edit " .. vim.fn.fnameescape(src))

    -- usa la plantilla exacta del plugin para C
    local icons = config.options.icons
    local compile_run
    for _, label in ipairs(actions.get_actions().c.__order) do
      if label:find("Compile & Run", 1, true) then
        compile_run = label
      end
    end

    shell.IS_WIN = PLATFORM_WIN
    local cmd = shell.substitute(actions.get_actions().c[compile_run])
    local out = vim.fn.system(shell.wrap_command(cmd))

    T.eq(0, vim.v.shell_error, "compile & run sin errores")
    T.contains(out, marker, "salida del binario")
  end)

  T.it("compilar con un error produce entrada quickfix en la línea correcta", function()
    local dir = vim.fn.tempname() .. "/cr_e2e_qf"
    vim.fn.mkdir(dir, "p")

    -- error deliberado en la línea 3
    local src = dir .. "/bad.c"
    vim.fn.writefile({ "int main(void) {", "  int x;", "  x = x + ;", "  return 0;", "}" }, src)
    vim.cmd("edit " .. vim.fn.fnameescape(src))

    local icons = config.options.icons
    local compile
    for _, label in ipairs(actions.get_actions().c.__order) do
      if not label:find("Run", 1, true) and not label:find("Compile & Run", 1, true) then
        compile = label
      end
    end

    shell.IS_WIN = PLATFORM_WIN
    local cmd = shell.substitute(actions.get_actions().c[compile])
    local out = vim.fn.system(shell.wrap_command(cmd))

    local qf = require "code-runner.quickfix"
    local entries = qf.parse(vim.split(out, "\n"), dir)

    T.truthy(#entries >= 1, "al menos un error parseado")
    T.eq(3, entries[1].lnum, "la línea del error es la 3")
    T.truthy(entries[1].filename:find("bad.c", 1, true), "apunta a bad.c")
  end)
else
  T.skip("plantilla C", "gcc no está en PATH")
end

T.section("e2e: Java (package + classpath reales)")

if vim.fn.executable "javac" == 1 and vim.fn.executable "java" == 1 then
  T.it("java_source_root + javac -sourcepath + java -cp funcionan juntos", function()
    local internals = actions._internals
    local root = vim.fn.tempname() .. "/cr_e2e_java"
    local src_root = root .. "/src/main/java"
    local pkg_dir = src_root .. "/com/ejemplo/test"

    vim.fn.mkdir(pkg_dir, "p")
    local marker = "JAVA_E2E_OK_" .. os.time()
    local file = pkg_dir .. "/App.java"
    vim.fn.writefile({
      "package com.ejemplo.test;",
      "",
      "public class App {",
      "    public static void main(String[] args) {",
      '        System.out.println("' .. marker .. '");',
      "    }",
      "}",
    }, file)

    -- lo que haría java_plain_run()
    local package = internals.java_package_of(vim.fn.readfile(file))
    T.eq("com.ejemplo.test", package)

    local fqcn = package .. "." .. vim.fn.fnamemodify(file, ":t:r")
    local source_root = internals.java_source_root(vim.fn.fnamemodify(file, ":h"), package)
    T.eq(src_root:gsub("\\", "/"), source_root, "raíz deducida")

    local out_dir = vim.fn.tempname()
    local cmd = string.format(
      'javac -encoding UTF-8 -sourcepath "%s" -d "%s" "%s" && java -cp "%s" "%s"',
      source_root,
      out_dir,
      file,
      out_dir,
      fqcn
    )

    shell.IS_WIN = PLATFORM_WIN
    local out = vim.fn.system(shell.wrap_command(cmd))
    T.eq(0, vim.v.shell_error, "javac+java sin errores")
    T.contains(out, marker, "salida de la JVM")
  end)
else
  T.skip("pipeline Java", "JDK no está en PATH")
end

T.section("e2e: Python")

if vim.fn.executable "python" == 1 then
  T.it("acción python ejecuta el script actual", function()
    local dir = vim.fn.tempname() .. "/cr_e2e_py"
    vim.fn.mkdir(dir, "p")
    local marker = "PY_E2E_OK_" .. os.time()

    local f = dir .. "/script.py"
    vim.fn.writefile({ 'print("' .. marker .. '")' }, f)
    vim.cmd("edit " .. vim.fn.fnameescape(f))

    shell.IS_WIN = PLATFORM_WIN
    local cmd = shell.substitute('python "%"')
    local out = vim.fn.system(shell.wrap_command(cmd))

    T.eq(0, vim.v.shell_error)
    T.contains(out, marker)
  end)
else
  T.skip("python", "python no está en PATH")
end

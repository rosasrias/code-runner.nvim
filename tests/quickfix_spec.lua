local quickfix = require "code-runner.quickfix"

local CWD = "C:/proy/src"

local function norm_win(p)
  return vim.fs.normalize(vim.fn.fnamemodify(p, ":p")):gsub("\\", "/")
end

T.section("quickfix: parsing de errores")

T.it("gcc/clang: path:line:col: msg", function()
  local entries = quickfix.parse({ "src/main.c:12:5: error: dereferencing pointer to incomplete type" }, CWD)
  T.eq(1, #entries)
  T.eq(norm_win(CWD .. "/src/main.c"), entries[1].filename)
  T.eq(12, entries[1].lnum)
  T.eq(5, entries[1].col)
  T.eq("E", entries[1].type)
end)

T.it("ruta con drive Windows: C:\\...:line:col: msg", function()
  local entries = quickfix.parse({ "C:\\src\\main.c:12:5: error: implicit declaration of fn" }, CWD)
  T.eq(norm_win("C:/src/main.c"), norm_win(entries[1].filename))
  T.eq(12, entries[1].lnum)
end)

T.it("sin columna: path:line: msg", function()
  local entries = quickfix.parse({ "a.c:4: warning: implicit declaration of function" }, CWD)
  T.eq(norm_win(CWD .. "/a.c"), entries[1].filename)
  T.eq(4, entries[1].lnum)
  T.eq("W", entries[1].type, "warning marca tipo W")
end)

T.it("maven: [ERROR] path:[line,col]", function()
  local entries = quickfix.parse({ "[ERROR] C:/x/App.java:[12,5] cannot find symbol" }, CWD)
  T.eq(norm_win("C:/x/App.java"), entries[1].filename)
  T.eq(12, entries[1].lnum)
  T.eq(5, entries[1].col)
end)

T.it("maven sin columna: [ERROR] path:[line]", function()
  local entries = quickfix.parse({ "[ERROR] App.java:[9] illegal start of expression" }, CWD)
  T.eq(9, entries[1].lnum)
end)

T.it("MSVC: path(line,col) : error CODE: msg", function()
  local entries = quickfix.parse({ "C:\\proj\\a.cs(14,9): error CS0103: The name 'x' does not exist" }, CWD)
  T.eq(14, entries[1].lnum)
  T.eq(9, entries[1].col)
  T.contains(entries[1].text, "CS0103")
end)

T.it("go test: --- FAIL: TestX es entrada sin archivo", function()
  local entries = quickfix.parse({ "--- FAIL: TestAdd (0.00s)" }, CWD)
  T.eq(1, #entries)
  T.truthy(entries[1].text:find "FAIL")
  T.falsy(entries[1].filename)
end)

T.it("códigos ANSI de color se ignoran", function()
  local entries = quickfix.parse({ "\27[31m src/a.c:1:2: error: x\27[0m" }, CWD)
  T.eq(norm_win(CWD .. "/src/a.c"), norm_win(entries[1].filename))
  T.eq(2, entries[1].col)
end)

T.it("./ en la ruta se limpia y resuelve contra el cwd", function()
  local entries = quickfix.parse({ "./test_spec.rb:3:1: warning: unused variable" }, CWD)
  T.eq(norm_win(CWD .. "/test_spec.rb"), entries[1].filename)
end)

T.it("python traceback: File \"path\", line N", function()
  local entries = quickfix.parse({
    "Traceback (most recent call last):",
    '  File "src\\app.py", line 4, in <module>',
    "    x = 1",
    "NameError: name 'x' is not defined",
  }, CWD)
  T.eq(1, #entries)
  T.eq(norm_win(CWD .. "/src/app.py"), norm_win(entries[1].filename))
  T.eq(4, entries[1].lnum)
  T.falsy(entries[1].col, "sin columna")
end)

T.it("python traceback con ruta absoluta no usa el cwd", function()
  local entries = quickfix.parse({
    '  File "C:\\Otro\\mod.py", line 12, in foo',
    "    raise RuntimeError",
  }, CWD)
  T.eq(norm_win("C:/Otro/mod.py"), norm_win(entries[1].filename))
  T.eq(12, entries[1].lnum)
end)

T.it("handle devuelve 0 cuando no se parsea nada", function()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "Command not found", "oops" })
  local cwd = vim.fn.getcwd()

  local count = quickfix.handle(buf, 1, cwd)
  T.eq(0, count)

  vim.api.nvim_buf_delete(buf, { force = true })
end)

local function qf_windows()
  local wins = {}

  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.fn.win_gettype(w) == "quickfix" then
      table.insert(wins, w)
    end
  end

  return wins
end

T.it("éxito sin salidas: cierra la ventana quickfix y vacía la lista", function()
  -- una lista vieja con errores de un build anterior
  vim.fn.setqflist({ { filename = "a.c", lnum = 1, text = "viejo error" } }, "r")
  pcall(vim.cmd, "silent copen")

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "Compilation finished", "OK" })

  local count = quickfix.handle(buf, 0, vim.fn.getcwd())
  T.eq(0, count)
  T.eq(0, #qf_windows(), "la ventana quickfix se cerró")
  T.eq(0, #vim.fn.getqflist(), "la lista quedó vacía")

  vim.api.nvim_buf_delete(buf, { force = true })
  pcall(vim.cmd, "silent cclose")
end)

T.it("éxito con warnings: refresca la lista sin abrir ventana forzada", function()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "src/a.c:3:1: warning: unused variable" })

  vim.fn.setqflist({ { filename = "a.c", lnum = 1, text = "viejo" } }, "r")

  local count = quickfix.handle(buf, 0, CWD)
  T.eq(0, count)
  T.eq(1, #vim.fn.getqflist(), "la lista se actualizó con el warning")
  T.eq(3, vim.fn.getqflist()[1].lnum)

  vim.api.nvim_buf_delete(buf, { force = true })
end)

T.it("sin coincidencias -> lista vacía", function()
  local entries = quickfix.parse({ "hello world", "", "Success! built in 2s" }, CWD)
  T.eq(0, #entries)
end)

T.it("múltiples errores en varias líneas", function()
  local entries = quickfix.parse({
    "src/a.c:1:1: error: syntax error",
    "src/a.c:6:3: error: expected ';'",
  }, CWD)
  T.eq(2, #entries)
  T.eq(1, entries[1].lnum)
  T.eq(6, entries[2].lnum)
end)

T.it("style=diagnostic redirige a vim.diagnostic y no a la quickfix", function()
  local cfg = require "code-runner.config"
  local saved = cfg.options.quickfix.style
  cfg.options.quickfix.style = "diagnostic"

  local src = vim.fn.tempname() .. ".c"
  vim.fn.writefile({ "" }, src)
  local bufnr = vim.fn.bufadd(src)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { src .. ":2:3: error: bad token" })

  vim.fn.setqflist({ { filename = "a.c", lnum = 1, text = "viejo" } }, "r")
  local count = quickfix.handle(buf, 1, "")

  T.eq(1, count)
  local diags = vim.diagnostic.get(bufnr, { namespace = require("code-runner.diagnostics").ns })
  T.eq(1, #diags, "cayó en vim.diagnostic")
  T.eq(1, diags[1].lnum, "base 0")
  -- sin abrir ventana ni tocarse la lista quickfix para el build fallido
  local qfl = vim.fn.getqflist()
  T.eq(1, #qfl, "la quickfix conserva su entrada previa")
  T.eq("viejo", qfl[1].text, "la quickfix no se sobrescribió")
  T.eq(0, #qf_windows(), "no abrió la ventana quickfix")

  cfg.options.quickfix.style = saved
  vim.diagnostic.reset(require("code-runner.diagnostics").ns)
  vim.fn.delete(src)
  pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
  pcall(vim.api.nvim_buf_delete, buf, { force = true })
  pcall(vim.cmd, "silent cclose")
end)
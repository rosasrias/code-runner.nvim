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
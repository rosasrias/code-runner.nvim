local diagnostics = require "code-runner.diagnostics"

local CWD = "C:/proy"

local function norm_win(p)
  return vim.fs.normalize(vim.fn.fnamemodify(p, ":p")):gsub("\\", "/")
end

local function read_diag(bufnr)
  return vim.diagnostic.get(bufnr, { namespace = diagnostics.ns }) or {}
end

T.section("diagnostics: canal vim.diagnostic")

T.it("convierte una entrada de quickfix a la forma de vim.diagnostic", function()
  local e = { filename = CWD .. "/a.c", lnum = 3, col = 5, text = "error: x", type = "E" }
  local d = diagnostics._to_diag(e)
  T.eq(2, d.lnum, "base 0")
  T.eq(4, d.col, "base 0")
  T.eq(5, d.end_col, "subraya el token")
  T.eq(vim.diagnostic.severity.ERROR, d.severity)
  T.eq("code-runner", d.source)
end)

T.it("warning usa severidad WARN", function()
  local d = diagnostics._to_diag({ filename = "a.c", lnum = 1, text = "warning: y", type = "W" })
  T.eq(vim.diagnostic.severity.WARN, d.severity)
end)

T.it("entradas sin filename (--- FAIL:) se descartan del canal diagnostic", function()
  T.falsy(diagnostics._to_diag({ text = "--- FAIL: TestX", type = "E" }))
end)

T.it("handle asigna diagnostics por buffer y los limpia en éxit", function()
  local src = vim.fn.tempname() .. ".c"
  local bufnr = vim.fn.bufadd(src)
  vim.fn.writefile({ "int main", "}", "  return x; // error" }, src)

  local entries = {
    { filename = src, lnum = 3, col = 10, text = "error: undeclared 'x'", type = "E" },
    { filename = src, lnum = 1, col = 4, text = "warning: unused", type = "W" },
  }

  diagnostics.handle(entries, 1)
  local list = read_diag(bufnr)
  T.eq(2, #list)
  T.eq("code-runner", list[1].source)

  -- código 0 (éxito) limpia todos los diagnostics del namespace
  diagnostics.handle({}, 0)
  T.eq(0, #read_diag(bufnr))

  vim.fn.delete(src)
  pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
end)

T.it("solo limpia su namespace, no toca otros diagnostics", function()
  local other_ns = vim.api.nvim_create_namespace("otros")
  local src = vim.fn.tempname() .. ".lua"
  local bufnr = vim.fn.bufadd(src)
  vim.fn.writefile({ "local x = 1" }, src)

  vim.diagnostic.set(other_ns, bufnr, { {
    lnum = 0,
    col = 0,
    end_lnum = 0,
    end_col = 1,
    severity = vim.diagnostic.severity.INFO,
    message = "ajeno",
  } })

  diagnostics.handle({}, 0)
  T.eq(1, #vim.diagnostic.get(bufnr, { namespace = other_ns }), "el ajeno sigue")

  vim.fn.delete(src)
  pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
end)

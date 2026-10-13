local tex = require "code-runner.context.tex"

local tmpdir = vim.fn.tempname() .. "/cr_tex_test"
vim.fn.mkdir(tmpdir, "p")

local function write(name, lines)
  local f = tmpdir .. "/" .. name
  vim.fn.writefile(lines, f)
  return f
end

T.section("tex: main_file puro (extracción de detect_main_tex)")

T.it("sin directiva devuelve el actual", function()
  local f = write("plain.tex", { "\\documentclass{article}", "\\begin{document}", "x" })

  T.eq(f, tex.main_file { current = f, lines = vim.fn.readfile(f, "", 15) })
end)

local function same_path(a, b)
  return (a or ""):gsub("\\", "/") == (b or ""):gsub("\\", "/")
end

T.it("resuelve % !TEX root como el legacy", function()
  local f = write("cap.tex", { "% !TEX root = main.tex", "\\section{x}" })
  vim.cmd("edit " .. vim.fn.fnameescape(f))

  local legacy = require("code-runner.actions.latex").detect_main_tex()
  local ours = tex.main_file { current = f, lines = vim.fn.readfile(f, "", 15) }

  T.truthy(same_path(legacy, ours), "misma ruta salvo separadores")
  T.falsy(ours:find("\\", 1, true), "forma canónica forward-slash")
end)

T.it("paridad con espacios raros y subdirectorios", function()
  local f = write("a.tex", { "%!TEX   root=  sub/main.tex" })
  vim.cmd("edit " .. vim.fn.fnameescape(f))

  local legacy = require("code-runner.actions.latex").detect_main_tex()
  local ours = tex.main_file { current = f, lines = vim.fn.readfile(f, "", 15) }

  T.truthy(same_path(legacy, ours))
  T.truthy(ours:find("sub/main%.tex$", 1) ~= nil)
end)

T.it("paridad con .. en la directiva", function()
  vim.fn.mkdir(tmpdir .. "/ch", "p")
  local f = write("ch/cap.tex", { "% !TEX root = ../main.tex" })
  vim.cmd("edit " .. vim.fn.fnameescape(f))

  local legacy = require("code-runner.actions.latex").detect_main_tex()
  local ours = tex.main_file { current = f, lines = vim.fn.readfile(f, "", 15) }

  T.truthy(same_path(legacy, ours))
end)

T.it("sin líneas no hay directiva que buscar", function()
  T.eq("/x/cap.tex", tex.main_file { current = "/x/cap.tex" })
  T.eq("/x/cap.tex", tex.main_file { current = "/x/cap.tex", lines = "no-tabla" })
end)

T.it("normaliza separadores Windows", function()
  local out = tex.main_file { current = "C:\\proj\\cap.tex", lines = { "% !TEX root = main.tex" } }

  T.falsy(out:find("\\", 1, true), "sin backslashes: " .. out)
  T.truthy(out:find("C:/proj/main%.tex$") ~= nil)
end)

T.it("primera directiva manda (como el legacy)", function()
  local out = tex.main_file {
    current = "/x/cap.tex",
    lines = { "% !TEX root = uno.tex", "% !TEX root = dos.tex" },
  }

  T.eq("/x/uno.tex", out)
end)

T.it("current inválido se devuelve tal cual, sin errores", function()
  T.eq(nil, tex.main_file {})
  T.eq("", tex.main_file { current = "" })
end)

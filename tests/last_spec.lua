local last = require "code-runner.last"
local config = require "code-runner.config"

local tmpfile = os.tmpname()
last._data_file = tmpfile

local function fresh()
  pcall(os.remove, tmpfile)
end

T.section("last: persistencia de la última ejecución")

T.it("set guarda y get lee una entrada persistida", function()
  fresh()
  config.options.last_run.persist = true

  last.set { lang = "go", choice = "Run", cwd = "C:/proj" }

  local got = last.get()
  T.truthy(got, "existe la última ejecución")
  T.eq("go", got.lang)
  T.eq("Run", got.choice)
  T.eq("C:/proj", got.cwd)
end)

T.it("get sin archivo devuelve nil", function()
  fresh()
  config.options.last_run.persist = true
  T.eq(nil, last.get(), "sin ejecución previa no hay nada")
end)

T.it("un archivo corrupto devuelve nil sin error", function()
  fresh()
  local f = io.open(tmpfile, "w")
  f:write "{,,, not json}"
  f:close()

  T.eq(nil, last.get())
end)

T.it("persist=false no escribe y get sigue devolviendo nil", function()
  fresh()
  config.options.last_run.persist = false
  last.set { lang = "py" }
  T.eq(nil, last.get(), "no se persiste si está desactivado")
end)

T.it("clear borra la última ejecución persistida", function()
  fresh()
  config.options.last_run.persist = true
  last.set { lang = "java" }
  T.truthy(last.get())

  last.clear()
  T.eq(nil, last.get(), "clear lo borra")
end)
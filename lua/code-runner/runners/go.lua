-- Runner Go: primera migración vertical (paridad, sin retirar legacy).
--
-- Declaración 1:1 de las plantillas vigentes del catálogo (`compiled.lua`
-- go: run/build). Sin guards, sin closures, sin ramas por plataforma: el
-- sufijo `.exe` sale de la variable `$exeSuffix` del adaptador shell, no de
-- código Lua en la declaración.
--
-- Alcance explícito: run + build (lo que el catálogo posee). El test
-- contextual (`go test -run ...`) vive en el sistema de contexto
-- (`context.test_action`) y migra con él, no con este runner. El `test`
-- de `kind=test` NO se declara aquí para no duplicar fuentes.
--
-- Sin cableado productivo todavía: este módulo solo se `require` en tests
-- de paridad. Ni el picker, ni el seed, ni la resolución lo consumen aún
-- (descubrimiento = RUN-003, switch = slice propio con criterios).
-- Los ids coinciden con los que `task.id` deriva hoy de los labels, para
-- que la identidad sobreviva a la migración.
local M = {}

M.spec = {
  id = "go",
  filetypes = { "go" },
  project = { markers = { "go.mod" } },
  tasks = {
    {
      id = "go.run",
      name = "Run",
      kind = "run",
      filetypes = { "go" },
      command = 'go run "%"',
    },
    {
      id = "go.build",
      name = "Build",
      kind = "build",
      filetypes = { "go" },
      command = 'go build -o "$fileBase$exeSuffix"',
    },
  },
}

return M

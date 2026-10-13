-- Resolución pura de candidatos (RUN-002, base).
--
-- Dada una lista de RunnerSpecs declarados y un contexto YA detectado,
-- determina qué runners y tareas son candidatos. Pura: no toca filesystem,
-- no sondea ejecutables, no ejecuta nada.
--
-- Secuencia (ADR-016):
--   1. declarar  RunnerSpec (runner.lua)
--   2. detectar  adaptadores → contexto + disponibilidad (DATOS de entrada)
--   3. resolver  ESTE MÓDULO (candidatos ordenados)
--   4. ejecutar  aplicación + Engine (fases posteriores)
--
-- Entrada:
--   {
--     runners = RunnerSpec[],       -- declarados (validados aquí por índice)
--     context = {                   -- ya detectado, todos opcionales salvo tabla
--       filetype = string|nil,      -- ej. "go"
--       extension = string|nil,     -- ej. "go" (sin punto)
--       project = { root = string|nil, marker = string|nil, kind = string|nil }|nil,
--     },
--     availability = {              -- detectada por adaptadores, inyectada
--       os = "win"|"unix"|nil,      -- plataforma actual
--       tools = { [exe] = true }|nil, -- ejecutables disponibles (conjunto)
--     }|nil,
--   }
--
-- Salida (siempre tabla, nunca nil en éxito):
--   { candidates = { { runner_id = string, score = number, tasks = TaskSpec[] } } }
--   Sin coincidencias → `{ candidates = {} }` (representación explícita, no
--   error ni nil).
--
-- Política ante múltiples candidatos (determinista E inequívoca):
--   - Señales por runner: filetype/extension ∈ filetypes vale 2 puntos;
--     project.marker ∈ markers vale 1 punto. 0 puntos = no candidato (sin
--     señales no hay match: nada de catch-all implícitos).
--   - Cada categoría suma UNA sola vez: filetype y extensión son la misma
--     señal (N coincidencias no multiplican).
--   - Coherencia de formato: se ignora un "." inicial (".go" ≡ "go") en
--     señales de lenguaje, ambos lados; fuera de eso comparación exacta.
--     Los markers comparan exacto siempre (".git" no se toca).
--   - Orden: score descendente, desempate por runner_id ascendente (los ids
--     son minúsculas por contrato: orden total sin equivalencias ocultas),
--     tareas en su orden declarado. Misma entrada → misma salida, siempre.
--   - Tareas: se excluyen con `enabled == false`, con `filetypes` no vacío
--     que no matchea el contexto, o con `when` insatisfecho contra
--     `availability` inyectada (conjunción; sin datos se excluye). (Los
--     RunnerSpec no admiten `condition` ni `command` función: RUN-001 los
--     rechaza; no hay qué evaluar.)
--   - Mismo task id en dos runners: se conservan ambos, cada uno anotado con
--     su runner_id (el picker/desambiguador decide; ocultar sería silencioso).
--
-- Diferido a propósito (no pertenece a esta fase):
--   - registro built-in/runtime y carga perezosa (RUN-002-título/RUN-003).
--
-- Core puro: solo depende de `runner.lua` (+ `task.lua` vía él).
local runner = require "code-runner.runner"

local M = {}

local SCORE_FILETYPE = 2
local SCORE_MARKER = 1

local function has_value(list, value)
  if type(list) ~= "table" or value == nil or value == "" then
    return false
  end

  for _, v in ipairs(list) do
    if v == value then
      return true
    end
  end

  return false
end

-- Señal filetype/extensión con coherencia de formato: se ignora un punto
-- inicial (".go" ≡ "go") en ambos lados; fuera de eso, comparación exacta
-- (mayúsculas no equivalen: los ids y filetypes del contrato son
-- minúsculas). Solo para señales de lenguaje, NUNCA para markers (".git"
-- debe seguir exacto).
local function sig_has(list, value)
  if type(list) ~= "table" or type(value) ~= "string" or value == "" then
    return false
  end

  local want = value:gsub("^%.+", "")

  for _, v in ipairs(list) do
    if type(v) == "string" and v:gsub("^%.+", "") == want then
      return true
    end
  end

  return false
end

-- Puntaje de un runner normalizado contra el contexto. 0 = no candidato.
-- Cada categoría suma UNA sola vez (filetype y extensión son la misma señal;
-- N coincidencias no multiplican).
local function score_runner(rspec, context)
  local score = 0

  if sig_has(rspec.filetypes, context.filetype) or sig_has(rspec.filetypes, context.extension) then
    score = score + SCORE_FILETYPE
  end

  local markers = rspec.project and rspec.project.markers
  local marker = context.project and context.project.marker

  if has_value(markers, marker) then
    score = score + SCORE_MARKER
  end

  return score
end

-- Tareas visibles del runner para el contexto (orden declarado).
-- `enabled` ausente = incluida (default); `false` = exclusión explícita.
-- `when` (ADR-018) se evalúa contra `availability` inyectada, en conjunción:
-- todo lo declarado debe cumplirse. Sin datos para evaluarlo (os/tools
-- ausentes teniendo `when`), la tarea se excluye: explícito, nunca
-- permisividad silenciosa.
local function when_satisfied(when, availability)
  if when == nil then
    return true
  end

  availability = availability or {}

  if when.os ~= nil and availability.os ~= when.os then
    return false
  end

  if when.tools ~= nil then
    local have = availability.tools

    if type(have) ~= "table" then
      return false
    end

    for _, tool in ipairs(when.tools) do
      if not have[tool] then
        return false
      end
    end
  end

  return true
end

local function visible_tasks(rspec, context, availability)
  local out = {}

  for _, t in ipairs(rspec.tasks or {}) do
    if t.enabled ~= false and when_satisfied(t.when, availability) then
      if not t.filetypes or #t.filetypes == 0
        or sig_has(t.filetypes, context.filetype)
        or sig_has(t.filetypes, context.extension)
      then
        out[#out + 1] = t
      end
    end
  end

  return out
end

-- Resuelve candidatos. Devuelve ({ candidates }, nil) o (nil, error) con
-- entrada malformada (incluye el índice del runner inválido).
function M.resolve(input)
  if type(input) ~= "table" then
    return nil, "resolve: entrada debe ser tabla"
  end

  if type(input.runners) ~= "table" then
    return nil, "resolve: 'runners' debe ser tabla"
  end

  if type(input.context) ~= "table" then
    return nil, "resolve: 'context' debe ser tabla"
  end

  local context = input.context
  local availability = input.availability
  local candidates = {}

  for i, rspec in ipairs(input.runners) do
    local err = runner.validate(rspec)

    if err then
      return nil, "resolve: runners[" .. i .. "] inválido: " .. err
    end

    local score = score_runner(rspec, context)

    if score > 0 then
      candidates[#candidates + 1] = {
        runner_id = rspec.id,
        score = score,
        tasks = visible_tasks(rspec, context, availability),
      }
    end
  end

  table.sort(candidates, function(a, b)
    if a.score ~= b.score then
      return a.score > b.score
    end

    return a.runner_id < b.runner_id
  end)

  return { candidates = candidates }, nil
end

return M

-- Output streaming normalizado (EXEC-003).
--
-- Los jobs (termopen/jobstart) entregan chunks arbitrarios por stdout/stderr:
-- una línea puede venir partida entre dos chunks, y ambas salidas se mezclan.
-- Este módulo (Core puro) normaliza eso a:
--
--   - líneas completas EN ORDEN (conservando el canal "stdout"|"stderr"),
--   - sin partir líneas por el límite arbitrario de los chunks,
--   - output final { stdout, stderr } listo para un Result (CONTRACTS §7).
--
-- No depende de vim ni del adapter: recibe feed("stdout"|"stderr", chunk).
-- El adapter de procesos (EXEC-002) y el terminal (EXEC-009) lo alimentarán.
local M = {}

-- Crea un collector de streaming.
--   opts.on_line = fn({ channel, line })   -- cada línea completa, en orden
--   opts.on_stdout = fn(chunk)             -- cada chunk crudo de stdout
--   opts.on_stderr = fn(chunk)             -- cada chunk crudo de stderr
function M.new(opts)
  opts = opts or {}

  local collector = {
    _opts = opts,
    _lines = {}, -- { { channel, line } } en orden de llegada (líneas completas)
    _pending = { stdout = "", stderr = "" }, -- partial line por canal
    _chunks = { stdout = 0, stderr = 0 },
    _bytes = { stdout = 0, stderr = 0 },
  }

  -- Recibe un chunk de un canal. Normaliza a líneas completas.
  function collector:feed(channel, chunk)
    if channel ~= "stdout" and channel ~= "stderr" then
      return false, "canal inválido: " .. tostring(channel)
    end

    if type(chunk) ~= "string" then
      return false, "chunk debe ser string"
    end

    self._chunks[channel] = self._chunks[channel] + 1
    self._bytes[channel] = self._bytes[channel] + #chunk

    if self._opts.on_stdout and channel == "stdout" then
      self._opts.on_stdout(chunk)
    end

    if self._opts.on_stderr and channel == "stderr" then
      self._opts.on_stderr(chunk)
    end

    -- Junta con la partial de su canal (una línea partida entre chunks).
    local text = self._pending[channel] .. chunk
    self._pending[channel] = ""

    local start = 1

    while true do
      local nl = text:find("\n", start, true)

      if not nl then
        -- Lo que queda es una partial line: queda pendiente para el próximo.
        self._pending[channel] = text:sub(start)
        break
      end

      local line = text:sub(start, nl - 1)
      self._lines[#self._lines + 1] = { channel = channel, line = line }

      if self._opts.on_line then
        self._opts.on_line({ channel = channel, line = line })
      end

      start = nl + 1
    end

    return true, nil
  end

  -- Líneas completas emitidas hasta ahora (copia).
  function collector:lines()
    local out = {}

    for i, l in ipairs(self._lines) do
      out[i] = { channel = l.channel, line = l.line }
    end

    return out
  end

  -- Conteo de líneas completas.
  function collector:line_count()
    return #self._lines
  end

  -- Stats de chunks y bytes por canal.
  function collector:stats()
    return {
      chunks = { stdout = self._chunks.stdout, stderr = self._chunks.stderr },
      bytes = { stdout = self._bytes.stdout, stderr = self._bytes.stderr },
    }
  end

  -- Output final listo para un Result (CONTRACTS §7): stdout/stderr únicos,
  -- sin \n final (las líneas no se tragan el delimitador). Si un canal no
  -- recibió nada, ese campo es nil (como el contrato).
  function collector:output()
    local function join(channel)
      if self._bytes[channel] == 0 and self._pending[channel] == "" then
        return nil
      end

      local parts = {}

      for _, l in ipairs(self._lines) do
        if l.channel == channel then
          parts[#parts + 1] = l.line
        end
      end

      if self._pending[channel] ~= "" then
        parts[#parts + 1] = self._pending[channel]
      end

      return table.concat(parts, "\n")
    end

    return {
      stdout = join "stdout",
      stderr = join "stderr",
    }
  end

  -- Limpia todo el estado (reutilizar collector en otro run).
  function collector:reset()
    self._lines = {}
    self._pending = { stdout = "", stderr = "" }
    self._chunks = { stdout = 0, stderr = 0 }
    self._bytes = { stdout = 0, stderr = 0 }
    return true
  end

  return collector
end

return M
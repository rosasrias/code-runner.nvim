-- Adaptador headless del contrato `process` (EXEC-009 slice 6).
--
-- Implementa `spawn/send/terminate` (CONTRACTS §19) sobre `jobstart`: el
-- mecanismo para procesos sin PTY que el workflow necesita (captura el exit
-- sin abrir terminal visible). El workflow orquesta pasos; el Engine posee
-- el ciclo de vida; este módulo solo habla con el proceso.
--
-- Responde a la misma forma que el puerto, verificable con
-- `process.validate_adapter(M)`: es intercambiable a nivel de contrato.
-- No se instala globalmente: el puerto lo ocupa el PTY interactivo y este
-- slice no crea un registro de adaptadores (ver decisión en TODO slice 6);
-- el workflow lo usa directamente.
--
-- Límites explícitos (no son fallos del contrato):
--   - `on_stdout`/`on_stderr` reciben las líneas bufferizadas de jobstart
--     (listas, no chunks). El workflow actual las ignora; quedan disponibles.
--   - `on_exit(code, signal)` recibe `signal = nil`: jobstart no entrega
--     señal. `result_handler` clasifica solo con code (suficiente).
--
-- Capa Adapter: puede usar APIs de Neovim.
local M = {}

function M.spawn(opts)
  if type(opts) ~= "table" then
    return nil, "headless.spawn: opts debe ser tabla"
  end

  if type(opts.cmd) ~= "table" or #opts.cmd == 0 then
    return nil, "headless.spawn: opts.cmd debe ser string[] no vacío"
  end

  local job_opts = {
    on_stdout = opts.on_stdout and function(_, data)
      opts.on_stdout(data)
    end or nil,
    on_stderr = opts.on_stderr and function(_, data)
      opts.on_stderr(data)
    end or nil,
    on_exit = function(_, code)
      if type(opts.on_exit) == "function" then
        opts.on_exit(code, nil)
      end
    end,
  }

  if opts.cwd ~= nil then
    job_opts.cwd = opts.cwd
  end

  local ok_call, job = pcall(vim.fn.jobstart, opts.cmd, job_opts)

  -- jobstart devuelve 0 o -1 al fallar (y LANZA E475 con cwd inválido).
  -- Antes el on_exit nunca llegaba y `run` esperaba para siempre.
  if not ok_call or type(job) ~= "number" or job <= 0 then
    return nil, "headless.spawn: jobstart falló (" .. tostring(job) .. ")"
  end

  return { job = job }, nil
end

function M.send(handle, data)
  if type(handle) ~= "table" or type(handle.job) ~= "number" then
    return false, "headless.send: handle inválido"
  end

  local ok, n = pcall(vim.fn.chansend, handle.job, data)

  if ok and type(n) == "number" and n > 0 then
    return true
  end

  return false, "headless.send: chansend no aceptó los datos"
end

function M.terminate(handle)
  if type(handle) ~= "table" or type(handle.job) ~= "number" then
    return false, "headless.terminate: handle inválido"
  end

  local ok, res = pcall(vim.fn.jobstop, handle.job)

  if ok and res == 1 then
    return true
  end

  return false, "headless.terminate: jobstop falló"
end

return M

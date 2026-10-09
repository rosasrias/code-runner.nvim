-- Adaptador PTY del puerto `process` (EXEC-009 slice 5).
--
-- Implementa el contrato `spawn/send/terminate` (CONTRACTS §19) sobre
-- `termopen`: el mecanismo concreto de PTY interactivo que la terminal
-- necesita (scrollback, colores, input). El contrato queda separado del
-- mecanismo: `terminal.open` lanza por el puerto, este módulo decide CÓMO.
--
-- Límites explícitos del PTY (no son fallos del contrato):
--   - `on_stdout`/`on_stderr` nunca se invocan: termopen vuelca la salida
--     mezclada al propio buffer (así la ve el usuario). El Result sale del
--     exit code, como antes.
--   - `on_exit(code, signal)` recibe `signal = nil`: termopen no entrega
--     señal. `result_handler` clasifica solo con code (suficiente).
--   - `opts.buf` (buffer ya preparado por `terminal.open`) es OBLIGATORIO:
--     el PTY vive en ese buffer y termopen exige el buffer actual.
--
-- Capa Adapter: puede usar APIs de Neovim. Core no depende de este módulo;
-- `terminal.lua` lo instala de forma perezosa si el puerto no tiene adapter.
local process = require "code-runner.process"

local M = {}

function M.spawn(opts)
  if type(opts) ~= "table" then
    return nil, "pty.spawn: opts debe ser tabla"
  end

  local buf = opts.buf

  if type(buf) ~= "number" or not vim.api.nvim_buf_is_valid(buf) then
    return nil, "pty.spawn: opts.buf debe ser un buffer válido"
  end

  -- termopen corre sobre el buffer actual: la terminal ya lo dejó enfocado.
  local ok_buf = pcall(vim.api.nvim_set_current_buf, buf)

  if not ok_buf then
    return nil, "pty.spawn: no se pudo enfocar el buffer del PTY"
  end

  local term_opts = {}

  if opts.cwd ~= nil then
    term_opts.cwd = opts.cwd
  end

  term_opts.on_exit = function(_, code)
    if type(opts.on_exit) == "function" then
      opts.on_exit(code, nil)
    end
  end

  local ok_call, job = pcall(vim.fn.termopen, opts.cmd, term_opts)

  -- termopen devuelve 0 o -1 al fallar (y puede lanzar con cwd inválido).
  -- El path legacy solo miraba -1.
  if not ok_call or type(job) ~= "number" or job <= 0 then
    return nil, "pty.spawn: termopen falló (" .. tostring(job) .. ")"
  end

  return { job = job, buf = buf }, nil
end

function M.send(handle, data)
  if type(handle) ~= "table" or type(handle.job) ~= "number" then
    return false, "pty.send: handle inválido"
  end

  local ok, n = pcall(vim.fn.chansend, handle.job, data)

  if ok and type(n) == "number" and n > 0 then
    return true
  end

  return false, "pty.send: chansend no aceptó los datos"
end

function M.terminate(handle)
  if type(handle) ~= "table" or type(handle.job) ~= "number" then
    return false, "pty.terminate: handle inválido"
  end

  local ok, res = pcall(vim.fn.jobstop, handle.job)

  if ok and res == 1 then
    return true
  end

  return false, "pty.terminate: jobstop falló"
end

-- Instala este adapter en el puerto. Devuelve nil o string de error.
function M.install()
  return process.set_adapter(M)
end

-- Lanza un job PTY por el puerto (`terminal.open` decide QUÉ; aquí el CÓMO).
-- Instala el adapter perezosamente si el puerto no tiene uno (un mock
-- inyectado se respeta tal cual). `opts = { cmd, cwd|nil, buf, on_exit }`.
-- Devuelve (handle, nil) o (nil, err).
function M.launch(cmd, opts)
  opts = opts or {}

  if not process.valid() then
    M.install()
  end

  return process.spawn {
    cmd = cmd,
    cwd = opts.cwd,
    buf = opts.buf,
    on_exit = opts.on_exit,
  }
end

return M

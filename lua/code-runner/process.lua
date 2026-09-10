-- Process port: interfaz para spawn/send/terminate (CONTRACTS §19).
--
-- Core puro: no depende de vim.fn.jobstart, vim.system ni termopen. Estos
-- viven en el adapter concreto que se inyecta (Neovim adapter, EXEC-002);
-- el resto de la aplicación solo usa este módulo.
--
-- Puerto inyectable:
--   adapter.spawn(opts)        -> handle (tabla/opaca, el adapter decide)
--   adapter.send(handle, data) -> boolean
--   adapter.terminate(handle)  -> boolean
--
-- opts para spawn:
--   cmd      string[]  comando + args (ej. {"go","run","."})
--   cwd      string|nil
--   env      table<string,string>|nil
--   on_stdout  fn(data:string)  línea/bloque de stdout
--   on_stderr  fn(data:string)  línea/bloque de stderr
--   on_exit    fn(code:integer, signal:integer)  terminación del proceso
local M = {}

local adapter = nil

-- Valida que un adapter tenga la forma requerida. Devuelve nil o string de error.
function M.validate_adapter(a)
  if type(a) ~= "table" then
    return "adapter debe ser una tabla"
  end

  if type(a.spawn) ~= "function" then
    return "adapter falta 'spawn'"
  end

  if type(a.send) ~= "function" then
    return "adapter falta 'send'"
  end

  if type(a.terminate) ~= "function" then
    return "adapter falta 'terminate'"
  end

  return nil
end

-- True si el adapter actual es válido.
function M.valid()
  return M.validate_adapter(adapter) == nil
end

-- Inyecta el adapter de procesos. nil desactiva. Devuelve nil o string de error.
function M.set_adapter(a)
  if a == nil then
    adapter = nil
    return nil
  end

  local err = M.validate_adapter(a)

  if err then
    return err
  end

  adapter = a
  return nil
end

-- Devuelve el adapter actual (o nil).
function M.get_adapter()
  return adapter
end

-- Spawn delega al adapter. Requiere adapter seteado y opts válidos.
-- Devuelve (handle, nil) o (nil, error).
function M.spawn(opts)
  if not adapter then
    return nil, "process: no hay adapter inyectado (set_adapter)"
  end

  if type(opts) ~= "table" then
    return nil, "process: spawn requiere opts tabla"
  end

  if type(opts.cmd) ~= "table" or #opts.cmd == 0 then
    return nil, "process: opts.cmd debe ser string[] no vacío"
  end

  for i, v in ipairs(opts.cmd) do
    if type(v) ~= "string" then
      return nil, "process: opts.cmd[" .. i .. "] debe ser string"
    end
  end

  if opts.cwd ~= nil and type(opts.cwd) ~= "string" then
    return nil, "process: opts.cwd debe ser string o nil"
  end

  if opts.on_stdout ~= nil and type(opts.on_stdout) ~= "function" then
    return nil, "process: opts.on_stdout debe ser función o nil"
  end

  if opts.on_stderr ~= nil and type(opts.on_stderr) ~= "function" then
    return nil, "process: opts.on_stderr debe ser función o nil"
  end

  if opts.on_exit ~= nil and type(opts.on_exit) ~= "function" then
    return nil, "process: opts.on_exit debe ser función o nil"
  end

  local handle, herr = adapter.spawn(opts)

  if not handle then
    return nil, "process: spawn falló: " .. tostring(herr)
  end

  return handle, nil
end

-- Send datos al proceso (stdin). Delega al adapter.
function M.send(handle, data)
  if not adapter then
    return false, "process: no hay adapter"
  end

  if not handle then
    return false, "process: handle inválido"
  end

  return adapter.send(handle, data)
end

-- Terminate el proceso. Delega al adapter.
function M.terminate(handle)
  if not adapter then
    return false, "process: no hay adapter"
  end

  if not handle then
    return false, "process: handle inválido"
  end

  return adapter.terminate(handle)
end

return M
-- Canal de errores alternativo a la quickfix: vuelca las entradas parseadas de
-- build/test a `vim.diagnostic` (signos en el búfer) bajo un namespace propio.
-- Se activa con `quickfix.style = "diagnostic"` o `"both"` en la config.
local M = {}

-- Namespace dedicado: solo limpiamos lo nuestro, nunca tocamos los
-- diagnostics de otros plugins (nvim-lint, lsp, etc.).
M.ns = vim.api.nvim_create_namespace("code-runner")

local SEVERITY = vim.diagnostic.severity

-- Convierte una entrada de quickfix.parse (filename/lnum/col/text/type) a la
-- forma de vim.diagnostic (lnum/col en base 0). Entradas sin filename (p.ej.
-- "--- FAIL:") no tienen búfer destino → se descartan aquí.
function M._to_diag(e)
  if not e.filename then
    return nil
  end

  local d = {
    lnum = math.max((e.lnum or 1) - 1, 0),
    col = math.max((e.col or 1) - 1, 0),
    severity = e.type == "W" and SEVERITY.WARN or SEVERITY.ERROR,
    message = e.text or "",
    source = "code-runner",
  }

  -- Con columna su subrayado es el token exacto; sin columna igual marcamos
  -- la línea completa.
  d.end_lnum = d.lnum
  d.end_col = e.col and d.col + 1 or 0

  return d
end

-- Asigna/limpia los diagnostics del plugin. `code` es el exit del job:
-- con código 0 no quedan errores y se limpia todo (los warnings se mantienen
-- si se parsearon, igual que la quickfix refresca la lista en ese caso).
function M.handle(entries, code)
  vim.diagnostic.reset(M.ns)

  if code ~= 0 then
    local by_buf = {}

    for _, e in ipairs(entries) do
      local d = M._to_diag(e)
      if d then
        local bufnr = vim.fn.bufadd(e.filename)
        by_buf[bufnr] = by_buf[bufnr] or {}
        table.insert(by_buf[bufnr], d)
      end
    end

    for bufnr, list in pairs(by_buf) do
      vim.diagnostic.set(M.ns, bufnr, list)
    end
  end
end

return M

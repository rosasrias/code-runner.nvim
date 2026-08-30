-- Mini framework de tests sin dependencias externas
local M = { passed = 0, failed = 0, skipped = 0 }

function M.section(name)
  print("\n" .. name)
  print(string.rep("─", math.max(#name + 4, 30)))
end

function M.it(name, fn)
  local ok, err = pcall(fn)

  if ok then
    M.passed = M.passed + 1
    print("  [PASS] " .. name)
  else
    M.failed = M.failed + 1
    print("  [FAIL] " .. name)
    print("         " .. tostring(err):gsub("\n", "\n         "))
  end
end

function M.skip(name, reason)
  M.skipped = M.skipped + 1
  print("  [SKIP] " .. name .. (reason and (" — " .. reason) or ""))
end

function M.eq(expected, actual, msg)
  if expected ~= actual then
    error(
      (msg or "eq falló") .. "\n           esperado: " .. vim.inspect(expected) .. "\n           obtenido: "
        .. vim.inspect(actual),
      2
    )
  end
end

function M.truthy(value, msg)
  if not value then
    error(msg or "se esperaba un valor truthy", 2)
  end
end

function M.falsy(value, msg)
  if value then
    error(msg or "se esperaba un valor falsy, obtuve: " .. vim.inspect(value), 2)
  end
end

function M.contains(haystack, needle, msg)
  if type(haystack) ~= "string" or not haystack:find(needle, 1, true) then
    error((msg or "contains falló") .. ": '" .. needle .. "' no está en:\n           " .. vim.inspect(haystack), 2)
  end
end

function M.summary()
  print("\n" .. string.rep("═", 40))
  print(("Resultado: %d pass · %d fail · %d skip"):format(M.passed, M.failed, M.skipped))
  print(string.rep("═", 40))

  if M.failed > 0 then
    os.exit(1)
  end
end

return M

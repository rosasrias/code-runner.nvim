-- Presets de perfiles (P1): variantes Release/Benchmark para los lenguajes
-- donde la herramienta tiene un modo real. Feature opt-in (`profiles.enabled`,
-- por defecto false) para no ensuciar el picker del zero-config.
--
-- NO es un motor genérico de perfiles: solo presets concretos por lenguaje,
-- al nivel del catálogo (el usuario y el action registry pueden sobrescribirlos).
local M = {}

-- Acciones extra por lenguaje/`key`, o nil si ese lenguaje no tiene presets.
--   env = { RUN, BUILD, shell }
function M.for_lang(env, key)
  local RUN, BUILD, shell = env.RUN, env.BUILD, env.shell

  if key == "rust" then
    -- cargo tiene modos build/run y un release real con optimización.
    return {
      [BUILD .. " Build (release)"] = "cargo build --release",
      [RUN .. " Run (release)"] = "cargo run --release",
    }
  elseif key == "go" then
    -- go test tiene benchmarks nativos (-bench): el único "perfil" con
    -- significado real para Go sin caer en flags de release arbitrarios.
    return {
      [RUN .. " Test (benchmark)"] = "go test -bench . -benchmem",
    }
  elseif key == "c" or key == "cpp" then
    -- Release de C/C++ = compilar con optimización (-O2), igualando la
    -- plantilla nativa (compile / compile & run) pero con el flag de release.
    local cc = key == "c" and "gcc" or "g++"
    local compile = cc .. ' -O2 "%" -o "$fileBase' .. shell.EXE_SUFFIX .. '"'
    local run = "$binRun"
    return {
      [BUILD .. " Compile (release)"] = compile,
      [RUN .. BUILD .. " Compile & Run (release)"] = compile .. " && " .. run,
    }
  end

  return nil
end

return M

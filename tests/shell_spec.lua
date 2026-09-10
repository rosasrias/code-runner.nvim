local shell = require "code-runner.shell"

-- Compara rutas normalizando separadores (expand puede devolver \ en Windows
-- aunque el fixture se construyó con /).
local function slashes(p)
  return (p or ""):gsub("\\", "/")
end

local function norm(p)
  return slashes(vim.fs.normalize(p))
end

T.section("shell: substitute()")

-- Contexto: buffer con ruta que contiene espacios
local tmpdir = vim.fn.tempname()
vim.fn.mkdir(tmpdir, "p")
local file = tmpdir .. "/mi programa.lua"
vim.fn.writefile({ "-- test", "print(1)" }, file)
vim.cmd("edit " .. vim.fn.fnameescape(file))

T.it("% expande a la ruta completa del archivo", function()
  T.eq(norm(file), norm(shell.substitute("%")))
end)

T.it("$fileBase expande a ruta sin extensión", function()
  T.eq(norm(tmpdir .. "/mi programa"), norm(shell.substitute("$fileBase")))
end)

T.it("$filePath y $dir expanden correctamente", function()
  T.eq(norm(file), norm(shell.substitute("$filePath")))
  T.eq(norm(tmpdir), norm(shell.substitute("$dir")))
end)

T.it("precedencia: $filePath no es cortado por $file", function()
  T.eq(slashes(file .. " " .. file), slashes(shell.substitute("$filePath $file")))
end)

T.it("tokens desconocidos se preservan ($PATH)", function()
  T.eq('"$PATH"', shell.substitute('"$PATH"'))
end)

T.it("plantilla gcc con espacios en ruta", function()
  local out = shell.substitute('gcc "%" -o "$fileBase' .. shell.EXE_SUFFIX .. '"')
  T.contains(slashes(out), '"' .. slashes(file) .. '"', "fuente entre comillas")
  T.contains(slashes(out), '"' .. slashes(tmpdir .. "/mi programa") .. shell.EXE_SUFFIX .. '"', "salida entre comillas")
end)

T.it("$altFile expande al alternate file", function()
  local other = tmpdir .. "/otro archivo.lua"
  vim.fn.writefile({ "-- alt" }, other)
  -- editar A luego B deja A como alternate desde B
  vim.cmd("edit " .. vim.fn.fnameescape(file))
  vim.cmd("edit " .. vim.fn.fnameescape(other))
  T.eq(norm(file), norm(shell.substitute("$altFile")))
  vim.cmd("edit " .. vim.fn.fnameescape(file))
end)

T.section("shell: wrap_command()")

local IS_WIN_BACKUP = shell.IS_WIN

T.it("Windows: envuelve en powershell -Command", function()
  shell.IS_WIN = true
  local argv = shell.wrap_command "echo hola"
  T.eq("powershell", argv[1])
  T.eq("-Command", argv[#argv - 1])
  T.eq("echo hola", argv[#argv])
end)

T.it("un && produce if ($?)", function()
  shell.IS_WIN = true
  local argv = shell.wrap_command("a && b")
  T.contains(argv[#argv], "; if ($?) { b }")
  T.falsy(argv[#argv]:find("&&", 1, true), "no debe quedar && sin convertir")
end)

T.it("múltiples && se anidan en orden correcto", function()
  shell.IS_WIN = true
  local argv = shell.wrap_command("javac x.java && java X && echo fin")
  T.eq(
    "javac x.java; if ($?) { java X; if ($?) { echo fin } }",
    argv[#argv],
    "encadenamiento anidado exacto"
  )
end)

T.it("sin && pasa intacto", function()
  shell.IS_WIN = true
  T.eq("solo esto", shell.wrap_command("solo esto")[#shell.wrap_command "solo esto"])
end)

T.it("Unix: bash -lc y sin transformaciones", function()
  shell.IS_WIN = false
  local argv = shell.wrap_command("gcc x.c -o x && ./x")
  T.eq("bash", argv[1])
  T.eq("-lc", argv[2])
  T.contains(argv[3], "&&", "bash mantiene && nativo")
end)

T.it("quoted_run usa & en Windows (bug de PowerShell)", function()
  shell.IS_WIN = true
  T.eq('& ".\\prog.exe"', shell.quoted_run(".\\prog.exe"))
  shell.IS_WIN = false
  T.eq('"./prog"', shell.quoted_run("./prog"))
  shell.IS_WIN = IS_WIN_BACKUP
end)

T.it("&& literal dentro de comillas no se convierte (no rompe strings)", function()
  shell.IS_WIN = true
  local argv = shell.wrap_command('echo "a && b"')
  T.eq('echo "a && b"', argv[#argv], "&& dentro de \"...\" queda intacto")
end)

T.it("&& dentro de comillas simples tampoco se convierte", function()
  shell.IS_WIN = true
  local argv = shell.wrap_command("echo 'a && b'x")
  T.eq("echo 'a && b'x", argv[#argv])
end)

T.it("mezcla: && fuera convierte, dentro de comillas no", function()
  shell.IS_WIN = true
  local argv = shell.wrap_command('set MSG="a && b" && echo %MSG%')
  local out = argv[#argv]
  T.contains(out, "; if ($?) { echo %MSG% }", "el && real se convierte")
  T.contains(out, '"a && b"', "el && literal del valor queda")
end)

T.section("shell: bin_run()")

-- Fixture con archivo DENTRO del cwd => %:r es relativo
local function with_relative_buffer(callback)
  local reldir = "cr_rel_fixture"
  vim.fn.mkdir(reldir, "p")
  local rel_path = reldir .. "/prog.lua"
  vim.fn.writefile({ "-- x" }, rel_path)
  -- editar con RUTA RELATIVA para que % sea relativa (como al abrir del proyecto)
  vim.cmd("edit " .. vim.fn.fnameescape(rel_path))

  local ok, err = pcall(function()
    T.truthy(vim.fn.expand "%:r":match "^cr_rel_fixture", "precondición: %:r relativo")
    callback()
  end)

  shell.IS_WIN = IS_WIN_BACKUP
  vim.cmd("edit " .. vim.fn.fnameescape(file))
  vim.fn.delete(rel_path)
  vim.fn.delete(reldir, "d")

  if not ok then
    error(err, 0)
  end
end

-- Fixture con archivo FUERA del cwd => %:r es absoluto
local function with_absolute_buffer(callback)
  local subdir = tmpdir .. "/sub_abs"
  vim.fn.mkdir(subdir, "p")
  local f = subdir .. "/prog.lua"
  vim.fn.writefile({ "-- x" }, f)
  vim.cmd("edit " .. vim.fn.fnameescape(f))

  local ok, err = pcall(function()
    local base = vim.fn.expand "%:r"
    local is_rel = base:match "^cr_rel_fixture" ~= nil
    local is_abs = base:match "^%a:[/\\]" ~= nil or base:sub(1, 1) == "/"
    T.truthy(not is_rel and is_abs, "precondición: %:r absoluto")
    callback()
  end)

  shell.IS_WIN = IS_WIN_BACKUP
  vim.cmd("edit " .. vim.fn.fnameescape(file))

  if not ok then
    error(err, 0)
  end
end

T.it("$binRun relativo lleva el prefijo del ejecutable según plataforma", function()
  with_relative_buffer(function()
    -- Fix cwd: $binRun ahora es siempre absoluto (%:p:r) para no romper
    -- cuando vim se abre desde carpeta padre (01_data_types/main.c con cwd=01_data_types)
    local base = vim.fn.expand "%:p:r"

    shell.IS_WIN = true
    T.eq(norm('& "' .. base .. shell.EXE_SUFFIX .. '"'), norm(shell.substitute("$binRun")), "windows absoluto sin prefijo")

    shell.IS_WIN = false
    T.eq(norm('"' .. base .. shell.EXE_SUFFIX .. '"'), norm(shell.substitute("$binRun")), "unix absoluto sin prefijo")

    shell.IS_WIN = IS_WIN_BACKUP
  end)
end)

T.it("$binRun con ruta absoluta no duplica prefijo", function()
  with_absolute_buffer(function()
    local base = vim.fn.expand "%:p:r"

    shell.IS_WIN = true
    T.eq(norm('& "' .. base .. '.exe"'), norm(shell.substitute("$binRun")), "windows sin .\\")

    -- En una máquina Unix EXE_SUFFIX sería "", aquí solo verificamos
    -- que NO se añade prefijo a una ruta absoluta
    shell.IS_WIN = false
    local out = shell.substitute("$binRun")
    T.contains(norm(out), norm(base), "usa la ruta absoluta tal cual")
    T.falsy(norm(out):find('"./', 1, true), "sin ./ delante de ruta absoluta")
    T.falsy(norm(out):find('"\\.\\', 1, true), "sin .\\ delante de ruta absoluta")

    shell.IS_WIN = IS_WIN_BACKUP
  end)
end)

T.section("shell: E2E del pipeline con comando real")

T.it("substitute + wrap_command ejecuta y produce salida correcta", function()
  local marker = "CODE_RUNNER_E2E_OK_" .. os.time()
  local script = tmpdir .. "/e2e.ps1"
  vim.fn.writefile({ 'Write-Output "' .. marker .. '"' }, script)
  vim.cmd("edit " .. vim.fn.fnameescape(script))

  -- simula la acción ps1: pwsh/powershell -File "%"
  local exe = vim.fn.executable "pwsh" == 1 and "pwsh" or "powershell"
  local cmd = shell.substitute(exe .. ' -NoLogo -NoProfile -File "%"')
  local out = vim.fn.system(shell.wrap_command(cmd))

  T.eq(0, vim.v.shell_error, "código de salida 0")
  T.contains(out, marker)
end)

T.section("shell: use_wrappers() Maven/Gradle Wrapper")

local wdir = vim.fn.tempname()
vim.fn.mkdir(wdir, "p")

T.it("sin wrapper en el cwd devuelve el comando intacto", function()
  shell.IS_WIN = IS_WIN_BACKUP
  T.eq("mvn -q clean package", shell.use_wrappers("mvn -q clean package", wdir))
  T.eq("gradle build", shell.use_wrappers("gradle build", wdir))
end)

T.it("no es mvn/gradle: intacto aunque exista mvnw", function()
  vim.fn.writefile({ "@echo off" }, wdir .. "/mvnw.cmd")
  T.eq("go test", shell.use_wrappers("go test", wdir))
end)

T.it("Unix con ./mvnw: mvn → ./mvnw", function()
  vim.fn.writefile({ "#!/bin/sh" }, wdir .. "/mvnw")
  shell.IS_WIN = false
  T.eq("./mvnw -q clean package", shell.use_wrappers("mvn -q clean package", wdir))
  shell.IS_WIN = IS_WIN_BACKUP
end)

T.it("Windows con mvnw.cmd: mvn → .\\mvnw.cmd", function()
  vim.fn.writefile({ "@echo off" }, wdir .. "/mvnw.cmd")
  shell.IS_WIN = true
  T.eq(".\\mvnw.cmd -q clean package", shell.use_wrappers("mvn -q clean package", wdir))
  shell.IS_WIN = IS_WIN_BACKUP
end)

T.it("gradlew: gradle → .\\gradlew.bat en Windows", function()
  vim.fn.writefile({ "@echo off" }, wdir .. "/gradlew.bat")
  shell.IS_WIN = true
  T.eq(".\\gradlew.bat build", shell.use_wrappers("gradle build", wdir))
  shell.IS_WIN = IS_WIN_BACKUP
end)

T.it("otro cwd sin wrappers devuelve intacto (solo mira en el cwd dado)", function()
  -- "other" es un dir aparte: aunque wdir tenga mvnw.cmd, aquí no aplica
  local other = vim.fn.tempname()
  vim.fn.mkdir(other, "p")
  shell.IS_WIN = true
  T.eq("mvn clean", shell.use_wrappers("mvn clean", other))
  T.eq("gradle build", shell.use_wrappers("gradle build", other))
  shell.IS_WIN = IS_WIN_BACKUP
end)

T.it("cwd vacío/nil no rompe y no sustituye", function()
  T.eq("mvn test", shell.use_wrappers("mvn test", nil))
  T.eq("mvn test", shell.use_wrappers("mvn test", ""))
  T.eq("mvn test", shell.use_wrappers("mvn test"))
end)

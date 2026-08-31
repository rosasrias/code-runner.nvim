# AGENTS.md — reglas para agentes que trabajan en code-runner.nvim

- **Leer `.opencode/README.md` antes de trabajar** (y ROADMAP/ARCHITECTURE/
  CHANGELOG/TODO cuando aplique). Es el contexto persistente del proyecto.
- **No hacer big-bang rewrites.** Una unidad de trabajo por sesión; cada
  refactor deja el proyecto funcionando.
- **Ejecutar la suite después de cualquier cambio**:
  `nvim --headless -l tests/run.lua`. Debe quedar verde. No eliminar tests
  para solucionar fallos: los tests son el contrato.
- **Multiplataforma siempre**: Windows/Linux/macOS. PowerShell/cmd y bash,
  `.exe`, rutas con espacios, quoting, UTF-8. No asumir comportamiento POSIX.
- **No romper la API existente sin migración.** API pública pequeña y estable.
- **Actualizar documentación** después de cambios arquitectónicos
  (`.opencode/*`, README cuando corresponda) y marcar el ROADMAP/TODO.
- **Priorizar simple > clever, estable > experimental, test > confianza.**
- **Mantener archivos <= ~300 líneas.** Si uno crece, modularizar por
  responsabilidad (`actions/`, `context/`, `terminal/`...), no por decoración.
- No agregar lenguajes al catálogo sin demanda real, mantenibilidad y tests.
- No introducir MCPs/agentes externos/servidores infra innecesaria.
- No convertir esto en Overseer: sigue siendo un code-runner zero-config.
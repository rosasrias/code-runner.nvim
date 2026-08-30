# ⚡ code-runner.nvim — contexto persistente

> Primera lectura obligatoria de cualquier agente antes de tocar código.

## Propósito

`code-runner.nvim` es un **code runner zero-config para Neovim**: `Ctrl-b` y
obtener una acción útil sin configurar nada, con detección inteligente de
proyecto y contexto, y un pequeño task engine extensible detrás.

> **No** debe convertirse en otro Overseer. Se diferencia por la cadena:
> `archivo → filetype → proyecto → contexto → test/main → acción inteligente → ejecución`.

## Filosofía

- Zero-config > configuración obligatoria.
- Simple > clever. Estable > experimental. Componible > monolítico.
- API pequeña > API gigante. Tests > confianza.
- **No romper lo que funciona.** No hacer big-bang rewrites. Migrar de forma
  incremental, una unidad de trabajo por sesión.
- `simple > clever` también significa: no inventar parsers de shell completos;
  preferir estructuras de comandos cuando el string no sea suficiente.
- Multiplataforma real (Windows/Linux/macOS): PowerShell/cmd y bash, `.exe`,
  quoting de rutas con espacios, UTF-8. No asumir comportamiento POSIX.

## Estado del proyecto

- **No hay versión taggeada.** Última feature importante: quickfix que se
  cierra sola con éxito (`33ec363`). En `main`, 136 tests verdes, CI 3 OS.
- El plugin **funciona end-to-end** hoy: picker (volt/fallback), 60+
  lenguajes, Java smart run + Maven auto, contexto (tests + entry main),
  project root, terminal identificada con título/estado, quickfix, historial
  persistente, variables de contexto, autosave.
- Camino hacia V1.0 sin resolver aún: estado central/stop/restart, run-last
  robusto, revisar `shell.lua`, cache de contexto, cleanup de temporales Java,
  action registry, `.code-runner.lua`, profiles, diagnostics, checkhealth,
  events (ver `.opencode/ROADMAP.md`).

## Arquitectura (resumen)

Estructura **plana** en `lua/code-runner/` (aún no hay subcarpetas):

| Módulo | Responsabilidad |
| --- | --- |
| `init.lua` | Orquestación: `setup`, `build_run` (picker), `run_last`, `run_history`, `state` |
| `state.lua` | Estado central (`idle|running|success|failed|cancelled`) + `run_id` anti-carreras |
| `config.lua` | Defaults + merge de `opts` |
| `actions.lua` | Catálogo de acciones por lenguaje (tabla estática + overrides de usuario) |
| `context.lua` | Detección de test bajo el cursor y entry point (main) vía TS/regex |
| `project.lua` | Raíz del proyecto por marcadores por lenguaje + genéricos |
| `terminal.lua` | Ventanas horizontales/verticales/float, título/winbar, `q`, autoclose |
| `quickfix.lua` | Parseo de salida → lista quickfix (`:cn`/`:cp`), auto-close en éxito |
| `history.lua` | Persistencia en `stdpath("data")/code-runner/history.json` |
| `picker.lua` | Selector volt con fallback `vim.ui.select` |
| `shell.lua` | Sustitución de variables y wrapping PowerShell/bash |
| `highlight.lua` | Grupos propios `CodeRunner*` (defaults enlazados al tema) |

Entrada: `plugin/code-runner.lua` define `:CodeRun`, `:CodeRunLast`,
`:CodeRunHistory`. Lazy-friendly: cargan `code-runner` al invocarse.

Detalle completo y flujo de ejecución: `.opencode/ARCHITECTURE.md`.

## Reglas de trabajo

1. Antes de tocar código: leer este README, el estado de `git status`/`git diff`, y la
   unidad elegida del TODO. Trabajar **una** unidad por sesión.
2. **La suite siempre verde** antes y después de cada cambio:
   `nvim --headless -l tests/run.lua`. No eliminar tests para hacerlos pasar.
3. Windows/Linux/macOS: todo cambio debe ser multiplataforma; atención a
   PowerShell/cmd, rutas, `.exe`, quoting, UTF-8.
4. No romper la API existente sin migración. Cada refactor deja el proyecto
   funcionando y documentación actualizada.
5. No agregar lenguajes nuevos ahora (P1+): primero arquitectura/API/tests/UX.
6. Update de `ROADMAP.md`, `TODO.md`, `CHANGELOG.md` y docs ante decisiones
   importantes. Definición de DONE en `.opencode/README.md` (sección abajo).

## Comandos

```powershell
# suite completa (exit 1 si falla; apto CI)
nvim --headless -l tests/run.lua
# un espectro específico
nvim --headless -u NONE -l tests/run.lua
```

## Definición de DONE (criterios de una feature terminada)

- [ ] código implementado
- [ ] tests añadidos y pasando
- [ ] Windows considerado
- [ ] Linux/macOS considerados
- [ ] documentación actualizada (README/interna si aplica)
- [ ] API documentada si es pública
- [ ] sin warnings nuevos ni archivos temporales ni código muerto
- [ ] `ROADMAP.md`/`TODO.md` actualizados

## Objetivos V1.0

API pública estable (`run`, `run_last`, `stop`, `restart`, `state`,
`context`, `register_action`), arquitectura mantenible, project/context/test
detection, Smart Run, terminal, quickfix, history, custom actions, project
config (`.code-runner.lua`), tasks/profile básicos, stop/restart,
diagnostics, checkhealth, tests+E2E, Windows/Linux/macOS, docs, CI.

V1.1+ (no bloquea V1.0): workflows avanzados, DAP, Neotest, VS Code tasks.
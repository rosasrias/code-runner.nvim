local config = require "code-runner.config"

T.section("config")

T.it("los defaults están completos", function()
  config.options = vim.deepcopy(config.defaults)
  T.eq("auto", config.options.ui)
  T.eq(true, config.options.autosave)
  T.eq("horizontal", config.options.terminal.direction)
  T.truthy(config.options.icons.run and config.options.icons.build)
  T.truthy(config.options.picker.title == "CodeRunner")
end)

T.it("setup hace deep merge sin perder defaults", function()
  config.setup { terminal = { height = 20 } }
  T.eq(20, config.options.terminal.height)
  T.eq(45, config.options.terminal.vertical_width, "no debe pisar vertical_width")
  T.eq("auto", config.options.ui)
end)

T.it("acepta acciones de usuario", function()
  config.setup { actions = { go = { [" custom"] = "go vet %" } } }
  T.truthy(config.options.actions.go[" custom"])
end)

T.it("restaurar defaults", function()
  config.options = vim.deepcopy(config.defaults)
  T.eq(12, config.options.terminal.height)
end)

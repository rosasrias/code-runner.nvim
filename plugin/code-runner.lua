if vim.g.loaded_code_runner then
  return
end
vim.g.loaded_code_runner = true

vim.api.nvim_create_user_command("CodeRun", function()
  require("code-runner").build_run()
end, { desc = "code-runner: selector de build/run" })

vim.api.nvim_create_user_command("CodeRunLast", function()
  require("code-runner").run_last()
end, { desc = "code-runner: repetir última ejecución" })

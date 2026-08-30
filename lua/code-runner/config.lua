local M = {}

M.defaults = {
  -- "volt" | "select" | "auto" (volt si está disponible, si no vim.ui.select)
  ui = "auto",
  picker = {
    title = "CodeRunner", -- el título se muestra como "⚡ <title> · <archivo>"
    hl_selected = "ExBlue",
    hl_run = "ExGreen",
    hl_build = "ExYellow",
    hl_misc = "ExGreen",
    hl_hint = "CommentFg",
  },
  terminal = {
    direction = "horizontal", -- "horizontal" | "vertical"
    height = 12,
    vertical_width = 45,
  },
  icons = {
    run = "",
    build = "󱤵 ",
  },
  autosave = true,
}

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", M.options, opts or {})
end

return M

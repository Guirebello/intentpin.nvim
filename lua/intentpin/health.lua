local M = {}

function M.check()
  vim.health.start("IntentPin")

  if vim.fn.has("nvim-0.11.2") == 1 then
    vim.health.ok("Neovim >= 0.11.2")
  else
    vim.health.error("IntentPin requires Neovim >= 0.11.2")
  end

  local ok = pcall(require, "nui.popup")
  if ok then
    vim.health.ok("nui.nvim is available")
  else
    vim.health.error("nui.nvim is missing", { "Add MunifTanjim/nui.nvim as a dependency" })
  end

  local path = require("intentpin.config").get().storage.path
  if vim.fn.isdirectory(path) == 1 or vim.fn.mkdir(path, "p") == 1 then
    vim.health.ok("State directory: " .. path)
  else
    vim.health.error("Could not create state directory: " .. path)
  end

  if vim.fn.has("clipboard") == 1 then
    vim.health.ok("Clipboard provider is available")
  else
    vim.health.warn("No clipboard provider detected; exports still use the unnamed register")
  end
end

return M

if vim.g.loaded_intentpin then
  return
end
vim.g.loaded_intentpin = true

require("intentpin").setup()

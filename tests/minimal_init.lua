vim.opt.runtimepath:append(vim.fn.getcwd())
local cwd = vim.fn.getcwd()
local nui_paths = {
  vim.fs.joinpath(vim.fs.dirname(cwd), "neovim-good-extensions", "nui.nvim"),
  vim.fs.joinpath(vim.fs.dirname(vim.fs.dirname(cwd)), "neovim-good-extensions", "nui.nvim"),
}
if vim.env.INTENTPIN_NUI_PATH then
  table.insert(nui_paths, 1, vim.env.INTENTPIN_NUI_PATH)
end
for _, path in ipairs(nui_paths) do
  if path and vim.fn.isdirectory(path) == 1 then
    vim.opt.runtimepath:append(path)
    break
  end
end
vim.opt.swapfile = false
vim.opt.shadafile = "NONE"

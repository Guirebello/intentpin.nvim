local config = require("intentpin.config")

local M = {}

---@param path string
---@return string
local function canonical(path)
  path = vim.fs.normalize(path)
  return vim.uv.fs_realpath(path) or path
end

---@param path string
---@return string
function M.for_path(path)
  path = canonical(path)
  local opts = config.get()
  local configured = opts.root_dir
  local root

  if type(configured) == "function" then
    root = configured(path)
  elseif type(configured) == "string" and configured ~= "" then
    root = configured
  end

  root = root or vim.fs.root(path, opts.root_markers)
  if not root then
    local cwd = canonical(vim.uv.cwd() or vim.fn.getcwd())
    local relative = vim.fs.relpath(cwd, path)
    root = relative and not relative:match("^%.%.[/\\]") and cwd or vim.fs.dirname(path)
  end

  return canonical(root)
end

---@param buf? integer
---@return string
function M.current(buf)
  buf = buf or 0
  local path = vim.api.nvim_buf_get_name(buf)
  if path == "" or vim.bo[buf].buftype ~= "" then
    error("IntentPin: save the file before using IntentPin")
  end
  return M.for_path(path)
end

---@param project_root string
---@param path string
---@return string
function M.relative(project_root, path)
  local relative = vim.fs.relpath(project_root, canonical(path))
  if not relative or relative == "" or relative:match("^%.%.[/\\]") then
    error("IntentPin: the selected file is outside the project root")
  end
  return relative:gsub("\\", "/")
end

return M

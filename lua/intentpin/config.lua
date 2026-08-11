local M = {}

M.defaults = {
  root_markers = { ".git" },
  root_dir = nil,
  storage = {
    path = vim.fs.joinpath(vim.fn.stdpath("state"), "intentpin"),
  },
  context_lines = 2,
  inline = {
    enabled = true,
    sign = "󰆉",
    orphan_sign = "!",
    virtual_text = false,
    max_length = 60,
    highlight_range = false,
    priority = 120,
  },
  hover = {
    mode = "virtual_lines",
    width = 72,
    max_height = 14,
    border = "rounded",
  },
  editor = {
    width = 0.62,
    height = 0.32,
    border = "rounded",
    spell = false,
    spelllang = nil,
  },
  manager = {
    width = 0.88,
    height = 0.76,
    border = "rounded",
    preview = true,
  },
  export = {
    include_selected_text = true,
    instruction_language = "en",
    custom_instruction = "",
  },
}

M.options = vim.deepcopy(M.defaults)

---@param opts? table
---@return table
function M.setup(opts)
  opts = opts or {}
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts)

  local language = M.options.export.instruction_language
  if not vim.tbl_contains({ "en", "pt-BR", "es", "custom" }, language) then
    error("IntentPin: export.instruction_language must be en, pt-BR, es, or custom")
  end

  if type(M.options.storage.path) ~= "string" or M.options.storage.path == "" then
    error("IntentPin: storage.path must be a non-empty string")
  end

  if type(M.options.editor.spell) ~= "boolean" then
    error("IntentPin: editor.spell must be a boolean")
  end
  if
    M.options.editor.spelllang ~= nil
    and (type(M.options.editor.spelllang) ~= "string" or M.options.editor.spelllang == "")
  then
    error("IntentPin: editor.spelllang must be a non-empty string")
  end

  if not vim.tbl_contains({ "virtual_lines", "floating_window" }, M.options.hover.mode) then
    error("IntentPin: hover.mode must be virtual_lines or floating_window")
  end

  return M.options
end

---@return table
function M.get()
  return M.options
end

return M

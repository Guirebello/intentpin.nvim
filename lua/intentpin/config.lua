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
    orphan_sign = "?",
    virtual_text = true,
    max_length = 60,
    highlight_range = true,
    priority = 120,
  },
  editor = {
    width = 0.62,
    height = 0.32,
    border = "rounded",
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

  return M.options
end

---@return table
function M.get()
  return M.options
end

return M

local anchor = require("intentpin.anchor")
local config = require("intentpin.config")
local project = require("intentpin.root")
local store = require("intentpin.store")
local virtual_lines = require("intentpin.ui.hover.virtual_lines")

local M = {}
local namespace = vim.api.nvim_create_namespace("intentpin-expanded")
local group = vim.api.nvim_create_augroup("IntentPinExpanded", { clear = true })
local active = {}

---@param buf integer
---@param project_root string
---@return table[]
local function buffer_notes(buf, project_root)
  local file = project.relative(project_root, vim.api.nvim_buf_get_name(buf))
  local notes = {}
  for _, note in ipairs(store.list(project_root)) do
    if note.file == file then
      notes[#notes + 1] = note
    end
  end
  table.sort(notes, function(left, right)
    if left.range.start.line ~= right.range.start.line then
      return left.range.start.line < right.range.start.line
    end
    return left.range.start.character < right.range.start.character
  end)
  return notes
end

---@param buf integer
function M.close(buf)
  active[buf] = nil
  if vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_clear_namespace(buf, namespace, 0, -1)
    vim.api.nvim_clear_autocmds({ group = group, buffer = buf })
  end
end

---@param buf integer
---@return boolean
function M.is_open(buf)
  return active[buf] ~= nil and vim.api.nvim_buf_is_valid(buf)
end

---@param buf integer
---@param project_root string
---@return boolean?
function M.open(buf, project_root)
  M.close(buf)
  local notes = buffer_notes(buf, project_root)
  if #notes == 0 then
    return nil
  end

  require("intentpin.ui.hover").close()
  for _, note in ipairs(notes) do
    local range = anchor.position(buf, note.id) or note.range
    if not anchor.is_orphaned(project_root, note.id) then
      vim.api.nvim_buf_set_extmark(buf, namespace, range.start.line, range.start.character, {
        end_row = range["end"].line,
        end_col = range["end"].character,
        hl_group = "IntentPinActiveRange",
        hl_mode = "combine",
        priority = config.get().inline.priority + 10,
        strict = false,
      })
    end
    virtual_lines.open({
      buf = buf,
      notes = { note },
      namespace = namespace,
      ranges = { range },
    })
  end

  active[buf] = { root = project_root }
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    buffer = buf,
    once = true,
    callback = function()
      active[buf] = nil
    end,
  })
  return true
end

---@param buf integer
---@param project_root string
---@return boolean?
function M.toggle(buf, project_root)
  if M.is_open(buf) then
    M.close(buf)
    return false
  end
  return M.open(buf, project_root)
end

---@param project_root string
function M.refresh_root(project_root)
  local buffers = {}
  for buf, state in pairs(active) do
    if state.root == project_root then
      buffers[#buffers + 1] = buf
    end
  end
  for _, buf in ipairs(buffers) do
    if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_is_loaded(buf) then
      M.open(buf, project_root)
    else
      active[buf] = nil
    end
  end
end

return M

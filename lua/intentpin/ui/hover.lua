local anchor = require("intentpin.anchor")
local config = require("intentpin.config")

local M = {}
local namespace = vim.api.nvim_create_namespace("intentpin-hover")
local adapters = {
  floating_window = "intentpin.ui.hover.floating_window",
  virtual_lines = "intentpin.ui.hover.virtual_lines",
}
local active

---@param notes table[]
---@return string
local function note_key(notes)
  local ids = {}
  for _, note in ipairs(notes) do
    ids[#ids + 1] = note.id
  end
  table.sort(ids)
  return table.concat(ids, ":")
end

---@return string, table
local function adapter()
  local mode = config.get().hover.mode
  return mode, require(adapters[mode])
end

function M.close()
  if not active then
    return
  end
  local current = active
  active = nil
  if vim.api.nvim_buf_is_valid(current.buf) then
    vim.api.nvim_buf_clear_namespace(current.buf, namespace, 0, -1)
  end
  current.adapter.close(current.state)
end

---@return boolean
function M.is_open()
  if not active then
    return false
  end
  if not active.adapter.is_open(active.state) then
    M.close()
    return false
  end
  return true
end

---@param buf integer
---@param notes table[]
---@return boolean
function M.toggle(buf, notes)
  local mode, selected = adapter()
  local key = note_key(notes)
  if active and active.buf == buf and active.key == key and active.mode == mode then
    M.close()
    return false
  end
  M.close()

  local ranges = {}
  for _, note in ipairs(notes) do
    local range = anchor.position(buf, note.id) or note.range
    ranges[#ranges + 1] = range
    vim.api.nvim_buf_set_extmark(buf, namespace, range.start.line, range.start.character, {
      end_row = range["end"].line,
      end_col = range["end"].character,
      hl_group = "IntentPinActiveRange",
      hl_mode = "combine",
      priority = config.get().inline.priority + 10,
      strict = false,
    })
  end

  local ok, state = pcall(selected.open, {
    buf = buf,
    notes = notes,
    namespace = namespace,
    ranges = ranges,
  })
  if not ok then
    vim.api.nvim_buf_clear_namespace(buf, namespace, 0, -1)
    error(state)
  end

  active = {
    adapter = selected,
    buf = buf,
    key = key,
    mode = mode,
    state = state,
  }
  local group = vim.api.nvim_create_augroup("IntentPinHover", { clear = true })
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "InsertEnter", "BufLeave" }, {
    group = group,
    buffer = buf,
    once = true,
    callback = M.close,
  })
  return true
end

return M

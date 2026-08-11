local anchor = require("intentpin.anchor")
local config = require("intentpin.config")
local util = require("intentpin.util")

local M = {}
local namespace = vim.api.nvim_create_namespace("intentpin-hover")
local active

local function note_key(notes)
  local ids = {}
  for _, note in ipairs(notes) do
    ids[#ids + 1] = note.id
  end
  table.sort(ids)
  return table.concat(ids, ":")
end

local function padding(value, width)
  return value .. string.rep(" ", math.max(0, width - vim.fn.strdisplaywidth(value)))
end

local function card_lines(notes, indent, width)
  local lines = {}
  local left = string.rep(" ", indent)
  local title = #notes == 1 and " IntentPin " or string.format(" IntentPin · %d notes ", #notes)
  local top_fill = string.rep("─", math.max(1, width - vim.fn.strdisplaywidth(title)))
  lines[#lines + 1] = {
    { left .. "╭─", "IntentPinHoverBorder" },
    { title, "IntentPinHoverTitle" },
    { top_fill .. "─╮", "IntentPinHoverBorder" },
  }

  for index, note in ipairs(notes) do
    if #notes > 1 then
      local label = string.format("%d. %s:L%s", index, note.file, util.range_label(note.range))
      lines[#lines + 1] = {
        { left .. "│ ", "IntentPinHoverBorder" },
        { padding(util.summary(label, width), width), "IntentPinHoverTitle" },
        { " │", "IntentPinHoverBorder" },
      }
    end
    for _, line in ipairs(util.wrap(note.comment, width)) do
      lines[#lines + 1] = {
        { left .. "│ ", "IntentPinHoverBorder" },
        { padding(line, width), "IntentPinHoverText" },
        { " │", "IntentPinHoverBorder" },
      }
    end
    if index < #notes then
      lines[#lines + 1] = {
        { left .. "├─" .. string.rep("─", width) .. "─┤", "IntentPinHoverBorder" },
      }
    end
  end

  lines[#lines + 1] = {
    { left .. "╰─" .. string.rep("─", width) .. "─╯", "IntentPinHoverBorder" },
  }
  return lines
end

function M.close()
  if active and vim.api.nvim_buf_is_valid(active.buf) then
    vim.api.nvim_buf_clear_namespace(active.buf, namespace, 0, -1)
  end
  active = nil
end

---@return boolean
function M.is_open()
  return active ~= nil
end

---@param buf integer
---@param notes table[]
---@return boolean
function M.toggle(buf, notes)
  local key = note_key(notes)
  if active and active.buf == buf and active.key == key then
    M.close()
    return false
  end
  M.close()

  local ranges = {}
  local final_row = 0
  local first_col = math.huge
  for _, note in ipairs(notes) do
    local range = anchor.position(buf, note.id) or note.range
    ranges[#ranges + 1] = range
    final_row = math.max(final_row, range["end"].line)
    first_col = math.min(first_col, range.start.character)
    vim.api.nvim_buf_set_extmark(buf, namespace, range.start.line, range.start.character, {
      end_row = range["end"].line,
      end_col = range["end"].character,
      hl_group = "IntentPinActiveRange",
      hl_mode = "combine",
      priority = config.get().inline.priority + 10,
      strict = false,
    })
  end

  local win = vim.fn.bufwinid(buf)
  local win_width = win ~= -1 and vim.api.nvim_win_get_width(win) or vim.o.columns
  local source_line = vim.api.nvim_buf_get_lines(buf, ranges[1].start.line, ranges[1].start.line + 1, false)[1]
    or ""
  local indent = math.min(12, vim.fn.strdisplaywidth(source_line:sub(1, first_col)))
  local width = math.max(20, math.min(config.get().hover.width, win_width - indent - 8))
  vim.api.nvim_buf_set_extmark(buf, namespace, final_row, 0, {
    virt_lines = card_lines(notes, indent, width),
    virt_lines_above = false,
    strict = false,
  })

  active = { buf = buf, key = key }
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

local config = require("intentpin.config")
local util = require("intentpin.util")

local M = {}

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

---@param context { buf: integer, notes: table[], namespace: integer, ranges: table[] }
---@return table
function M.open(context)
  local final_row = 0
  local first_col = math.huge
  for _, range in ipairs(context.ranges) do
    final_row = math.max(final_row, range["end"].line)
    first_col = math.min(first_col, range.start.character)
  end

  local win = vim.fn.bufwinid(context.buf)
  local win_width = win ~= -1 and vim.api.nvim_win_get_width(win) or vim.o.columns
  local source_line = vim.api.nvim_buf_get_lines(
    context.buf,
    context.ranges[1].start.line,
    context.ranges[1].start.line + 1,
    false
  )[1] or ""
  local indent = math.min(12, vim.fn.strdisplaywidth(source_line:sub(1, first_col)))
  local width = math.max(20, math.min(config.get().hover.width, win_width - indent - 8))
  vim.api.nvim_buf_set_extmark(context.buf, context.namespace, final_row, 0, {
    virt_lines = card_lines(context.notes, indent, width),
    virt_lines_above = false,
    strict = false,
  })
  return {}
end

function M.close() end

---@return boolean
function M.is_open()
  return true
end

return M

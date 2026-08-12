local config = require("intentpin.config")
local border = require("intentpin.ui.border")
local util = require("intentpin.util")

local M = {}

local function content(notes, width)
  local lines = {}
  for index, note in ipairs(notes) do
    if #notes > 1 then
      lines[#lines + 1] = string.format("%d. %s:L%s", index, note.file, util.range_label(note.range))
      lines[#lines + 1] = ""
    end
    vim.list_extend(lines, util.wrap(note.comment, width))
    if index < #notes then
      lines[#lines + 1] = ""
      lines[#lines + 1] = string.rep("─", width)
      lines[#lines + 1] = ""
    end
  end
  return lines
end

---@param context { buf: integer, notes: table[] }
---@return table
function M.open(context)
  local ok, Popup = pcall(require, "nui.popup")
  if not ok then
    error("IntentPin: nui.nvim is required for floating hover")
  end

  local opts = config.get().hover
  local source_win = vim.fn.bufwinid(context.buf)
  local win_width = source_win ~= -1 and vim.api.nvim_win_get_width(source_win) or vim.o.columns
  local width = math.max(24, math.min(opts.width, win_width - 6))
  local lines = content(context.notes, width)
  if #lines > opts.max_height then
    lines = vim.list_slice(lines, 1, math.max(1, opts.max_height - 1))
    lines[#lines + 1] = "… open :IntentPin open to read the full note"
  end

  local popup = Popup({
    enter = false,
    focusable = false,
    relative = "cursor",
    position = { row = 1, col = 1 },
    size = { width = width, height = math.max(1, #lines) },
    border = border.with_text(opts.border, {
      top = #context.notes == 1 and " IntentPin " or string.format(" IntentPin · %d notes ", #context.notes),
      top_align = "center",
    }),
    win_options = {
      wrap = false,
      winhighlight = "Normal:IntentPinHoverText,FloatBorder:IntentPinHoverBorder",
    },
  })
  popup:mount()
  vim.bo[popup.bufnr].buftype = "nofile"
  vim.bo[popup.bufnr].bufhidden = "wipe"
  vim.bo[popup.bufnr].swapfile = false
  vim.bo[popup.bufnr].filetype = "markdown"
  vim.api.nvim_buf_set_lines(popup.bufnr, 0, -1, false, lines)
  vim.bo[popup.bufnr].modifiable = false
  return popup
end

---@param popup table
function M.close(popup)
  if popup.bufnr and vim.api.nvim_buf_is_valid(popup.bufnr) then
    popup:unmount()
  end
end

---@param popup table
---@return boolean
function M.is_open(popup)
  return popup.winid ~= nil and vim.api.nvim_win_is_valid(popup.winid)
end

return M

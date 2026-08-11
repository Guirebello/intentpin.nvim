local config = require("intentpin.config")

local M = {}
local namespace = vim.api.nvim_create_namespace("intentpin-help")
local active

local entries = {
  { title = "Navigation" },
  { key = "<CR>", description = "Jump to the selected note" },
  { key = "p", description = "Toggle the preview pane" },
  { key = "r", description = "Refresh and re-anchor loaded files" },
  {},
  { title = "Notes" },
  { key = "<Space>", description = "Include or exclude the selected note" },
  { key = "a", description = "Include every note" },
  { key = "u", description = "Exclude every note" },
  { key = "e", description = "Edit the selected note" },
  { key = "d", description = "Delete the selected note" },
  { key = "D", description = "Delete every note in the project" },
  {},
  { title = "Export" },
  { key = "y", description = "Copy the selected note" },
  { key = "Y", description = "Copy checked notes with relative paths" },
  { key = "gY", description = "Copy checked notes with absolute paths" },
  { key = "A", description = "Copy every note with relative paths" },
  {},
  { title = "Interface" },
  { key = "? / q / <Esc>", description = "Close this help" },
}

local function content()
  local lines = {}
  local highlights = {}
  for _, entry in ipairs(entries) do
    if entry.title then
      lines[#lines + 1] = entry.title
      highlights[#highlights + 1] = { row = #lines, start_col = 0, end_col = #entry.title, group = "IntentPinFile" }
    elseif entry.key then
      lines[#lines + 1] = string.format("  %-14s %s", entry.key, entry.description)
      highlights[#highlights + 1] = {
        row = #lines,
        start_col = 2,
        end_col = 2 + #entry.key,
        group = "IntentPinLocation",
      }
    else
      lines[#lines + 1] = ""
    end
  end
  return lines, highlights
end

function M.close()
  if not active then
    return
  end
  local current = active
  active = nil
  if current.popup.bufnr and vim.api.nvim_buf_is_valid(current.popup.bufnr) then
    current.popup:unmount()
  end
  if current.return_win and vim.api.nvim_win_is_valid(current.return_win) then
    vim.api.nvim_set_current_win(current.return_win)
  end
end

---@return boolean
function M.is_open()
  return active ~= nil
end

---@param return_win integer
function M.open(return_win)
  M.close()
  local ok, Popup = pcall(require, "nui.popup")
  if not ok then
    error("IntentPin: nui.nvim is required for manager help")
  end

  local lines, highlights = content()
  local popup = Popup({
    enter = true,
    focusable = true,
    zindex = 60,
    relative = "editor",
    position = "50%",
    size = {
      width = math.min(vim.o.columns - 4, 68),
      height = math.min(vim.o.lines - 4, #lines),
    },
    border = {
      style = config.get().manager.border,
      text = {
        top = " IntentPin Help ",
        top_align = "center",
        bottom = " ? / q / <Esc> close ",
        bottom_align = "center",
      },
    },
    win_options = {
      wrap = true,
      linebreak = true,
      winhighlight = "Normal:IntentPinNormal,FloatBorder:IntentPinBorder",
    },
  })
  active = { popup = popup, return_win = return_win }
  popup:mount()

  vim.bo[popup.bufnr].buftype = "nofile"
  vim.bo[popup.bufnr].bufhidden = "wipe"
  vim.bo[popup.bufnr].swapfile = false
  vim.bo[popup.bufnr].filetype = "intentpin-help"
  vim.api.nvim_buf_set_lines(popup.bufnr, 0, -1, false, lines)
  vim.bo[popup.bufnr].modifiable = false

  for _, highlight in ipairs(highlights) do
    vim.api.nvim_buf_set_extmark(popup.bufnr, namespace, highlight.row - 1, highlight.start_col, {
      end_col = highlight.end_col,
      hl_group = highlight.group,
    })
  end

  popup:map("n", "?", M.close, { noremap = true, nowait = true })
  popup:map("n", "q", M.close, { noremap = true, nowait = true })
  popup:map("n", "<Esc>", M.close, { noremap = true, nowait = true })

  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = popup.bufnr,
    once = true,
    callback = function()
      if active and active.popup == popup then
        active = nil
      end
    end,
  })
end

return M

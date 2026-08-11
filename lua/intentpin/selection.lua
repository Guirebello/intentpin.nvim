local config = require("intentpin.config")
local root = require("intentpin.root")

local M = {}

---@param line string
---@param column integer
---@return integer
local function next_character(line, column)
  if column >= #line then
    return #line
  end
  local tail = line:sub(column + 1)
  local width = vim.fn.byteidx(tail, 1)
  return math.min(#line, column + math.max(width, 1))
end

---@param buf integer
---@param start_row integer
---@param end_row integer
---@return string[], string[]
local function context(buf, start_row, end_row)
  local count = config.get().context_lines
  local line_count = vim.api.nvim_buf_line_count(buf)
  local before = vim.api.nvim_buf_get_lines(buf, math.max(0, start_row - count), start_row, false)
  local after = vim.api.nvim_buf_get_lines(buf, end_row + 1, math.min(line_count, end_row + count + 1), false)
  return before, after
end

---@param buf? integer
---@return table
function M.capture(buf)
  buf = buf or 0
  if not vim.api.nvim_buf_is_valid(buf) then
    error("IntentPin: the source buffer is no longer valid")
  end
  local path = vim.api.nvim_buf_get_name(buf)
  if path == "" or vim.bo[buf].buftype ~= "" then
    error("IntentPin: save the file before adding a note")
  end

  local visual_mode = vim.fn.visualmode()
  if visual_mode == "\22" then
    error("IntentPin: blockwise visual selections are not supported yet")
  end
  local start_mark = vim.fn.getpos("'<")
  local end_mark = vim.fn.getpos("'>")
  if start_mark[2] == 0 or end_mark[2] == 0 then
    error("IntentPin: select some code before adding a note")
  end

  local start_row = start_mark[2] - 1
  local end_row = end_mark[2] - 1
  local start_col = math.max(0, start_mark[3] - 1)
  local end_col = math.max(0, end_mark[3] - 1)
  if visual_mode == "V" then
    start_col = 0
    end_col = #(vim.api.nvim_buf_get_lines(buf, end_row, end_row + 1, false)[1] or "")
  elseif vim.o.selection ~= "exclusive" then
    local line = vim.api.nvim_buf_get_lines(buf, end_row, end_row + 1, false)[1] or ""
    end_col = next_character(line, end_col)
  end

  local selected = table.concat(
    vim.api.nvim_buf_get_text(buf, start_row, start_col, end_row, end_col, {}),
    "\n"
  )
  if selected == "" then
    error("IntentPin: select some code before adding a note")
  end

  local project_root = root.current(buf)
  local before, after = context(buf, start_row, end_row)
  return {
    root = project_root,
    buf = buf,
    file = root.relative(project_root, path),
    language_id = vim.bo[buf].filetype,
    range = {
      start = { line = start_row, character = start_col },
      ["end"] = { line = end_row, character = end_col },
    },
    selected_text = selected,
    context_before = before,
    context_after = after,
  }
end

return M

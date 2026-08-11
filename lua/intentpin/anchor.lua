local config = require("intentpin.config")
local project = require("intentpin.root")
local store = require("intentpin.store")
local util = require("intentpin.util")

local M = {}
local namespace = vim.api.nvim_create_namespace("intentpin")
local marks = {}
local statuses = {}

---@param lines string[]
---@param range table
---@return table
local function clamp(lines, range)
  local last_row = math.max(0, #lines - 1)
  local start_row = math.min(math.max(0, range.start.line), last_row)
  local end_row = math.min(math.max(start_row, range["end"].line), last_row)
  local start_col = math.min(math.max(0, range.start.character), #(lines[start_row + 1] or ""))
  local end_col = math.min(math.max(0, range["end"].character), #(lines[end_row + 1] or ""))
  if end_row == start_row and end_col < start_col then
    end_col = start_col
  end
  return {
    start = { line = start_row, character = start_col },
    ["end"] = { line = end_row, character = end_col },
  }
end

---@param lines string[]
---@param range table
---@return string
local function range_text(lines, range)
  if range.start.line == range["end"].line then
    local line = lines[range.start.line + 1] or ""
    return line:sub(range.start.character + 1, range["end"].character)
  end

  local selected = {}
  selected[#selected + 1] = (lines[range.start.line + 1] or ""):sub(range.start.character + 1)
  for row = range.start.line + 1, range["end"].line - 1 do
    selected[#selected + 1] = lines[row + 1] or ""
  end
  selected[#selected + 1] = (lines[range["end"].line + 1] or ""):sub(1, range["end"].character)
  return table.concat(selected, "\n")
end

---@param lines string[]
---@param offset integer
---@return table
local function offset_to_position(lines, offset)
  local remaining = offset
  for row, line in ipairs(lines) do
    if remaining <= #line then
      return { line = row - 1, character = remaining }
    end
    remaining = remaining - #line - 1
  end
  local last = lines[#lines] or ""
  return { line = math.max(0, #lines - 1), character = #last }
end

---@param lines string[]
---@param note table
---@param range table
---@return integer
local function candidate_score(lines, note, range)
  local score = math.abs(range.start.line - note.range.start.line) * 2
  for offset = 1, #note.context_before do
    local expected = note.context_before[#note.context_before - offset + 1]
    local actual = lines[range.start.line - offset + 1]
    if actual == expected then
      score = score - 100
    end
  end
  local final_row = range["end"].line
  if range["end"].character == 0 and final_row > range.start.line then
    final_row = final_row - 1
  end
  for offset, expected in ipairs(note.context_after) do
    if lines[final_row + offset + 1] == expected then
      score = score - 100
    end
  end
  return score
end

---@param lines string[]
---@param note table
---@return table, boolean, boolean
function M.resolve(lines, note)
  if #lines == 0 then
    lines = { "" }
  end
  local stored = clamp(lines, note.range)
  if note.selected_text == "" or range_text(lines, stored) == note.selected_text then
    return stored, false, not util.range_equal(stored, note.range)
  end

  local document = table.concat(lines, "\n")
  local from = 1
  local best
  local best_score = math.huge
  while true do
    local start_offset = document:find(note.selected_text, from, true)
    if not start_offset then
      break
    end
    local candidate = {
      start = offset_to_position(lines, start_offset - 1),
      ["end"] = offset_to_position(lines, start_offset - 1 + #note.selected_text),
    }
    local score = candidate_score(lines, note, candidate)
    if score < best_score then
      best = candidate
      best_score = score
    end
    from = start_offset + 1
  end

  if best then
    return best, false, not util.range_equal(best, note.range)
  end
  return stored, true, not util.range_equal(stored, note.range)
end

---@param project_root string
---@param id string
---@return boolean
function M.is_orphaned(project_root, id)
  return statuses[project_root] and statuses[project_root][id] or false
end

---@param buf integer
---@return string[]
local function buffer_lines(buf)
  return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
end

---@param buf integer
---@param range table
---@return string[], string[]
local function range_context(buf, range)
  local count = config.get().context_lines
  local line_count = vim.api.nvim_buf_line_count(buf)
  local final_row = range["end"].line
  if range["end"].character == 0 and final_row > range.start.line then
    final_row = final_row - 1
  end
  return vim.api.nvim_buf_get_lines(buf, math.max(0, range.start.line - count), range.start.line, false),
    vim.api.nvim_buf_get_lines(buf, final_row + 1, math.min(line_count, final_row + count + 1), false)
end

---@param buf integer
---@param project_root string
function M.attach(buf, project_root)
  if not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_buf_is_loaded(buf) then
    return
  end
  local path = vim.api.nvim_buf_get_name(buf)
  if path == "" or vim.bo[buf].buftype ~= "" then
    return
  end
  local ok, file = pcall(project.relative, project_root, path)
  if not ok then
    return
  end

  vim.api.nvim_buf_clear_namespace(buf, namespace, 0, -1)
  marks[buf] = {}
  statuses[project_root] = statuses[project_root] or {}
  local lines = buffer_lines(buf)
  local moved = false
  local inline = config.get().inline

  for _, note in ipairs(store.list(project_root)) do
    if note.file == file then
      local range, orphaned, changed = M.resolve(lines, note)
      statuses[project_root][note.id] = orphaned
      if changed and not orphaned then
        note.range = range
        moved = true
      end

      local extmark = {
        end_row = range["end"].line,
        end_col = range["end"].character,
        right_gravity = true,
        end_right_gravity = false,
        strict = false,
        priority = inline.priority,
      }
      if inline.enabled then
        extmark.sign_text = orphaned and inline.orphan_sign or inline.sign
        extmark.sign_hl_group = orphaned and "IntentPinOrphan" or "IntentPinSign"
        if inline.virtual_text then
          extmark.virt_text = {
            {
              " " .. util.summary(note.comment, inline.max_length),
              orphaned and "IntentPinOrphan" or "IntentPinVirtualText",
            },
          }
          extmark.virt_text_pos = "eol"
        end
        if inline.highlight_range and not orphaned then
          extmark.hl_group = "IntentPinRange"
          extmark.hl_mode = "combine"
        end
      end
      marks[buf][note.id] = vim.api.nvim_buf_set_extmark(
        buf,
        namespace,
        range.start.line,
        range.start.character,
        extmark
      )
    end
  end

  if moved then
    store.save(project_root, false)
  end
end

---@param project_root string
function M.refresh_root(project_root)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.api.nvim_buf_get_name(buf) ~= "" then
      local ok, candidate = pcall(project.for_path, vim.api.nvim_buf_get_name(buf))
      if ok and candidate == project_root then
        M.attach(buf, project_root)
      end
    end
  end
end

---@param buf integer
---@param id string
---@return table?
function M.position(buf, id)
  local extmark_id = marks[buf] and marks[buf][id]
  if extmark_id then
    local position = vim.api.nvim_buf_get_extmark_by_id(buf, namespace, extmark_id, { details = true })
    if #position > 0 then
      local details = position[3]
      return {
        start = { line = position[1], character = position[2] },
        ["end"] = {
          line = details.end_row or position[1],
          character = details.end_col or position[2],
        },
      }
    end
  end
end

---@param buf integer
function M.sync(buf)
  if not marks[buf] then
    return
  end
  local ok, project_root = pcall(project.current, buf)
  if not ok then
    return
  end
  local file = project.relative(project_root, vim.api.nvim_buf_get_name(buf))
  local changed = false

  for _, note in ipairs(store.list(project_root)) do
    if note.file == file then
      local range = M.position(buf, note.id)
      if range then
        local selected = table.concat(vim.api.nvim_buf_get_text(
          buf,
          range.start.line,
          range.start.character,
          range["end"].line,
          range["end"].character,
          {}
        ), "\n")
        if selected ~= "" and (selected ~= note.selected_text or not util.range_equal(range, note.range)) then
          local before, after = range_context(buf, range)
          note.range = range
          note.selected_text = selected
          note.context_before = before
          note.context_after = after
          note.updated_at = util.timestamp()
          changed = true
        end
      end
    end
  end

  if changed then
    store.save(project_root)
  end
end

---@param project_root string
---@param buf integer
---@return table[]
function M.at_cursor(project_root, buf)
  local ok, file = pcall(project.relative, project_root, vim.api.nvim_buf_get_name(buf))
  if not ok then
    return {}
  end
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1] - 1
  local found = {}
  for _, note in ipairs(store.list(project_root)) do
    if note.file == file then
      local range = M.position(buf, note.id) or note.range
      if row >= range.start.line and row <= range["end"].line then
        found[#found + 1] = note
      end
    end
  end
  return found
end

return M

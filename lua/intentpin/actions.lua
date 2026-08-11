local anchor = require("intentpin.anchor")
local exporter = require("intentpin.export")
local project = require("intentpin.root")
local selection = require("intentpin.selection")
local store = require("intentpin.store")
local util = require("intentpin.util")

local M = {}

local function new_id()
  local seed = table.concat({
    tostring(vim.uv.hrtime()),
    tostring(vim.uv.os_getpid()),
    tostring(math.random()),
  }, ":")
  return vim.fn.sha256(seed):sub(1, 32)
end

---@param prompt string
---@param label string
---@param callback fun()
local function confirm(prompt, label, callback)
  vim.ui.select({ label, "Cancel" }, { prompt = prompt }, function(choice)
    if choice == label then
      callback()
    end
  end)
end

---@param project_root string
---@param notes table[]
---@param absolute boolean
local function copy_notes(project_root, notes, absolute)
  local output = exporter.copy(project_root, notes, { absolute_paths = absolute })
  local suffix = absolute and " with absolute paths" or ""
  util.notify(string.format("Copied %d %s%s", #notes, #notes == 1 and "note" or "notes", suffix))
  return output
end

function M.add()
  local captured = selection.capture(0)
  require("intentpin.ui.editor").open({
    title = string.format("New note · %s:L%s", captured.file, util.range_label(captured.range)),
    on_submit = function(comment)
      local now = util.timestamp()
      local note = {
        id = new_id(),
        file = captured.file,
        language_id = captured.language_id,
        range = captured.range,
        selected_text = captured.selected_text,
        context_before = captured.context_before,
        context_after = captured.context_after,
        comment = comment,
        included = true,
        created_at = now,
        updated_at = now,
      }
      store.add(captured.root, note)
      anchor.attach(captured.buf, captured.root)
      util.notify("Note pinned")
    end,
  })
end

---@param project_root? string
---@param opts? table
function M.open(project_root, opts)
  project_root = project_root or project.current(0)
  store.workspace(project_root)
  require("intentpin.ui.manager").open(project_root, opts)
end

---@param project_root string
---@param id string
---@param reopen? boolean
function M.edit(project_root, id, reopen)
  local note = store.get(project_root, id)
  if not note then
    return
  end
  local manager = require("intentpin.ui.manager")
  if manager.is_open() then
    manager.close()
  end
  local function reopen_manager()
    if reopen then
      manager.open(project_root, { focus_id = id, force = true })
    end
  end
  require("intentpin.ui.editor").open({
    title = string.format("Edit note · %s:L%s", note.file, util.range_label(note.range)),
    initial = note.comment,
    on_submit = function(comment)
      store.update(project_root, id, { comment = comment })
      util.notify("Note updated")
      reopen_manager()
    end,
    on_cancel = reopen_manager,
  })
end

---@param project_root string
---@param ids string[]
function M.delete(project_root, ids)
  if #ids == 0 then
    return
  end
  local prompt = #ids == 1 and "Delete this IntentPin note?"
    or string.format("Delete %d IntentPin notes?", #ids)
  confirm(prompt, "Delete", function()
    store.remove(project_root, ids)
    util.notify(#ids == 1 and "Note deleted" or "Notes deleted")
  end)
end

---@param project_root string
function M.clear(project_root)
  local count = #store.list(project_root)
  if count == 0 then
    return
  end
  confirm(string.format("Delete all %d IntentPin notes in this project?", count), "Delete all", function()
    store.clear(project_root)
    util.notify("All notes deleted")
  end)
end

---@param project_root string
---@param id string
function M.jump(project_root, id)
  local note = store.get(project_root, id)
  if not note then
    return
  end
  require("intentpin.ui.manager").close()
  local path = util.absolute_path(project_root, note.file)
  if vim.fn.filereadable(path) == 0 then
    error("IntentPin: file no longer exists: " .. note.file)
  end
  vim.cmd.edit(vim.fn.fnameescape(path))
  local buf = vim.api.nvim_get_current_buf()
  anchor.attach(buf, project_root)
  local range = anchor.position(buf, id) or note.range
  vim.api.nvim_win_set_cursor(0, { range.start.line + 1, range.start.character })
  vim.cmd("normal! zvzz")
  if anchor.is_orphaned(project_root, id) then
    util.notify("The original code was not found; jumped to the last known location", vim.log.levels.WARN)
  end
end

---@param project_root string
---@param kind "checked"|"all"|"ids"
---@param absolute boolean
---@param ids? string[]
---@return string?
function M.copy(project_root, kind, absolute, ids)
  local selected = {}
  local wanted = {}
  for _, id in ipairs(ids or {}) do
    wanted[id] = true
  end
  for _, note in ipairs(store.list(project_root)) do
    if kind == "all" or (kind == "checked" and note.included) or (kind == "ids" and wanted[note.id]) then
      selected[#selected + 1] = note
    end
  end
  return copy_notes(project_root, selected, absolute)
end

---@param callback fun(project_root: string, note: table)
local function with_note_at_cursor(callback)
  local project_root = project.current(0)
  local notes = anchor.at_cursor(project_root, 0)
  if #notes == 0 then
    util.notify("No IntentPin note at the cursor", vim.log.levels.WARN)
    return
  end
  if #notes == 1 then
    callback(project_root, notes[1])
    return
  end
  vim.ui.select(notes, {
    prompt = "Choose an IntentPin note",
    format_item = function(note)
      return util.summary(note.comment)
    end,
  }, function(note)
    if note then
      callback(project_root, note)
    end
  end)
end

function M.show_at_cursor()
  with_note_at_cursor(function(project_root, note)
    M.open(project_root, { focus_id = note.id, force = true })
  end)
end

function M.edit_at_cursor()
  with_note_at_cursor(function(project_root, note)
    M.edit(project_root, note.id, false)
  end)
end

function M.delete_at_cursor()
  with_note_at_cursor(function(project_root, note)
    M.delete(project_root, { note.id })
  end)
end

function M.copy_at_cursor(absolute)
  with_note_at_cursor(function(project_root, note)
    M.copy(project_root, "ids", absolute, { note.id })
  end)
end

---@return boolean
function M.hover()
  local project_root = project.current(0)
  local notes = anchor.at_cursor(project_root, 0)
  if #notes == 0 then
    require("intentpin.ui.hover").close()
    util.notify("No IntentPin note at the cursor", vim.log.levels.WARN)
    return false
  end
  return require("intentpin.ui.hover").toggle(0, notes)
end

---@param mode? "show"|"hide"|"toggle"
---@return boolean?
function M.expand(mode)
  mode = mode or "toggle"
  local project_root = project.current(0)
  local buf = vim.api.nvim_get_current_buf()
  local expanded = require("intentpin.ui.expanded")
  local visible
  if mode == "hide" then
    expanded.close(buf)
    visible = false
  elseif mode == "show" then
    visible = expanded.open(buf, project_root)
  else
    visible = expanded.toggle(buf, project_root)
  end
  if visible == nil then
    util.notify("No IntentPin notes in the current file", vim.log.levels.WARN)
    return nil
  end
  util.notify("IntentPin notes " .. (visible and "expanded" or "collapsed"))
  return visible
end

---@param project_root? string
---@return { checked: integer, recovered: integer, missing: integer, files: integer }
function M.reanchor(project_root)
  project_root = project_root or project.current(0)
  local result = anchor.refresh_root(project_root)
  require("intentpin.ui.expanded").refresh_root(project_root)
  require("intentpin.ui.manager").refresh(project_root)
  if result.checked == 0 then
    util.notify("No loaded IntentPin notes to re-anchor", vim.log.levels.WARN)
    return result
  end
  util.notify(string.format(
    "Anchors: %d checked · %d recovered · %d still missing",
    result.checked,
    result.recovered,
    result.missing
  ))
  return result
end

---@param mode "show"|"hide"|"toggle"
function M.inline(mode)
  local inline = require("intentpin.config").get().inline
  if mode == "toggle" then
    inline.enabled = not inline.enabled
  else
    inline.enabled = mode == "show"
  end
  if not inline.enabled then
    require("intentpin.ui.hover").close()
  end
  local project_root = project.current(0)
  anchor.refresh_root(project_root)
  util.notify("Inline markers " .. (inline.enabled and "shown" or "hidden"))
end

---@param direction 1|-1
function M.navigate(direction)
  local project_root = project.current(0)
  local notes = vim.deepcopy(store.list(project_root))
  if #notes == 0 then
    util.notify("No IntentPin notes in this project", vim.log.levels.WARN)
    return
  end
  table.sort(notes, function(left, right)
    if left.file ~= right.file then
      return left.file < right.file
    end
    if left.range.start.line ~= right.range.start.line then
      return left.range.start.line < right.range.start.line
    end
    return left.range.start.character < right.range.start.character
  end)

  local current_file = project.relative(project_root, vim.api.nvim_buf_get_name(0))
  local cursor = vim.api.nvim_win_get_cursor(0)
  local index
  if direction == 1 then
    for candidate, note in ipairs(notes) do
      if note.file > current_file
        or (note.file == current_file and note.range.start.line > cursor[1] - 1)
        or (note.file == current_file
          and note.range.start.line == cursor[1] - 1
          and note.range.start.character > cursor[2])
      then
        index = candidate
        break
      end
    end
    index = index or 1
  else
    for candidate = #notes, 1, -1 do
      local note = notes[candidate]
      if note.file < current_file
        or (note.file == current_file and note.range.start.line < cursor[1] - 1)
        or (note.file == current_file
          and note.range.start.line == cursor[1] - 1
          and note.range.start.character < cursor[2])
      then
        index = candidate
        break
      end
    end
    index = index or #notes
  end
  M.jump(project_root, notes[index].id)
end

return M

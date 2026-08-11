local config = require("intentpin.config")
local util = require("intentpin.util")

local M = {}
local VERSION = 1
local workspaces = {}
local listener

---@param value any
---@return boolean
local function is_position(value)
  return type(value) == "table"
    and type(value.line) == "number"
    and value.line >= 0
    and value.line % 1 == 0
    and type(value.character) == "number"
    and value.character >= 0
    and value.character % 1 == 0
end

---@param value any
---@return boolean
local function is_note(value)
  local safe_file = type(value) == "table"
    and type(value.file) == "string"
    and value.file ~= ""
    and not value.file:match("^[/\\]")
    and not value.file:match("^%a:[/\\]")
    and not value.file:match("^%.%.[/\\]")
    and not value.file:match("[/\\]%.%.[/\\]")
  return type(value) == "table"
    and type(value.id) == "string"
    and value.id ~= ""
    and safe_file
    and type(value.language_id) == "string"
    and type(value.range) == "table"
    and is_position(value.range.start)
    and is_position(value.range["end"])
    and type(value.selected_text) == "string"
    and util.is_array_of_strings(value.context_before)
    and util.is_array_of_strings(value.context_after)
    and type(value.comment) == "string"
    and type(value.included) == "boolean"
    and type(value.created_at) == "string"
    and type(value.updated_at) == "string"
end

---@param project_root string
---@return string
function M.path(project_root)
  local hash = vim.fn.sha256(project_root)
  return vim.fs.joinpath(config.get().storage.path, hash .. ".json")
end

---@param project_root string
---@return table
local function load(project_root)
  local path = M.path(project_root)
  local workspace = {
    root = project_root,
    path = path,
    notes = {},
  }

  if vim.fn.filereadable(path) == 0 then
    return workspace
  end

  local contents = table.concat(vim.fn.readfile(path, "b"), "\n")
  local ok, decoded = pcall(vim.json.decode, contents)
  if not ok then
    error("IntentPin: could not decode " .. path .. ": " .. tostring(decoded))
  end
  if type(decoded) ~= "table" or decoded.version ~= VERSION or type(decoded.notes) ~= "table" then
    error("IntentPin: " .. path .. " has an unsupported format")
  end
  if decoded.root and decoded.root ~= project_root then
    error("IntentPin: storage root does not match the current project")
  end
  for _, note in ipairs(decoded.notes) do
    if not is_note(note) then
      error("IntentPin: " .. path .. " contains an invalid note")
    end
    workspace.notes[#workspace.notes + 1] = note
  end
  return workspace
end

---@param project_root string
---@return table
function M.workspace(project_root)
  if not workspaces[project_root] then
    workspaces[project_root] = load(project_root)
  end
  return workspaces[project_root]
end

---@param project_root string
---@param emit? boolean
function M.save(project_root, emit)
  local workspace = M.workspace(project_root)
  vim.fn.mkdir(vim.fs.dirname(workspace.path), "p")
  local payload = vim.json.encode({
    version = VERSION,
    root = project_root,
    notes = workspace.notes,
  })
  local temp = string.format("%s.tmp.%d", workspace.path, vim.uv.os_getpid())
  if vim.fn.writefile({ payload }, temp, "b") ~= 0 then
    error("IntentPin: could not write temporary state file")
  end
  local ok, err = vim.uv.fs_rename(temp, workspace.path)
  if not ok then
    vim.uv.fs_unlink(temp)
    error("IntentPin: could not replace state file: " .. tostring(err))
  end
  if emit ~= false and listener then
    listener(project_root)
  end
end

---@param callback fun(project_root: string)
function M.set_listener(callback)
  listener = callback
end

---@param project_root string
---@return table[]
function M.list(project_root)
  return M.workspace(project_root).notes
end

---@param project_root string
---@param id string
---@return table?
function M.get(project_root, id)
  for _, note in ipairs(M.list(project_root)) do
    if note.id == id then
      return note
    end
  end
end

---@param project_root string
---@param note table
function M.add(project_root, note)
  if not is_note(note) then
    error("IntentPin: refusing to store an invalid note")
  end
  local notes = M.list(project_root)
  notes[#notes + 1] = note
  M.save(project_root)
end

---@param project_root string
---@param id string
---@param changes table
function M.update(project_root, id, changes)
  local note = M.get(project_root, id)
  if not note then
    return
  end
  for key, value in pairs(changes) do
    if key ~= "id" and key ~= "created_at" then
      note[key] = value
    end
  end
  note.updated_at = changes.updated_at or util.timestamp()
  if not is_note(note) then
    error("IntentPin: update produced an invalid note")
  end
  M.save(project_root)
end

---@param project_root string
---@param id string
function M.toggle(project_root, id)
  local note = M.get(project_root, id)
  if note then
    M.update(project_root, id, { included = not note.included })
  end
end

---@param project_root string
---@param included boolean
function M.set_all_included(project_root, included)
  local changed = false
  local updated_at = util.timestamp()
  for _, note in ipairs(M.list(project_root)) do
    if note.included ~= included then
      note.included = included
      note.updated_at = updated_at
      changed = true
    end
  end
  if changed then
    M.save(project_root)
  end
end

---@param project_root string
---@param ids string[]
function M.remove(project_root, ids)
  local remove = {}
  for _, id in ipairs(ids) do
    remove[id] = true
  end
  local workspace = M.workspace(project_root)
  local notes = {}
  for _, note in ipairs(workspace.notes) do
    if not remove[note.id] then
      notes[#notes + 1] = note
    end
  end
  if #notes ~= #workspace.notes then
    workspace.notes = notes
    M.save(project_root)
  end
end

---@param project_root string
function M.clear(project_root)
  local workspace = M.workspace(project_root)
  if #workspace.notes > 0 then
    workspace.notes = {}
    M.save(project_root)
  end
end

function M.reset()
  workspaces = {}
end

return M

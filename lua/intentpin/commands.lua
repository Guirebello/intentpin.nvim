local util = require("intentpin.util")

local M = {}

local commands = {
  "add",
  "open",
  "show",
  "edit",
  "delete",
  "hover",
  "expand",
  "reanchor",
  "inline",
  "next",
  "prev",
  "copy",
  "clear",
}

local copy_modes = {
  "checked",
  "checked-absolute",
  "all",
  "all-absolute",
  "current",
  "current-absolute",
}

local inline_modes = { "show", "hide", "toggle" }
local expand_modes = { "show", "hide", "toggle" }

---@param callback fun()
local function safely(callback)
  local ok, err = xpcall(callback, debug.traceback)
  if not ok then
    local message = tostring(err):match("^[^\n]+") or tostring(err)
    util.notify(message, vim.log.levels.ERROR)
  end
end

---@param args table
local function execute(args)
  local action = require("intentpin.actions")
  local project = require("intentpin.root")
  local name = args.fargs[1] or "open"

  if name == "add" then
    action.add()
  elseif name == "open" then
    action.open()
  elseif name == "show" then
    action.show_at_cursor()
  elseif name == "edit" then
    action.edit_at_cursor()
  elseif name == "delete" then
    action.delete_at_cursor()
  elseif name == "hover" then
    action.hover()
  elseif name == "expand" then
    local mode = args.fargs[2] or "toggle"
    if not vim.tbl_contains(expand_modes, mode) then
      error("IntentPin: unknown expand mode: " .. mode)
    end
    action.expand(mode)
  elseif name == "reanchor" then
    action.reanchor()
  elseif name == "inline" then
    local mode = args.fargs[2] or "toggle"
    if not vim.tbl_contains(inline_modes, mode) then
      error("IntentPin: unknown inline mode: " .. mode)
    end
    action.inline(mode)
  elseif name == "next" then
    action.navigate(1)
  elseif name == "prev" then
    action.navigate(-1)
  elseif name == "clear" then
    action.clear(project.current(0))
  elseif name == "copy" then
    local mode = args.fargs[2] or "checked"
    local absolute = mode:match("%-absolute$") ~= nil
    local kind = mode:gsub("%-absolute$", "")
    if kind == "current" then
      action.copy_at_cursor(absolute)
    elseif kind == "checked" or kind == "all" then
      action.copy(project.current(0), kind, absolute)
    else
      error("IntentPin: unknown copy mode: " .. mode)
    end
  else
    error("IntentPin: unknown action: " .. name)
  end
end

---@param arglead string
---@param cmdline string
---@return string[]
local function complete(arglead, cmdline)
  local words = vim.split(cmdline, "%s+", { trimempty = true })
  local candidates = words[2] == "copy" and copy_modes
    or words[2] == "inline" and inline_modes
    or words[2] == "expand" and expand_modes
    or commands
  return vim.tbl_filter(function(candidate)
    return candidate:sub(1, #arglead) == arglead
  end, candidates)
end

function M.setup()
  pcall(vim.api.nvim_del_user_command, "IntentPin")
  vim.api.nvim_create_user_command("IntentPin", function(args)
    safely(function()
      execute(args)
    end)
  end, {
    nargs = "*",
    range = true,
    desc = "Add, manage, navigate, and export IntentPin notes",
    complete = complete,
  })
end

return M

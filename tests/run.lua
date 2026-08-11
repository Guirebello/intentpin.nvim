local failures = 0
local total = 0

local function inspect(value)
  return vim.inspect(value)
end

local function equal(expected, actual, message)
  if not vim.deep_equal(expected, actual) then
    error(string.format(
      "%s\nexpected: %s\nactual:   %s",
      message or "values differ",
      inspect(expected),
      inspect(actual)
    ))
  end
end

local function truthy(value, message)
  if not value then
    error(message or "expected a truthy value")
  end
end

local function test(name, callback)
  total = total + 1
  local ok, err = xpcall(callback, debug.traceback)
  if ok then
    print("ok " .. total .. " - " .. name)
  else
    failures = failures + 1
    print("not ok " .. total .. " - " .. name)
    print(err)
  end
end

local temp = vim.fn.tempname()
vim.fn.mkdir(temp, "p")
require("intentpin").setup({ storage = { path = temp } })

local function note(overrides)
  return vim.tbl_deep_extend("force", {
    id = "note-1",
    file = "src/example.lua",
    language_id = "lua",
    range = {
      start = { line = 1, character = 0 },
      ["end"] = { line = 1, character = 6 },
    },
    selected_text = "target",
    context_before = { "before" },
    context_after = { "after" },
    comment = "Change this",
    included = true,
    created_at = "2026-01-01T00:00:00Z",
    updated_at = "2026-01-01T00:00:00Z",
  }, overrides or {})
end

test("exports sorted compact notes and multiline comments", function()
  local exporter = require("intentpin.export")
  local second = note({
    id = "note-2",
    file = "src/alpha.lua",
    range = {
      start = { line = 0, character = 0 },
      ["end"] = { line = 0, character = 5 },
    },
    selected_text = "alpha",
    comment = "First line\nSecond line",
  })
  local output = exporter.format("/work/project", { note(), second }, { instruction_language = "pt-BR" })
  equal(
    "Altere os trechos indicados. Ajuste código relacionado somente se necessário.\n\n"
      .. "src/alpha.lua:1\n| alpha\n> First line\n> Second line\n\n"
      .. "src/example.lua:2\n| target\n> Change this\n",
    output
  )
end)

test("supports absolute paths and omitted selected text", function()
  local output = require("intentpin.export").format("/work/project", { note() }, {
    absolute_paths = true,
    include_selected_text = false,
  })
  truthy(output:find("/work/project/src/example.lua:2", 1, true))
  truthy(not output:find("| target", 1, true))
end)

test("persists, reloads, updates, and removes notes", function()
  local store = require("intentpin.store")
  local root = "/work/intentpin-test-project"
  store.reset()
  store.add(root, note())
  truthy(vim.fn.filereadable(store.path(root)) == 1)
  store.reset()
  equal("Change this", store.get(root, "note-1").comment)
  store.update(root, "note-1", { comment = "Updated" })
  equal("Updated", store.get(root, "note-1").comment)
  store.remove(root, { "note-1" })
  equal(0, #store.list(root))
end)

test("reanchors moved text using surrounding context", function()
  local range, orphaned, moved = require("intentpin.anchor").resolve(
    { "header", "before", "target", "after" },
    note()
  )
  equal(2, range.start.line)
  equal(0, range.start.character)
  equal(6, range["end"].character)
  equal(false, orphaned)
  equal(true, moved)
end)

test("marks a note orphaned when its text disappears", function()
  local range, orphaned = require("intentpin.anchor").resolve({ "before", "different", "after" }, note())
  equal(1, range.start.line)
  equal(true, orphaned)
end)

test("captures a visual selection and creates a note", function()
  local project_dir = vim.fs.joinpath(temp, "selection-project")
  local source_dir = vim.fs.joinpath(project_dir, "src")
  vim.fn.mkdir(vim.fs.joinpath(project_dir, ".git"), "p")
  vim.fn.mkdir(source_dir, "p")
  local path = vim.fs.joinpath(source_dir, "example.lua")
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(buf, path)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "target value", "after" })
  vim.bo[buf].filetype = "lua"
  vim.api.nvim_win_set_buf(0, buf)
  vim.cmd("normal! gg0v5l")
  vim.cmd("normal! \27")

  local captured = require("intentpin.selection").capture(buf)
  equal("target", captured.selected_text)
  equal("src/example.lua", captured.file)

  local editor = require("intentpin.ui.editor")
  local original_open = editor.open
  local editor_opts
  editor.open = function(opts)
    editor_opts = opts
  end
  require("intentpin.actions").add()
  editor.open = original_open
  truthy(editor_opts)
  editor_opts.on_submit("Pin this selection")

  local notes = require("intentpin.store").list(captured.root)
  equal(1, #notes)
  equal("Pin this selection", notes[1].comment)
  equal("target", notes[1].selected_text)

  local namespace = vim.api.nvim_get_namespaces().intentpin
  local extmarks = vim.api.nvim_buf_get_extmarks(buf, namespace, 0, -1, { details = true })
  equal(1, #extmarks)
  truthy(extmarks[1][4].sign_text)

  vim.api.nvim_buf_set_lines(buf, 0, 0, false, { "inserted before" })
  require("intentpin.anchor").sync(buf)
  equal(1, notes[1].range.start.line)
  equal("target", notes[1].selected_text)
  vim.api.nvim_buf_delete(buf, { force = true })
end)

test("opens and closes the NUI manager", function()
  local manager = require("intentpin.ui.manager")
  manager.open("/work/empty-project", { preview = true })
  truthy(manager.is_open())
  manager.close()
  equal(false, manager.is_open())
end)

test("registers the IntentPin command", function()
  truthy(vim.fn.exists(":IntentPin") == 2)
end)

vim.fn.delete(temp, "rf")
print(string.format("1..%d", total))
if failures > 0 then
  print(string.format("%d test(s) failed", failures))
  vim.cmd("cquit 1")
else
  print(string.format("all %d tests passed", total))
  vim.cmd("qa!")
end

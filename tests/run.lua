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

test("attaches signs to buffers that were open before setup", function()
  require("intentpin.config").setup({ storage = { path = temp } })

  local project_dir = vim.fs.joinpath(temp, "late-setup-project")
  local source_dir = vim.fs.joinpath(project_dir, "src")
  vim.fn.mkdir(vim.fs.joinpath(project_dir, ".git"), "p")
  vim.fn.mkdir(source_dir, "p")

  local store = require("intentpin.store")
  store.reset()
  store.add(project_dir, note())

  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(buf, vim.fs.joinpath(source_dir, "example.lua"))
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "before", "target", "after" })
  vim.api.nvim_win_set_buf(0, buf)

  require("intentpin").setup({ storage = { path = temp } })

  local namespace = vim.api.nvim_get_namespaces().intentpin
  local extmarks = vim.api.nvim_buf_get_extmarks(buf, namespace, 0, -1, { details = true })
  equal(1, #extmarks, "setup should render persisted signs in already-open buffers")
  truthy(extmarks[1][4].sign_text)
  vim.api.nvim_buf_delete(buf, { force = true })
end)

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

test("prepends a custom prompt to exports with absolute paths", function()
  local output = require("intentpin.export").format("/work/project", { note() }, {
    absolute_paths = true,
    instruction_language = "custom",
    custom_instruction = "Implement every request below.",
  })
  truthy(vim.startswith(output, "Implement every request below.\n\n"))
  truthy(output:find("/work/project/src/example.lua:2", 1, true))
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

test("validates the configured hover mode", function()
  local config = require("intentpin.config")
  local ok, err = pcall(config.setup, {
    storage = { path = temp },
    hover = { mode = "unknown" },
  })
  equal(false, ok)
  truthy(tostring(err):find("hover.mode", 1, true))
  config.setup({ storage = { path = temp } })
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
  equal("v", vim.api.nvim_get_mode().mode, "selection should still be active")

  local captured = require("intentpin.selection").capture(buf)
  equal("target", captured.selected_text)
  equal("src/example.lua", captured.file)

  vim.cmd("normal! \27gg05lv5h")
  equal("v", vim.api.nvim_get_mode().mode, "reverse selection should still be active")
  local reversed = require("intentpin.selection").capture(buf)
  equal("target", reversed.selected_text, "reverse selections should be normalized")
  vim.cmd("normal! \27gg0v5l")

  local editor = require("intentpin.ui.editor")
  local original_open = editor.open
  local editor_opts
  editor.open = function(opts)
    editor_opts = opts
  end
  require("intentpin.actions").add()
  editor.open = original_open
  truthy(editor_opts)
  vim.cmd("normal! \27")
  editor_opts.on_submit("Pin this selection")

  local notes = require("intentpin.store").list(captured.root)
  equal(1, #notes)
  equal("Pin this selection", notes[1].comment)
  equal("target", notes[1].selected_text)

  local namespace = vim.api.nvim_get_namespaces().intentpin
  local extmarks = vim.api.nvim_buf_get_extmarks(buf, namespace, 0, -1, { details = true })
  equal(1, #extmarks)
  truthy(extmarks[1][4].sign_text)
  equal(nil, extmarks[1][4].virt_text)
  equal(nil, extmarks[1][4].hl_group)

  vim.api.nvim_buf_set_lines(buf, 0, 0, false, { "inserted before" })
  require("intentpin.anchor").sync(buf)
  equal(1, notes[1].range.start.line)
  equal("target", notes[1].selected_text)

  vim.api.nvim_win_set_cursor(0, { 2, 1 })
  equal(true, require("intentpin.actions").hover())
  truthy(require("intentpin.ui.hover").is_open())
  local hover_namespace = vim.api.nvim_get_namespaces()["intentpin-hover"]
  local hover_marks = vim.api.nvim_buf_get_extmarks(buf, hover_namespace, 0, -1, { details = true })
  equal(2, #hover_marks)
  local has_virtual_lines = false
  for _, mark in ipairs(hover_marks) do
    has_virtual_lines = has_virtual_lines or mark[4].virt_lines ~= nil
  end
  truthy(has_virtual_lines, "hover should render virtual lines")
  vim.api.nvim_exec_autocmds("CursorMoved", { buffer = buf })
  equal(false, require("intentpin.ui.hover").is_open())
  equal(0, #vim.api.nvim_buf_get_extmarks(buf, hover_namespace, 0, -1, {}))

  require("intentpin.config").get().hover.mode = "floating_window"
  equal(true, require("intentpin.actions").hover())
  truthy(require("intentpin.ui.hover").is_open())
  hover_marks = vim.api.nvim_buf_get_extmarks(buf, hover_namespace, 0, -1, { details = true })
  equal(1, #hover_marks)
  equal(nil, hover_marks[1][4].virt_lines)
  vim.api.nvim_exec_autocmds("CursorMoved", { buffer = buf })
  equal(false, require("intentpin.ui.hover").is_open())
  equal(0, #vim.api.nvim_buf_get_extmarks(buf, hover_namespace, 0, -1, {}))
  require("intentpin.config").get().hover.mode = "virtual_lines"
  vim.api.nvim_buf_delete(buf, { force = true })
end)

test("keeps the note editor open when leaving insert mode", function()
  local editor = require("intentpin.ui.editor")
  editor.open({
    title = "Editor mode test",
    on_submit = function() end,
  })
  truthy(editor.is_open())
  local escape = vim.api.nvim_replace_termcodes("<Esc>", true, false, true)
  vim.api.nvim_feedkeys(escape, "x", false)
  vim.wait(20)
  truthy(editor.is_open(), "editor closed when entering normal mode")
  vim.api.nvim_feedkeys("q", "x", false)
  vim.wait(20)
  equal(false, editor.is_open())

  editor.open({
    title = "Editor Ctrl-C test",
    on_submit = function() end,
  })
  equal({}, vim.fn.maparg("<C-c>", "i", false, true), "editor must not map Ctrl-C to close")
  vim.cmd.stopinsert()
  truthy(editor.is_open(), "editor closed when entering normal mode")
  vim.api.nvim_feedkeys("q", "x", false)
  vim.wait(20)
  equal(false, editor.is_open())

  local cancelled = false
  editor.open({
    title = "Editor quit test",
    on_submit = function() end,
    on_cancel = function()
      cancelled = true
    end,
  })
  vim.cmd.stopinsert()
  vim.cmd.quit()
  vim.wait(20)
  equal(false, editor.is_open())
  equal(true, cancelled)
end)

test("configures spellcheck in the note editor", function()
  local config = require("intentpin.config")
  local editor = require("intentpin.ui.editor")

  config.setup({
    storage = { path = temp },
    editor = { spell = true, spelllang = "en_us" },
  })
  editor.open({
    title = "Editor spell test",
    on_submit = function() end,
  })
  equal(true, vim.wo.spell)
  equal("en_us", vim.bo.spelllang)
  vim.cmd.stopinsert()
  vim.api.nvim_feedkeys("q", "x", false)
  vim.wait(20)

  config.setup({ storage = { path = temp }, editor = { spell = false } })
  vim.wo.spell = true
  editor.open({
    title = "Editor spell disabled test",
    on_submit = function() end,
  })
  equal(false, vim.wo.spell)
  vim.cmd.stopinsert()
  vim.api.nvim_feedkeys("q", "x", false)
  vim.wait(20)
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

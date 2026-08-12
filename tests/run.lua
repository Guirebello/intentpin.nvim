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
    "Faça as alterações indicadas e responda às perguntas. Altere código somente quando necessário para atender a um pedido de mudança.\n\n"
      .. "src/alpha.lua:1\n| alpha\n> First line\n> Second line\n\n"
      .. "src/example.lua:2\n| target\n> Change this\n",
    output
  )
end)

test("matches the VSCode built-in export instructions", function()
  local expected = {
    ["pt-BR"] = "Faça as alterações indicadas e responda às perguntas. Altere código somente quando necessário para atender a um pedido de mudança.",
    en = "Make the indicated changes and answer any questions. Change code only when necessary to fulfill a requested change.",
    es = "Realiza los cambios indicados y responde las preguntas. Modifica código solo cuando sea necesario para cumplir un cambio solicitado.",
  }
  for language, instruction in pairs(expected) do
    local output = require("intentpin.export").format("/work/project", { note() }, {
      instruction_language = language,
    })
    truthy(vim.startswith(output, instruction .. "\n\n"), "unexpected " .. language .. " instruction")
  end
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

test("includes and excludes every note in one operation", function()
  local store = require("intentpin.store")
  local root = "/work/intentpin-bulk-inclusion-project"
  store.reset()
  store.add(root, note({ id = "bulk-1", included = true }))
  store.add(root, note({ id = "bulk-2", included = false }))

  store.set_all_included(root, true)
  equal(true, store.get(root, "bulk-1").included)
  equal(true, store.get(root, "bulk-2").included)

  store.set_all_included(root, false)
  equal(false, store.get(root, "bulk-1").included)
  equal(false, store.get(root, "bulk-2").included)
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

test("reports recovered and missing anchors in loaded files", function()
  local project_dir = vim.fs.joinpath(temp, "reanchor-project")
  local source_dir = vim.fs.joinpath(project_dir, "src")
  vim.fn.mkdir(vim.fs.joinpath(project_dir, ".git"), "p")
  vim.fn.mkdir(source_dir, "p")
  require("intentpin.store").add(project_dir, note({ id = "reanchor-note" }))

  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(buf, vim.fs.joinpath(source_dir, "example.lua"))
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "before", "different", "after" })
  vim.api.nvim_win_set_buf(0, buf)
  local anchor = require("intentpin.anchor")
  anchor.attach(buf, project_dir)
  truthy(anchor.is_orphaned(project_dir, "reanchor-note"))

  vim.api.nvim_buf_set_lines(buf, 1, 2, false, { "target" })
  local notifications = {}
  local original_notify = vim.notify
  vim.notify = function(message)
    notifications[#notifications + 1] = message
  end
  local ok, recovered = pcall(require("intentpin.actions").reanchor, project_dir)
  vim.notify = original_notify
  if not ok then
    error(recovered)
  end

  equal({ checked = 1, recovered = 1, missing = 0, files = 1 }, recovered)
  equal("Anchors: 1 checked · 1 recovered · 0 still missing", notifications[#notifications])
  equal(false, anchor.is_orphaned(project_dir, "reanchor-note"))

  vim.api.nvim_buf_set_lines(buf, 1, 2, false, { "different again" })
  local missing = anchor.refresh_root(project_dir)
  equal({ checked = 1, recovered = 0, missing = 1, files = 1 }, missing)
  truthy(anchor.is_orphaned(project_dir, "reanchor-note"))
  vim.api.nvim_buf_delete(buf, { force = true })
end)

test("expands every note in the current file until toggled", function()
  local project_dir = vim.fs.joinpath(temp, "expanded-project")
  local source_dir = vim.fs.joinpath(project_dir, "src")
  vim.fn.mkdir(vim.fs.joinpath(project_dir, ".git"), "p")
  vim.fn.mkdir(source_dir, "p")

  local store = require("intentpin.store")
  store.add(project_dir, note({ id = "expanded-1" }))
  store.add(project_dir, note({
    id = "expanded-2",
    range = {
      start = { line = 2, character = 0 },
      ["end"] = { line = 2, character = 5 },
    },
    selected_text = "after",
    context_before = { "target" },
    context_after = {},
    comment = "Check the final line",
  }))

  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(buf, vim.fs.joinpath(source_dir, "example.lua"))
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "before", "target", "after" })
  vim.api.nvim_win_set_buf(0, buf)
  require("intentpin.anchor").attach(buf, project_dir)

  local actions = require("intentpin.actions")
  local expanded = require("intentpin.ui.expanded")
  equal(true, actions.expand("toggle"))
  truthy(expanded.is_open(buf))

  local expanded_namespace = vim.api.nvim_get_namespaces()["intentpin-expanded"]
  local extmarks = vim.api.nvim_buf_get_extmarks(buf, expanded_namespace, 0, -1, { details = true })
  equal(4, #extmarks, "each note should have a range highlight and virtual lines")
  local virtual_line_count = 0
  for _, mark in ipairs(extmarks) do
    if mark[4].virt_lines then
      virtual_line_count = virtual_line_count + 1
    end
  end
  equal(2, virtual_line_count)

  vim.api.nvim_exec_autocmds("CursorMoved", { buffer = buf })
  vim.api.nvim_exec_autocmds("InsertEnter", { buffer = buf })
  truthy(expanded.is_open(buf), "expanded notes should stay open while editing")

  equal(false, actions.expand("toggle"))
  equal(false, expanded.is_open(buf))
  equal(0, #vim.api.nvim_buf_get_extmarks(buf, expanded_namespace, 0, -1, {}))
  vim.api.nvim_buf_delete(buf, { force = true })
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

test("configures diagnostics in the note editor", function()
  local config = require("intentpin.config")
  local editor = require("intentpin.ui.editor")

  config.setup({ storage = { path = temp }, editor = { diagnostics = false } })
  editor.open({
    title = "Editor diagnostics disabled test",
    on_submit = function() end,
  })
  equal(false, vim.diagnostic.is_enabled({ bufnr = vim.api.nvim_get_current_buf() }))
  vim.cmd.stopinsert()
  vim.api.nvim_feedkeys("q", "x", false)
  vim.wait(20)

  config.setup({ storage = { path = temp }, editor = { diagnostics = true } })
  editor.open({
    title = "Editor diagnostics enabled test",
    on_submit = function() end,
  })
  equal(true, vim.diagnostic.is_enabled({ bufnr = vim.api.nvim_get_current_buf() }))
  vim.cmd.stopinsert()
  vim.api.nvim_feedkeys("q", "x", false)
  vim.wait(20)
end)

test("disables completion in the note editor by default", function()
  local config = require("intentpin.config")
  local editor = require("intentpin.ui.editor")
  local previous_cmp = package.loaded["cmp"]
  local cmp_enabled

  package.loaded["cmp"] = {
    setup = {
      buffer = function(opts)
        cmp_enabled = opts.enabled
      end,
    },
    visible = function()
      return false
    end,
  }

  config.setup({ storage = { path = temp } })
  editor.open({
    title = "Editor completion disabled test",
    on_submit = function() end,
  })
  local bufnr = vim.api.nvim_get_current_buf()
  equal(false, vim.b[bufnr].completion)
  if vim.fn.exists("+autocomplete") == 1 then
    equal(false, vim.bo[bufnr].autocomplete)
  end
  equal("", vim.bo[bufnr].completefunc)
  equal("", vim.bo[bufnr].omnifunc)
  equal(false, cmp_enabled)
  vim.cmd.stopinsert()
  vim.api.nvim_feedkeys("q", "x", false)
  vim.wait(20)

  cmp_enabled = nil
  config.setup({ storage = { path = temp }, editor = { completion = true } })
  editor.open({
    title = "Editor completion enabled test",
    on_submit = function() end,
  })
  equal(nil, vim.b[vim.api.nvim_get_current_buf()].completion)
  equal(nil, cmp_enabled, "enabled completion should preserve the user's completion configuration")
  vim.cmd.stopinsert()
  vim.api.nvim_feedkeys("q", "x", false)
  vim.wait(20)

  package.loaded["cmp"] = previous_cmp
end)

test("opens and closes the NUI manager", function()
  local manager = require("intentpin.ui.manager")
  manager.open("/work/empty-project", { preview = true })
  truthy(manager.is_open())
  manager.close()
  equal(false, manager.is_open())
end)

test("opens persistent manager help without a preview pane", function()
  local manager = require("intentpin.ui.manager")
  local help = require("intentpin.ui.help")
  manager.open("/work/help-project", { preview = false, force = true })
  truthy(manager.is_open())

  vim.api.nvim_feedkeys("?", "x", false)
  vim.wait(50, function()
    return help.is_open()
  end)
  truthy(help.is_open(), "? should open the manager help buffer")

  local help_buf
  local list_buf
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) then
      if vim.bo[buf].filetype == "intentpin-help" then
        help_buf = buf
      elseif vim.bo[buf].filetype == "intentpin" then
        list_buf = buf
      end
    end
  end
  truthy(help_buf, "manager help buffer was not found")
  truthy(list_buf, "manager list buffer was not found")
  local help_zindex = vim.api.nvim_win_get_config(vim.fn.bufwinid(help_buf)).zindex
  local manager_zindex = vim.api.nvim_win_get_config(vim.fn.bufwinid(list_buf)).zindex
  truthy(help_zindex > manager_zindex, "manager help should render above the manager")
  local lines = vim.api.nvim_buf_get_lines(help_buf, 0, -1, false)
  truthy(vim.tbl_contains(lines, "Navigation"))
  truthy(vim.tbl_contains(lines, "Export"))

  vim.api.nvim_feedkeys("?", "x", false)
  vim.wait(50, function()
    return not help.is_open()
  end)
  equal(false, help.is_open())
  truthy(manager.is_open(), "closing help should return to the manager")
  manager.close()
end)

test("shows orphan warnings beside manager checkboxes", function()
  local project_dir = vim.fs.joinpath(temp, "orphan-manager-project")
  local source_dir = vim.fs.joinpath(project_dir, "src")
  vim.fn.mkdir(vim.fs.joinpath(project_dir, ".git"), "p")
  vim.fn.mkdir(source_dir, "p")

  local orphan = note({
    id = "orphan-manager",
    comment = string.rep("Long comment ", 10),
  })
  require("intentpin.store").add(project_dir, orphan)

  local source_buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(source_buf, vim.fs.joinpath(source_dir, "example.lua"))
  vim.api.nvim_buf_set_lines(source_buf, 0, -1, false, { "before", "different", "after" })
  vim.api.nvim_win_set_buf(0, source_buf)
  require("intentpin.anchor").attach(source_buf, project_dir)
  truthy(require("intentpin.anchor").is_orphaned(project_dir, orphan.id))
  local anchor_namespace = vim.api.nvim_get_namespaces().intentpin
  local anchor_marks = vim.api.nvim_buf_get_extmarks(source_buf, anchor_namespace, 0, -1, { details = true })
  equal(1, #anchor_marks)
  equal("!", vim.trim(anchor_marks[1][4].sign_text), "orphan gutter signs should match manager warnings")

  local manager = require("intentpin.ui.manager")
  manager.open(project_dir, { preview = true, force = true })

  local list_buf
  local preview_buf
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) then
      if vim.bo[buf].filetype == "intentpin" then
        list_buf = buf
      elseif vim.bo[buf].filetype == "intentpin-preview" then
        preview_buf = buf
      end
    end
  end
  truthy(list_buf, "manager list buffer was not found")
  truthy(preview_buf, "manager preview buffer was not found")

  local lines = vim.api.nvim_buf_get_lines(list_buf, 0, -1, false)
  local note_row
  for row, line in ipairs(lines) do
    if line:find("[x] ! L2", 1, true) then
      note_row = row
      break
    end
  end
  truthy(note_row, "orphan warning should be visible beside the checkbox")

  local manager_namespace = vim.api.nvim_get_namespaces()["intentpin-manager"]
  local extmarks = vim.api.nvim_buf_get_extmarks(list_buf, manager_namespace, 0, -1, { details = true })
  local warning_is_highlighted = false
  for _, mark in ipairs(extmarks) do
    local details = mark[4]
    if mark[2] == note_row - 1 and mark[3] == 8 and details.hl_group == "IntentPinOrphan" then
      warning_is_highlighted = details.end_col == 9
      break
    end
  end
  truthy(warning_is_highlighted, "orphan warning should use IntentPinOrphan")

  local preview_lines = vim.api.nvim_buf_get_lines(preview_buf, 0, -1, false)
  equal("Anchor needs attention: the original code was not found.", preview_lines[3])
  local preview_marks = vim.api.nvim_buf_get_extmarks(preview_buf, manager_namespace, 0, -1, { details = true })
  local preview_warning_is_highlighted = false
  for _, mark in ipairs(preview_marks) do
    local details = mark[4]
    if mark[2] == 2 and mark[3] == 0 and details.hl_group == "IntentPinOrphan" then
      preview_warning_is_highlighted = details.end_col == #preview_lines[3]
      break
    end
  end
  truthy(preview_warning_is_highlighted, "preview warning should use IntentPinOrphan")

  manager.close()
  vim.api.nvim_buf_delete(source_buf, { force = true })
end)

test("supports a borderless note editor", function()
  local config = require("intentpin.config")
  local editor = require("intentpin.ui.editor")
  config.setup({
    storage = { path = temp },
    editor = { border = "none" },
  })

  local ok, err = pcall(editor.open, {
    title = "Borderless editor test",
    on_submit = function() end,
  })
  truthy(ok, tostring(err))

  vim.cmd.stopinsert()
  vim.api.nvim_feedkeys("q", "x", false)
  vim.wait(20)
  equal(false, editor.is_open())
end)

test("supports a borderless note manager and help", function()
  local config = require("intentpin.config")
  local manager = require("intentpin.ui.manager")
  local help = require("intentpin.ui.help")
  config.setup({
    storage = { path = temp },
    manager = { border = "none" },
  })

  local ok, err = pcall(manager.open, "/work/borderless-manager-project", {
    preview = true,
    force = true,
  })
  truthy(ok, tostring(err))
  truthy(manager.is_open())

  vim.api.nvim_feedkeys("?", "x", false)
  vim.wait(50, function()
    return help.is_open()
  end)
  truthy(help.is_open(), "borderless manager help should open")
  help.close()
  manager.close()
end)

test("supports a borderless floating hover", function()
  local config = require("intentpin.config")
  local floating_hover = require("intentpin.ui.hover.floating_window")
  config.setup({
    storage = { path = temp },
    hover = { mode = "floating_window", border = "none" },
  })

  local popup
  local ok, err = pcall(function()
    popup = floating_hover.open({
      buf = vim.api.nvim_get_current_buf(),
      notes = { note() },
    })
  end)
  truthy(ok, tostring(err))
  truthy(floating_hover.is_open(popup))
  floating_hover.close(popup)
end)

test("omits titles for NUI border styles without text support", function()
  local border = require("intentpin.ui.border")
  local text = { top = " IntentPin " }

  for _, style in ipairs({ "none", "shadow" }) do
    equal({ style = style }, border.with_text(style, text))
  end

  for _, style in ipairs({ "default", "double", "rounded", "single", "solid" }) do
    equal({ style = style, text = text }, border.with_text(style, text))
  end
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

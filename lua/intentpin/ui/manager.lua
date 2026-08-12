local anchor = require("intentpin.anchor")
local border_ui = require("intentpin.ui.border")
local config = require("intentpin.config")
local help = require("intentpin.ui.help")
local store = require("intentpin.store")
local util = require("intentpin.util")

local M = {}
local namespace = vim.api.nvim_create_namespace("intentpin-manager")
local ui

local function dimensions()
  local opts = config.get().manager
  local width = math.min(vim.o.columns - 4, math.max(60, math.floor(vim.o.columns * opts.width)))
  local height = math.min(vim.o.lines - 4, math.max(14, math.floor(vim.o.lines * opts.height)))
  return width, height
end

---@param notes table[]
---@return table[]
local function sorted(notes)
  local result = vim.deepcopy(notes)
  table.sort(result, function(left, right)
    if left.file ~= right.file then
      return left.file < right.file
    end
    if left.range.start.line ~= right.range.start.line then
      return left.range.start.line < right.range.start.line
    end
    return left.range.start.character < right.range.start.character
  end)
  return result
end

local function current_id()
  if not ui or not vim.api.nvim_win_is_valid(ui.list.winid) then
    return nil
  end
  local row = vim.api.nvim_win_get_cursor(ui.list.winid)[1]
  return ui.row_to_id[row]
end

local function current_note()
  local id = current_id()
  return id and store.get(ui.root, id) or nil
end

local function set_lines(buf, lines)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
end

local function render_preview()
  if not ui or not ui.show_preview or not ui.preview.bufnr or not vim.api.nvim_buf_is_valid(ui.preview.bufnr) then
    return
  end
  local note = current_note()
  if not note then
    set_lines(ui.preview.bufnr, { "Move the cursor onto a note to preview it." })
    return
  end

  local lines = {
    string.format("%s:%s", note.file, util.range_label(note.range)),
    note.included and "Included in checked exports" or "Excluded from checked exports",
  }
  local warning_row
  if anchor.is_orphaned(ui.root, note.id) then
    lines[#lines + 1] = "Anchor needs attention: the original code was not found."
    warning_row = #lines
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = "Selected code"
  for _, line in ipairs(util.lines(note.selected_text)) do
    lines[#lines + 1] = "│ " .. line
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = "Note"
  for _, line in ipairs(util.lines(note.comment)) do
    lines[#lines + 1] = "> " .. line
  end
  set_lines(ui.preview.bufnr, lines)
  vim.api.nvim_buf_clear_namespace(ui.preview.bufnr, namespace, 0, -1)
  vim.api.nvim_buf_set_extmark(ui.preview.bufnr, namespace, 0, 0, {
    end_col = #lines[1],
    hl_group = "IntentPinLocation",
  })
  vim.api.nvim_buf_set_extmark(ui.preview.bufnr, namespace, 1, 0, {
    end_col = #lines[2],
    hl_group = note.included and "IntentPinIncluded" or "IntentPinExcluded",
  })
  if warning_row then
    vim.api.nvim_buf_set_extmark(ui.preview.bufnr, namespace, warning_row - 1, 0, {
      end_col = #lines[warning_row],
      hl_group = "IntentPinOrphan",
    })
  end
end

local function render_list(focus_id)
  if not ui or not vim.api.nvim_buf_is_valid(ui.list.bufnr) then
    return
  end
  local previous = focus_id or current_id()
  local notes = sorted(store.list(ui.root))
  local lines = {}
  local headings = {}
  local note_rows = {}
  ui.row_to_id = {}
  local last_file

  if #notes == 0 then
    lines = { "", "  No IntentPin notes in this project.", "", "  Select code and run :IntentPin add" }
  else
    for _, note in ipairs(notes) do
      if note.file ~= last_file then
        if #lines > 0 then
          lines[#lines + 1] = ""
        end
        lines[#lines + 1] = "  " .. note.file
        headings[#headings + 1] = #lines
        last_file = note.file
      end
      local checked = note.included and "[x]" or "[ ]"
      local orphaned = anchor.is_orphaned(ui.root, note.id)
      local warning = orphaned and "!" or " "
      lines[#lines + 1] = string.format(
        "    %s %s %-10s %s",
        checked,
        warning,
        "L" .. util.range_label(note.range),
        util.summary(note.comment, 70)
      )
      ui.row_to_id[#lines] = note.id
      note_rows[#note_rows + 1] = { row = #lines, included = note.included, orphaned = orphaned }
    end
  end

  set_lines(ui.list.bufnr, lines)
  vim.api.nvim_buf_clear_namespace(ui.list.bufnr, namespace, 0, -1)
  for _, row in ipairs(headings) do
    vim.api.nvim_buf_set_extmark(ui.list.bufnr, namespace, row - 1, 0, {
      end_col = #lines[row],
      hl_group = "IntentPinFile",
    })
  end
  for _, item in ipairs(note_rows) do
    vim.api.nvim_buf_set_extmark(ui.list.bufnr, namespace, item.row - 1, 4, {
      end_col = 7,
      hl_group = item.included and "IntentPinIncluded" or "IntentPinExcluded",
    })
    if item.orphaned then
      vim.api.nvim_buf_set_extmark(ui.list.bufnr, namespace, item.row - 1, 8, {
        end_col = 9,
        hl_group = "IntentPinOrphan",
      })
    end
  end

  if vim.api.nvim_win_is_valid(ui.list.winid) then
    local target = 1
    for row = 1, #lines do
      local id = ui.row_to_id[row]
      if (previous and id == previous) or (not previous and id) then
        target = row
        break
      end
    end
    vim.api.nvim_win_set_cursor(ui.list.winid, { math.min(target, #lines), 0 })
  end
  render_preview()
end

function M.close()
  if not ui then
    return
  end
  local current = ui
  ui = nil
  help.close()
  if current.layout then
    current.layout:unmount()
  end
end

---@return boolean
function M.is_open()
  return ui ~= nil and ui.list.winid ~= nil and vim.api.nvim_win_is_valid(ui.list.winid)
end

---@param project_root string
---@param opts? { focus_id?: string, preview?: boolean, force?: boolean }
function M.open(project_root, opts)
  opts = opts or {}
  if M.is_open() and ui.root == project_root and not opts.force then
    M.close()
    return
  end
  M.close()

  local ok_popup, Popup = pcall(require, "nui.popup")
  local ok_layout, Layout = pcall(require, "nui.layout")
  if not ok_popup or not ok_layout then
    error("IntentPin: nui.nvim is required for the note manager")
  end

  local border = config.get().manager.border
  local list = Popup({
    enter = true,
    focusable = true,
    border = border_ui.with_text(border, {
      top = " IntentPin ",
      top_align = "center",
      bottom = " <CR> jump · <Space> include · e edit · d delete · ? help ",
      bottom_align = "center",
    }),
    win_options = {
      cursorline = true,
      wrap = false,
      winhighlight = "Normal:IntentPinNormal,FloatBorder:IntentPinBorder,CursorLine:IntentPinCursorLine",
    },
  })
  local preview = Popup({
    enter = false,
    focusable = false,
    border = border_ui.with_text(border, { top = " Preview ", top_align = "center" }),
    win_options = {
      wrap = true,
      linebreak = true,
      winhighlight = "Normal:IntentPinNormal,FloatBorder:IntentPinBorder",
    },
  })
  local width, height = dimensions()
  local show_preview = opts.preview
  if show_preview == nil then
    show_preview = config.get().manager.preview
  end
  local box
  if show_preview then
    local direction = vim.o.columns >= 110 and "row" or "col"
    box = Layout.Box({
      Layout.Box(list, { size = direction == "row" and "44%" or "46%" }),
      Layout.Box(preview, { size = direction == "row" and "56%" or "54%" }),
    }, { dir = direction })
  else
    box = Layout.Box({ Layout.Box(list, { size = "100%" }) })
  end
  local layout = Layout({ position = "50%", size = { width = width, height = height } }, box)
  ui = {
    root = project_root,
    list = list,
    preview = preview,
    layout = layout,
    show_preview = show_preview,
    row_to_id = {},
  }
  layout:mount()

  vim.bo[list.bufnr].buftype = "nofile"
  vim.bo[list.bufnr].bufhidden = "wipe"
  vim.bo[list.bufnr].swapfile = false
  vim.bo[list.bufnr].filetype = "intentpin"
  if show_preview then
    vim.bo[preview.bufnr].buftype = "nofile"
    vim.bo[preview.bufnr].bufhidden = "wipe"
    vim.bo[preview.bufnr].swapfile = false
    vim.bo[preview.bufnr].filetype = "intentpin-preview"
  end

  local function with_current(callback)
    local id = current_id()
    if id then
      callback(id)
    end
  end
  list:map("n", "q", M.close, { noremap = true, nowait = true })
  list:map("n", "<Esc>", M.close, { noremap = true, nowait = true })
  list:map("n", "<CR>", function()
    with_current(function(id)
      require("intentpin.actions").jump(project_root, id)
    end)
  end, { noremap = true, nowait = true })
  list:map("n", "<Space>", function()
    with_current(function(id)
      store.toggle(project_root, id)
    end)
  end, { noremap = true, nowait = true })
  list:map("n", "a", function()
    store.set_all_included(project_root, true)
  end, { noremap = true, nowait = true })
  list:map("n", "u", function()
    store.set_all_included(project_root, false)
  end, { noremap = true, nowait = true })
  list:map("n", "e", function()
    with_current(function(id)
      require("intentpin.actions").edit(project_root, id, true)
    end)
  end, { noremap = true, nowait = true })
  list:map("n", "d", function()
    with_current(function(id)
      require("intentpin.actions").delete(project_root, { id })
    end)
  end, { noremap = true, nowait = true })
  list:map("n", "D", function()
    require("intentpin.actions").clear(project_root)
  end, { noremap = true, nowait = true })
  list:map("n", "y", function()
    with_current(function(id)
      require("intentpin.actions").copy(project_root, "ids", false, { id })
    end)
  end, { noremap = true, nowait = true })
  list:map("n", "Y", function()
    require("intentpin.actions").copy(project_root, "checked", false)
  end, { noremap = true, nowait = true })
  list:map("n", "gY", function()
    require("intentpin.actions").copy(project_root, "checked", true)
  end, { noremap = true, nowait = true })
  list:map("n", "A", function()
    require("intentpin.actions").copy(project_root, "all", false)
  end, { noremap = true, nowait = true })
  list:map("n", "r", function()
    require("intentpin.actions").reanchor(project_root)
  end, { noremap = true, nowait = true })
  list:map("n", "p", function()
    local id = current_id()
    M.open(project_root, { focus_id = id, preview = not show_preview, force = true })
  end, { noremap = true, nowait = true })
  list:map("n", "?", function()
    help.open(list.winid)
  end, { noremap = true, nowait = true })

  vim.api.nvim_create_autocmd("CursorMoved", {
    buffer = list.bufnr,
    callback = render_preview,
  })
  render_list(opts.focus_id)
end

---@param project_root string
function M.refresh(project_root)
  if M.is_open() and ui.root == project_root then
    render_list()
  end
end

return M

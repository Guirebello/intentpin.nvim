local config = require("intentpin.config")
local util = require("intentpin.util")

local M = {}
local active

local function dimensions()
  local opts = config.get().editor
  local width = math.min(vim.o.columns - 4, math.max(40, math.floor(vim.o.columns * opts.width)))
  local height = math.min(vim.o.lines - 4, math.max(8, math.floor(vim.o.lines * opts.height)))
  return width, height
end

function M.close()
  if active then
    local popup = active
    active = nil
    if popup.bufnr and vim.api.nvim_buf_is_valid(popup.bufnr) then
      popup:unmount()
    end
  end
end

---@return boolean
function M.is_open()
  return active ~= nil
end

---@param opts { title: string, initial?: string, on_submit: fun(value: string), on_cancel?: fun() }
function M.open(opts)
  M.close()
  local ok, Popup = pcall(require, "nui.popup")
  if not ok then
    error("IntentPin: nui.nvim is required for the note editor")
  end

  local editor_opts = config.get().editor
  local width, height = dimensions()
  local popup = Popup({
    enter = true,
    focusable = true,
    relative = "editor",
    position = "50%",
    size = { width = width, height = height },
    border = {
      style = editor_opts.border,
      text = {
        top = " " .. opts.title .. " ",
        top_align = "center",
        bottom = " <C-s> save · q/:q cancel · <Esc>/<C-c> normal mode ",
        bottom_align = "center",
      },
    },
    win_options = {
      winhighlight = "Normal:IntentPinNormal,FloatBorder:IntentPinBorder",
      wrap = true,
      linebreak = true,
    },
  })
  active = popup
  popup:mount()

  vim.bo[popup.bufnr].buftype = "nofile"
  vim.bo[popup.bufnr].bufhidden = "wipe"
  vim.bo[popup.bufnr].swapfile = false
  vim.bo[popup.bufnr].filetype = "markdown"
  vim.diagnostic.enable(editor_opts.diagnostics, { bufnr = popup.bufnr })
  vim.wo[popup.winid].spell = editor_opts.spell
  if editor_opts.spelllang then
    vim.bo[popup.bufnr].spelllang = editor_opts.spelllang
  end
  vim.api.nvim_buf_set_lines(popup.bufnr, 0, -1, false, util.lines(opts.initial or ""))
  vim.bo[popup.bufnr].modified = false

  local finished = false
  local function cancel()
    if finished then
      return
    end
    finished = true
    M.close()
    if opts.on_cancel then
      vim.schedule(opts.on_cancel)
    end
  end

  local function submit()
    if finished then
      return
    end
    local value = vim.trim(table.concat(vim.api.nvim_buf_get_lines(popup.bufnr, 0, -1, false), "\n"))
    if value == "" then
      util.notify("A note cannot be empty", vim.log.levels.WARN)
      return
    end
    finished = true
    M.close()
    vim.schedule(function()
      opts.on_submit(value)
    end)
  end

  popup:map("n", "<C-s>", submit, { noremap = true, nowait = true })
  popup:map("i", "<C-s>", function()
    vim.cmd.stopinsert()
    vim.schedule(submit)
  end, { noremap = true, nowait = true })
  popup:map("n", "q", cancel, { noremap = true, nowait = true })

  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = popup.bufnr,
    once = true,
    callback = function()
      if not finished then
        finished = true
        active = nil
        if opts.on_cancel then
          vim.schedule(opts.on_cancel)
        end
      end
    end,
  })

  vim.cmd.startinsert()
end

return M

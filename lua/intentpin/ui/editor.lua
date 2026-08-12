local config = require("intentpin.config")
local border = require("intentpin.ui.border")
local util = require("intentpin.util")

local M = {}
local active

---@param bufnr integer
local function disable_completion(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  -- blink.cmp respects this buffer variable, while the remaining options
  -- disable Neovim's built-in completion sources for this scratch buffer.
  vim.b[bufnr].completion = false
  if vim.fn.exists("+autocomplete") == 1 then
    vim.bo[bufnr].autocomplete = false
  end
  vim.bo[bufnr].completefunc = ""
  vim.bo[bufnr].omnifunc = ""

  -- nvim-cmp needs an explicit buffer-local override. Do not require it here:
  -- completion plugins remain optional and may be loaded on InsertEnter.
  local cmp = package.loaded["cmp"]
  if type(cmp) == "table" and type(cmp.setup) == "table" and type(cmp.setup.buffer) == "function" then
    vim.api.nvim_buf_call(bufnr, function()
      cmp.setup.buffer({ enabled = false })
      if type(cmp.visible) == "function" and cmp.visible() and type(cmp.abort) == "function" then
        cmp.abort()
      end
    end)
  end
end

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
    border = border.with_text(editor_opts.border, {
      top = " " .. opts.title .. " ",
      top_align = "center",
      bottom = " <C-s> save · q/:q cancel · <Esc>/<C-c> normal mode ",
      bottom_align = "center",
    }),
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
  if not editor_opts.completion then
    disable_completion(popup.bufnr)
    vim.api.nvim_create_autocmd("InsertEnter", {
      buffer = popup.bufnr,
      once = true,
      callback = function()
        -- Let lazy-loaded completion plugins finish their InsertEnter handlers,
        -- then apply the buffer-local override without loading them ourselves.
        vim.schedule(function()
          disable_completion(popup.bufnr)
        end)
      end,
    })
  end
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

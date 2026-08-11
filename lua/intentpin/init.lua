local M = {}

local function highlights()
  local groups = {
    IntentPinNormal = { link = "NormalFloat" },
    IntentPinBorder = { link = "FloatBorder" },
    IntentPinCursorLine = { link = "CursorLine" },
    IntentPinFile = { link = "Directory" },
    IntentPinLocation = { link = "Title" },
    IntentPinIncluded = { link = "DiagnosticOk" },
    IntentPinExcluded = { link = "Comment" },
    IntentPinSign = { link = "DiagnosticHint" },
    IntentPinOrphan = { link = "DiagnosticWarn" },
    IntentPinVirtualText = { link = "Comment" },
    IntentPinRange = { link = "LspReferenceText" },
    IntentPinActiveRange = { link = "Visual" },
    IntentPinHoverBorder = { link = "FloatBorder" },
    IntentPinHoverTitle = { link = "Title" },
    IntentPinHoverText = { link = "NormalFloat" },
  }
  for name, value in pairs(groups) do
    value.default = true
    vim.api.nvim_set_hl(0, name, value)
  end
end

local function safely(callback)
  local ok, err = pcall(callback)
  if not ok then
    require("intentpin.util").notify(tostring(err), vim.log.levels.ERROR)
  end
end

---@param opts? table
function M.setup(opts)
  require("intentpin.config").setup(opts)
  require("intentpin.commands").setup()
  highlights()

  local anchor = require("intentpin.anchor")
  local root = require("intentpin.root")
  local store = require("intentpin.store")
  local function attach(buf)
    if
      vim.api.nvim_buf_is_valid(buf)
      and vim.api.nvim_buf_is_loaded(buf)
      and vim.bo[buf].buftype == ""
      and vim.api.nvim_buf_get_name(buf) ~= ""
    then
      anchor.attach(buf, root.current(buf))
    end
  end

  store.set_listener(function(project_root)
    anchor.refresh_root(project_root)
    require("intentpin.ui.manager").refresh(project_root)
  end)

  local group = vim.api.nvim_create_augroup("IntentPin", { clear = true })
  vim.api.nvim_create_autocmd({ "BufEnter", "BufReadPost" }, {
    group = group,
    callback = function(event)
      safely(function()
        attach(event.buf)
      end)
    end,
  })
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    callback = function(event)
      safely(function()
        anchor.sync(event.buf)
      end)
    end,
  })

  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    safely(function()
      attach(buf)
    end)
  end
end

---@return boolean
function M.hover()
  return require("intentpin.actions").hover()
end

return M

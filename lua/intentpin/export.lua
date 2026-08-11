local config = require("intentpin.config")
local util = require("intentpin.util")

local M = {}

local instructions = {
  ["pt-BR"] = "Faça as alterações indicadas e responda às perguntas. Altere código somente quando necessário para atender a um pedido de mudança.",
  en = "Make the indicated changes and answer any questions. Change code only when necessary to fulfill a requested change.",
  es = "Realiza los cambios indicados y responde las preguntas. Modifica código solo cuando sea necesario para cumplir un cambio solicitado.",
}

---@param value string
---@param prefix string
---@return string
local function prefix_lines(value, prefix)
  value = value:gsub("[\r\n]+$", "")
  local lines = vim.split(value, "\n", { plain = true })
  for index, line in ipairs(lines) do
    lines[index] = line == "" and prefix or (prefix .. " " .. line)
  end
  return table.concat(lines, "\n")
end

---@param left table
---@param right table
---@return boolean
local function before(left, right)
  if left.file ~= right.file then
    return left.file < right.file
  end
  if left.range.start.line ~= right.range.start.line then
    return left.range.start.line < right.range.start.line
  end
  return left.range.start.character < right.range.start.character
end

---@param opts table
---@return string
local function instruction(opts)
  if opts.instruction_language == "custom" then
    local custom = vim.trim(opts.custom_instruction or "")
    if custom == "" then
      error("IntentPin: set export.custom_instruction before copying notes")
    end
    return custom
  end
  return instructions[opts.instruction_language] or instructions.en
end

---@param project_root string
---@param notes table[]
---@param opts? table
---@return string
function M.format(project_root, notes, opts)
  opts = vim.tbl_deep_extend("force", vim.deepcopy(config.get().export), opts or {})
  local sorted = vim.deepcopy(notes)
  table.sort(sorted, before)
  local sections = {}

  for _, note in ipairs(sorted) do
    local file = opts.absolute_paths and util.absolute_path(project_root, note.file) or note.file
    local section = { string.format("%s:%s", file, util.range_label(note.range)) }
    if opts.include_selected_text and note.selected_text ~= "" then
      section[#section + 1] = prefix_lines(note.selected_text, "|")
    end
    section[#section + 1] = prefix_lines(note.comment, ">")
    sections[#sections + 1] = table.concat(section, "\n")
  end

  return string.format("%s\n\n%s\n", instruction(opts), table.concat(sections, "\n\n"))
end

---@param project_root string
---@param notes table[]
---@param opts? table
---@return string
function M.copy(project_root, notes, opts)
  if #notes == 0 then
    error("IntentPin: no notes were selected to copy")
  end
  local output = M.format(project_root, notes, opts)
  vim.fn.setreg('"', output)
  pcall(vim.fn.setreg, "+", output)
  return output
end

return M

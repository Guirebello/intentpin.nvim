local M = {}

---@param value string
---@return string[]
function M.lines(value)
  if value == "" then
    return { "" }
  end
  return vim.split(value, "\n", { plain = true })
end

---@param value string
---@param limit? number
---@return string
function M.summary(value, limit)
  limit = limit or 72
  local first = vim.trim((value:match("([^\r\n]*)") or "")):gsub("%s+", " ")
  if first == "" then
    return "Untitled note"
  end
  if vim.fn.strdisplaywidth(first) <= limit then
    return first
  end
  return vim.fn.strcharpart(first, 0, math.max(1, limit - 1)) .. "…"
end

---@param range table
---@param prefix? string
---@return string
function M.range_label(range, prefix)
  local start_line = range.start.line + 1
  local end_line = range["end"].line + 1
  if range["end"].character == 0 and range["end"].line > range.start.line then
    end_line = range["end"].line
  end

  local label = start_line == end_line and tostring(start_line)
    or string.format("%d-%d", start_line, end_line)
  return (prefix or "") .. label
end

---@return string
function M.timestamp()
  return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

---@param root string
---@param file string
---@return string
function M.absolute_path(root, file)
  local parts = vim.split(file, "/", { plain = true, trimempty = true })
  return vim.fs.joinpath(root, unpack(parts))
end

---@param value any
---@return boolean
function M.is_array_of_strings(value)
  if type(value) ~= "table" then
    return false
  end
  for _, item in ipairs(value) do
    if type(item) ~= "string" then
      return false
    end
  end
  return true
end

---@param message string
---@param level? integer
function M.notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = "IntentPin" })
end

---@param left table
---@param right table
---@return boolean
function M.range_equal(left, right)
  return left.start.line == right.start.line
    and left.start.character == right.start.character
    and left["end"].line == right["end"].line
    and left["end"].character == right["end"].character
end

---@param value string
---@param width integer
---@return string[]
function M.wrap(value, width)
  width = math.max(12, width)
  local result = {}
  for _, source in ipairs(M.lines(value)) do
    if source == "" then
      result[#result + 1] = ""
    else
      local current = ""
      for word in source:gmatch("%S+") do
        local candidate = current == "" and word or (current .. " " .. word)
        if vim.fn.strdisplaywidth(candidate) <= width then
          current = candidate
        else
          if current ~= "" then
            result[#result + 1] = current
          end
          current = word
        end
      end
      result[#result + 1] = current
    end
  end
  return #result > 0 and result or { "" }
end

return M

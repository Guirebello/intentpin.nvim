local M = {}

local styles_without_text = {
  none = true,
  shadow = true,
}

---@param style string|table
---@param text table
---@return table
function M.with_text(style, text)
  local border = { style = style }
  if not (type(style) == "string" and styles_without_text[style]) then
    border.text = text
  end
  return border
end

return M

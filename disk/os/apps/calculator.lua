--[[ calculator -- a simple button-grid calculator with keyboard support. ]]

local M = {}
M.id = "calculator"
M.name = "Calculator"

local ROWS = {
  { "7", "8", "9", "/" },
  { "4", "5", "6", "*" },
  { "1", "2", "3", "-" },
  { "0", ".", "=", "+" },
}

function M.run(ctx)
  local api = ctx.api
  local expr = ""
  local result = ""
  local w, h = api.getSize()
  local btnW = math.floor(w / 4)
  local gridTop = 4
  local buttons = {}

  local function compute()
    local clean = expr:gsub("[^%d%.%+%-%*/%(%)]", "")
    if clean == "" then return end
    local fn, err = load("return " .. clean, "calc", "t", {})
    if not fn then result = "error" return end
    local ok, val = pcall(fn)
    if not ok or type(val) ~= "number" then result = "error"
    else result = tostring(val) end
  end

  local function draw()
    local T = api.getTheme()
    term.setBackgroundColor(T.bg)
    term.setTextColor(T.fg)
    term.clear()

    term.setBackgroundColor(T.field)
    for row = 1, 2 do
      term.setCursorPos(1, row)
      term.write(string.rep(" ", w))
    end
    term.setTextColor(T.fieldText)
    term.setCursorPos(2, 1)
    local e = expr
    if #e > w - 2 then e = e:sub(#e - (w - 2) + 1) end
    term.write(e)
    term.setCursorPos(2, 2)
    term.setTextColor(T.accent)
    term.write(result)

    buttons = {}
    for r = 1, #ROWS do
      for c = 1, 4 do
        local label = ROWS[r][c]
        local x = (c - 1) * btnW + 1
        local y = gridTop + (r - 1) * 2
        local bg = (label == "=") and T.accent or T.chrome
        local fg = (label == "=") and T.chromeFocusText or T.chromeText
        term.setBackgroundColor(bg)
        term.setTextColor(fg)
        term.setCursorPos(x, y)
        local w2 = (c == 4) and (w - x + 1) or btnW
        local pad = math.max(0, math.floor((w2 - #label) / 2))
        term.write(string.rep(" ", w2))
        term.setCursorPos(x + pad, y)
        term.write(label)
        buttons[#buttons + 1] = { x = x, y = y, w = w2, h = 1, label = label }
      end
    end

    term.setBackgroundColor(T.err)
    term.setTextColor(colors.white)
    local cy = gridTop + #ROWS * 2
    term.setCursorPos(1, cy)
    term.write(string.rep(" ", w))
    local clearLabel = "Clear (C)"
    term.setCursorPos(math.max(1, math.floor((w - #clearLabel) / 2)), cy)
    term.write(clearLabel)
    buttons[#buttons + 1] = { x = 1, y = cy, w = w, h = 1, label = "C" }
  end

  local function press(label)
    if label == "=" then
      compute()
    elseif label == "C" then
      expr, result = "", ""
    else
      expr = expr .. label
    end
  end

  draw()
  while true do
    local ev = { api.pullEvent() }
    if ev[1] == "mouse_click" then
      local x, y = ev[3], ev[4]
      for i = 1, #buttons do
        local b = buttons[i]
        if x >= b.x and x < b.x + b.w and y == b.y then press(b.label) break end
      end
    elseif ev[1] == "char" then
      if ev[2]:match("[%d%.%+%-%*/%(%)]") then expr = expr .. ev[2] end
    elseif ev[1] == "key" then
      if ev[2] == keys.enter or ev[2] == keys.numPadEnter then compute()
      elseif ev[2] == keys.backspace then expr = expr:sub(1, -2)
      end
    end
    draw()
  end
end

return M

--[[ about -- a small pixel-art masthead plus version info, shortcuts, and
  the bundled app list. Doubles as a smoke-test app: it exercises the same
  api.require() path any app can use to pull in lib.canvas/lib.icons/lib.font
  for real graphics instead of plain text.
]]

local M = {}
M.id = "about"
M.name = "About"

local VERSION = "1.0.0"

local SHORTCUTS = {
  "Drag a titlebar to move a window",
  "[_] [o] [x] minimize / maximize / close",
  "Drag a window's corner to resize it",
  "Right-click for a context menu",
  "Alt+Tab cycles focus between windows",
}

--- Splits text into lines no wider than `width`, breaking on spaces
--- (never mid-word, except a single word that's wider than `width` alone).
local function wrap(text, width)
  local lines, cur = {}, ""
  for word in text:gmatch("%S+") do
    local candidate = (cur == "" and word) or (cur .. " " .. word)
    if #candidate <= width then
      cur = candidate
    else
      if cur ~= "" then lines[#lines + 1] = cur end
      cur = (#word <= width) and word or word:sub(1, width)
    end
  end
  if cur ~= "" then lines[#lines + 1] = cur end
  return lines
end

function M.run(ctx)
  local api = ctx.api
  local Canvas = api.require("lib.canvas")
  local font = api.require("lib.font")
  local icons = api.require("lib.icons")
  local appsReg = api.require("lib.apps")

  local function draw()
    local T = api.getTheme()
    local w, h = api.getSize()
    term.setBackgroundColor(T.bg)
    term.setTextColor(T.fg)
    term.clear()

    -- masthead: the About icon plus a small "CC-OS" wordmark, side by side
    local head = Canvas.new(1, 1, math.min(w, 20), icons.CELLS.h, T.bg)
    icons.draw(head, "about", 1, 1)
    font.draw(head, icons.SIZE.w + 4, 2, "CC-OS", T.accent, 1, 1)
    head:render()

    term.setTextColor(T.fg)
    term.setCursorPos(2, icons.CELLS.h + 1)
    term.write("version " .. VERSION)

    local textW = w - 2
    local shortcutLines = {}
    for i = 1, #SHORTCUTS do
      local wrapped = wrap(SHORTCUTS[i], textW)
      for j = 1, #wrapped do shortcutLines[#shortcutLines + 1] = wrapped[j] end
    end

    local y = icons.CELLS.h + 3
    term.setTextColor(T.accent2)
    term.setCursorPos(2, y)
    term.write(#appsReg.list .. " bundled apps:")
    term.setTextColor(T.desktopText)
    local names = {}
    for i = 1, #appsReg.list do names[#names + 1] = appsReg.list[i].name end
    local appLines = wrap(table.concat(names, "  "), textW)
    y = y + 1
    local appLimit = h - #shortcutLines - 1
    for i = 1, #appLines do
      if y >= appLimit then break end
      term.setCursorPos(2, y)
      term.write(appLines[i])
      y = y + 1
    end

    y = h - #shortcutLines
    term.setTextColor(T.fg)
    for i = 1, #shortcutLines do
      term.setCursorPos(2, y)
      term.write(shortcutLines[i])
      y = y + 1
    end
  end

  draw()
  while true do
    api.pullEvent()
    draw()
  end
end

return M

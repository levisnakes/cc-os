--[[ about -- version info and a live event log, useful as a smoke-test app. ]]

local M = {}
M.id = "about"
M.name = "About"

function M.run(ctx)
  local api = ctx.api
  local th = api.getTheme()

  local function draw()
    local w, h = api.getSize()
    term.setBackgroundColor(th.bg)
    term.setTextColor(th.fg)
    term.clear()
    term.setCursorPos(2, 2)
    term.setTextColor(th.accent)
    term.write("cc-OS")
    term.setTextColor(th.fg)
    term.setCursorPos(2, 3)
    term.write("version 1.0.0")
    term.setCursorPos(2, 5)
    term.write("A windowed, multitasking desktop")
    term.setCursorPos(2, 6)
    term.write("for CC:Tweaked advanced computers.")
    term.setCursorPos(2, 8)
    term.write("Drag titlebars to move windows.")
    term.setCursorPos(2, 9)
    term.write("[_] minimizes, [x] closes.")
    term.setCursorPos(2, h - 1)
    term.setTextColor(th.desktopText)
  end

  draw()
  while true do
    api.pullEvent()
  end
end

return M

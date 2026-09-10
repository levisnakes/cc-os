-- t_icons.lua -- render every app icon on one canvas and screenshot it, so
-- the pixel art can be reviewed visually (not just "did it error").

local Canvas = require_os("lib.canvas")
local icons = require_os("lib.icons")
local appsReg = require_os("lib.apps")

term.setBackgroundColor(colors.black)
term.clear()

-- 4 columns x 3 rows of icons, each icon 4x3 cells with a 1-cell gap
local cols, rows = 4, 3
local cellW, cellH = icons.CELLS.w + 2, icons.CELLS.h + 1
local canvasW, canvasH = cols * cellW, rows * cellH
local c = Canvas.new(1, 1, canvasW, canvasH, colors.black)

local i = 0
for row = 0, rows - 1 do
  for col = 0, cols - 1 do
    i = i + 1
    local a = appsReg.list[i]
    if a then
      local px = col * cellW * 2 + 1
      local py = row * cellH * 3 + 1
      icons.draw(c, a.id, px, py)
    end
  end
end
c:render()
SHOT("icon_grid")

check(true, "rendered without error")
finish("icons")

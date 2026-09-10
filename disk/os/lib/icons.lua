--[[ icons -- small pixel-art app icons drawn on a lib.canvas sub-pixel
  canvas (2x3 sub-pixels per character cell -- the highest resolution
  CC:Tweaked's font supports; there's no finer "sub-sub-pixel" than that).

  Each icon occupies an 8x9 pixel box (a 4x3 character cell region) and is
  drawn with fixed, per-app colours so it stays recognisable across themes,
  the way a real desktop's app icons don't repaint themselves when you
  change your wallpaper.
]]

local icons = {}
icons.CELLS = { w = 4, h = 3 }
icons.SIZE = { w = 8, h = 9 }

--- One signature colour per app, used as a small swatch in places too
--- cramped for real pixel art (titlebars, taskbar buttons).
icons.COLOR = {
  about = colors.blue, files = colors.yellow, editor = colors.lightGray,
  terminal = colors.lime, settings = colors.lightGray, chat = colors.cyan,
  share = colors.orange, calc = colors.lime, clock = colors.white,
  notes = colors.yellow, piano = colors.white, snake = colors.green,
}

local DRAW = {}

function DRAW.about(c, x, y)
  c:circle(x + 4, y + 4, 4, colors.blue, true)
  c:fill(x + 4, y + 2, 1, 1, colors.white)
  c:fill(x + 4, y + 4, 1, 3, colors.white)
end

function DRAW.files(c, x, y)
  c:fill(x, y + 1, 4, 2, colors.yellow)
  c:fill(x, y + 2, 8, 5, colors.yellow)
  c:box(x, y + 2, 8, 5, colors.brown)
end

function DRAW.editor(c, x, y)
  c:fill(x + 1, y, 6, 9, colors.white)
  c:fill(x + 5, y, 2, 2, colors.lightGray)
  c:fill(x + 2, y + 3, 4, 1, colors.gray)
  c:fill(x + 2, y + 5, 4, 1, colors.gray)
  c:fill(x + 2, y + 7, 3, 1, colors.gray)
end

function DRAW.terminal(c, x, y)
  c:fill(x, y, 8, 9, colors.black)
  c:box(x, y, 8, 9, colors.gray)
  c:fill(x + 1, y + 2, 1, 1, colors.lime)
  c:fill(x + 1, y + 4, 3, 1, colors.lime)
  c:fill(x + 2, y + 6, 3, 1, colors.lime)
end

function DRAW.settings(c, x, y)
  c:circle(x + 4, y + 4, 4, colors.lightGray, true)
  c:fill(x + 3, y, 2, 2, colors.gray)
  c:fill(x + 3, y + 7, 2, 2, colors.gray)
  c:fill(x, y + 3, 2, 2, colors.gray)
  c:fill(x + 7, y + 3, 2, 2, colors.gray)
  c:circle(x + 4, y + 4, 2, colors.gray, true)
end

function DRAW.chat(c, x, y)
  c:fill(x, y, 8, 6, colors.cyan)
  c:box(x, y, 8, 6, colors.blue)
  c:fill(x + 1, y + 6, 2, 2, colors.cyan)
  c:fill(x + 2, y + 2, 1, 1, colors.white)
  c:fill(x + 4, y + 2, 1, 1, colors.white)
  c:fill(x + 6, y + 2, 1, 1, colors.white)
end

function DRAW.share(c, x, y)
  -- a bold upward arrow: a stepped triangular head over a stem
  c:fill(x + 3, y, 2, 1, colors.orange)
  c:fill(x + 2, y + 1, 4, 1, colors.orange)
  c:fill(x + 1, y + 2, 6, 2, colors.orange)
  c:fill(x + 3, y + 4, 2, 5, colors.orange)
end

function DRAW.calc(c, x, y)
  -- opaque throughout (never relies on the desktop colour showing through,
  -- since a dark "screen" tone could vanish against a dark theme)
  c:fill(x, y, 8, 9, colors.lightGray)
  c:fill(x, y, 8, 3, colors.gray)
  c:fill(x + 1, y + 1, 5, 1, colors.lime)
end

function DRAW.clock(c, x, y)
  c:circle(x + 4, y + 4, 4, colors.white, true)
  c:fill(x + 4, y + 1, 1, 3, colors.black)
  c:fill(x + 4, y + 4, 3, 1, colors.black)
end

function DRAW.notes(c, x, y)
  c:fill(x, y, 8, 8, colors.yellow)
  c:fill(x + 5, y, 3, 3, colors.white)
  c:fill(x + 1, y + 3, 5, 1, colors.orange)
  c:fill(x + 1, y + 5, 5, 1, colors.orange)
end

function DRAW.piano(c, x, y)
  c:fill(x, y + 1, 8, 6, colors.white)
  c:box(x, y + 1, 8, 6, colors.gray)
  c:fill(x + 1, y + 1, 1, 4, colors.black)
  c:fill(x + 3, y + 1, 1, 4, colors.black)
  c:fill(x + 5, y + 1, 1, 4, colors.black)
end

function DRAW.snake(c, x, y)
  c:fill(x, y + 6, 3, 2, colors.lime)
  c:fill(x + 2, y + 4, 3, 2, colors.lime)
  c:fill(x + 4, y + 2, 3, 2, colors.lime)
  c:fill(x + 6, y, 2, 2, colors.lime)
  c:fill(x, y, 2, 2, colors.red)
end

function DRAW.default(c, x, y)
  c:fill(x, y, 8, 9, colors.gray)
  c:box(x, y, 8, 9, colors.lightGray)
end

--- Draws the icon for `appId` with its top-left pixel at (x, y) on `canvas`.
function icons.draw(canvas, appId, x, y)
  local fn = DRAW[appId] or DRAW.default
  fn(canvas, x, y)
end

return icons

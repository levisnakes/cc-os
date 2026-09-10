-- t_splash.lua -- visual review of the boot splash's pixel-art wordmark
-- (drawn directly, since the real one is only on screen during os.sleep).

local Canvas = require_os("lib.canvas")
local font = require_os("lib.font")

local screenW, screenH = 51, 19
local full = Canvas.new(1, 1, screenW, screenH, colors.black)
local midY = math.floor(full.h / 2)
font.centerShadow(full, midY - 9, "CC-OS", colors.cyan, colors.gray, 2, 2)
font.center(full, midY + 8, "STARTING UP", colors.lightGray, 1, 1)
full:render()
SHOT("boot_splash")

check(true, "rendered without error")
finish("splash")

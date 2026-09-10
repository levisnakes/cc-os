-- t_qa_ctxmenu.lua -- right-clicking elsewhere while a context menu is open
-- should close the old one and open a new one in the same click, not just
-- dismiss (which would need a second right-click to open the new menu).

local kernel = require_os("kernel")
local phase = "start"

local function onEvent(ev, procs, focusedId, menus)
  if phase == "start" then
    -- fixed position/size so the rest of the test has deterministic geometry
    kernel.launch("about", nil, { x = 1, y = 1, w = 36, h = 12 })
    phase = "open_first"
  elseif phase == "open_first" then
    local p = procs[1]
    check(p ~= nil, "about window open")
    MOCK.push("mouse_click", 2, p.x + 2, p.y)
    MOCK.push("mouse_up", 2, p.x + 2, p.y)
    phase = "first_open"
  elseif phase == "first_open" and ev[1] == "mouse_up" and ev[2] == 2 then
    check(menus.ctxMenuOpen, "titlebar right-click opened a context menu")
    check(menus.ctxMenuLabels and menus.ctxMenuLabels[1] == "Minimize", "it's the titlebar menu (starts with Minimize)")
    SHOT("first_menu_open")
    -- right-click on empty desktop (well clear of the 36x12 window above),
    -- in one shot -- no dismiss click first
    MOCK.push("mouse_click", 2, 45, 15)
    MOCK.push("mouse_up", 2, 45, 15)
    phase = "second_open"
  elseif phase == "second_open" and ev[1] == "mouse_up" and ev[2] == 2 then
    check(menus.ctxMenuOpen, "a context menu is open after the second right-click")
    check(menus.ctxMenuLabels and menus.ctxMenuLabels[1] == "Open Terminal",
      "it's the NEW desktop menu (starts with Open Terminal), not the stale titlebar one")
    SHOT("second_menu_opened_in_one_click")
    phase = "done"
    error("TEST_DONE", 0)
  end
end

MOCK.push("mouse_up", 1, 1, 1)
local ok, err = pcall(kernel.run, { onEvent = onEvent, noSession = true, skipSplash = true })
check(tostring(err):find("TEST_DONE", 1, true) ~= nil, "kernel stopped cleanly: " .. tostring(err))
finish("qa_ctxmenu")

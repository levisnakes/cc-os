-- t_wm2.lua -- new window-manager features: icons, maximize, resize, crash
-- dialog, right-click menus, alt-tab, session persistence.

local kernel = require_os("kernel")
local appsReg = require_os("lib.apps")

MOCK.mount({ ["os/__test/crashapp.lua"] = [[
local M = {}
M.id = "crashtest"
M.name = "Crash Test"
function M.run(ctx)
  ctx.api.pullEvent()
  error("boom: something went wrong on purpose", 0)
end
return M
]] })
appsReg.list[#appsReg.list + 1] = { id = "crashtest", name = "Crash Test", icon = "!", module = "__test.crashapp", width = 30, height = 10 }

local phase = "start"

local function closeFocused(procs, focusedId)
  local p = nil
  for i = 1, #procs do if procs[i].id == focusedId then p = procs[i] end end
  if not p then return end
  click(1, p.x + p.w - 2, p.y)
end

local function onEvent(ev, procs, focusedId)
  ------------------------------------------------------------ desktop icons
  if phase == "start" then
    check(#procs == 0, "nothing open at boot")
    SHOT("desktop_icons")
    phase = "icon_dbl_1"
    -- double-click the first icon (About) to launch it
    click(1, 2, 1)

  elseif phase == "icon_dbl_1" and ev[1] == "mouse_up" then
    phase = "icon_dbl_2"
    click(1, 2, 1)

  elseif phase == "icon_dbl_2" and ev[1] == "mouse_up" then
    check(#procs == 1, "double-clicking a desktop icon launched its app")
    if procs[1] then eq(procs[1].appId, "about", "launched the right app") end
    SHOT("icon_launched")
    phase = "maximize"
    local p = procs[1]
    -- click the [o] maximize button: 6 cols in from the right edge, middle one
    click(1, p.x + p.w - 5, p.y)

  ------------------------------------------------------------------ maximize
  elseif phase == "maximize" and ev[1] == "mouse_up" then
    local p = procs[1]
    check(p.maximized == true, "maximize button maximized the window")
    check(p.w > 40, "maximized window fills the screen width")
    SHOT("maximized")
    phase = "restore"
    click(1, p.x + p.w - 5, p.y)

  elseif phase == "restore" and ev[1] == "mouse_up" then
    local p = procs[1]
    check(p.maximized == false, "clicking [o] again restores it")
    SHOT("restored")
    phase = "resize"
    -- drag the bottom-right resize handle outward
    local sx, sy = p.x + p.w - 1, p.y + p.h - 1
    MOCK.push("mouse_click", 1, sx, sy)
    MOCK.push("mouse_drag", 1, sx + 6, sy + 3)
    MOCK.push("mouse_up", 1, sx + 6, sy + 3)

  ------------------------------------------------------------------- resize
  elseif phase == "resize" and ev[1] == "mouse_up" then
    local p = procs[1]
    check(p.w >= 40 and p.h >= 14, "dragging the corner resized the window (w=" .. p.w .. " h=" .. p.h .. ")")
    SHOT("resized")
    phase = "rclick_title"
    MOCK.push("mouse_click", 2, p.x + 2, p.y)
    MOCK.push("mouse_up", 2, p.x + 2, p.y)

  ------------------------------------------------------------ context menus
  elseif phase == "rclick_title" and ev[1] == "mouse_up" and ev[2] == 2 then
    SHOT("titlebar_context_menu")
    phase = "rclick_close"
    -- the context menu opens anchored at the click point (p.x+2, p.y); its
    -- 5 rows are Minimize/Maximize/Snap Left/Snap Right/Close in that order
    local p = procs[1]
    click(1, p.x + 3, p.y + 4)

  elseif phase == "rclick_close" and ev[1] == "mouse_up" then
    check(#procs == 0, "context menu Close item closed the window")
    phase = "rclick_desktop"
    MOCK.push("mouse_click", 2, 30, 8)
    MOCK.push("mouse_up", 2, 30, 8)

  elseif phase == "rclick_desktop" and ev[1] == "mouse_up" and ev[2] == 2 then
    SHOT("desktop_context_menu")
    phase = "rclick_dismiss"
    -- click "Open Terminal" (first row of the desktop menu, at the anchor y)
    click(1, 32, 8)

  elseif phase == "rclick_dismiss" and ev[1] == "mouse_up" then
    check(#procs == 1, "desktop context menu launched Terminal")
    SHOT("terminal_from_menu")
    phase = "close_terminal"
    closeFocused(procs, focusedId)

  ------------------------------------------------------------------ crash
  elseif phase == "close_terminal" and ev[1] == "mouse_up" then
    check(#procs == 0, "terminal closed")
    phase = "bogus_launch"
    kernel.launch("__no_such_app__")

  elseif phase == "bogus_launch" then
    -- an unknown app id fails to load -> a notification, no new window
    check(#procs == 0, "loading a bogus app id did not open a blank window")
    phase = "crash_wait"
    kernel.launch("crashtest")

  elseif phase == "crash_wait" then
    check(#procs == 1, "crash-test app window opened")
    phase = "crash_trigger"
    MOCK.push("key", keys.space, false)

  elseif phase == "crash_trigger" and ev[1] == "key" then
    local p = procs[1]
    check(p ~= nil and p.crashed == true, "kernel marked the window as crashed")
    check(#procs == 1, "a crashed window stays open instead of vanishing")
    SHOT("crash_dialog")
    phase = "crash_close"
    closeFocused(procs, focusedId)

  ------------------------------------------------------------------- alt-tab
  elseif phase == "crash_close" and ev[1] == "mouse_up" then
    check(#procs == 0, "the crashed window can still be closed normally")
    phase = "alttab_open"
    kernel.launch("about")
    kernel.launch("notes")

  elseif phase == "alttab_open" then
    if #procs == 2 then
      local frontId = focusedId
      phase = "alttab_press"
      MOCK.push("key", keys.leftAlt, false)
      MOCK.push("key", keys.tab, false)
      MOCK.push("key_up", keys.leftAlt)
      -- stash which one was in front before the switch
      _G.__preAltTabFocus = frontId
    end

  elseif phase == "alttab_press" and ev[1] == "key_up" then
    check(focusedId ~= _G.__preAltTabFocus, "alt-tab switched focus to the other window")
    SHOT("alt_tabbed")
    phase = "cleanup1"
    closeFocused(procs, focusedId)

  elseif phase == "cleanup1" and ev[1] == "mouse_up" then
    phase = "cleanup2"
    if #procs > 0 then closeFocused(procs, focusedId) else phase = "session_done" end

  elseif phase == "cleanup2" and ev[1] == "mouse_up" then
    check(#procs == 0, "both windows closed")
    phase = "session_done"
    error("TEST_DONE", 0)
  end
end

MOCK.push("mouse_up", 1, 1, 1) -- harmless kick-off event

local ok, err = pcall(kernel.run, { onEvent = onEvent, skipSplash = true, noSession = true })
if not ok then
  check(tostring(err):find("TEST_DONE", 1, true) ~= nil, "kernel stopped cleanly: " .. tostring(err))
end
eq(phase, "session_done", "reached the end of the script")

finish("wm2")

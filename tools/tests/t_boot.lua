-- t_boot.lua -- exercises the kernel: start menu, launch, drag, minimize,
-- restore, close. Drives kernel.run() with a reactive onEvent hook that
-- queues the next scripted action once it sees the effect of the last one.

local kernel = require_os("kernel")

local phase = "menu"

local function onEvent(ev, procs, focusedId)
  if phase == "menu" and ev[1] == "mouse_up" then
    check(#procs == 0, "no windows before launching anything")
    SHOT("menu_open")
    phase = "click_about"
    click(1, 2, 7) -- "About" is the first entry in the Start menu

  elseif phase == "click_about" and ev[1] == "mouse_up" then
    check(#procs == 1, "About window opened")
    if #procs == 1 then
      local p = procs[1]
      LOG("about window at", p.x, p.y, p.w, p.h)
      eq(p.appId, "about", "launched app id")
      SHOT("about_open")
      phase = "drag"
      local sx, sy = p.x + 2, p.y
      MOCK.push("mouse_click", 1, sx, sy)
      MOCK.push("mouse_drag", 1, sx + 3, sy + 2)
      MOCK.push("mouse_up", 1, sx + 3, sy + 2)
    else
      phase = "done"
    end

  elseif phase == "drag" and ev[1] == "mouse_up" then
    SHOT("about_dragged")
    phase = "minimize"
    local p = procs[1]
    click(1, p.x + p.w - 8, p.y)

  elseif phase == "minimize" and ev[1] == "mouse_up" then
    check(procs[1].minimized == true, "About minimized")
    SHOT("about_minimized")
    phase = "restore"
    click(1, 9, 19)

  elseif phase == "restore" and ev[1] == "mouse_up" then
    check(procs[1].minimized == false, "About restored")
    SHOT("about_restored")
    phase = "close"
    local p = procs[1]
    click(1, p.x + p.w - 2, p.y)

  elseif phase == "close" and ev[1] == "mouse_up" then
    check(#procs == 0, "About window closed")
    SHOT("about_closed")
    phase = "done"
    error("TEST_DONE", 0)
  end
end

click(1, 1, 19) -- open the Start menu

local ok, err = pcall(kernel.run, { onEvent = onEvent, skipSplash = true, noSession = true })
if not ok then
  check(tostring(err):find("TEST_DONE", 1, true) ~= nil, "kernel stopped cleanly: " .. tostring(err))
end
eq(phase, "done", "reached the end of the script")

finish("boot")

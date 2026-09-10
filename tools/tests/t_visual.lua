-- t_visual.lua -- one-shot visual review: desktop icons, the Start menu icon
-- grid, and titlebar/taskbar colour swatches with a few windows open.

local kernel = require_os("kernel")

local phase = "boot"
local function onEvent(ev, procs, focusedId)
  if phase == "boot" then
    SHOT("desktop_with_icons")
    phase = "menu"
    click(1, 1, 19)
  elseif phase == "menu" and ev[1] == "mouse_up" then
    SHOT("start_menu_grid")
    phase = "windows"
    kernel.launch("editor")
    kernel.launch("files")
    kernel.launch("piano")
  elseif phase == "windows" then
    if #procs == 3 then
      SHOT("windows_with_swatches")
      phase = "done"
      error("TEST_DONE", 0)
    end
  end
end

MOCK.push("mouse_up", 1, 1, 1)
local ok, err = pcall(kernel.run, { onEvent = onEvent, noSession = true, skipSplash = true })
if not ok then
  check(tostring(err):find("TEST_DONE", 1, true) ~= nil, "kernel stopped cleanly: " .. tostring(err))
end
finish("visual")

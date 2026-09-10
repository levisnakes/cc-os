-- t_resize.lua -- resizing a window (drag its corner) actually makes the app
-- re-layout at the new size, not just grow blank space. Checks the app's own
-- window buffer directly (proc.win.getLine) rather than just "did not crash".

local kernel = require_os("kernel")

local function findProc(procs, appId)
  for i = 1, #procs do if procs[i].appId == appId then return procs[i] end end
  return nil
end

local function grow(p, dw, dh)
  local sx, sy = p.x + p.w - 1, p.y + p.h - 1
  MOCK.push("mouse_click", 1, sx, sy)
  MOCK.push("mouse_drag", 1, sx + dw, sy + dh)
  MOCK.push("mouse_up", 1, sx + dw, sy + dh)
end

local phase = "start"
local realWin = nil -- the real proc's .win (not in the debug snapshot)

local function onEvent(ev, procs, focusedId)
  ------------------------------------------------------------------- files
  if phase == "start" then
    phase = "files_open"
    realWin = kernel.launch("files").win

  elseif phase == "files_open" then
    local p = findProc(procs, "files")
    check(p ~= nil, "files window open")
    phase = "files_resized"
    grow(p, 0, 6) -- taller only, so the footer row moves down

  elseif phase == "files_resized" and ev[1] == "mouse_up" then
    local w, h = realWin.getSize()
    local footerLine = realWin.getLine(h) -- outer h, client rows are h-2
    check(footerLine:find("item", 1, true) ~= nil or footerLine:find("Enter", 1, true) ~= nil,
      "after growing taller, the files footer redrew at the new bottom row")
    SHOT("files_resized")
    phase = "close_files"
    local p = findProc(procs, "files")
    click(1, p.x + p.w - 2, p.y)

  ------------------------------------------------------------------ settings
  elseif phase == "close_files" and ev[1] == "mouse_up" then
    check(findProc(procs, "files") == nil, "files closed")
    phase = "settings_open"
    realWin = kernel.launch("settings").win

  elseif phase == "settings_open" then
    local p = findProc(procs, "settings")
    check(p ~= nil, "settings window open")
    phase = "settings_resized"
    grow(p, 0, 6)

  elseif phase == "settings_resized" and ev[1] == "mouse_up" then
    local w, h = realWin.getSize()
    local footerLine = realWin.getLine(h)
    check(footerLine:find("Shut Down", 1, true) ~= nil or footerLine:find("Reboot", 1, true) ~= nil,
      "after growing taller, settings' buttons redrew near the new bottom")
    SHOT("settings_resized")
    phase = "close_settings"
    local p = findProc(procs, "settings")
    click(1, p.x + p.w - 2, p.y)

  ------------------------------------------------------------------ calculator
  elseif phase == "close_settings" and ev[1] == "mouse_up" then
    check(findProc(procs, "settings") == nil, "settings closed")
    phase = "calc_open"
    realWin = kernel.launch("calc").win

  elseif phase == "calc_open" then
    local p = findProc(procs, "calc")
    check(p ~= nil, "calculator window open")
    phase = "calc_resized"
    grow(p, 8, 0) -- wider only

  elseif phase == "calc_resized" and ev[1] == "mouse_up" then
    local w, h = realWin.getSize()
    check(w > 22, "the calculator's own window buffer grew (w=" .. w .. ")")
    -- the "/" button is in the last (4th) column, which stretches to fill
    -- the new width; on the old 22-wide layout it was drawn at column 19,
    -- so if the grid actually redrew, it should now be further right
    local ch = realWin.getLine(4) -- row 4 is the first button row
    local slashAt = ch:find("/", 1, true)
    check(slashAt ~= nil and slashAt > 22,
      "calculator's button grid redrew across the new width (/ at col " .. tostring(slashAt) .. ")")
    SHOT("calc_resized")
    phase = "done"
    error("TEST_DONE", 0)
  end
end

MOCK.push("mouse_up", 1, 1, 1)

local ok, err = pcall(kernel.run, { onEvent = onEvent, skipSplash = true, noSession = true })
if not ok then
  check(tostring(err):find("TEST_DONE", 1, true) ~= nil, "kernel stopped cleanly: " .. tostring(err))
end
eq(phase, "done", "reached the end of the script")

finish("resize")

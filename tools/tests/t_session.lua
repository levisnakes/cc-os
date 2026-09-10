-- t_session.lua -- open windows are persisted continuously (not just at a
-- clean shutdown), and restored, at the same position/size, on next boot.

local kernel = require_os("kernel")

----------------------------------------------------------- first boot: open apps
local phase = "start"
local calcAt = nil

local function onEvent1(ev, procs, focusedId)
  if phase == "start" then
    check(#procs == 0, "nothing open at first boot")
    phase = "opened"
    kernel.launch("about")
    kernel.launch("calc")
  elseif phase == "opened" then
    check(#procs == 2, "two windows open")
    for i = 1, #procs do if procs[i].appId == "calc" then calcAt = { x = procs[i].x, y = procs[i].y, w = procs[i].w, h = procs[i].h } end end
    phase = "done"
    error("TEST_DONE", 0)
  end
end

MOCK.push("mouse_up", 1, 1, 1)
local ok1, err1 = pcall(kernel.run, { onEvent = onEvent1, skipSplash = true })
check(ok1 == false and tostring(err1):find("TEST_DONE", 1, true) ~= nil, "first session ended cleanly")
eq(phase, "done", "first session reached the end of its script")

----------------------------------------------------------------- verify on disk
local raw
do
  local h = fs.open("os/data/settings.dat", "r")
  check(h ~= nil, "settings.dat exists after the session")
  if h then raw = h.readAll() h.close() end
end
if raw then
  check(raw:find('"about"', 1, true) ~= nil, "saved session mentions the about app")
  check(raw:find('"calc"', 1, true) ~= nil, "saved session mentions the calculator app")
end

--------------------------------------------------- second boot: session restores
local phase2 = "start"
local function onEvent2(ev, procs, focusedId)
  if phase2 == "start" then
    check(#procs == 2, "both windows came back on the next boot")
    local found = false
    for i = 1, #procs do
      if procs[i].appId == "calc" and calcAt then
        found = true
        eq(procs[i].x, calcAt.x, "restored calculator x matches")
        eq(procs[i].y, calcAt.y, "restored calculator y matches")
        eq(procs[i].w, calcAt.w, "restored calculator w matches")
        eq(procs[i].h, calcAt.h, "restored calculator h matches")
      end
    end
    check(found, "the calculator window was among the restored windows")
    SHOT("session_restored")
    phase2 = "done"
    error("TEST_DONE", 0)
  end
end

MOCK.push("mouse_up", 1, 1, 1)
local ok2, err2 = pcall(kernel.run, { onEvent = onEvent2, skipSplash = true })
check(ok2 == false and tostring(err2):find("TEST_DONE", 1, true) ~= nil, "second session ended cleanly")
eq(phase2, "done", "second session reached the end of its script")

finish("session")

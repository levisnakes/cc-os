-- t_qa_clock_delete.lua -- removing an alarm (X key) used to delete it
-- instantly with no confirmation, the same pattern already fixed in
-- Files and Notes.

local kernel = require_os("kernel")
local phase = "start"

local function alarmsFileHasHour(hh)
  local h = fs.open("os/data/alarms.dat", "r")
  if not h then return false end
  local raw = h.readAll()
  h.close()
  return raw:find("hour = " .. hh, 1, true) ~= nil
end

local function onEvent(ev, procs, focusedId)
  if phase == "start" then
    kernel.launch("clock")
    phase = "add"
  elseif phase == "add" then
    check(#procs == 1, "clock window open")
    MOCK.push("key", keys.a)
    phase = "typing"
  elseif phase == "typing" and ev[1] == "key" and ev[2] == keys.a then
    for ch in ("09:30"):gmatch(".") do MOCK.push("char", ch) end
    MOCK.push("key", keys.enter)
    phase = "wait_added"
  elseif phase == "wait_added" and ev[1] == "key" and ev[2] == keys.enter then
    check(alarmsFileHasHour(9), "the 09:30 alarm was added")
    MOCK.push("key", keys.x)
    phase = "cancel"
  elseif phase == "cancel" and ev[1] == "key" and ev[2] == keys.x then
    SHOT("clock_remove_confirm")
    MOCK.push("key", keys.n)
    phase = "check_kept"
  elseif phase == "check_kept" and ev[1] == "key" and ev[2] == keys.n then
    check(alarmsFileHasHour(9), "declining kept the alarm")
    MOCK.push("key", keys.x)
    phase = "confirm"
  elseif phase == "confirm" and ev[1] == "key" and ev[2] == keys.x then
    MOCK.push("key", keys.y)
    phase = "check_gone"
  elseif phase == "check_gone" and ev[1] == "key" and ev[2] == keys.y then
    check(not alarmsFileHasHour(9), "confirming removed the alarm")
    phase = "done"
    error("TEST_DONE", 0)
  end
end

MOCK.push("mouse_up", 1, 1, 1)
local ok, err = pcall(kernel.run, { onEvent = onEvent, noSession = true, skipSplash = true })
check(tostring(err):find("TEST_DONE", 1, true) ~= nil, "kernel stopped cleanly: " .. tostring(err))
finish("qa_clock_delete")

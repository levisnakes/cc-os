-- t_clock_notes.lua -- alarm scheduling/firing and the notes app.

local kernel = require_os("kernel")

local phase = "start"

local function closeFocused(procs, focusedId)
  local p = nil
  for i = 1, #procs do if procs[i].id == focusedId then p = procs[i] end end
  if not p then return end
  click(1, p.x + p.w - 2, p.y)
end

local function onEvent(ev, procs, focusedId)
  --------------------------------------------------------------------- clock
  if phase == "start" then
    phase = "clock_wait"
    kernel.launch("clock")

  elseif phase == "clock_wait" then
    check(#procs == 1, "clock window open")
    phase = "clock_add"
    MOCK.push("key", keys.a)

  elseif phase == "clock_add" and ev[1] == "key" and ev[2] == keys.a then
    phase = "clock_typing"
    for ch in ("00:00"):gmatch(".") do MOCK.push("char", ch) end
    -- os.time() starts at 0 in the mock, so an alarm at 00:00 fires ~immediately
    MOCK.push("key", keys.enter)

  elseif phase == "clock_typing" and ev[1] == "key" and ev[2] == keys.enter then
    check(fs.exists("os/data/alarms.dat"), "alarm was persisted to disk")
    phase = "clock_ring"

  elseif phase == "clock_ring" and ev[1] == "alarm" then
    SHOT("clock_ringing")
    phase = "clock_dismiss"
    MOCK.push("key", keys.space)

  elseif phase == "clock_dismiss" and ev[1] == "key" then
    SHOT("clock_dismissed")
    phase = "clock_close"
    closeFocused(procs, focusedId)

  ---------------------------------------------------------------------- notes
  elseif phase == "clock_close" and ev[1] == "mouse_up" then
    check(#procs == 0, "clock closed")
    phase = "notes_wait"
    kernel.launch("notes")

  elseif phase == "notes_wait" then
    check(#procs == 1, "notes window open")
    phase = "notes_new"
    MOCK.push("key", keys.n)

  elseif phase == "notes_new" and ev[1] == "key" and ev[2] == keys.n then
    phase = "notes_typing"
    local p = procs[1]
    for ch in ("buy milk"):gmatch(".") do MOCK.push("char", ch) end
    -- click inside the note's own client area to go back to the list (and save)
    MOCK.push("mouse_click", 1, p.x + 2, p.y + 2)
    MOCK.push("mouse_up", 1, p.x + 2, p.y + 2)

  elseif phase == "notes_typing" and ev[1] == "mouse_up" then
    check(fs.exists("os/data/notes.dat"), "note was persisted to disk")
    local h = fs.open("os/data/notes.dat", "r")
    local raw = h.readAll() h.close()
    check(raw:find("buy milk", 1, true) ~= nil, "saved note contains the typed text")
    SHOT("notes_list")
    phase = "done"
    error("TEST_DONE", 0)
  end
end

MOCK.push("mouse_up", 1, 1, 1) -- harmless kick-off event

local ok, err = pcall(kernel.run, { onEvent = onEvent })
if not ok then
  check(tostring(err):find("TEST_DONE", 1, true) ~= nil, "kernel stopped cleanly: " .. tostring(err))
end
eq(phase, "done", "reached the end of the script")

finish("clock_notes")

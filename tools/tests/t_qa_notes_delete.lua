-- t_qa_notes_delete.lua -- Notes' D key deleted the selected note instantly
-- with zero confirmation, same footgun as Files had. Now requires Y/N.

local kernel = require_os("kernel")
local phase = "start"

local function notesFileHasMarker()
  local h = fs.open("os/data/notes.dat", "r")
  if not h then return false end
  local raw = h.readAll()
  h.close()
  return raw:find("dont delete me", 1, true) ~= nil
end

local function onEvent(ev, procs, focusedId)
  if phase == "start" then
    -- fixed position so later clicks can be aimed reliably
    kernel.launch("notes", nil, { x = 1, y = 1, w = 38, h = 17 })
    phase = "new_note"
  elseif phase == "new_note" then
    check(#procs == 1, "notes window open")
    MOCK.push("key", keys.n) -- create a new note (enters edit mode)
    phase = "typing"
  elseif phase == "typing" and ev[1] == "key" and ev[2] == keys.n then
    for ch in ("dont delete me"):gmatch(".") do MOCK.push("char", ch) end
    local p = procs[1]
    -- click inside the window's own client area to leave edit mode
    MOCK.push("mouse_click", 1, p.x + 5, p.y + 5)
    MOCK.push("mouse_up", 1, p.x + 5, p.y + 5)
    phase = "back_to_list"
  elseif phase == "back_to_list" and ev[1] == "mouse_up" then
    MOCK.push("key", keys.d)
    phase = "cancel"
  elseif phase == "cancel" and ev[1] == "key" and ev[2] == keys.d then
    SHOT("notes_delete_confirm")
    MOCK.push("key", keys.n) -- decline
    phase = "check_kept"
  elseif phase == "check_kept" and ev[1] == "key" and ev[2] == keys.n then
    check(notesFileHasMarker(), "declining the confirmation kept the note")
    MOCK.push("key", keys.d)
    phase = "confirm"
  elseif phase == "confirm" and ev[1] == "key" and ev[2] == keys.d then
    MOCK.push("key", keys.y) -- accept
    phase = "check_gone"
  elseif phase == "check_gone" and ev[1] == "key" and ev[2] == keys.y then
    check(not notesFileHasMarker(), "confirming the prompt actually deleted the note")
    SHOT("notes_after_delete")
    phase = "done"
    error("TEST_DONE", 0)
  end
end

MOCK.push("mouse_up", 1, 1, 1)
local ok, err = pcall(kernel.run, { onEvent = onEvent, noSession = true, skipSplash = true })
check(tostring(err):find("TEST_DONE", 1, true) ~= nil, "kernel stopped cleanly: " .. tostring(err))
finish("qa_notes_delete")

-- t_qa_editor_quit.lua -- Ctrl+Q used to discard unsaved edits instantly.
-- Now it asks for confirmation when there are unsaved changes, and quits
-- immediately (no prompt) when there's nothing to lose.

local kernel = require_os("kernel")
local phase = "start"

local function onEvent(ev, procs, focusedId)
  if phase == "start" then
    kernel.launch("editor", { "scratch2.txt" })
    phase = "type"
  elseif phase == "type" then
    check(#procs == 1, "editor window open")
    for ch in ("unsaved work"):gmatch(".") do MOCK.push("char", ch) end
    MOCK.push("key", keys.leftCtrl)
    MOCK.push("key", keys.q)
    phase = "wait_quit_attempt"
  elseif phase == "wait_quit_attempt" and ev[1] == "key" and ev[2] == keys.q then
    check(#procs == 1, "^Q with unsaved changes did not close the window yet")
    SHOT("editor_quit_confirm")
    MOCK.push("key_up", keys.leftCtrl)
    MOCK.push("key", keys.n) -- decline: keep editing
    phase = "declined"
  elseif phase == "declined" and ev[1] == "key" and ev[2] == keys.n then
    check(#procs == 1, "declining kept the editor open")
    MOCK.push("key", keys.leftCtrl)
    MOCK.push("key", keys.q)
    phase = "confirm_again"
  elseif phase == "confirm_again" and ev[1] == "key" and ev[2] == keys.q then
    MOCK.push("key", keys.y) -- accept: discard and close
    phase = "check_closed"
  elseif phase == "check_closed" and ev[1] == "key" and ev[2] == keys.y then
    check(#procs == 0, "confirming discarded the changes and closed the window")
    check(not fs.exists("scratch2.txt"), "the unsaved file was never written to disk")
    phase = "done"
    error("TEST_DONE", 0)
  end
end

MOCK.push("mouse_up", 1, 1, 1)
local ok, err = pcall(kernel.run, { onEvent = onEvent, noSession = true, skipSplash = true })
check(tostring(err):find("TEST_DONE", 1, true) ~= nil, "kernel stopped cleanly: " .. tostring(err))
finish("qa_editor_quit")

-- t_qa_files_delete.lua -- deleting a file in Files now requires a Y/N
-- confirmation instead of deleting instantly on one keypress.

local kernel = require_os("kernel")

-- an isolated directory containing only the one file, so its position in
-- the (sorted) listing is unambiguous regardless of what else is on disk
fs.makeDir("testdir")
do
  local h = fs.open("testdir/doomed.txt", "w")
  h.write("please don't delete me by accident") h.close()
end

local phase = "start"
local function onEvent(ev, procs, focusedId)
  if phase == "start" then
    kernel.launch("files", { "testdir" })
    phase = "select"
  elseif phase == "select" then
    check(#procs == 1, "files window open")
    -- entries in testdir/ are [".."] then ["doomed.txt"] -- Down once selects it
    MOCK.push("key", keys.down)
    phase = "press_d_cancel"
  elseif phase == "press_d_cancel" and ev[1] == "key" and ev[2] == keys.down then
    MOCK.push("key", keys.d)
    phase = "cancel"
  elseif phase == "cancel" and ev[1] == "key" and ev[2] == keys.d then
    SHOT("delete_confirm_prompt")
    MOCK.push("key", keys.n) -- decline
    phase = "check_not_deleted"
  elseif phase == "check_not_deleted" and ev[1] == "key" and ev[2] == keys.n then
    check(fs.exists("testdir/doomed.txt"), "declining the confirmation kept the file")
    MOCK.push("key", keys.d)
    phase = "confirm"
  elseif phase == "confirm" and ev[1] == "key" and ev[2] == keys.d then
    MOCK.push("key", keys.y) -- accept
    phase = "check_deleted"
  elseif phase == "check_deleted" and ev[1] == "key" and ev[2] == keys.y then
    check(not fs.exists("testdir/doomed.txt"), "confirming the prompt actually deleted the file")
    phase = "done"
    error("TEST_DONE", 0)
  end
end

MOCK.push("mouse_up", 1, 1, 1)
local ok, err = pcall(kernel.run, { onEvent = onEvent, noSession = true, skipSplash = true })
check(tostring(err):find("TEST_DONE", 1, true) ~= nil, "kernel stopped cleanly: " .. tostring(err))
finish("qa_files_delete")

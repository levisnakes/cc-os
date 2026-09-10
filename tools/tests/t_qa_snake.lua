local kernel = require_os("kernel")
local phase = "start"
local function onEvent(ev, procs, focusedId)
  if phase == "start" then
    kernel.launch("snake", nil, { x = 1, y = 1, w = 44, h = 17 })
    phase = "shot"
  elseif phase == "shot" then
    check(#procs == 1, "snake window open")
    SHOT("snake")
    phase = "done"
    error("TEST_DONE", 0)
  end
end
MOCK.push("mouse_up", 1, 1, 1)
local ok, err = pcall(kernel.run, { onEvent = onEvent, noSession = true, skipSplash = true })
check(tostring(err):find("TEST_DONE", 1, true) ~= nil, "kernel stopped cleanly")
finish("qa_snake")

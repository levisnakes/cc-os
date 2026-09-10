-- t_qa_about.lua -- visual + sanity check for the redesigned About screen
-- (pixel-art masthead via api.require, version, app list, shortcuts).

local kernel = require_os("kernel")
local phase = "start"

local function onEvent(ev, procs, focusedId)
  if phase == "start" then
    kernel.launch("about", nil, { x = 1, y = 1, w = 40, h = 18 })
    phase = "shot"
  elseif phase == "shot" then
    check(#procs == 1, "about window open")
    SHOT("about_redesigned")
    phase = "done"
    error("TEST_DONE", 0)
  end
end

MOCK.push("mouse_up", 1, 1, 1)
local ok, err = pcall(kernel.run, { onEvent = onEvent, noSession = true, skipSplash = true })
check(tostring(err):find("TEST_DONE", 1, true) ~= nil, "kernel stopped cleanly: " .. tostring(err))
finish("qa_about")

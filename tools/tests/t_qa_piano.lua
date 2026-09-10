-- t_qa_piano.lua -- regression test: all 25 keys must be visible and
-- clickable within the piano's default window size (a two-row keyboard
-- layout; the original one-row layout let 4 keys overflow off-screen).

local kernel = require_os("kernel")
local phase = "start"

local function onEvent(ev, procs, focusedId)
  if phase == "start" then
    kernel.launch("piano")
    phase = "click_last"
  elseif phase == "click_last" then
    local p = procs[1]
    check(p ~= nil, "piano window open")
    SHOT("piano_default")
    -- click the last key ("G", the 25th: row 1, col 11 of 13-per-row),
    -- using the layout math from piano.lua (keyW = floor(clientW / 13))
    local clientW = p.w - 2
    local keyW = math.max(2, math.floor(clientW / 13))
    local localX = 11 * keyW + 2 -- +2 to land inside (not on) the key's left edge
    local localY = 4 + 1 * 3 + 1 -- row 1 (0-indexed), middle of its 3-row box
    click(1, p.x + localX, p.y + localY)
    phase = "verify"
  elseif phase == "verify" and ev[1] == "mouse_up" then
    check(#MOCK.notes >= 1, "clicking the last (25th) key played a note")
    if #MOCK.notes >= 1 then
      eq(MOCK.notes[#MOCK.notes].pitch, 24, "clicking the last key played pitch 24 (the top note)")
    end
    phase = "done"
    error("TEST_DONE", 0)
  end
end

MOCK.push("mouse_up", 1, 1, 1)
local ok, err = pcall(kernel.run, { onEvent = onEvent, noSession = true, skipSplash = true })
check(tostring(err):find("TEST_DONE", 1, true) ~= nil, "kernel stopped cleanly: " .. tostring(err))
finish("qa_piano")

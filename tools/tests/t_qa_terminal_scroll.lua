-- t_qa_terminal_scroll.lua -- mouse_scroll in Terminal used to be a no-op;
-- verify scrolling up actually reveals earlier output, and typing snaps
-- the view back to the live tail.

local kernel = require_os("kernel")
local phase = "start"
local proc = nil
local scrollsLeft = 0

local function typeLine(line)
  for ch in line:gmatch(".") do MOCK.push("char", ch) end
  MOCK.push("key", keys.enter)
end

local function bufferText(p)
  local lines = {}
  local _, h = p.win.getSize()
  for y = 1, h do lines[#lines + 1] = (p.win.getLine(y)) end
  return table.concat(lines, "\n")
end

local function onEvent(ev, procs, focusedId)
  if phase == "start" then
    proc = kernel.launch("terminal")
    phase = "fill"
  elseif phase == "fill" then
    check(#procs == 1, "terminal window open")
    -- produce enough output to overflow the visible area (well past the
    -- default client height): one echo per distinct marker line
    for i = 1, 20 do typeLine("echo MARKER_" .. i) end
    phase = "wait_fill"
  elseif phase == "wait_fill" and ev[1] == "key" and ev[2] == keys.enter then
    -- keep waiting for the queued commands to actually run; the 20th
    -- marker landing in the buffer means we're caught up
    local text = bufferText(proc)
    if text:find("MARKER_20", 1, true) then
      phase = "check_tail"
    end
  elseif phase == "check_tail" then
    local text = bufferText(proc)
    check(text:find("MARKER_20", 1, true) ~= nil, "latest output is visible before scrolling")
    check(text:find("MARKER_1 ", 1, true) == nil and not text:find("echo MARKER_1$"),
      "earliest output has scrolled off the visible tail")
    SHOT("before_scroll")
    scrollsLeft = 6
    for i = 1, scrollsLeft do MOCK.push("mouse_scroll", -1, 5, 5) end
    phase = "scrolling"
  elseif phase == "scrolling" and ev[1] == "mouse_scroll" then
    scrollsLeft = scrollsLeft - 1
    if scrollsLeft <= 0 then phase = "scrolled" end
  elseif phase == "scrolled" then
    local text = bufferText(proc)
    check(text:find("MARKER_1", 1, true) ~= nil, "scrolling up revealed the earliest output")
    SHOT("after_scroll_up")
    -- typing should snap the view back to the live tail
    MOCK.push("char", "x")
    phase = "typed"
  elseif phase == "typed" and ev[1] == "char" then
    local text = bufferText(proc)
    check(text:find("MARKER_20", 1, true) ~= nil, "typing snapped the view back to the live tail")
    check(text:find("/> x", 1, true) ~= nil, "the prompt shows what was typed")
    SHOT("after_typing_snaps_back")
    phase = "done"
    error("TEST_DONE", 0)
  end
end

MOCK.push("mouse_up", 1, 1, 1)
local ok, err = pcall(kernel.run, { onEvent = onEvent, noSession = true, skipSplash = true })
check(tostring(err):find("TEST_DONE", 1, true) ~= nil, "kernel stopped cleanly: " .. tostring(err))
finish("qa_terminal_scroll")

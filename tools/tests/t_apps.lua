-- t_apps.lua -- end-to-end smoke test for every bundled app, driven through
-- the real kernel scheduler (kernel.launch + real key/mouse events), not by
-- calling app internals directly.

local kernel = require_os("kernel")

-- seed a scratch file for the editor/files test
do
  local h = fs.open("scratch.txt", "w")
  h.write("hello") h.close()
end

local phase = "start"
local proc = nil -- the single app window under test in most phases

local function closeFocused(procs, focusedId)
  local p = nil
  for i = 1, #procs do if procs[i].id == focusedId then p = procs[i] end end
  if not p then return end
  click(1, p.x + p.w - 2, p.y)
end

local function onEvent(ev, procs, focusedId)
  ----------------------------------------------------------------- editor
  if phase == "start" then
    phase = "editor_wait"
    proc = kernel.launch("editor", { "scratch.txt" })

  elseif phase == "editor_wait" then
    check(#procs == 1, "editor window open")
    phase = "editor_type"
    -- move cursor to end of "hello" and append " world", then save
    MOCK.push("key", keys["end"])
    MOCK.push("char", " ")
    MOCK.push("char", "w")
    MOCK.push("char", "o")
    MOCK.push("char", "r")
    MOCK.push("char", "l")
    MOCK.push("char", "d")
    MOCK.push("key", keys.leftCtrl)
    MOCK.push("key", keys.s)
    MOCK.push("key_up", keys.leftCtrl)

  elseif phase == "editor_type" and ev[1] == "key_up" then
    SHOT("editor_saved")
    local fh = fs.open("scratch.txt", "r")
    local content = fh.readAll() fh.close()
    eq(content, "hello world", "editor saved the edited text")
    phase = "editor_close"
    closeFocused(procs, focusedId)

  ----------------------------------------------------------------- files
  elseif phase == "editor_close" and ev[1] == "mouse_up" then
    check(#procs == 0, "editor closed")
    phase = "files_wait"
    proc = kernel.launch("files")

  elseif phase == "files_wait" then
    check(#procs == 1, "files window open")
    eq(procs[1].appId, "files", "files launched")
    SHOT("files_open")
    phase = "files_close"
    closeFocused(procs, focusedId)

  ----------------------------------------------------------------- calculator
  elseif phase == "files_close" and ev[1] == "mouse_up" then
    check(#procs == 0, "files closed")
    phase = "calc_wait"
    proc = kernel.launch("calc")

  elseif phase == "calc_wait" then
    check(#procs == 1, "calculator window open")
    phase = "calc_compute"
    MOCK.push("char", "6")
    MOCK.push("char", "*")
    MOCK.push("char", "7")
    MOCK.push("key", keys.enter)

  elseif phase == "calc_compute" and ev[1] == "key" and ev[2] == keys.enter then
    phase = "calc_verify"

  elseif phase == "calc_verify" then
    SHOT("calc_result")
    phase = "calc_close"
    closeFocused(procs, focusedId)

  ----------------------------------------------------------------- terminal
  elseif phase == "calc_close" and ev[1] == "mouse_up" then
    check(#procs == 0, "calculator closed")
    phase = "term_wait"
    proc = kernel.launch("terminal")

  elseif phase == "term_wait" then
    check(#procs == 1, "terminal window open")
    phase = "term_run"
    for ch in ("mkdir stuff"):gmatch(".") do MOCK.push("char", ch) end
    MOCK.push("key", keys.enter)

  elseif phase == "term_run" and ev[1] == "key" and ev[2] == keys.enter then
    phase = "term_verify"

  elseif phase == "term_verify" then
    check(fs.isDir("stuff"), "terminal's mkdir created a real directory")
    SHOT("terminal_mkdir")
    phase = "term_close"
    closeFocused(procs, focusedId)

  ----------------------------------------------------------------- snake
  elseif phase == "term_close" and ev[1] == "mouse_up" then
    check(#procs == 0, "terminal closed")
    phase = "snake_wait"
    proc = kernel.launch("snake")

  elseif phase == "snake_wait" then
    check(#procs == 1, "snake window open")
    phase = "snake_running"

  elseif phase == "snake_running" and ev[1] == "timer" then
    SHOT("snake_tick")
    phase = "snake_close"
    closeFocused(procs, focusedId)

  ----------------------------------------------------------------- piano
  elseif phase == "snake_close" and ev[1] == "mouse_up" then
    check(#procs == 0, "snake closed")
    phase = "piano_wait"
    proc = kernel.launch("piano")

  elseif phase == "piano_wait" then
    check(#procs == 1, "piano window open")
    phase = "piano_play"
    MOCK.push("key", keys.one, false)

  elseif phase == "piano_play" and ev[1] == "key" then
    check(#MOCK.notes >= 1, "piano played a note")
    phase = "piano_close"
    closeFocused(procs, focusedId)

  ----------------------------------------------------------------- settings
  elseif phase == "piano_close" and ev[1] == "mouse_up" then
    check(#procs == 0, "piano closed")
    phase = "settings_wait"
    proc = kernel.launch("settings")

  elseif phase == "settings_wait" then
    check(#procs == 1, "settings window open")
    SHOT("settings_open")
    -- click the second theme row ("Paper") -- row 1 is "Theme" label, row 2 is Slate, row 3 Paper
    local p = procs[1]
    phase = "settings_theme"
    click(1, p.x + 3, p.y + 3)

  elseif phase == "settings_theme" and ev[1] == "mouse_up" then
    eq(kernel.getTheme().id, "paper", "clicking a theme row applies it")
    SHOT("settings_paper")
    phase = "settings_close"
    closeFocused(procs, focusedId)

  elseif phase == "settings_close" and ev[1] == "mouse_up" then
    check(#procs == 0, "settings closed")
    phase = "done"
    error("TEST_DONE", 0)
  end
end

MOCK.push("mouse_up", 1, 1, 1) -- harmless kick-off event

local ok, err = pcall(kernel.run, { onEvent = onEvent, skipSplash = true, noSession = true })
if not ok then
  check(tostring(err):find("TEST_DONE", 1, true) ~= nil, "kernel stopped cleanly: " .. tostring(err))
end
eq(phase, "done", "reached the end of the script")

finish("apps")

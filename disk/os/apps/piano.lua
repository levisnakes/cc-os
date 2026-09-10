--[[ piano -- a playable on-screen keyboard driven by the computer keyboard,
  using the attached speaker (peripheral "speaker"). ]]

local M = {}
M.id = "piano"
M.name = "Piano"

local INSTRUMENTS = {
  "harp", "bass", "bell", "flute", "chime", "guitar", "xylophone",
  "iron_xylophone", "cow_bell", "banjo", "pling", "bit", "didgeridoo",
}

local KEY_ORDER = {
  "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "zero",
  "q", "w", "e", "r", "t", "y", "u", "i", "o", "p", "a", "s", "d", "f", "g",
}
local LABELS = {
  "1", "2", "3", "4", "5", "6", "7", "8", "9", "0",
  "Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P", "A", "S", "D", "F", "G",
}

function M.run(ctx)
  local api = ctx.api
  local data = api.getSettings()
  local speaker = peripheral.find("speaker")

  local keyToPitch = {}
  for i = 1, #KEY_ORDER do keyToPitch[keys[KEY_ORDER[i]]] = i - 1 end

  local instIdx = 1
  local activeKey = nil
  local activeTimer = nil

  local w, h
  local function refreshSize() w, h = api.getSize() end
  refreshSize()

  local function draw()
    local T = api.getTheme()
    term.setBackgroundColor(T.bg)
    term.setTextColor(T.fg)
    term.clear()

    term.setCursorPos(2, 1)
    term.setTextColor(T.accent)
    term.write("Instrument: " .. INSTRUMENTS[instIdx] .. "  ([ / ] to change)")

    if not speaker then
      term.setCursorPos(2, 3)
      term.setTextColor(T.err)
      term.write("No speaker attached.")
      return
    end

    local n = #KEY_ORDER
    local perRow = math.ceil(n / 2)
    local keyW = math.max(2, math.floor(w / perRow))
    for i = 1, n do
      local row = math.floor((i - 1) / perRow)
      local col = (i - 1) % perRow
      local x = col * keyW + 1
      local y = 4 + row * 3
      local pressed = (activeKey == i - 1)
      term.setBackgroundColor(pressed and T.accent or T.field)
      term.setTextColor(pressed and T.chromeFocusText or T.fieldText)
      term.setCursorPos(x, y)
      term.write(string.rep(" ", keyW - 1))
      term.setCursorPos(x, y + 1)
      local pad = math.max(0, math.floor((keyW - 1 - #LABELS[i]) / 2))
      term.write(string.rep(" ", pad) .. LABELS[i])
      term.setCursorPos(x, y + 2)
      term.write(string.rep(" ", keyW - 1))
    end

    term.setBackgroundColor(T.bg)
    term.setTextColor(T.desktopText)
    term.setCursorPos(2, h)
    term.write("Play with the keyboard, or click a key.")
  end

  local function play(pitch)
    if not speaker then return end
    activeKey = pitch
    if activeTimer then os.cancelTimer(activeTimer) end
    activeTimer = os.startTimer(0.2)
    local vol = (data.get("volume") or 7) / 10
    pcall(speaker.playNote, INSTRUMENTS[instIdx], vol, pitch)
  end

  draw()
  while true do
    local ev = { api.pullEvent() }
    local kind = ev[1]
    if kind == "key" then
      local held = ev[3]
      local pitch = keyToPitch[ev[2]]
      if pitch and not held then
        play(pitch)
      elseif ev[2] == keys.leftBracket then
        instIdx = instIdx - 1
        if instIdx < 1 then instIdx = #INSTRUMENTS end
      elseif ev[2] == keys.rightBracket then
        instIdx = instIdx + 1
        if instIdx > #INSTRUMENTS then instIdx = 1 end
      end
    elseif kind == "mouse_click" and speaker then
      local x, y = ev[3], ev[4]
      local n = #KEY_ORDER
      local perRow = math.ceil(n / 2)
      local keyW = math.max(2, math.floor(w / perRow))
      if y >= 4 and y <= 9 then
        local row = math.floor((y - 4) / 3)
        local col = math.floor((x - 1) / keyW)
        local idx = row * perRow + col + 1
        if idx >= 1 and idx <= n and col >= 0 and col < perRow then play(idx - 1) end
      end
    elseif kind == "timer" and ev[2] == activeTimer then
      activeKey = nil
      activeTimer = nil
    elseif kind == "term_resize" then
      refreshSize()
    end
    draw()
  end
end

return M

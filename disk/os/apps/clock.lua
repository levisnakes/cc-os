--[[ clock -- digital clock plus a small alarm list (uses os.setAlarm). ]]

local M = {}
M.id = "clock"
M.name = "Clock"

local PATH = "/os/data/alarms.dat"

function M.run(ctx)
  local api = ctx.api
  local data = api.getSettings()

  local function loadAlarms()
    if fs.exists(PATH) then
      local h = fs.open(PATH, "r")
      if h then
        local raw = h.readAll()
        h.close()
        local ok, t = pcall(textutils.unserialize, raw)
        if ok and type(t) == "table" then return t end
      end
    end
    return {}
  end

  local function saveAlarms(alarms)
    local h = fs.open(PATH, "w")
    if h then h.write(textutils.serialize(alarms)) h.close() end
  end

  local alarms = loadAlarms()
  local armed = {} -- os.setAlarm id -> alarm index

  local function armAll()
    for id in pairs(armed) do os.cancelAlarm(id) armed[id] = nil end
    for i = 1, #alarms do
      local a = alarms[i]
      if a.enabled then
        local id = os.setAlarm(a.hour + a.minute / 60)
        armed[id] = i
      end
    end
  end

  local firing = nil -- alarm currently ringing, or nil

  local function fmt2(n) return string.format("%02d", n) end

  local function draw()
    local T = api.getTheme()
    local w, h = api.getSize()
    term.setBackgroundColor(T.bg)
    term.setTextColor(T.fg)
    term.clear()

    local clock24h = data.get("clock24h")
    local t = os.time()
    local hh = math.floor(t) % 24
    local mm = math.floor((t % 1) * 60)
    local ss = math.floor((t * 3600) % 60)
    local label
    if clock24h then
      label = fmt2(hh) .. ":" .. fmt2(mm) .. ":" .. fmt2(ss)
    else
      local h12 = hh % 12
      if h12 == 0 then h12 = 12 end
      label = h12 .. ":" .. fmt2(mm) .. ":" .. fmt2(ss) .. (hh < 12 and " AM" or " PM")
    end

    term.setTextColor(T.accent)
    term.setCursorPos(math.max(1, math.floor((w - #label) / 2)), 1)
    term.write(label)

    term.setTextColor(T.fg)
    term.setCursorPos(2, 3)
    term.write("Alarms:")
    for i = 1, #alarms do
      local a = alarms[i]
      local y = 3 + i
      if y > h - 2 then break end
      term.setCursorPos(2, y)
      term.setTextColor(a.enabled and T.ok or T.desktopText)
      term.write((a.enabled and "[x] " or "[ ] ") .. fmt2(a.hour) .. ":" .. fmt2(a.minute) .. " " .. (a.label or ""))
    end

    term.setCursorPos(2, h)
    term.setBackgroundColor(T.chrome)
    term.setTextColor(T.chromeText)
    term.write(string.rep(" ", w - 2))
    term.setCursorPos(2, h)
    term.write(" A=add  X=remove selected  Space=toggle ")

    if firing then
      term.setBackgroundColor(T.err)
      term.setTextColor(colors.white)
      local msg = "ALARM: " .. (firing.label or "") .. "  (press any key)"
      term.setCursorPos(1, math.floor(h / 2))
      term.write(string.rep(" ", w))
      term.setCursorPos(math.max(1, math.floor((w - #msg) / 2)), math.floor(h / 2))
      term.write(msg)
    end
  end

  local function prompt(question)
    local T = api.getTheme()
    local w, h = api.getSize()
    term.setCursorPos(2, h)
    term.setBackgroundColor(T.field)
    term.setTextColor(T.fieldText)
    term.write(string.rep(" ", w - 2))
    term.setCursorPos(2, h)
    term.write(question)
    local buf = ""
    while true do
      local ev = { api.pullEvent() }
      if ev[1] == "char" then buf = buf .. ev[2]
      elseif ev[1] == "key" and ev[2] == keys.backspace then buf = buf:sub(1, -2)
      elseif ev[1] == "key" and (ev[2] == keys.enter or ev[2] == keys.numPadEnter) then return buf
      end
      term.setCursorPos(2, h)
      term.write(string.rep(" ", w - 2))
      term.setCursorPos(2, h)
      term.write(question .. buf)
    end
  end

  local function confirm(question)
    local T = api.getTheme()
    local w, h = api.getSize()
    term.setCursorPos(2, h)
    term.setBackgroundColor(T.err)
    term.setTextColor(colors.white)
    term.write(string.rep(" ", w - 2))
    term.setCursorPos(2, h)
    term.write(question .. " (Y/N)")
    while true do
      local ev = { api.pullEvent() }
      if ev[1] == "key" then
        if ev[2] == keys.y then return true end
        if ev[2] == keys.n or ev[2] == keys.enter or ev[2] == keys.numPadEnter then return false end
      end
    end
  end

  local selected = 1
  armAll()
  draw()
  while true do
    local ev = { api.pullEvent() }
    local kind = ev[1]
    if firing then
      if kind == "key" or kind == "mouse_click" then
        firing = nil
        armAll()
      end
    elseif kind == "alarm" then
      local idx = armed[ev[2]]
      if idx and alarms[idx] then firing = alarms[idx] end
    elseif kind == "timer" then
      -- redraw to tick the seconds
    elseif kind == "key" then
      local k = ev[2]
      if k == keys.a then
        local timeStr = prompt("HH:MM: ")
        local hh2, mm2 = timeStr:match("^(%d+):(%d+)$")
        if hh2 then
          alarms[#alarms + 1] = { hour = tonumber(hh2) % 24, minute = tonumber(mm2) % 60, enabled = true, label = "Alarm" }
          saveAlarms(alarms)
          armAll()
        end
      elseif k == keys.x then
        local a = alarms[selected]
        if a and confirm(string.format("Remove %02d:%02d alarm?", a.hour, a.minute)) then
          table.remove(alarms, selected)
          saveAlarms(alarms)
          armAll()
        end
      elseif k == keys.space then
        if alarms[selected] then
          alarms[selected].enabled = not alarms[selected].enabled
          saveAlarms(alarms)
          armAll()
        end
      elseif k == keys.down then
        selected = math.min(#alarms, selected + 1)
      elseif k == keys.up then
        selected = math.max(1, selected - 1)
      end
    end
    draw()
  end
end

return M

--[[ cc-OS installer -- the whole OS in one file.

  This writes 26 files and then you are done. Nothing is downloaded, so
  it works on a computer with HTTP disabled.

    install            unpack into this computer
    install <folder>   unpack somewhere else

  After it finishes, reboot the computer (or run: cc-os).
]]

local target = ({ ... })[1] or ""
if target ~= "" then
  target = "/" .. target:gsub("^/+", ""):gsub("/+$", "")
end

local FILES = {}
local ORDER = {}

local function file(path, body)
  FILES[path] = body
  ORDER[#ORDER + 1] = path
end

file("cc-os.lua", [[
-- cc-os -- manually launch the desktop without rebooting.
if not fs.exists("/os/boot.lua") then
  print("cc-OS is not installed.")
  print("Expected to find /os/boot.lua")
  return
end
shell.run("/os/boot.lua")
]])
file("os/apps/about.lua", [=[
--[[ about -- version info and a live event log, useful as a smoke-test app. ]]

local M = {}
M.id = "about"
M.name = "About"

function M.run(ctx)
  local api = ctx.api

  local function draw()
    local th = api.getTheme()
    local w, h = api.getSize()
    term.setBackgroundColor(th.bg)
    term.setTextColor(th.fg)
    term.clear()
    term.setCursorPos(2, 2)
    term.setTextColor(th.accent)
    term.write("cc-OS")
    term.setTextColor(th.fg)
    term.setCursorPos(2, 3)
    term.write("version 1.0.0")
    term.setCursorPos(2, 5)
    term.write("A windowed, multitasking desktop")
    term.setCursorPos(2, 6)
    term.write("for CC:Tweaked advanced computers.")
    term.setCursorPos(2, 8)
    term.write("Drag titlebars to move windows.")
    term.setCursorPos(2, 9)
    term.write("[_] minimizes, [x] closes.")
    term.setCursorPos(2, h - 1)
    term.setTextColor(th.desktopText)
  end

  draw()
  while true do
    api.pullEvent()
    draw()
  end
end

return M
]=])
file("os/apps/calculator.lua", [=[
--[[ calculator -- a simple button-grid calculator with keyboard support. ]]

local M = {}
M.id = "calc"
M.name = "Calc"

local ROWS = {
  { "7", "8", "9", "/" },
  { "4", "5", "6", "*" },
  { "1", "2", "3", "-" },
  { "0", ".", "=", "+" },
}

function M.run(ctx)
  local api = ctx.api
  local expr = ""
  local result = ""
  local gridTop = 4
  local buttons = {}

  local function compute()
    local clean = expr:gsub("[^%d%.%+%-%*/%(%)]", "")
    if clean == "" then return end
    local fn, err = load("return " .. clean, "calc", "t", {})
    if not fn then result = "error" return end
    local ok, val = pcall(fn)
    if not ok or type(val) ~= "number" then result = "error"
    else result = tostring(val) end
  end

  local function draw()
    local T = api.getTheme()
    local w, h = api.getSize()
    local btnW = math.floor(w / 4)
    term.setBackgroundColor(T.bg)
    term.setTextColor(T.fg)
    term.clear()

    term.setBackgroundColor(T.field)
    for row = 1, 2 do
      term.setCursorPos(1, row)
      term.write(string.rep(" ", w))
    end
    term.setTextColor(T.fieldText)
    term.setCursorPos(2, 1)
    local e = expr
    if #e > w - 2 then e = e:sub(#e - (w - 2) + 1) end
    term.write(e)
    term.setCursorPos(2, 2)
    term.setTextColor(T.accent)
    term.write(result)

    buttons = {}
    for r = 1, #ROWS do
      for c = 1, 4 do
        local label = ROWS[r][c]
        local x = (c - 1) * btnW + 1
        local y = gridTop + (r - 1) * 2
        local bg = (label == "=") and T.accent or T.chrome
        local fg = (label == "=") and T.chromeFocusText or T.chromeText
        term.setBackgroundColor(bg)
        term.setTextColor(fg)
        term.setCursorPos(x, y)
        local w2 = (c == 4) and (w - x + 1) or btnW
        local pad = math.max(0, math.floor((w2 - #label) / 2))
        term.write(string.rep(" ", w2))
        term.setCursorPos(x + pad, y)
        term.write(label)
        buttons[#buttons + 1] = { x = x, y = y, w = w2, h = 1, label = label }
      end
    end

    term.setBackgroundColor(T.err)
    term.setTextColor(colors.white)
    local cy = gridTop + #ROWS * 2
    term.setCursorPos(1, cy)
    term.write(string.rep(" ", w))
    local clearLabel = "Clear (C)"
    term.setCursorPos(math.max(1, math.floor((w - #clearLabel) / 2)), cy)
    term.write(clearLabel)
    buttons[#buttons + 1] = { x = 1, y = cy, w = w, h = 1, label = "C" }
  end

  local function press(label)
    if label == "=" then
      compute()
    elseif label == "C" then
      expr, result = "", ""
    else
      expr = expr .. label
    end
  end

  draw()
  while true do
    local ev = { api.pullEvent() }
    if ev[1] == "mouse_click" then
      local x, y = ev[3], ev[4]
      for i = 1, #buttons do
        local b = buttons[i]
        if x >= b.x and x < b.x + b.w and y == b.y then press(b.label) break end
      end
    elseif ev[1] == "char" then
      if ev[2]:match("[%d%.%+%-%*/%(%)]") then expr = expr .. ev[2] end
    elseif ev[1] == "key" then
      if ev[2] == keys.enter or ev[2] == keys.numPadEnter then compute()
      elseif ev[2] == keys.backspace then expr = expr:sub(1, -2)
      end
    end
    draw()
  end
end

return M
]=])
file("os/apps/chat.lua", [=[
--[[ chat -- broadcast text chat with every other cc-OS computer in modem range. ]]

local req = ...
local net = req("lib.net")

local M = {}
M.id = "chat"
M.name = "Chat"

function M.run(ctx)
  local api = ctx.api
  local log = {}
  local input = ""
  local modem, err = net.open()

  local function push(sender, text)
    log[#log + 1] = sender .. ": " .. text
  end

  if not modem then
    push("system", "No modem attached: " .. tostring(err))
  else
    push("system", "Connected as " .. net.myName() .. ". Messages reach every cc-OS computer in range.")
  end

  local function draw()
    local T = api.getTheme()
    local w, h = api.getSize()
    term.setBackgroundColor(T.bg)
    term.setTextColor(T.fg)
    term.clear()
    local outH = h - 1
    local first = math.max(1, #log - outH + 1)
    for row = 0, outH - 1 do
      local idx = first + row
      local line = log[idx]
      if line then
        term.setCursorPos(1, row + 1)
        if #line > w then line = line:sub(1, w) end
        term.write(line)
      end
    end
    term.setCursorPos(1, h)
    term.setBackgroundColor(T.chrome)
    term.setTextColor(T.chromeText)
    term.write(string.rep(" ", w))
    term.setCursorPos(1, h)
    local visible = "> " .. input
    if #visible > w then visible = visible:sub(#visible - w + 1) end
    term.write(visible)
    term.setCursorPos(math.min(w, #visible + 1), h)
    term.setCursorBlink(true)
  end

  draw()
  while true do
    local ev = { api.pullEvent() }
    local kind = ev[1]
    if kind == "char" then
      input = input .. ev[2]
    elseif kind == "key" then
      if ev[2] == keys.backspace then
        input = input:sub(1, -2)
      elseif ev[2] == keys.enter or ev[2] == keys.numPadEnter then
        if #input > 0 then
          push(net.myName() .. " (you)", input)
          net.send("chat", { text = input })
          input = ""
        end
      end
    elseif kind == "modem_message" then
      local msg = net.parse(ev)
      if msg and msg.t == "chat" and type(msg.data) == "table" then
        push(msg.from or "?", tostring(msg.data.text))
      end
    end
    draw()
  end
end

return M
]=])
file("os/apps/clock.lua", [=[
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
        if alarms[selected] then
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
]=])
file("os/apps/editor.lua", [=[
--[[ editor -- a small text editor with line numbers and light Lua highlighting. ]]

local M = {}
M.id = "editor"
M.name = "Editor"

local KEYWORDS = {}
for _, kw in ipairs({
  "and", "break", "do", "else", "elseif", "end", "false", "for", "function",
  "if", "in", "local", "nil", "not", "or", "repeat", "return", "then",
  "true", "until", "while",
}) do KEYWORDS[kw] = true end

local function loadLines(path)
  local lines = { "" }
  if path and fs.exists(path) and not fs.isDir(path) then
    local h = fs.open(path, "r")
    if h then
      lines = {}
      while true do
        local l = h.readLine()
        if l == nil then break end
        lines[#lines + 1] = l
      end
      h.close()
      if #lines == 0 then lines = { "" } end
    end
  end
  return lines
end

--- Splits a line of Lua source into {text, kind} runs for highlighting.
--- kind is "kw" | "str" | "comment" | "num" | nil (plain).
local function tokenize(line)
  local runs = {}
  local i, n = 1, #line
  while i <= n do
    local c = line:sub(i, i)
    if line:sub(i, i + 1) == "--" then
      runs[#runs + 1] = { text = line:sub(i), kind = "comment" }
      break
    elseif c == "\"" or c == "'" then
      local q = c
      local j = i + 1
      while j <= n and line:sub(j, j) ~= q do
        if line:sub(j, j) == "\\" then j = j + 1 end
        j = j + 1
      end
      j = math.min(j, n)
      runs[#runs + 1] = { text = line:sub(i, j), kind = "str" }
      i = j
    elseif c:match("%d") then
      local j = i
      while j <= n and line:sub(j, j):match("[%w%.]") do j = j + 1 end
      runs[#runs + 1] = { text = line:sub(i, j - 1), kind = "num" }
      i = j - 1
    elseif c:match("[%a_]") then
      local j = i
      while j <= n and line:sub(j, j):match("[%w_]") do j = j + 1 end
      local word = line:sub(i, j - 1)
      runs[#runs + 1] = { text = word, kind = KEYWORDS[word] and "kw" or nil }
      i = j - 1
    else
      runs[#runs + 1] = { text = c, kind = nil }
    end
    i = i + 1
  end
  return runs
end

function M.run(ctx)
  local api = ctx.api
  local path = ctx.args and ctx.args[1]
  local lines = loadLines(path)
  local cy, cx = 1, 1
  local scrollY, scrollX = 0, 0
  local modified = false
  local status = ""

  local gutter = 4
  local w, h, textW, textH
  local function refreshSize()
    w, h = api.getSize()
    textW, textH = w - gutter, h - 1
  end
  refreshSize()

  local function highlight(lineText, useColor)
    if not useColor then
      term.write(lineText)
      return
    end
    local T = api.getTheme()
    local runs = tokenize(lineText)
    for i = 1, #runs do
      local r = runs[i]
      if r.kind == "kw" then term.setTextColor(T.accent)
      elseif r.kind == "str" then term.setTextColor(T.ok)
      elseif r.kind == "comment" then term.setTextColor(T.desktopText)
      elseif r.kind == "num" then term.setTextColor(T.accent2)
      else term.setTextColor(T.fg) end
      term.write(r.text)
    end
  end

  local function draw()
    local T = api.getTheme()
    local isLua = path and path:sub(-4) == ".lua"
    term.setBackgroundColor(T.bg)
    term.setTextColor(T.fg)
    term.clear()

    if cy - scrollY > textH then scrollY = cy - textH end
    if cy - scrollY < 1 then scrollY = cy - 1 end
    if cx - scrollX > textW then scrollX = cx - textW end
    if cx - scrollX < 1 then scrollX = cx - 1 end
    if scrollX < 0 then scrollX = 0 end

    for row = 0, textH - 1 do
      local ln = scrollY + row + 1
      term.setCursorPos(1, row + 1)
      term.setBackgroundColor(T.chrome)
      term.setTextColor(T.chromeText)
      if lines[ln] then
        term.write(string.format("%" .. (gutter - 1) .. "d ", ln))
      else
        term.write(string.rep(" ", gutter))
      end
      term.setBackgroundColor(T.bg)
      if lines[ln] then
        local visible = lines[ln]:sub(scrollX + 1, scrollX + textW)
        highlight(visible, isLua)
      end
    end

    term.setCursorPos(1, h)
    term.setBackgroundColor(T.chrome)
    term.setTextColor(T.chromeText)
    term.write(string.rep(" ", w))
    term.setCursorPos(1, h)
    local name = path and fs.getName(path) or "untitled"
    term.write((modified and "*" or "") .. name .. "  Ln " .. cy .. ", Col " .. cx ..
      "  ^S save  ^Q close" .. (status ~= "" and ("  " .. status) or ""))

    local cursorScreenX = gutter + (cx - scrollX)
    local cursorScreenY = (cy - scrollY)
    if cursorScreenX >= gutter + 1 and cursorScreenX <= w and cursorScreenY >= 1 and cursorScreenY <= textH then
      term.setCursorPos(cursorScreenX, cursorScreenY)
      term.setCursorBlink(true)
    else
      term.setCursorBlink(false)
    end
  end

  local function save()
    if not path then
      status = "no filename"
      return
    end
    local h2 = fs.open(path, "w")
    if not h2 then
      status = "save failed"
      return
    end
    h2.write(table.concat(lines, "\n"))
    h2.close()
    modified = false
    status = "saved"
    api.notify("Saved " .. fs.getName(path))
  end

  local ctrl = false
  draw()
  while true do
    local ev = { api.pullEvent() }
    local kind = ev[1]
    status = ""
    if kind == "char" then
      local line = lines[cy]
      lines[cy] = line:sub(1, cx - 1) .. ev[2] .. line:sub(cx)
      cx = cx + #ev[2]
      modified = true
    elseif kind == "key" then
      local k = ev[2]
      if k == keys.leftCtrl or k == keys.rightCtrl then
        ctrl = true
      elseif ctrl and k == keys.s then
        save()
      elseif ctrl and k == keys.q then
        api.exit()
      elseif k == keys.left then
        if cx > 1 then cx = cx - 1 elseif cy > 1 then cy = cy - 1 cx = #lines[cy] + 1 end
      elseif k == keys.right then
        if cx <= #lines[cy] then cx = cx + 1 elseif cy < #lines then cy = cy + 1 cx = 1 end
      elseif k == keys.up then
        if cy > 1 then cy = cy - 1 cx = math.min(cx, #lines[cy] + 1) end
      elseif k == keys.down then
        if cy < #lines then cy = cy + 1 cx = math.min(cx, #lines[cy] + 1) end
      elseif k == keys.home then
        cx = 1
      elseif k == keys["end"] then
        cx = #lines[cy] + 1
      elseif k == keys.backspace then
        if cx > 1 then
          lines[cy] = lines[cy]:sub(1, cx - 2) .. lines[cy]:sub(cx)
          cx = cx - 1
          modified = true
        elseif cy > 1 then
          local prevLen = #lines[cy - 1]
          lines[cy - 1] = lines[cy - 1] .. lines[cy]
          table.remove(lines, cy)
          cy = cy - 1
          cx = prevLen + 1
          modified = true
        end
      elseif k == keys.delete then
        if cx <= #lines[cy] then
          lines[cy] = lines[cy]:sub(1, cx - 1) .. lines[cy]:sub(cx + 1)
          modified = true
        elseif cy < #lines then
          lines[cy] = lines[cy] .. lines[cy + 1]
          table.remove(lines, cy + 1)
          modified = true
        end
      elseif k == keys.enter or k == keys.numPadEnter then
        local line = lines[cy]
        local rest = line:sub(cx)
        lines[cy] = line:sub(1, cx - 1)
        table.insert(lines, cy + 1, rest)
        cy = cy + 1
        cx = 1
        modified = true
      elseif k == keys.tab then
        lines[cy] = lines[cy]:sub(1, cx - 1) .. "  " .. lines[cy]:sub(cx)
        cx = cx + 2
        modified = true
      end
    elseif kind == "key_up" then
      if ev[2] == keys.leftCtrl or ev[2] == keys.rightCtrl then ctrl = false end
    elseif kind == "mouse_click" then
      local x, y = ev[3], ev[4]
      if y >= 1 and y <= textH then
        local ln = scrollY + y
        if lines[ln] then
          cy = ln
          cx = math.min(#lines[cy] + 1, math.max(1, scrollX + (x - gutter) + 1))
        end
      end
    elseif kind == "mouse_scroll" then
      scrollY = math.max(0, scrollY + ev[2] * 2)
    elseif kind == "term_resize" then
      refreshSize()
    elseif kind == "os_theme" then
      -- redraw below
    end
    draw()
  end
end

return M
]=])
file("os/apps/files.lua", [=[
--[[ files -- a simple file manager: browse, open, rename, delete, new file/folder. ]]

local M = {}
M.id = "files"
M.name = "Files"

local function join(dir, name)
  if dir == "" or dir == "/" then return "/" .. name end
  return dir .. "/" .. name
end

function M.run(ctx)
  local api = ctx.api
  local cwd = (ctx.args and ctx.args[1]) or ""
  local entries = {}
  local selected = 1
  local top = 0
  local status = ""

  local function refresh()
    entries = {}
    if cwd ~= "" then entries[#entries + 1] = { name = "..", dir = true } end
    local names = fs.list(cwd == "" and "/" or cwd)
    table.sort(names)
    local dirs, files_ = {}, {}
    for i = 1, #names do
      local full = join(cwd, names[i])
      if fs.isDir(full) then dirs[#dirs + 1] = names[i] else files_[#files_ + 1] = names[i] end
    end
    for i = 1, #dirs do entries[#entries + 1] = { name = dirs[i], dir = true } end
    for i = 1, #files_ do entries[#entries + 1] = { name = files_[i], dir = false } end
    if selected > #entries then selected = #entries end
    if selected < 1 and #entries > 0 then selected = 1 end
  end

  local function fullPath(i)
    local e = entries[i]
    if not e then return nil end
    if e.name == ".." then return fs.getDir(cwd) end
    return join(cwd, e.name)
  end

  local w, h, listH
  local function refreshSize()
    w, h = api.getSize()
    listH = h - 3
  end
  refreshSize()

  local function draw()
    local T = api.getTheme()
    term.setBackgroundColor(T.bg)
    term.setTextColor(T.fg)
    term.clear()

    term.setCursorPos(1, 1)
    term.setBackgroundColor(T.chrome)
    term.setTextColor(T.chromeText)
    term.write(string.rep(" ", w))
    term.setCursorPos(1, 1)
    local pathStr = "/" .. cwd
    if #pathStr > w then pathStr = "..." .. pathStr:sub(#pathStr - w + 4) end
    term.write(pathStr)

    if selected - top > listH then top = selected - listH end
    if selected - top < 1 then top = selected - 1 end
    if top < 0 then top = 0 end

    for row = 0, listH - 1 do
      local idx = top + row + 1
      local y = 2 + row
      local e = entries[idx]
      local bg = T.bg
      local fg = T.fg
      if e and idx == selected then bg, fg = T.accent, T.chromeFocusText end
      term.setCursorPos(1, y)
      term.setBackgroundColor(bg)
      term.setTextColor(fg)
      local line = string.rep(" ", w)
      term.write(line)
      term.setCursorPos(2, y)
      if e then
        local label = e.name .. (e.dir and "/" or "")
        if #label > w - 2 then label = label:sub(1, w - 4) .. ".." end
        term.write(label)
      end
    end

    term.setCursorPos(1, h - 1)
    term.setBackgroundColor(T.bg)
    term.setTextColor(T.desktopText)
    term.write(string.rep(" ", w))
    term.setCursorPos(1, h - 1)
    term.write("Enter=open  N=new  D=del  R=rename")

    term.setCursorPos(1, h)
    term.setBackgroundColor(T.chrome)
    term.setTextColor(T.err)
    term.write(string.rep(" ", w))
    term.setCursorPos(1, h)
    term.setTextColor(T.chromeText)
    term.write((status ~= "" and status) or (#entries .. " item(s)"))
  end

  local function prompt(question)
    local T = api.getTheme()
    term.setCursorPos(1, h - 1)
    term.setBackgroundColor(T.field)
    term.setTextColor(T.fieldText)
    term.write(string.rep(" ", w))
    term.setCursorPos(1, h - 1)
    term.write(question)
    local buf = ""
    while true do
      local ev = { api.pullEvent() }
      if ev[1] == "char" then
        buf = buf .. ev[2]
      elseif ev[1] == "key" and ev[2] == keys.backspace then
        buf = buf:sub(1, -2)
      elseif ev[1] == "key" and (ev[2] == keys.enter or ev[2] == keys.numPadEnter) then
        return buf
      end
      term.setCursorPos(1, h - 1)
      term.write(string.rep(" ", w))
      term.setCursorPos(1, h - 1)
      term.write(question .. buf)
    end
  end

  local function confirm(question)
    local T = api.getTheme()
    term.setCursorPos(1, h - 1)
    term.setBackgroundColor(T.err)
    term.setTextColor(colors.white)
    term.write(string.rep(" ", w))
    term.setCursorPos(1, h - 1)
    term.write(question .. " (Y/N)")
    while true do
      local ev = { api.pullEvent() }
      if ev[1] == "key" then
        if ev[2] == keys.y then return true end
        if ev[2] == keys.n or ev[2] == keys.enter or ev[2] == keys.numPadEnter then return false end
      end
    end
  end

  local function open(idx)
    local e = entries[idx]
    if not e then return end
    if e.name == ".." then
      cwd = fs.getDir(cwd)
      selected, top = 1, 0
      refresh()
      return
    end
    local full = fullPath(idx)
    if e.dir then
      cwd = full
      selected, top = 1, 0
      refresh()
    else
      api.launch("editor", { full })
    end
  end

  refresh()
  draw()
  while true do
    local ev = { api.pullEvent() }
    local kind = ev[1]
    status = ""
    if kind == "mouse_click" then
      local y = ev[4]
      if y >= 2 and y < 2 + listH then
        local idx = top + (y - 2) + 1
        if entries[idx] then
          if idx == selected then open(idx) else selected = idx end
        end
      end
    elseif kind == "key" then
      local k = ev[2]
      if k == keys.down then selected = math.min(#entries, selected + 1)
      elseif k == keys.up then selected = math.max(1, selected - 1)
      elseif k == keys.enter or k == keys.numPadEnter then open(selected)
      elseif k == keys.n then
        local name = prompt("New file name: ")
        if name and #name > 0 then
          local h2 = fs.open(join(cwd, name), "w")
          if h2 then h2.close() end
          refresh()
        end
      elseif k == keys.d then
        local e = entries[selected]
        if e and e.name ~= ".." then
          local what = e.dir and (e.name .. "/ and everything in it") or e.name
          if confirm("Delete " .. what .. "?") then
            fs.delete(fullPath(selected))
            status = "Deleted " .. e.name
            refresh()
          else
            status = "Cancelled"
          end
        end
      elseif k == keys.r then
        local e = entries[selected]
        if e and e.name ~= ".." then
          local newName = prompt("Rename to: ")
          if newName and #newName > 0 then
            fs.move(fullPath(selected), join(cwd, newName))
            refresh()
          end
        end
      end
    elseif kind == "term_resize" then
      refreshSize()
    elseif kind == "os_theme" then
      -- redraw below
    end
    draw()
  end
end

return M
]=])
file("os/apps/notes.lua", [=[
--[[ notes -- a list of sticky text notes, each edited full-screen. ]]

local M = {}
M.id = "notes"
M.name = "Notes"

local PATH = "/os/data/notes.dat"

local function load_()
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

local function save_(notes)
  local h = fs.open(PATH, "w")
  if h then h.write(textutils.serialize(notes)) h.close() end
end

function M.run(ctx)
  local api = ctx.api
  local notes = load_()
  local selected = 1
  local top = 0
  local mode = "list" -- "list" | "edit"
  local w, h, listH
  local function refreshSize()
    w, h = api.getSize()
    listH = h - 3
  end
  refreshSize()

  local function titleOf(n)
    local first = (n.text or ""):match("^[^\n]*") or ""
    if first == "" then return "(empty note)" end
    return first
  end

  local function drawList()
    local T = api.getTheme()
    term.setBackgroundColor(T.bg)
    term.setTextColor(T.fg)
    term.clear()
    term.setCursorPos(1, 1)
    term.setBackgroundColor(T.chrome)
    term.setTextColor(T.chromeText)
    term.write(string.rep(" ", w))
    term.setCursorPos(1, 1)
    term.write(" Notes (" .. #notes .. ")")

    if selected - top > listH then top = selected - listH end
    if selected - top < 1 then top = selected - 1 end
    if top < 0 then top = 0 end

    for row = 0, listH - 1 do
      local idx = top + row + 1
      local y = 2 + row
      local n = notes[idx]
      local bg, fg = T.bg, T.fg
      if n and idx == selected then bg, fg = T.accent, T.chromeFocusText end
      term.setCursorPos(1, y)
      term.setBackgroundColor(bg)
      term.setTextColor(fg)
      term.write(string.rep(" ", w))
      if n then
        term.setCursorPos(2, y)
        local label = titleOf(n)
        if #label > w - 2 then label = label:sub(1, w - 4) .. ".." end
        term.write(label)
      end
    end

    term.setCursorPos(1, h)
    term.setBackgroundColor(T.chrome)
    term.setTextColor(T.chromeText)
    term.write(string.rep(" ", w))
    term.setCursorPos(1, h)
    term.write(" N=new  Enter=open  D=delete")
  end

  local function drawEdit(n)
    local T = api.getTheme()
    term.setBackgroundColor(T.bg)
    term.setTextColor(T.fg)
    term.clear()
    local y = 1
    for line in (n.text .. "\n"):gmatch("([^\n]*)\n") do
      if y > h - 1 then break end
      term.setCursorPos(1, y)
      term.write(line:sub(1, w))
      y = y + 1
    end
    term.setCursorPos(1, h)
    term.setBackgroundColor(T.chrome)
    term.setTextColor(T.chromeText)
    term.write(string.rep(" ", w))
    term.setCursorPos(1, h)
    term.write(" Click here to save and go back")
  end

  local function draw()
    if mode == "list" then drawList() else drawEdit(notes[selected]) end
  end

  draw()
  while true do
    local ev = { api.pullEvent() }
    local kind = ev[1]
    if kind == "term_resize" then
      refreshSize()
    elseif mode == "list" then
      if kind == "key" then
        local k = ev[2]
        if k == keys.down then selected = math.min(#notes, selected + 1)
        elseif k == keys.up then selected = math.max(1, selected - 1)
        elseif k == keys.n then
          notes[#notes + 1] = { text = "" }
          save_(notes)
          selected = #notes
          mode = "edit"
        elseif k == keys.enter or k == keys.numPadEnter then
          if notes[selected] then mode = "edit" end
        elseif k == keys.d then
          if notes[selected] then
            table.remove(notes, selected)
            save_(notes)
          end
        end
      elseif kind == "mouse_click" then
        local y = ev[4]
        if y >= 2 and y < 2 + listH then
          local idx = top + (y - 2) + 1
          if notes[idx] then
            if idx == selected then mode = "edit" else selected = idx end
          end
        end
      end
    else -- edit mode
      local n = notes[selected]
      if kind == "char" then
        n.text = n.text .. ev[2]
        save_(notes)
      elseif kind == "key" then
        local k = ev[2]
        if k == keys.enter or k == keys.numPadEnter then
          n.text = n.text .. "\n"
          save_(notes)
        elseif k == keys.backspace then
          n.text = n.text:sub(1, -2)
          save_(notes)
        end
      elseif kind == "mouse_click" then
        mode = "list"
      end
    end
    draw()
  end
end

return M
]=])
file("os/apps/piano.lua", [=[
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
]=])
file("os/apps/settings.lua", [=[
--[[ settings -- theme, volume, clock format, username, power controls. ]]

local M = {}
M.id = "settings"
M.name = "Settings"

function M.run(ctx)
  local api = ctx.api
  local data = api.getSettings()
  local themes = api.listThemes()

  local volume = data.get("volume") or 7
  local clock24h = data.get("clock24h") and true or false
  local username = data.get("username") or "user"

  local w, h = api.getSize()
  local rows = {} -- populated each draw(): {y=, kind=, ...}
  local function refreshSize() w, h = api.getSize() end

  local function th() return api.getTheme() end

  local function draw()
    local T = th()
    term.setBackgroundColor(T.bg)
    term.setTextColor(T.fg)
    term.clear()
    rows = {}

    term.setCursorPos(2, 1)
    term.setTextColor(T.accent)
    term.write("Theme")

    for i = 1, #themes do
      local t = themes[i]
      local y = 1 + i
      local active = (t.id == data.get("theme"))
      term.setCursorPos(2, y)
      term.setBackgroundColor(T.bg)
      term.setTextColor(t.accent)
      term.write("##")
      term.setTextColor(active and T.accent or T.fg)
      term.setBackgroundColor(T.bg)
      term.write(" " .. t.name .. (active and "  (current)" or ""))
      rows[#rows + 1] = { y = y, kind = "theme", id = t.id }
    end

    local vy = 2 + #themes + 1
    term.setCursorPos(2, vy)
    term.setTextColor(T.fg)
    term.write(string.format("Volume: %2d ", volume))
    term.setTextColor(T.accent)
    term.write("[-][+]")
    rows[#rows + 1] = { y = vy, kind = "volDown", x1 = 2 + 15, x2 = 2 + 17 }
    rows[#rows + 1] = { y = vy, kind = "volUp", x1 = 2 + 18, x2 = 2 + 20 }

    local cy = vy + 1
    term.setCursorPos(2, cy)
    term.setTextColor(T.fg)
    term.write("Clock: " .. (clock24h and "24h" or "12h") .. " ")
    term.setTextColor(T.accent)
    term.write("[toggle]")
    rows[#rows + 1] = { y = cy, kind = "clock", x1 = 2, x2 = w - 1 }

    local uy = cy + 2
    term.setCursorPos(2, uy)
    term.setTextColor(T.fg)
    term.write("Username:")
    term.setCursorPos(2, uy + 1)
    term.setBackgroundColor(T.field)
    term.setTextColor(T.fieldText)
    term.write(" " .. username .. string.rep(" ", math.max(0, w - 4 - #username)))
    rows[#rows + 1] = { y = uy + 1, kind = "username", x1 = 2, x2 = w - 1 }

    local by = h - 1
    term.setCursorPos(2, by)
    term.setBackgroundColor(T.err)
    term.setTextColor(colors.white)
    term.write(" Shut Down ")
    rows[#rows + 1] = { y = by, kind = "shutdown", x1 = 2, x2 = 12 }

    term.setCursorPos(2, by + 1)
    term.setBackgroundColor(T.warn)
    term.setTextColor(colors.black)
    term.write(" Reboot ")
    rows[#rows + 1] = { y = by + 1, kind = "reboot", x1 = 2, x2 = 9 }
  end

  local function hitAt(x, y)
    for i = 1, #rows do
      local r = rows[i]
      if r.y == y then
        if r.kind == "theme" then return r end
        if r.x1 and x >= r.x1 and x <= r.x2 then return r end
      end
    end
    return nil
  end

  draw()
  while true do
    local ev = { api.pullEvent() }
    local kind = ev[1]
    if kind == "mouse_click" then
      local x, y = ev[3], ev[4]
      local hit = hitAt(x, y)
      if hit then
        if hit.kind == "theme" then
          api.setTheme(hit.id)
        elseif hit.kind == "volDown" then
          volume = math.max(0, volume - 1)
          data.set("volume", volume) data.save()
        elseif hit.kind == "volUp" then
          volume = math.min(10, volume + 1)
          data.set("volume", volume) data.save()
        elseif hit.kind == "clock" then
          clock24h = not clock24h
          data.set("clock24h", clock24h) data.save()
        elseif hit.kind == "username" then
          term.setCursorPos(2, hit.y)
          term.setBackgroundColor(th().field)
          term.setTextColor(th().fieldText)
          term.write(" " .. string.rep(" ", w - 3))
          term.setCursorPos(2, hit.y)
          term.write(" ")
          local buf = ""
          while true do
            local e2 = { api.pullEvent() }
            if e2[1] == "char" then
              buf = buf .. e2[2]
            elseif e2[1] == "key" and e2[2] == keys.backspace then
              buf = buf:sub(1, -2)
            elseif e2[1] == "key" and (e2[2] == keys.enter or e2[2] == keys.numPadEnter) then
              break
            elseif e2[1] == "mouse_click" then
              break
            end
            term.setCursorPos(2, hit.y)
            term.write(" " .. buf .. string.rep(" ", math.max(0, w - 4 - #buf)))
          end
          if #buf > 0 then
            username = buf
            data.set("username", username) data.save()
          end
        elseif hit.kind == "shutdown" then
          os.shutdown()
        elseif hit.kind == "reboot" then
          os.reboot()
        end
        draw()
      end
    elseif kind == "os_theme" then
      draw()
    elseif kind == "term_resize" then
      refreshSize()
      draw()
    end
  end
end

return M
]=])
file("os/apps/share.lua", [=[
--[[ share -- send a file to every cc-OS computer in modem range; anything
  sent to us lands in /os/data/received/. ]]

local req = ...
local net = req("lib.net")
local widgets = req("lib.widgets")

local M = {}
M.id = "share"
M.name = "Share"

local RECEIVED_DIR = "/os/data/received"

function M.run(ctx)
  local api = ctx.api
  local w, h = api.getSize()
  local function refreshSize() w, h = api.getSize() end
  local modem, openErr = net.open()
  local field = widgets.newTextField("")
  local log = {}
  local transfers = {}

  local function push(text) log[#log + 1] = text end

  if not modem then
    push("No modem attached: " .. tostring(openErr))
  else
    push("Ready. Received files are saved to " .. RECEIVED_DIR)
  end

  local function draw()
    local T = api.getTheme()
    term.setBackgroundColor(T.bg)
    term.setTextColor(T.fg)
    term.clear()

    term.setCursorPos(2, 1)
    term.setTextColor(T.accent)
    term.write("Send file (path):")
    field:render(2, 2, w - 12, T, true)
    widgets.button(w - 9, 2, 8, "Send", T.ok, colors.black)

    term.setCursorPos(2, 4)
    term.setBackgroundColor(T.bg)
    term.setTextColor(T.fg)
    term.write("Activity:")
    local outH = h - 5
    local first = math.max(1, #log - outH + 1)
    for row = 0, outH - 1 do
      local idx = first + row
      local line = log[idx]
      if line then
        term.setCursorPos(2, 5 + row)
        term.setBackgroundColor(T.bg)
        term.setTextColor(T.fg)
        if #line > w - 2 then line = line:sub(1, w - 2) end
        term.write(line)
      end
    end
  end

  local function sendPath(path)
    if not modem then push("No modem attached.") return end
    if not fs.exists(path) or fs.isDir(path) then
      push("No such file: " .. path)
      return
    end
    local h2 = fs.open(path, "r")
    if not h2 then push("Could not open " .. path) return end
    local content = h2.readAll() or ""
    h2.close()
    net.sendFile(fs.getName(path), content)
    push("Sent " .. fs.getName(path) .. " (" .. #content .. " bytes)")
  end

  draw()
  while true do
    local ev = { api.pullEvent() }
    local kind = ev[1]
    if kind == "char" then
      field:insert(ev[2])
    elseif kind == "key" then
      if ev[2] == keys.enter or ev[2] == keys.numPadEnter then
        sendPath(field.value)
      elseif not field:handleKey(ev[2]) then
        -- ignore other keys
      end
    elseif kind == "mouse_click" then
      local x, y = ev[3], ev[4]
      if y == 2 and x >= w - 9 and x < w - 1 then
        sendPath(field.value)
      end
    elseif kind == "modem_message" then
      local msg = net.parse(ev)
      if msg then
        if msg.t == "file_start" then
          transfers[msg.data.id] = { name = msg.data.name, parts = {} }
          push("Receiving " .. msg.data.name .. " from " .. msg.from .. "...")
        elseif msg.t == "file_chunk" then
          local t = transfers[msg.data.id]
          if t then t.parts[#t.parts + 1] = msg.data.part end
        elseif msg.t == "file_end" then
          local t = transfers[msg.data.id]
          if t then
            local content = table.concat(t.parts)
            if not fs.exists(RECEIVED_DIR) then fs.makeDir(RECEIVED_DIR) end
            local dest = RECEIVED_DIR .. "/" .. t.name
            local h3 = fs.open(dest, "w")
            if h3 then h3.write(content) h3.close() end
            push("Received " .. t.name .. " (" .. #content .. " bytes)")
            api.notify("Received " .. t.name)
            transfers[msg.data.id] = nil
          end
        end
      end
    elseif kind == "term_resize" then
      refreshSize()
    end
    draw()
  end
end

return M
]=])
file("os/apps/snake.lua", [=[
--[[ snake -- classic snake, arrow keys to steer, R to restart after death. ]]

local M = {}
M.id = "snake"
M.name = "Snake"

function M.run(ctx)
  local api = ctx.api
  -- the grid is sized once at launch and deliberately doesn't follow
  -- mid-game resizes: regridding a live snake (and its food) safely is more
  -- trouble than it's worth, so a resize just leaves extra blank border.
  local w, h = api.getSize()
  local gx, gy = w, h - 1 -- playfield size; row 1 is the score bar

  local snake, dir, pending, food, score, over, tickId

  local function place(x, y)
    term.setCursorPos(x, y + 1)
  end

  local function randomFood()
    while true do
      local fx, fy = math.random(1, gx), math.random(1, gy)
      local hit = false
      for i = 1, #snake do
        if snake[i].x == fx and snake[i].y == fy then hit = true break end
      end
      if not hit then return { x = fx, y = fy } end
    end
  end

  local function reset()
    local cx, cy = math.ceil(gx / 2), math.ceil(gy / 2)
    snake = { { x = cx, y = cy }, { x = cx - 1, y = cy }, { x = cx - 2, y = cy } }
    dir = { x = 1, y = 0 }
    pending = dir
    score = 0
    over = false
    food = randomFood()
    tickId = os.startTimer(0.3)
  end

  local function draw()
    local T = api.getTheme()
    term.setBackgroundColor(T.bg)
    term.setTextColor(T.fg)
    term.clear()
    term.setCursorPos(2, 1)
    term.write("Score: " .. score .. (over and "   GAME OVER - press R" or ""))

    term.setBackgroundColor(T.ok)
    for i = 1, #snake do
      place(snake[i].x, snake[i].y)
      term.write(" ")
    end
    term.setBackgroundColor(T.err)
    place(food.x, food.y)
    term.write(" ")
  end

  local function step()
    if over then return end
    dir = pending
    local head = snake[1]
    local nx, ny = head.x + dir.x, head.y + dir.y
    if nx < 1 then nx = gx elseif nx > gx then nx = 1 end
    if ny < 1 then ny = gy elseif ny > gy then ny = 1 end

    for i = 1, #snake do
      if snake[i].x == nx and snake[i].y == ny then over = true return end
    end

    table.insert(snake, 1, { x = nx, y = ny })
    if nx == food.x and ny == food.y then
      score = score + 1
      food = randomFood()
    else
      table.remove(snake)
    end
    tickId = os.startTimer(math.max(0.08, 0.3 - score * 0.01))
  end

  reset()
  draw()
  while true do
    local ev = { api.pullEvent() }
    local kind = ev[1]
    if kind == "timer" and ev[2] == tickId then
      step()
    elseif kind == "key" then
      local k = ev[2]
      if k == keys.up and dir.y == 0 then pending = { x = 0, y = -1 }
      elseif k == keys.down and dir.y == 0 then pending = { x = 0, y = 1 }
      elseif k == keys.left and dir.x == 0 then pending = { x = -1, y = 0 }
      elseif k == keys.right and dir.x == 0 then pending = { x = 1, y = 0 }
      elseif k == keys.r and over then reset()
      end
    end
    draw()
  end
end

return M
]=])
file("os/apps/terminal.lua", [=[
--[[ terminal -- a small self-contained shell: cd, ls, mkdir, rm, cp, mv, cat,
  echo, clear, help, run, exit. `run <file>` (or a bare command that resolves
  to a .lua file) loads and executes the program directly, so its own
  print()/term output lands right in the terminal window.
]]

local M = {}
M.id = "terminal"
M.name = "Terminal"

local function resolve(cwd, p)
  if p:sub(1, 1) == "/" then return p:sub(2) end
  if cwd == "" then return p end
  return cwd .. "/" .. p
end

local function split(s)
  local parts = {}
  for w in s:gmatch("%S+") do parts[#parts + 1] = w end
  return parts
end

function M.run(ctx)
  local api = ctx.api
  local cwd = ""
  local out = {}
  local input = ""
  local history = {}
  local histPos = 0

  local w, h, outH
  local function refreshSize()
    w, h = api.getSize()
    outH = h - 1
  end
  refreshSize()

  local function log(text)
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
      out[#out + 1] = line
    end
  end

  local function draw()
    local T = api.getTheme()
    term.setBackgroundColor(T.bg)
    term.setTextColor(T.fg)
    term.clear()
    local first = math.max(1, #out - outH + 1)
    for row = 0, outH - 1 do
      local idx = first + row
      if out[idx] then
        term.setCursorPos(1, row + 1)
        local line = out[idx]
        if #line > w then line = line:sub(1, w) end
        term.write(line)
      end
    end
    term.setCursorPos(1, h)
    term.setBackgroundColor(T.chrome)
    term.setTextColor(T.chromeText)
    term.write(string.rep(" ", w))
    term.setCursorPos(1, h)
    local prompt = "/" .. cwd .. "> "
    local visible = prompt .. input
    if #visible > w then visible = visible:sub(#visible - w + 1) end
    term.write(visible)
    term.setCursorPos(math.min(w, #visible + 1), h)
    term.setCursorBlink(true)
  end

  local function cmdLs(args)
    local dir = args[1] and resolve(cwd, args[1]) or cwd
    if not fs.exists(dir == "" and "/" or dir) then log("No such directory") return end
    local names = fs.list(dir)
    table.sort(names)
    if #names == 0 then log("(empty)") return end
    for i = 1, #names do
      local full = (dir == "" and names[i]) or (dir .. "/" .. names[i])
      log(names[i] .. (fs.isDir(full) and "/" or ""))
    end
  end

  local function cmdCd(args)
    local target = args[1]
    if not target or target == "~" then cwd = "" return end
    if target == ".." then cwd = fs.getDir(cwd) return end
    local dest = resolve(cwd, target)
    if fs.exists(dest) and fs.isDir(dest) then cwd = dest else log("No such directory: " .. target) end
  end

  local function cmdRun(args)
    local name = args[1]
    if not name then log("usage: run <file> [args]") return end
    local path = resolve(cwd, name)
    if not fs.exists(path) and fs.exists(path .. ".lua") then path = path .. ".lua" end
    if not fs.exists(path) or fs.isDir(path) then log(name .. ": not found") return end
    local rest = {}
    for i = 2, #args do rest[#rest + 1] = args[i] end
    local chunk, err = loadfile(path)
    if not chunk then log("error: " .. tostring(err)) return end
    local ok, runErr = pcall(chunk, table.unpack(rest))
    if not ok then log("error: " .. tostring(runErr)) end
  end

  local BUILTINS = {
    help = function() log("cd ls pwd mkdir rm cp mv cat echo clear run exit") end,
    ["?"] = function() log("cd ls pwd mkdir rm cp mv cat echo clear run exit") end,
    ls = cmdLs, dir = cmdLs,
    cd = cmdCd,
    pwd = function() log("/" .. cwd) end,
    mkdir = function(a) if a[1] then fs.makeDir(resolve(cwd, a[1])) else log("usage: mkdir <name>") end end,
    rm = function(a) if a[1] then fs.delete(resolve(cwd, a[1])) else log("usage: rm <name>") end end,
    del = function(a) if a[1] then fs.delete(resolve(cwd, a[1])) else log("usage: rm <name>") end end,
    cp = function(a) if a[1] and a[2] then fs.copy(resolve(cwd, a[1]), resolve(cwd, a[2])) else log("usage: cp <src> <dst>") end end,
    mv = function(a) if a[1] and a[2] then fs.move(resolve(cwd, a[1]), resolve(cwd, a[2])) else log("usage: mv <src> <dst>") end end,
    cat = function(a)
      if not a[1] then log("usage: cat <file>") return end
      local p = resolve(cwd, a[1])
      if not fs.exists(p) or fs.isDir(p) then log("No such file: " .. a[1]) return end
      local fh = fs.open(p, "r")
      if fh then log(fh.readAll() or "") fh.close() end
    end,
    echo = function(a) log(table.concat(a, " ")) end,
    clear = function() out = {} end,
    cls = function() out = {} end,
    run = cmdRun,
    exit = function() api.exit() end,
  }

  local function execute(line)
    log("/" .. cwd .. "> " .. line)
    local args = split(line)
    if #args == 0 then return end
    local cmd = table.remove(args, 1)
    local fn = BUILTINS[cmd]
    if fn then
      local ok, err = pcall(fn, args)
      if not ok then log("error: " .. tostring(err)) end
    else
      cmdRun({ cmd, table.unpack(args) })
    end
  end

  log("cc-OS terminal. Type 'help' for commands.")
  draw()
  while true do
    local ev = { api.pullEvent() }
    local kind = ev[1]
    if kind == "char" then
      input = input .. ev[2]
    elseif kind == "key" then
      local k = ev[2]
      if k == keys.backspace then
        input = input:sub(1, -2)
      elseif k == keys.enter or k == keys.numPadEnter then
        if #input > 0 then
          history[#history + 1] = input
          histPos = #history + 1
          execute(input)
        end
        input = ""
      elseif k == keys.up then
        if histPos > 1 then histPos = histPos - 1 input = history[histPos] or "" end
      elseif k == keys.down then
        if histPos < #history then
          histPos = histPos + 1
          input = history[histPos] or ""
        else
          histPos = #history + 1
          input = ""
        end
      end
    elseif kind == "mouse_scroll" then
      -- no-op: scrollback always shows the tail; nothing to scroll to yet
    elseif kind == "term_resize" then
      refreshSize()
    end
    draw()
  end
end

return M
]=])
file("os/boot.lua", [=[
--[[ cc-OS boot loader -- sets up the module loader and hands off to the kernel. ]]

local BASE = "/os"

local function makeLoader(base)
  local cache = {}
  local loading = {}
  local req
  req = function(name)
    local hit = cache[name]
    if hit ~= nil then return hit end
    if loading[name] then error("circular require: " .. name, 0) end
    local path = base .. "/" .. (name:gsub("%.", "/")) .. ".lua"
    local chunk, err = loadfile(path)
    if not chunk then error("module not found: " .. name .. " (" .. tostring(err) .. ")", 0) end
    loading[name] = true
    local mod = chunk(req, name)
    loading[name] = nil
    if mod == nil then mod = true end
    cache[name] = mod
    return mod
  end
  return req
end

local req = makeLoader(BASE)

local prevTerm = term.current()
local ok, err = pcall(function()
  local kernel = req("kernel")
  kernel.run()
end)

term.redirect(prevTerm)
term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
term.setCursorPos(1, 1)

if not ok then
  printError("cc-OS stopped: " .. tostring(err))
else
  print("cc-OS shut down.")
end
]=])
file("os/kernel.lua", [=[
--[[ kernel -- the windowing multitasking core of cc-OS.

  Apps are plain Lua modules with a `run(ctx)` function. Each runs inside its
  own coroutine, hosted in its own `window.create`d rectangle. The kernel is
  the only thing that ever calls `coroutine.resume`; apps get events by
  calling `ctx.api.pullEvent(filter)`, which is a thin wrapper around
  `coroutine.yield` -- NOT `os.pullEvent`, so app code never fights the
  kernel for the raw event stream. `term`, `colors`, `fs`, `peripheral` etc.
  are used directly by apps: `term` is redirected to an app's window for the
  whole duration of its turn (every line of app code that runs between two
  `pullEvent` calls), so plain `term.write` / `print` just work.

  A window can be resized (drag the bottom-right corner) or maximized (the
  `[o]` titlebar button, or a context-menu item); either way the app is sent
  a `term_resize` event and is expected to re-read `ctx.api.getSize()` and
  redraw -- every bundled app does this.
]]

local req = ...
local theme = req("lib.theme")
local widgets = req("lib.widgets")
local data = req("lib.data")
local appsReg = req("lib.apps")
local sound = req("lib.sound")
local Canvas = req("lib.canvas")
local icons = req("lib.icons")
local font = req("lib.font")

local kernel = {}
local MIN_W, MIN_H = 18, 7

--- opts is optional and only used by the test harness:
---   opts.maxEvents -- return after this many events instead of looping forever
---   opts.onEvent(ev) -- called after each event is fully handled and redrawn
---   opts.noSession -- skip restoring/saving the previous session (cleaner tests)
function kernel.run(opts)
  opts = opts or {}
  local native = term.native()
  term.redirect(native)
  local screenW, screenH = native.getSize()

  if not native.isColor() or screenW < 30 or screenH < 10 then
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)
    print("cc-OS needs an Advanced Computer")
    print("(a colour screen at least 30x10).")
    print("")
    print("This computer is " .. screenW .. "x" .. screenH ..
      (native.isColor() and "" or ", not colour") .. ".")
    return
  end

  local desktopH = screenH - 1 -- last row is the taskbar

  local currentTheme = theme.byId(data.get("theme"))

  local procs = {}       -- z-ordered, index 1 = back, last = front
  local nextId = 1
  local focusedId = nil
  local mouseCapture = nil  -- proc id currently owning a mouse drag
  local dragState = nil     -- {id, offX, offY} while moving a window by its titlebar
  local resizeState = nil   -- {id, startW, startH, startX, startY} while resizing

  local startMenuOpen = false
  local menuRect, menuItems = nil, {}
  local startBtnRect, taskbarButtons = nil, {}

  local ctxMenu = nil -- {x, y, w, items = {{label, action}}}

  local currentNotification, notifyTimerId = nil, nil
  local altHeld = false

  --------------------------------------------------------------- desktop icons
  -- each slot is 9 cols wide (a 4-cell/8px icon plus padding) and 4 rows tall
  -- (3 cell rows of icon, 1 text row of label underneath)
  local deskIcons = {}
  do
    local perCol = math.max(1, math.floor(desktopH / 4))
    for i = 1, #appsReg.list do
      local a = appsReg.list[i]
      local col = math.floor((i - 1) / perCol)
      local row = (i - 1) % perCol
      deskIcons[#deskIcons + 1] = { appId = a.id, name = a.name,
        x = 1 + col * 9, y = 1 + row * 4 }
    end
  end
  local lastIconClick = { appId = nil, t = -10 }

  ------------------------------------------------------------- forward decls
  local focus, closeProc, minimizeProc, launch, resumeProc, makeApi, notify
  local drawChrome, drawTaskbar, drawStartMenu, drawNotification, drawIcons, redrawFrame
  local procAt, findProc, handleMouseClick, handleMouseDrag, handleMouseUp
  local setRect, toggleMaximize, saveSession, openContextMenu, closeContextMenu

  --------------------------------------------------------------- bookkeeping
  function findProc(id)
    for i = 1, #procs do if procs[i].id == id then return procs[i], i end end
    return nil
  end

  function procAt(x, y)
    for i = #procs, 1, -1 do
      local p = procs[i]
      if not p.minimized then
        if x >= p.x and x < p.x + p.w and y >= p.y and y < p.y + p.h then return p end
      end
    end
    return nil
  end

  function focus(id)
    local p, idx = findProc(id)
    if not p or p.minimized then return end
    table.remove(procs, idx)
    procs[#procs + 1] = p
    focusedId = id
  end

  local function pickNewFocus()
    for i = #procs, 1, -1 do
      if not procs[i].minimized then return procs[i].id end
    end
    return nil
  end

  function closeProc(p)
    sound.play("close")
    local _, idx = findProc(p.id)
    if idx then table.remove(procs, idx) end
    if focusedId == p.id then focusedId = pickNewFocus() end
    saveSession()
  end

  function minimizeProc(p)
    sound.play("minimize")
    p.minimized = true
    if focusedId == p.id then focusedId = pickNewFocus() end
  end

  ------------------------------------------------------------------- events
  notify = function(msg, isError)
    currentNotification = tostring(msg)
    notifyTimerId = os.startTimer(2.5)
    sound.play(isError and "error" or "notify")
  end

  --- Applies a new outer rect to a window (used by resize, maximize, snap).
  --- Sends the app a term_resize event so it can redraw at the new size.
  function setRect(p, x, y, w, h)
    x = math.max(1, math.min(x, screenW - w + 1))
    y = math.max(1, math.min(y, desktopH - h + 1))
    w = math.max(MIN_W, math.min(w, screenW))
    h = math.max(MIN_H, math.min(h, desktopH))
    p.x, p.y, p.w, p.h = x, y, w, h
    p.win.reposition(x + 1, y + 1, w - 2, h - 2)
    resumeProc(p, { "term_resize" })
  end

  function toggleMaximize(p)
    if p.maximized then
      p.maximized = false
      local r = p.preRestore
      if r then setRect(p, r.x, r.y, r.w, r.h) end
    else
      p.preRestore = { x = p.x, y = p.y, w = p.w, h = p.h }
      p.maximized = true
      setRect(p, 1, 1, screenW, desktopH)
    end
    saveSession()
  end

  local function snap(p, side)
    if not p.maximized then p.preRestore = { x = p.x, y = p.y, w = p.w, h = p.h } end
    p.maximized = false
    local half = math.floor(screenW / 2)
    if side == "left" then setRect(p, 1, 1, half, desktopH)
    else setRect(p, half + 1, 1, screenW - half, desktopH) end
    saveSession()
  end

  ------------------------------------------------------------- context menus
  function closeContextMenu() ctxMenu = nil end

  function openContextMenu(x, y, items)
    local w = 14
    for i = 1, #items do w = math.max(w, #items[i].label + 3) end
    local h = #items
    x = math.min(x, screenW - w)
    y = math.min(y, screenH - h)
    ctxMenu = { x = math.max(1, x), y = math.max(1, y), w = w, items = items }
  end

  local function titlebarMenuItems(p)
    return {
      { label = "Minimize", action = function() minimizeProc(p) end },
      { label = p.maximized and "Restore" or "Maximize", action = function() toggleMaximize(p) end },
      { label = "Snap Left", action = function() snap(p, "left") end },
      { label = "Snap Right", action = function() snap(p, "right") end },
      { label = "Close", action = function() closeProc(p) end },
    }
  end

  local function desktopMenuItems()
    return {
      { label = "Open Terminal", action = function() launch("terminal") end },
      { label = "Open Files", action = function() launch("files") end },
      { label = "Open Settings", action = function() launch("settings") end },
      { label = "Refresh", action = function() end },
    }
  end

  ------------------------------------------------------------------ session
  function saveSession()
    if opts.noSession then return end
    local out = {}
    for i = 1, #procs do
      local p = procs[i]
      if not p.crashed then
        out[#out + 1] = { appId = p.appId, args = p.args, x = p.x, y = p.y, w = p.w, h = p.h, minimized = p.minimized }
      end
    end
    data.set("session", out)
    data.save()
  end

  ------------------------------------------------------------------- api
  function makeApi(proc)
    local api = {}
    function api.pullEvent(filter)
      while true do
        local ev = { coroutine.yield(filter) }
        if filter == nil or ev[1] == filter then return table.unpack(ev) end
      end
    end
    api.pullEventRaw = api.pullEvent
    function api.sleep(t)
      local id = os.startTimer(t or 0)
      while true do
        local _, tid = api.pullEvent("timer")
        if tid == id then return end
      end
    end
    function api.exit() error("__APP_EXIT__", 0) end
    function api.setTitle(t) proc.title = tostring(t) end
    function api.notify(msg, isError) notify(msg, isError) end
    function api.getTheme() return currentTheme end
    function api.getSize() return proc.win.getSize() end
    function api.listThemes() return theme.list() end
    function api.setTheme(id)
      currentTheme = theme.byId(id)
      data.set("theme", id)
      data.save()
      os.queueEvent("os_theme")
    end
    function api.launch(appId, args) return launch(appId, args) end
    function api.getSettings() return data end
    function api.sound(name) sound.play(name) end
    return api
  end

  function launch(appId, args, savedRect)
    local def = appsReg.byId(appId)
    if not def then notify("No such app: " .. tostring(appId), true) return nil end
    local ok, mod = pcall(req, def.module)
    if not ok or type(mod) ~= "table" or type(mod.run) ~= "function" then
      notify("Could not load " .. def.name, true)
      return nil
    end
    local w, h, x, y
    if savedRect then
      w, h, x, y = savedRect.w, savedRect.h, savedRect.x, savedRect.y
    else
      w = math.min(def.width or 40, screenW - 2)
      h = math.min(def.height or 15, desktopH - 1)
      x = math.random(1, math.max(1, screenW - w + 1))
      y = math.random(1, math.max(1, desktopH - h + 1))
    end
    w = math.max(MIN_W, math.min(w, screenW))
    h = math.max(MIN_H, math.min(h, desktopH))
    x = math.max(1, math.min(x, screenW - w + 1))
    y = math.max(1, math.min(y, desktopH - h + 1))

    local win = window.create(native, x + 1, y + 1, w - 2, h - 2, true)
    win.setBackgroundColor(currentTheme.bg)
    win.setTextColor(currentTheme.fg)
    win.clear()
    win.setCursorPos(1, 1)

    local proc = {
      id = nextId, appId = appId, title = def.name, args = args or {},
      x = x, y = y, w = w, h = h, win = win, minimized = false,
    }
    nextId = nextId + 1

    local ctx = { api = makeApi(proc), args = args or {}, win = win }
    proc.co = coroutine.create(function()
      local ok2, err = pcall(mod.run, ctx)
      if not ok2 and err ~= "__APP_EXIT__" then
        proc.crashError = tostring(err)
        proc.crashed = true
      end
    end)

    procs[#procs + 1] = proc
    resumeProc(proc, {})
    if not proc.dead then focus(proc.id) end
    sound.play("open")
    saveSession()
    return proc
  end

  local function renderCrash(p)
    term.redirect(p.win)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.red)
    term.clear()
    local w = select(1, p.win.getSize())
    term.setCursorPos(2, 1)
    term.write("This app crashed.")
    term.setTextColor(colors.white)
    local msg = tostring(p.crashError or "unknown error")
    local y = 3
    local line = ""
    for word in (msg .. " "):gmatch("(%S+) ") do
      if #line + #word + 1 > w - 2 then
        term.setCursorPos(2, y)
        term.write(line)
        line = word
        y = y + 1
      else
        line = (line == "" and word or (line .. " " .. word))
      end
    end
    if line ~= "" then term.setCursorPos(2, y) term.write(line) end
    term.redirect(native)
    sound.play("error")
  end

  function resumeProc(proc, eventArgs)
    if proc.dead then return end
    term.redirect(proc.win)
    local ok, err = pcall(coroutine.resume, proc.co, table.unpack(eventArgs or {}))
    term.redirect(native)
    if not ok then
      proc.dead = true
      proc.crashError = tostring(err)
      proc.crashed = true
      renderCrash(proc)
    elseif coroutine.status(proc.co) == "dead" then
      proc.dead = true
      if proc.crashed then renderCrash(proc) end
    end
  end

  --------------------------------------------------------------- rendering
  local function titleBounds(p)
    return {
      minX = p.x + p.w - 9, minEnd = p.x + p.w - 7,
      maxX = p.x + p.w - 6, maxEnd = p.x + p.w - 4,
      closeX = p.x + p.w - 3, closeEnd = p.x + p.w - 1,
    }
  end

  function drawChrome(p)
    local th = currentTheme
    local focused = (p.id == focusedId)
    local barBg = focused and th.chromeFocus or th.chrome
    local barFg = focused and th.chromeFocusText or th.chromeText
    term.setBackgroundColor(barBg)
    term.setTextColor(barFg)
    term.setCursorPos(p.x, p.y)
    term.write(string.rep(" ", p.w))
    term.setBackgroundColor(icons.COLOR[p.appId] or barBg)
    term.setCursorPos(p.x + 1, p.y)
    term.write(" ")
    term.setBackgroundColor(barBg)
    local titleW = p.w - 14
    if titleW > 0 then
      term.setCursorPos(p.x + 3, p.y)
      local title = (p.crashed and "[!] " or "") .. p.title
      term.write(widgets.clip(title, titleW))
    end
    term.setCursorPos(p.x + p.w - 9, p.y)
    term.write("[_][o][x]")
    if not p.crashed then
      term.setBackgroundColor(th.bg)
      term.setTextColor(th.fg)
    end
    for row = p.y + 1, p.y + p.h - 2 do
      term.setCursorPos(p.x, row)
      term.write("|")
      term.setCursorPos(p.x + p.w - 1, row)
      term.write("|")
    end
    term.setCursorPos(p.x, p.y + p.h - 1)
    term.write("+" .. string.rep("-", p.w - 2) .. "+")
    if not p.maximized then
      term.setCursorPos(p.x + p.w - 1, p.y + p.h - 1)
      term.setTextColor(th.accent)
      term.write(string.char(92)) -- resize handle, a literal backslash
    end
  end

  function drawIcons()
    local th = currentTheme
    term.setBackgroundColor(th.desktop)
    for i = 1, #deskIcons do
      local ic = deskIcons[i]
      local c = Canvas.new(ic.x, ic.y, icons.CELLS.w, icons.CELLS.h, th.desktop)
      icons.draw(c, ic.appId, 1, 1)
      c:render()
      term.setBackgroundColor(th.desktop)
      term.setTextColor(th.desktopText)
      term.setCursorPos(ic.x, ic.y + icons.CELLS.h)
      term.write(widgets.clip(ic.name, 8))
    end
  end

  function drawTaskbar()
    local th = currentTheme
    term.setBackgroundColor(th.taskbar)
    term.setTextColor(th.taskbarText)
    term.setCursorPos(1, screenH)
    term.write(string.rep(" ", screenW))

    term.setBackgroundColor(startMenuOpen and th.accent or th.taskbarActive)
    term.setTextColor(startMenuOpen and th.chromeFocusText or th.taskbarActiveText)
    term.setCursorPos(1, screenH)
    term.write(" Start ")
    startBtnRect = { x = 1, y = screenH, w = 7, h = 1 }

    taskbarButtons = {}
    local cx = 9
    for i = 1, #procs do
      local p = procs[i]
      local label = " " .. widgets.clip(p.title, 8) .. " "
      local w = #label + 1 -- +1 for the leading colour swatch
      if cx + w > screenW - 7 then break end
      local isFocused = (p.id == focusedId) and not p.minimized
      local barBg = isFocused and th.taskbarActive or th.taskbar
      term.setBackgroundColor(icons.COLOR[p.appId] or barBg)
      term.setCursorPos(cx, screenH)
      term.write(" ")
      term.setBackgroundColor(barBg)
      term.setTextColor(p.crashed and th.err or (isFocused and th.taskbarActiveText or th.taskbarText))
      term.setCursorPos(cx + 1, screenH)
      term.write(label)
      taskbarButtons[#taskbarButtons + 1] = { procId = p.id, x = cx, w = w }
      cx = cx + w + 1
    end

    local clockStr = textutils.formatTime(os.time(), data.get("clock24h"))
    term.setBackgroundColor(th.taskbar)
    term.setTextColor(th.taskbarText)
    term.setCursorPos(screenW - #clockStr, screenH)
    term.write(clockStr)
  end

  local function drawPopup(x, y, w, rows, highlight)
    -- rows: list of display strings; used by both the Start menu and context menus
    local th = currentTheme
    for i = 1, #rows do
      local row = y + i - 1
      term.setBackgroundColor((highlight == i) and th.accent or th.chrome)
      term.setTextColor((highlight == i) and th.chromeFocusText or th.chromeText)
      term.setCursorPos(x, row)
      term.write(widgets.clip(" " .. rows[i], w))
    end
  end

  -- a 4-column icon grid, each cell 9 cols wide (icon + padding) x 4 rows
  -- tall (3 rows of icon, 1 row of label) -- the same visual language as
  -- the desktop icons, so the Start menu reads as "more of the same app
  -- launcher" rather than a different, plainer UI bolted on.
  local MENU_COLS = 4
  function drawStartMenu()
    if not startMenuOpen then return end
    local th = currentTheme
    local list = appsReg.list
    local w = MENU_COLS * 9
    local x, y = 1, 1
    -- the panel covers the full desktop height so it fully occludes
    -- whatever desktop icons are behind it, not just the grid's own rows
    menuRect = { x = x, y = y, w = w, h = desktopH }
    menuItems = {}
    widgets.fill(x, y, w, desktopH, th.chrome)
    for i = 1, #list do
      local a = list[i]
      local col = (i - 1) % MENU_COLS
      local row = math.floor((i - 1) / MENU_COLS)
      local cx, cy = x + col * 9, y + row * 4
      local c = Canvas.new(cx, cy, icons.CELLS.w, icons.CELLS.h, th.chrome)
      icons.draw(c, a.id, 1, 1)
      c:render()
      term.setBackgroundColor(th.chrome)
      term.setTextColor(th.chromeText)
      term.setCursorPos(cx, cy + icons.CELLS.h)
      term.write(widgets.clip(a.name, 8))
      menuItems[#menuItems + 1] = { x = cx, y = cy, w = 9, h = 4, appId = a.id }
    end
  end

  local function drawContextMenu()
    if not ctxMenu then return end
    local rows = {}
    for i = 1, #ctxMenu.items do rows[i] = ctxMenu.items[i].label end
    drawPopup(ctxMenu.x, ctxMenu.y, ctxMenu.w, rows)
  end

  function drawNotification()
    if not currentNotification then return end
    local th = currentTheme
    local w = math.min(#currentNotification + 2, screenW - 2)
    local x = screenW - w
    local y = 1
    term.setBackgroundColor(th.accent)
    term.setTextColor(th.chromeFocusText)
    term.setCursorPos(x, y)
    term.write(widgets.clip(" " .. currentNotification, w))
  end

  function redrawFrame()
    term.redirect(native)
    local th = currentTheme
    widgets.fill(1, 1, screenW, desktopH, th.desktop)
    drawIcons()
    for i = 1, #procs do
      local p = procs[i]
      if not p.minimized then
        drawChrome(p)
        p.win.redraw()
      end
    end
    drawTaskbar()
    drawStartMenu()
    drawContextMenu()
    drawNotification()
  end

  ------------------------------------------------------------------- input
  local function forwardToClient(p, x, y, eventName, extra)
    local lx, ly = x - p.x, y - p.y
    resumeProc(p, { eventName, extra, lx, ly })
  end

  local function iconAt(x, y)
    for i = 1, #deskIcons do
      local ic = deskIcons[i]
      if x >= ic.x and x < ic.x + 8 and y >= ic.y and y < ic.y + 4 then return ic end
    end
    return nil
  end

  local function handlePopupClick(btn, x, y)
    -- returns true if the click was consumed by the Start menu / a context menu
    if startMenuOpen then
      startMenuOpen = false
      if widgets.hit(menuRect, x, y) then
        for i = 1, #menuItems do
          if widgets.hit(menuItems[i], x, y) then launch(menuItems[i].appId) break end
        end
      end
      return true
    end
    if ctxMenu then
      local hit = x >= ctxMenu.x and x < ctxMenu.x + ctxMenu.w and y >= ctxMenu.y and y < ctxMenu.y + #ctxMenu.items
      if hit then
        local idx = y - ctxMenu.y + 1
        local item = ctxMenu.items[idx]
        closeContextMenu()
        if item then item.action() end
        return true
      end
      closeContextMenu()
      -- a right-click that lands outside the menu closes it but falls
      -- through to the normal right-click handling below, so right-clicking
      -- somewhere new re-opens a menu there in one click instead of needing
      -- a dismiss click followed by a second right-click
      return btn ~= 2
    end
    return false
  end

  function handleMouseClick(btn, x, y)
    if handlePopupClick(btn, x, y) then return end

    if btn == 2 then -- right click
      if y == screenH then return end
      local p = procAt(x, y)
      if p and y == p.y then
        openContextMenu(x, y, titlebarMenuItems(p))
      elseif not p then
        openContextMenu(x, y, desktopMenuItems())
      end
      return
    end

    if y == screenH then
      if widgets.hit(startBtnRect, x, y) then
        startMenuOpen = true
        return
      end
      for i = 1, #taskbarButtons do
        local tb = taskbarButtons[i]
        if x >= tb.x and x < tb.x + tb.w then
          local p = findProc(tb.procId)
          if p then
            if p.minimized then
              p.minimized = false
              focus(p.id)
            elseif p.id == focusedId then
              minimizeProc(p)
            else
              focus(p.id)
            end
          end
          return
        end
      end
      return
    end

    local p = procAt(x, y)
    if not p then
      local ic = iconAt(x, y)
      if ic then
        local now = os.clock()
        if lastIconClick.appId == ic.appId and now - lastIconClick.t < 0.5 then
          launch(ic.appId)
          lastIconClick.t = -10
        else
          lastIconClick = { appId = ic.appId, t = now }
        end
      end
      return
    end
    focus(p.id)

    if y == p.y then
      local tb = titleBounds(p)
      if x >= tb.minX and x <= tb.minEnd then minimizeProc(p) return end
      if x >= tb.maxX and x <= tb.maxEnd then toggleMaximize(p) return end
      if x >= tb.closeX and x <= tb.closeEnd then closeProc(p) return end
      dragState = { id = p.id, offX = x - p.x, offY = y - p.y }
      return
    end

    if not p.maximized and x == p.x + p.w - 1 and y == p.y + p.h - 1 then
      resizeState = { id = p.id, startW = p.w, startH = p.h, startX = x, startY = y }
      return
    end

    if x == p.x or x == p.x + p.w - 1 or y == p.y + p.h - 1 then
      return -- border, not clickable
    end

    mouseCapture = p.id
    forwardToClient(p, x, y, "mouse_click", btn)
  end

  function handleMouseDrag(btn, x, y)
    if resizeState then
      local p = findProc(resizeState.id)
      if p then
        local nw = resizeState.startW + (x - resizeState.startX)
        local nh = resizeState.startH + (y - resizeState.startY)
        setRect(p, p.x, p.y, nw, nh)
      end
      return
    end
    if dragState then
      local p = findProc(dragState.id)
      if p then
        local nx = math.max(1, math.min(x - dragState.offX, screenW - p.w + 1))
        local ny = math.max(1, math.min(y - dragState.offY, desktopH - p.h + 1))
        p.x, p.y = nx, ny
        p.win.reposition(nx + 1, ny + 1)
      end
      return
    end
    if mouseCapture then
      local p = findProc(mouseCapture)
      if p then forwardToClient(p, x, y, "mouse_drag", btn) end
    end
  end

  function handleMouseUp(btn, x, y)
    if resizeState then
      resizeState = nil
      saveSession()
      return
    end
    if dragState then
      dragState = nil
      saveSession()
      return
    end
    if mouseCapture then
      local p = findProc(mouseCapture)
      mouseCapture = nil
      if p then forwardToClient(p, x, y, "mouse_up", btn) end
    end
  end

  local function handleMouseScroll(dir, x, y)
    local p = procAt(x, y)
    if not p then return end
    if x == p.x or x == p.x + p.w - 1 or y == p.y or y == p.y + p.h - 1 then return end
    forwardToClient(p, x, y, "mouse_scroll", dir)
  end

  --------------------------------------------------------- test introspection
  local function debugState()
    local out = {}
    for i = 1, #procs do
      local p = procs[i]
      out[i] = { id = p.id, appId = p.appId, title = p.title, x = p.x, y = p.y, w = p.w, h = p.h,
        minimized = p.minimized, maximized = p.maximized, crashed = p.crashed }
    end
    local menus = { startMenuOpen = startMenuOpen, ctxMenuOpen = ctxMenu ~= nil }
    if ctxMenu then
      menus.ctxMenuLabels = {}
      for i = 1, #ctxMenu.items do menus.ctxMenuLabels[i] = ctxMenu.items[i].label end
    end
    return out, focusedId, menus
  end

  ------------------------------------------------------------------ reaping
  local function reap()
    local i = 1
    while i <= #procs do
      local p = procs[i]
      if p.dead and not p.crashed then
        table.remove(procs, i)
        if focusedId == p.id then focusedId = pickNewFocus() end
      else
        i = i + 1
      end
    end
  end

  ------------------------------------------------------------- kernel API
  kernel.launch = launch
  kernel.getTheme = function() return currentTheme end
  kernel.setTheme = function(id)
    currentTheme = theme.byId(id)
    data.set("theme", id)
    data.save()
    os.queueEvent("os_theme")
  end
  kernel.notify = notify

  ------------------------------------------------------------- boot splash
  local function bootSplash()
    if opts.skipSplash then return end
    local full = Canvas.new(1, 1, screenW, screenH, colors.black)
    local midY = math.floor(full.h / 2)
    font.centerShadow(full, midY - 9, "CC-OS", colors.cyan, colors.gray, 2, 2)
    font.center(full, midY + 8, "STARTING UP", colors.lightGray, 1, 1)
    full:render()
    sound.play("boot")
    os.sleep(opts.splashSeconds or 0.6)
  end

  ------------------------------------------------------------ session restore
  local function restoreSession()
    if opts.noSession then return end
    local saved = data.get("session")
    if type(saved) ~= "table" then return end
    for i = 1, #saved do
      local s = saved[i]
      if type(s) == "table" and s.appId then
        local p = launch(s.appId, s.args, { x = s.x, y = s.y, w = s.w, h = s.h })
        if p and s.minimized then minimizeProc(p) end
      end
    end
  end

  ---------------------------------------------------------------- main loop
  bootSplash()
  restoreSession()
  redrawFrame()
  local eventCount = 0
  local tickId = os.startTimer(2)
  while true do
    local ev = { os.pullEventRaw() }
    local kind = ev[1]

    if kind == "timer" and ev[2] == tickId then
      -- periodic wake-up so the taskbar clock (and any app's own clock)
      -- stays live even when nobody is clicking or typing
      tickId = os.startTimer(2)
      for i = 1, #procs do
        if not procs[i].dead then resumeProc(procs[i], ev) end
      end
    elseif kind == "terminate" then
      local id = focusedId
      if id then
        local p = findProc(id)
        if p then closeProc(p) end
      end
    elseif kind == "mouse_click" then
      handleMouseClick(ev[2], ev[3], ev[4])
    elseif kind == "mouse_drag" then
      handleMouseDrag(ev[2], ev[3], ev[4])
    elseif kind == "mouse_up" then
      handleMouseUp(ev[2], ev[3], ev[4])
    elseif kind == "mouse_scroll" then
      handleMouseScroll(ev[2], ev[3], ev[4])
    elseif kind == "key" then
      if ev[2] == keys.leftAlt or ev[2] == keys.rightAlt then altHeld = true end
      if altHeld and ev[2] == keys.tab then
        -- alt-tab: focus the next non-minimized window, cycling
        local order = {}
        for i = 1, #procs do if not procs[i].minimized then order[#order + 1] = procs[i] end end
        if #order > 1 then
          local curIdx = 1
          for i = 1, #order do if order[i].id == focusedId then curIdx = i end end
          local nextP = order[(curIdx % #order) + 1]
          focus(nextP.id)
        end
      elseif focusedId then
        local p = findProc(focusedId)
        if p then resumeProc(p, ev) end
      end
    elseif kind == "key_up" then
      if ev[2] == keys.leftAlt or ev[2] == keys.rightAlt then altHeld = false end
      if focusedId then
        local p = findProc(focusedId)
        if p then resumeProc(p, ev) end
      end
    elseif kind == "char" or kind == "paste" then
      if focusedId then
        local p = findProc(focusedId)
        if p then resumeProc(p, ev) end
      end
    elseif kind == "timer" and ev[2] == notifyTimerId then
      currentNotification = nil
      notifyTimerId = nil
    else
      for i = 1, #procs do
        if not procs[i].dead then resumeProc(procs[i], ev) end
      end
    end

    reap()
    redrawFrame()

    eventCount = eventCount + 1
    if opts.onEvent then opts.onEvent(ev, debugState()) end
    if opts.maxEvents and eventCount >= opts.maxEvents then return end
  end
end

return kernel
]=])
file("os/lib/apps.lua", [=[
--[[ apps -- registry of installed applications, shown in the Start menu. ]]

local apps = {}

apps.list = {
  { id = "about",   name = "About",      icon = "i", module = "apps.about",      width = 36, height = 12 },
  { id = "files",   name = "Files",      icon = "F", module = "apps.files",      width = 46, height = 17 },
  { id = "editor",  name = "Editor",     icon = "E", module = "apps.editor",     width = 48, height = 18 },
  { id = "terminal",name = "Terminal",   icon = "T", module = "apps.terminal",   width = 46, height = 17 },
  { id = "settings",name = "Settings",   icon = "S", module = "apps.settings",   width = 40, height = 15 },
  { id = "chat",    name = "Chat",       icon = "C", module = "apps.chat",       width = 42, height = 16 },
  { id = "share",   name = "Share",      icon = "H", module = "apps.share",      width = 42, height = 16 },
  { id = "calc",    name = "Calc",       icon = "+", module = "apps.calculator", width = 24, height = 16 },
  { id = "clock",   name = "Clock",      icon = "O", module = "apps.clock",      width = 32, height = 14 },
  { id = "notes",   name = "Notes",      icon = "N", module = "apps.notes",      width = 38, height = 17 },
  { id = "piano",   name = "Piano",      icon = "P", module = "apps.piano",      width = 44, height = 12 },
  { id = "snake",   name = "Snake",      icon = "G", module = "apps.snake",      width = 36, height = 19 },
}

function apps.byId(id)
  for i = 1, #apps.list do
    if apps.list[i].id == id then return apps.list[i] end
  end
  return nil
end

return apps
]=])
file("os/lib/canvas.lua", [=[
--[[ canvas -- a square-pixel framebuffer on top of the terminal.

  Each character cell holds a 2x3 grid of sub-pixels, so a full 51x19 screen
  becomes 102x57 pixels that are square on screen (3x3 real pixels each).

  A cell can only carry two colours, so on render each cell picks its two most
  common sub-pixel colours; anything else in that cell is folded into the
  foreground. Blocky game art stays exact, gradients degrade gracefully.
]]

local Canvas = {}
Canvas.__index = Canvas

local floor = math.floor
local schar = string.char
local concat = table.concat

local BLIT = {}
do
  local hex = "0123456789abcdef"
  local c = 1
  for i = 1, 16 do BLIT[c] = hex:sub(i, i) c = c * 2 end
end

--- Create a canvas occupying a character rectangle of the 51x19 screen.
function Canvas.new(cx, cy, cw, ch, clearColour)
  local self = setmetatable({}, Canvas)
  self.cx, self.cy = cx, cy
  self.cw, self.ch = cw, ch
  self.w, self.h = cw * 2, ch * 3
  self.bg = clearColour or colors.black
  self.px = {}
  local px = self.px
  for i = 1, self.w * self.h do px[i] = self.bg end
  self._c, self._f, self._b, self._t = {}, {}, {}, {}
  return self
end

function Canvas:clear(col)
  col = col or self.bg
  local px = self.px
  for i = 1, self.w * self.h do px[i] = col end
end

function Canvas:set(x, y, col)
  x, y = floor(x), floor(y)
  if x < 1 or y < 1 or x > self.w or y > self.h then return end
  self.px[(y - 1) * self.w + x] = col
end

function Canvas:get(x, y)
  x, y = floor(x), floor(y)
  if x < 1 or y < 1 or x > self.w or y > self.h then return nil end
  return self.px[(y - 1) * self.w + x]
end

--- Filled rectangle: top-left (x,y), size w*h, clipped to the canvas.
function Canvas:fill(x, y, w, h, col)
  x, y, w, h = floor(x), floor(y), floor(w), floor(h)
  if w <= 0 or h <= 0 then return end
  local x2, y2 = x + w - 1, y + h - 1
  if x < 1 then x = 1 end
  if y < 1 then y = 1 end
  if x2 > self.w then x2 = self.w end
  if y2 > self.h then y2 = self.h end
  if x > x2 or y > y2 then return end
  local px, W = self.px, self.w
  for yy = y, y2 do
    local base = (yy - 1) * W
    for xx = x, x2 do px[base + xx] = col end
  end
end

function Canvas:box(x, y, w, h, col)
  if w <= 0 or h <= 0 then return end
  self:fill(x, y, w, 1, col)
  self:fill(x, y + h - 1, w, 1, col)
  self:fill(x, y, 1, h, col)
  self:fill(x + w - 1, y, 1, h, col)
end

function Canvas:hline(x, y, w, col) self:fill(x, y, w, 1, col) end
function Canvas:vline(x, y, h, col) self:fill(x, y, 1, h, col) end

function Canvas:line(x0, y0, x1, y1, col)
  x0, y0, x1, y1 = floor(x0), floor(y0), floor(x1), floor(y1)
  local dx = math.abs(x1 - x0)
  local dy = -math.abs(y1 - y0)
  local sx = x0 < x1 and 1 or -1
  local sy = y0 < y1 and 1 or -1
  local err = dx + dy
  local guard = dx - dy + 4
  while guard > 0 do
    guard = guard - 1
    self:set(x0, y0, col)
    if x0 == x1 and y0 == y1 then return end
    local e2 = err + err
    if e2 >= dy then err = err + dy x0 = x0 + sx end
    if e2 <= dx then err = err + dx y0 = y0 + sy end
  end
end

function Canvas:circle(cx, cy, r, col, filled)
  cx, cy, r = floor(cx), floor(cy), floor(r)
  if r < 0 then return end
  local x, y, d = r, 0, 1 - r
  while x >= y do
    if filled then
      self:fill(cx - x, cy + y, x + x + 1, 1, col)
      self:fill(cx - x, cy - y, x + x + 1, 1, col)
      self:fill(cx - y, cy + x, y + y + 1, 1, col)
      self:fill(cx - y, cy - x, y + y + 1, 1, col)
    else
      self:set(cx + x, cy + y, col) self:set(cx - x, cy + y, col)
      self:set(cx + x, cy - y, col) self:set(cx - x, cy - y, col)
      self:set(cx + y, cy + x, col) self:set(cx - y, cy + x, col)
      self:set(cx + y, cy - x, col) self:set(cx - y, cy - x, col)
    end
    y = y + 1
    if d < 0 then
      d = d + 2 * y + 1
    else
      x = x - 1
      d = d + 2 * (y - x) + 1
    end
  end
end

------------------------------------------------------------------- sprites
--- Build a sprite from rows of characters. Characters absent from `map`
--- (or mapped to false) are transparent.
function Canvas.sprite(rows, map)
  local h = #rows
  local w = 0
  for i = 1, h do if #rows[i] > w then w = #rows[i] end end
  local s = { w = w, h = h, px = {} }
  for y = 1, h do
    local row = rows[y]
    for x = 1, w do
      local ch = row:sub(x, x)
      local v = map[ch]
      s.px[(y - 1) * w + x] = v or false
    end
  end
  return s
end

function Canvas:draw(x, y, spr, flipH, flipV)
  x, y = floor(x), floor(y)
  local w, h, sp = spr.w, spr.h, spr.px
  for sy = 1, h do
    local ry = flipV and (h - sy + 1) or sy
    local base = (ry - 1) * w
    local py = y + sy - 1
    if py >= 1 and py <= self.h then
      local rowBase = (py - 1) * self.w
      for sx = 1, w do
        local rx = flipH and (w - sx + 1) or sx
        local col = sp[base + rx]
        if col then
          local pxx = x + sx - 1
          if pxx >= 1 and pxx <= self.w then self.px[rowBase + pxx] = col end
        end
      end
    end
  end
end

--- Draw a sprite scaled up by an integer factor.
function Canvas:drawScaled(x, y, spr, scale)
  if scale == 1 then return self:draw(x, y, spr) end
  local w, h, sp = spr.w, spr.h, spr.px
  for sy = 1, h do
    local base = (sy - 1) * w
    for sx = 1, w do
      local col = sp[base + sx]
      if col then
        self:fill(x + (sx - 1) * scale, y + (sy - 1) * scale, scale, scale, col)
      end
    end
  end
end

-------------------------------------------------------------------- render
--- Convert the pixel buffer into drawing characters and blit it out.
function Canvas:render()
  local px, W = self.px, self.w
  local cw, ch = self.cw, self.ch
  local C, F, B, T = self._c, self._f, self._b, self._t
  local W2 = W + W
  for row = 0, ch - 1 do
    local base = row * 3 * W
    for col = 1, cw do
      local o = base + (col - 1) * 2
      local a, b = px[o + 1], px[o + 2]
      local c, d = px[o + W + 1], px[o + W + 2]
      local e, f = px[o + W2 + 1], px[o + W2 + 2]
      if a == b and a == c and a == d and a == e and a == f then
        C[col] = " "
        F[col] = "0"
        B[col] = BLIT[a]
      else
        local bgc, fgc
        -- Fast path: almost every non-uniform cell holds exactly two colours.
        local na = 1
        if b == a then na = na + 1 end
        if c == a then na = na + 1 end
        if d == a then na = na + 1 end
        if e == a then na = na + 1 end
        if f == a then na = na + 1 end
        local z
        if b ~= a then z = b
        elseif c ~= a then z = c
        elseif d ~= a then z = d
        elseif e ~= a then z = e
        else z = f end
        local nz = 0
        if b == z then nz = nz + 1 end
        if c == z then nz = nz + 1 end
        if d == z then nz = nz + 1 end
        if e == z then nz = nz + 1 end
        if f == z then nz = nz + 1 end

        if na + nz == 6 then
          if na >= nz then bgc, fgc = a, z else bgc, fgc = z, a end
        else
          -- three or more colours: keep the two most common, fold the rest in
          T[1], T[2], T[3], T[4], T[5], T[6] = a, b, c, d, e, f
          local bc, bn, sc, sn = nil, 0, nil, 0
          for i = 1, 6 do
            local v = T[i]
            if v ~= bc and v ~= sc then
              local n = 0
              for j = 1, 6 do if T[j] == v then n = n + 1 end end
              if n > bn then
                sc, sn = bc, bn
                bc, bn = v, n
              elseif n > sn then
                sc, sn = v, n
              end
            end
          end
          bgc = bc
          fgc = sc or bc
        end
        local bits = 0
        if a ~= bgc then bits = bits + 1 end
        if b ~= bgc then bits = bits + 2 end
        if c ~= bgc then bits = bits + 4 end
        if d ~= bgc then bits = bits + 8 end
        if e ~= bgc then bits = bits + 16 end
        if f ~= bgc then bits = bits + 32 end
        if bits >= 32 then
          bits = 63 - bits
          fgc, bgc = bgc, fgc
        end
        C[col] = schar(128 + bits)
        F[col] = BLIT[fgc]
        B[col] = BLIT[bgc]
      end
    end
    term.setCursorPos(self.cx, self.cy + row)
    term.blit(concat(C, "", 1, cw), concat(F, "", 1, cw), concat(B, "", 1, cw))
  end
end

return Canvas
]=])
file("os/lib/data.lua", [=[
--[[ data -- system settings, persisted at /os/data/settings.dat. ]]

local req = ...
local store = req("lib.store")

local PATH = "/os/data/settings.dat"

local DEFAULTS = {
  theme = "slate",
  volume = 7,
  clock24h = false,
  wallpaper = "cc-OS",
  username = "user",
}

local data = {}
local state = nil

local function ensure()
  if state then return end
  local loaded = store.load(PATH, nil)
  state = {}
  for k, v in pairs(DEFAULTS) do state[k] = v end
  if type(loaded) == "table" then
    for k, v in pairs(loaded) do state[k] = v end
  end
end

function data.get(key)
  ensure()
  return state[key]
end

function data.set(key, value)
  ensure()
  state[key] = value
end

function data.save()
  ensure()
  return store.save(PATH, state)
end

function data.all()
  ensure()
  return state
end

return data
]=])
file("os/lib/font.lua", [=[
--[[ font -- a 5-row pixel font drawn onto a canvas.

  Glyphs are 4 pixels wide apart from M, N and W, which need 5 to stay
  readable. Rows are listed top to bottom, "1" is an inked pixel. Lower case
  is folded to upper case; unknown characters render as a blank.

  Layout rule: a character cell holds three pixel rows and only two colours,
  so put text baselines on y = 3k + 1 and leave at least six pixels between
  lines of different colours. Lines that share a cell lose a colour.
]]

local font = { W = 4, H = 5 }

local RAW = {
  ["0"] = "0110 1001 1001 1001 0110",
  ["1"] = "0010 0110 0010 0010 0111",
  ["2"] = "1110 0001 0110 1000 1111",
  ["3"] = "1110 0001 0110 0001 1110",
  ["4"] = "1001 1001 1111 0001 0001",
  ["5"] = "1111 1000 1110 0001 1110",
  ["6"] = "0110 1000 1110 1001 0110",
  ["7"] = "1111 0001 0010 0100 0100",
  ["8"] = "0110 1001 0110 1001 0110",
  ["9"] = "0110 1001 0111 0001 0110",
  ["A"] = "0110 1001 1111 1001 1001",
  ["B"] = "1110 1001 1110 1001 1110",
  ["C"] = "0111 1000 1000 1000 0111",
  ["D"] = "1110 1001 1001 1001 1110",
  ["E"] = "1111 1000 1110 1000 1111",
  ["F"] = "1111 1000 1110 1000 1000",
  ["G"] = "0111 1000 1011 1001 0111",
  ["H"] = "1001 1001 1111 1001 1001",
  ["I"] = "1110 0100 0100 0100 1110",
  ["J"] = "0011 0001 0001 1001 0110",
  ["K"] = "1001 1010 1100 1010 1001",
  ["L"] = "1000 1000 1000 1000 1111",
  ["M"] = "10001 11011 10101 10001 10001",
  ["N"] = "10001 11001 10101 10011 10001",
  ["O"] = "0110 1001 1001 1001 0110",
  ["P"] = "1110 1001 1110 1000 1000",
  ["Q"] = "0110 1001 1001 1011 0111",
  ["R"] = "1110 1001 1110 1010 1001",
  ["S"] = "0111 1000 0110 0001 1110",
  ["T"] = "1111 0100 0100 0100 0100",
  ["U"] = "1001 1001 1001 1001 0110",
  ["V"] = "1001 1001 1001 1010 0100",
  ["W"] = "10001 10001 10101 11011 10001",
  ["X"] = "1001 1001 0110 1001 1001",
  ["Y"] = "1001 1001 0110 0100 0100",
  ["Z"] = "1111 0001 0110 1000 1111",
  [" "] = "0000 0000 0000 0000 0000",
  ["."] = "0000 0000 0000 0000 0100",
  [","] = "0000 0000 0000 0100 1000",
  [":"] = "0000 0100 0000 0100 0000",
  [";"] = "0000 0100 0000 0100 1000",
  ["-"] = "0000 0000 1110 0000 0000",
  ["+"] = "0000 0100 1110 0100 0000",
  ["="] = "0000 1110 0000 1110 0000",
  ["!"] = "0100 0100 0100 0000 0100",
  ["?"] = "1110 0001 0110 0000 0100",
  ["'"] = "0100 0100 0000 0000 0000",
  ["\""] = "1010 1010 0000 0000 0000",
  ["/"] = "0001 0010 0010 0100 1000",
  ["\\"] = "1000 0100 0100 0010 0001",
  ["("] = "0010 0100 0100 0100 0010",
  [")"] = "0100 0010 0010 0010 0100",
  ["["] = "0110 0100 0100 0100 0110",
  ["]"] = "0110 0010 0010 0010 0110",
  ["<"] = "0010 0100 1000 0100 0010",
  [">"] = "0100 0010 0001 0010 0100",
  ["*"] = "0000 1010 0100 1010 0000",
  ["%"] = "1001 0010 0100 1000 1001",
  ["#"] = "0101 1111 0101 1111 0101",
  ["_"] = "0000 0000 0000 0000 1111",
}

-- Compile to lists of {x, y} offsets so drawing is a flat loop.
font.glyphs = {}
for ch, spec in pairs(RAW) do
  local pts, y, w = {}, 0, 0
  for row in spec:gmatch("%S+") do
    if #row > w then w = #row end
    for x = 1, #row do
      if row:sub(x, x) == "1" then pts[#pts + 1] = { x - 1, y } end
    end
    y = y + 1
  end
  font.glyphs[ch] = { pts = pts, w = w }
end

local BLANK = font.glyphs[" "]

function font.width(text, scale, spacing)
  scale = scale or 1
  spacing = spacing or 1
  text = tostring(text):upper()
  local n = #text
  if n == 0 then return 0 end
  local total = 0
  for i = 1, n do
    local g = font.glyphs[text:sub(i, i)] or BLANK
    total = total + g.w * scale + spacing
  end
  return total - spacing
end

--- Draw text at pixel (x, y). Returns the x just past the last glyph.
function font.draw(canvas, x, y, text, col, scale, spacing)
  scale = scale or 1
  spacing = spacing or 1
  text = tostring(text):upper()
  local gx = x
  for i = 1, #text do
    local g = font.glyphs[text:sub(i, i)] or BLANK
    local pts = g.pts
    for j = 1, #pts do
      local p = pts[j]
      if scale == 1 then
        canvas:set(gx + p[1], y + p[2], col)
      else
        canvas:fill(gx + p[1] * scale, y + p[2] * scale, scale, scale, col)
      end
    end
    gx = gx + g.w * scale + spacing
  end
  return gx - spacing
end

--- Draw with a one-pixel drop shadow underneath.
function font.drawShadow(canvas, x, y, text, col, shadow, scale, spacing)
  font.draw(canvas, x + 1, y + 1, text, shadow, scale, spacing)
  return font.draw(canvas, x, y, text, col, scale, spacing)
end

--- Centre text horizontally across the whole canvas (or a given span).
function font.center(canvas, y, text, col, scale, spacing, x0, w)
  x0 = x0 or 1
  w = w or canvas.w
  local tw = font.width(text, scale, spacing)
  return font.draw(canvas, x0 + math.floor((w - tw) / 2), y, text, col, scale, spacing)
end

function font.centerShadow(canvas, y, text, col, shadow, scale, spacing, x0, w)
  x0 = x0 or 1
  w = w or canvas.w
  local tw = font.width(text, scale, spacing)
  local x = x0 + math.floor((w - tw) / 2)
  font.draw(canvas, x + 1, y + 1, text, shadow, scale, spacing)
  return font.draw(canvas, x, y, text, col, scale, spacing)
end

return font
]=])
file("os/lib/icons.lua", [=[
--[[ icons -- small pixel-art app icons drawn on a lib.canvas sub-pixel
  canvas (2x3 sub-pixels per character cell -- the highest resolution
  CC:Tweaked's font supports; there's no finer "sub-sub-pixel" than that).

  Each icon occupies an 8x9 pixel box (a 4x3 character cell region) and is
  drawn with fixed, per-app colours so it stays recognisable across themes,
  the way a real desktop's app icons don't repaint themselves when you
  change your wallpaper.
]]

local icons = {}
icons.CELLS = { w = 4, h = 3 }
icons.SIZE = { w = 8, h = 9 }

--- One signature colour per app, used as a small swatch in places too
--- cramped for real pixel art (titlebars, taskbar buttons).
icons.COLOR = {
  about = colors.blue, files = colors.yellow, editor = colors.lightGray,
  terminal = colors.lime, settings = colors.lightGray, chat = colors.cyan,
  share = colors.orange, calc = colors.lime, clock = colors.white,
  notes = colors.yellow, piano = colors.white, snake = colors.green,
}

local DRAW = {}

function DRAW.about(c, x, y)
  c:circle(x + 4, y + 4, 4, colors.blue, true)
  c:fill(x + 4, y + 2, 1, 1, colors.white)
  c:fill(x + 4, y + 4, 1, 3, colors.white)
end

function DRAW.files(c, x, y)
  c:fill(x, y + 1, 4, 2, colors.yellow)
  c:fill(x, y + 2, 8, 5, colors.yellow)
  c:box(x, y + 2, 8, 5, colors.brown)
end

function DRAW.editor(c, x, y)
  c:fill(x + 1, y, 6, 9, colors.white)
  c:fill(x + 5, y, 2, 2, colors.lightGray)
  c:fill(x + 2, y + 3, 4, 1, colors.gray)
  c:fill(x + 2, y + 5, 4, 1, colors.gray)
  c:fill(x + 2, y + 7, 3, 1, colors.gray)
end

function DRAW.terminal(c, x, y)
  c:fill(x, y, 8, 9, colors.black)
  c:box(x, y, 8, 9, colors.gray)
  c:fill(x + 1, y + 2, 1, 1, colors.lime)
  c:fill(x + 1, y + 4, 3, 1, colors.lime)
  c:fill(x + 2, y + 6, 3, 1, colors.lime)
end

function DRAW.settings(c, x, y)
  c:circle(x + 4, y + 4, 4, colors.lightGray, true)
  c:fill(x + 3, y, 2, 2, colors.gray)
  c:fill(x + 3, y + 7, 2, 2, colors.gray)
  c:fill(x, y + 3, 2, 2, colors.gray)
  c:fill(x + 7, y + 3, 2, 2, colors.gray)
  c:circle(x + 4, y + 4, 2, colors.gray, true)
end

function DRAW.chat(c, x, y)
  c:fill(x, y, 8, 6, colors.cyan)
  c:box(x, y, 8, 6, colors.blue)
  c:fill(x + 1, y + 6, 2, 2, colors.cyan)
  c:fill(x + 2, y + 2, 1, 1, colors.white)
  c:fill(x + 4, y + 2, 1, 1, colors.white)
  c:fill(x + 6, y + 2, 1, 1, colors.white)
end

function DRAW.share(c, x, y)
  -- a bold upward arrow: a stepped triangular head over a stem
  c:fill(x + 3, y, 2, 1, colors.orange)
  c:fill(x + 2, y + 1, 4, 1, colors.orange)
  c:fill(x + 1, y + 2, 6, 2, colors.orange)
  c:fill(x + 3, y + 4, 2, 5, colors.orange)
end

function DRAW.calc(c, x, y)
  -- opaque throughout (never relies on the desktop colour showing through,
  -- since a dark "screen" tone could vanish against a dark theme)
  c:fill(x, y, 8, 9, colors.lightGray)
  c:fill(x, y, 8, 3, colors.gray)
  c:fill(x + 1, y + 1, 5, 1, colors.lime)
end

function DRAW.clock(c, x, y)
  c:circle(x + 4, y + 4, 4, colors.white, true)
  c:fill(x + 4, y + 1, 1, 3, colors.black)
  c:fill(x + 4, y + 4, 3, 1, colors.black)
end

function DRAW.notes(c, x, y)
  c:fill(x, y, 8, 8, colors.yellow)
  c:fill(x + 5, y, 3, 3, colors.white)
  c:fill(x + 1, y + 3, 5, 1, colors.orange)
  c:fill(x + 1, y + 5, 5, 1, colors.orange)
end

function DRAW.piano(c, x, y)
  c:fill(x, y + 1, 8, 6, colors.white)
  c:box(x, y + 1, 8, 6, colors.gray)
  c:fill(x + 1, y + 1, 1, 4, colors.black)
  c:fill(x + 3, y + 1, 1, 4, colors.black)
  c:fill(x + 5, y + 1, 1, 4, colors.black)
end

function DRAW.snake(c, x, y)
  c:fill(x, y + 6, 3, 2, colors.lime)
  c:fill(x + 2, y + 4, 3, 2, colors.lime)
  c:fill(x + 4, y + 2, 3, 2, colors.lime)
  c:fill(x + 6, y, 2, 2, colors.lime)
  c:fill(x, y, 2, 2, colors.red)
end

function DRAW.default(c, x, y)
  c:fill(x, y, 8, 9, colors.gray)
  c:box(x, y, 8, 9, colors.lightGray)
end

--- Draws the icon for `appId` with its top-left pixel at (x, y) on `canvas`.
function icons.draw(canvas, appId, x, y)
  local fn = DRAW[appId] or DRAW.default
  fn(canvas, x, y)
end

return icons
]=])
file("os/lib/net.lua", [=[
--[[ net -- a tiny shared-channel protocol over the modem peripheral, used by
  the Chat and File Share apps. Not rednet: a fixed broadcast channel keeps
  every cc-OS computer within radio range able to see every message, with a
  `from`/`id` envelope so apps can filter out their own transmissions.
]]

local net = {}
net.CHANNEL = 6060
net.REPLY = 6061
net.CHUNK_SIZE = 900

local modem

function net.open()
  modem = peripheral.find("modem")
  if not modem then return nil, "no modem attached" end
  if not modem.isOpen(net.CHANNEL) then modem.open(net.CHANNEL) end
  return modem
end

function net.myName()
  local label = os.getComputerLabel()
  if label and label ~= "" then return label end
  return "PC-" .. os.getComputerID()
end

function net.send(kind, data)
  if not modem then return false end
  modem.transmit(net.CHANNEL, net.REPLY, { t = kind, from = net.myName(), id = os.getComputerID(), data = data })
  return true
end

--- Call with a raw event table. Returns the message payload table if this
--- event is one of ours (and not our own echo), else nil.
function net.parse(ev)
  if ev[1] ~= "modem_message" then return nil end
  local channel, msg = ev[3], ev[5]
  if channel ~= net.CHANNEL then return nil end
  if type(msg) ~= "table" or type(msg.t) ~= "string" then return nil end
  if msg.id == os.getComputerID() then return nil end
  return msg
end

--- Splits `content` into net.send "file_start"/"file_chunk"/"file_end" calls.
function net.sendFile(name, content)
  local id = tostring(os.getComputerID()) .. "-" .. tostring(os.epoch and os.epoch() or math.random(1, 1e9))
  net.send("file_start", { id = id, name = name, size = #content })
  local i = 1
  while i <= #content do
    net.send("file_chunk", { id = id, part = content:sub(i, i + net.CHUNK_SIZE - 1) })
    i = i + net.CHUNK_SIZE
  end
  net.send("file_end", { id = id })
  return id
end

return net
]=])
file("os/lib/sound.lua", [=[
--[[ sound -- tiny UI sound effects played on the attached speaker, if any.
  Volume comes from the shared settings (lib.data's "volume", 0-10). ]]

local req = ...
local data = req("lib.data")

local sound = {}
local speaker = peripheral.find("speaker")

local EFFECTS = {
  click = { inst = "hat", pitch = 14, vol = 0.6 },
  open = { inst = "pling", pitch = 16, vol = 0.8 },
  close = { inst = "pling", pitch = 8, vol = 0.8 },
  minimize = { inst = "hat", pitch = 6, vol = 0.6 },
  error = { inst = "bass", pitch = 2, vol = 1.0 },
  notify = { inst = "bell", pitch = 18, vol = 0.7 },
  boot = { inst = "chime", pitch = 12, vol = 1.0 },
}

function sound.play(name)
  if not speaker then return end
  local e = EFFECTS[name]
  if not e then return end
  local vol = ((data.get("volume") or 7) / 10) * e.vol
  pcall(speaker.playNote, e.inst, vol, e.pitch)
end

return sound
]=])
file("os/lib/store.lua", [=[
--[[ store -- tiny serialised key-value file helper shared by settings and apps. ]]

local store = {}

function store.load(path, default)
  if fs.exists(path) and not fs.isDir(path) then
    local h = fs.open(path, "r")
    if h then
      local raw = h.readAll()
      h.close()
      if raw and #raw > 0 then
        local ok, t = pcall(textutils.unserialize, raw)
        if ok and t ~= nil then return t end
      end
    end
  end
  return default
end

function store.save(path, value)
  local dir = fs.getDir(path)
  if dir ~= "" and not fs.exists(dir) then
    local ok = pcall(fs.makeDir, dir)
    if not ok then return false end
  end
  local h = fs.open(path, "w")
  if not h then return false end
  h.write(textutils.serialize(value))
  h.close()
  return true
end

return store
]=])
file("os/lib/theme.lua", [=[
--[[ theme -- named colour presets shared by the kernel chrome and every app. ]]

local theme = {}

theme.presets = {
  {
    id = "slate", name = "Slate",
    bg = colors.black, fg = colors.white,
    accent = colors.cyan, accent2 = colors.blue,
    chrome = colors.gray, chromeText = colors.white,
    chromeFocus = colors.cyan, chromeFocusText = colors.black,
    taskbar = colors.gray, taskbarText = colors.white,
    taskbarActive = colors.cyan, taskbarActiveText = colors.black,
    desktop = colors.blue, desktopText = colors.white,
    field = colors.lightGray, fieldText = colors.black,
    ok = colors.lime, warn = colors.yellow, err = colors.red,
  },
  {
    id = "paper", name = "Paper",
    bg = colors.white, fg = colors.black,
    accent = colors.blue, accent2 = colors.lightBlue,
    chrome = colors.lightGray, chromeText = colors.black,
    chromeFocus = colors.blue, chromeFocusText = colors.white,
    taskbar = colors.lightGray, taskbarText = colors.black,
    taskbarActive = colors.blue, taskbarActiveText = colors.white,
    desktop = colors.cyan, desktopText = colors.black,
    field = colors.white, fieldText = colors.black,
    ok = colors.green, warn = colors.orange, err = colors.red,
  },
  {
    id = "amber", name = "Amber CRT",
    bg = colors.black, fg = colors.orange,
    accent = colors.orange, accent2 = colors.yellow,
    chrome = colors.brown, chromeText = colors.orange,
    chromeFocus = colors.orange, chromeFocusText = colors.black,
    taskbar = colors.brown, taskbarText = colors.orange,
    taskbarActive = colors.orange, taskbarActiveText = colors.black,
    desktop = colors.black, desktopText = colors.orange,
    field = colors.gray, fieldText = colors.orange,
    ok = colors.lime, warn = colors.yellow, err = colors.red,
  },
  {
    id = "midnight", name = "Midnight",
    bg = colors.black, fg = colors.lightGray,
    accent = colors.purple, accent2 = colors.magenta,
    chrome = colors.gray, chromeText = colors.lightGray,
    chromeFocus = colors.purple, chromeFocusText = colors.white,
    taskbar = colors.black, taskbarText = colors.lightGray,
    taskbarActive = colors.purple, taskbarActiveText = colors.white,
    desktop = colors.gray, desktopText = colors.white,
    field = colors.gray, fieldText = colors.white,
    ok = colors.lime, warn = colors.yellow, err = colors.red,
  },
}

function theme.byId(id)
  for i = 1, #theme.presets do
    if theme.presets[i].id == id then return theme.presets[i] end
  end
  return theme.presets[1]
end

function theme.list()
  return theme.presets
end

return theme
]=])
file("os/lib/widgets.lua", [=[
--[[ widgets -- small reusable UI primitives for apps.

  Everything draws to whatever terminal is currently redirected (the app's
  own window during its turn), using 1-based screen coordinates local to
  that window. Nothing here touches the real cursor blink; a focused text
  field is shown as a reverse-video caret so multiple fields never fight
  over the hardware cursor.
]]

local widgets = {}

------------------------------------------------------------------- painting
function widgets.fill(x, y, w, h, bg)
  term.setBackgroundColor(bg)
  local blank = string.rep(" ", math.max(w, 0))
  for row = y, y + h - 1 do
    term.setCursorPos(x, row)
    term.write(blank)
  end
end

function widgets.text(x, y, str, fg, bg)
  term.setCursorPos(x, y)
  if fg then term.setTextColor(fg) end
  if bg then term.setBackgroundColor(bg) end
  term.write(str)
end

--- Truncates or space-pads `str` to exactly `w` columns.
function widgets.clip(str, w)
  str = tostring(str)
  if #str > w then
    if w <= 2 then return str:sub(1, w) end
    return str:sub(1, w - 2) .. ".."
  end
  return str .. string.rep(" ", w - #str)
end

------------------------------------------------------------------- buttons
function widgets.button(x, y, w, label, bg, fg)
  widgets.fill(x, y, w, 1, bg)
  local pad = math.max(0, math.floor((w - #label) / 2))
  widgets.text(x + pad, y, label, fg, bg)
  return { x = x, y = y, w = w, h = 1 }
end

function widgets.hit(rect, px, py)
  return rect and px >= rect.x and px < rect.x + rect.w and py >= rect.y and py < rect.y + rect.h
end

------------------------------------------------------------------- text field
local TextField = {}
TextField.__index = TextField

function widgets.newTextField(initial, maxLen)
  return setmetatable({
    value = initial or "",
    cursor = #(initial or "") + 1,
    scroll = 0,
    maxLen = maxLen,
  }, TextField)
end

function TextField:setValue(v)
  self.value = v or ""
  self.cursor = #self.value + 1
  self.scroll = 0
end

function TextField:insert(ch)
  if self.maxLen and #self.value >= self.maxLen then return end
  self.value = self.value:sub(1, self.cursor - 1) .. ch .. self.value:sub(self.cursor)
  self.cursor = self.cursor + #ch
end

function TextField:backspace()
  if self.cursor <= 1 then return end
  self.value = self.value:sub(1, self.cursor - 2) .. self.value:sub(self.cursor)
  self.cursor = self.cursor - 1
end

function TextField:delete()
  if self.cursor > #self.value then return end
  self.value = self.value:sub(1, self.cursor - 1) .. self.value:sub(self.cursor + 1)
end

function TextField:left() if self.cursor > 1 then self.cursor = self.cursor - 1 end end
function TextField:right() if self.cursor <= #self.value then self.cursor = self.cursor + 1 end end
function TextField:home() self.cursor = 1 end
function TextField:fin() self.cursor = #self.value + 1 end

--- key is a `keys.*` code. Returns true if it handled the key.
function TextField:handleKey(key)
  if key == keys.left then self:left() return true end
  if key == keys.right then self:right() return true end
  if key == keys.backspace then self:backspace() return true end
  if key == keys.delete then self:delete() return true end
  if key == keys.home then self:home() return true end
  if key == keys["end"] then self:fin() return true end
  return false
end

function TextField:render(x, y, w, th, focused)
  if self.cursor - self.scroll > w then self.scroll = self.cursor - w end
  if self.cursor - self.scroll < 1 then self.scroll = self.cursor - 1 end
  if self.scroll < 0 then self.scroll = 0 end
  local visible = self.value:sub(self.scroll + 1, self.scroll + w)
  widgets.fill(x, y, w, 1, th.field)
  widgets.text(x, y, visible, th.fieldText, th.field)
  if focused then
    local cx = x + (self.cursor - self.scroll) - 1
    if cx >= x and cx < x + w then
      local ch = self.value:sub(self.cursor, self.cursor)
      if ch == "" then ch = " " end
      widgets.text(cx, y, ch, th.field, th.accent)
    end
  end
end

------------------------------------------------------------------- list box
local ListBox = {}
ListBox.__index = ListBox

function widgets.newListBox(items)
  return setmetatable({ items = items or {}, selected = 1, top = 0 }, ListBox)
end

function ListBox:setItems(items)
  self.items = items or {}
  if self.selected > #self.items then self.selected = #self.items end
  if self.selected < 1 and #self.items > 0 then self.selected = 1 end
end

function ListBox:moveUp()
  if self.selected > 1 then self.selected = self.selected - 1 end
end

function ListBox:moveDown()
  if self.selected < #self.items then self.selected = self.selected + 1 end
end

function ListBox:render(x, y, w, h, th, toLabel)
  toLabel = toLabel or tostring
  if self.selected - self.top > h then self.top = self.selected - h end
  if self.selected - self.top < 1 then self.top = self.selected - 1 end
  if self.top < 0 then self.top = 0 end
  for row = 0, h - 1 do
    local idx = self.top + row + 1
    local item = self.items[idx]
    local bg = th.bg
    local fg = th.fg
    if item ~= nil and idx == self.selected then
      bg, fg = th.accent, th.chromeFocusText
    end
    widgets.fill(x, y + row, w, 1, bg)
    if item ~= nil then
      widgets.text(x, y + row, widgets.clip(" " .. toLabel(item), w), fg, bg)
    end
  end
end

--- Returns the item index a click at (px,py) within the box (x,y,w,h) hits,
--- or nil if the click missed / landed past the end of the list.
function ListBox:hitIndex(x, y, w, h, px, py)
  if px < x or px >= x + w or py < y or py >= y + h then return nil end
  local idx = self.top + (py - y) + 1
  if idx < 1 or idx > #self.items then return nil end
  return idx
end

return widgets
]=])
file("startup.lua", [[
-- cc-OS startup: hands control to the windowed desktop on boot.
if fs.exists("/os/boot.lua") then
  shell.run("/os/boot.lua")
else
  print("cc-OS: /os/boot.lua is missing.")
  print("Re-run the installer.")
end
]])

--------------------------------------------------------------------- unpack
local total = #ORDER
local written, failed = 0, 0

term.setTextColour(colours.white)
print("cc-OS installer")
print(total .. " files" .. (target ~= "" and (" -> " .. target) or ""))
print("")

for i = 1, total do
  local path = ORDER[i]
  local full = target .. "/" .. path
  local dir = fs.getDir(full)
  local ok, err = pcall(function()
    if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
    local handle = fs.open(full, "w")
    if not handle then error("cannot open for writing", 0) end
    handle.write(FILES[path])
    handle.close()
  end)
  if ok then
    written = written + 1
  else
    failed = failed + 1
    term.setTextColour(colours.red)
    print("failed: " .. path .. " (" .. tostring(err) .. ")")
    term.setTextColour(colours.white)
  end
  local w = term.getSize()
  local done = math.floor((i / total) * (w - 8))
  term.setCursorPos(1, select(2, term.getCursorPos()))
  term.clearLine()
  term.write(string.format("%3d%% [", math.floor(i / total * 100)))
  term.setTextColour(colours.lime)
  term.write(string.rep("=", done))
  term.setTextColour(colours.white)
  term.write(string.rep(" ", math.max(0, w - 8 - done)) .. "]")
  if i % 4 == 0 then sleep(0) end
end

print("")
print("")
if failed > 0 then
  term.setTextColour(colours.red)
  print(failed .. " file(s) failed -- cc-OS is not installed.")
  term.setTextColour(colours.white)
  return
end

term.setTextColour(colours.lime)
print("Installed " .. written .. " files.")
term.setTextColour(colours.white)
if target == "" then
  print("Reboot the computer, or run: cc-os")
else
  print("Run: " .. target .. "/cc-os")
end

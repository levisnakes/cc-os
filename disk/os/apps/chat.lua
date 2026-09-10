--[[ chat -- broadcast text chat with every other cc-OS computer in modem range. ]]

local req = ...
local net = req("lib.net")
local widgets = req("lib.widgets")

local M = {}
M.id = "chat"
M.name = "Chat"

function M.run(ctx)
  local api = ctx.api
  local log = {}
  local input = ""
  local modem, err = net.open()

  local function push(sender, text)
    local w = api.getSize()
    local prefix = sender .. ": "
    local wrapped = widgets.wrap(text, math.max(10, w - #prefix))
    log[#log + 1] = prefix .. wrapped[1]
    for i = 2, #wrapped do
      log[#log + 1] = string.rep(" ", #prefix) .. wrapped[i]
    end
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

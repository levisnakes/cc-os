--[[ share -- send a file to every cc-OS computer in modem range; anything
  sent to us lands in /os/data/received/. ]]

local req = ...
local net = req("lib.net")
local widgets = req("lib.widgets")

local M = {}
M.id = "share"
M.name = "File Share"

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

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

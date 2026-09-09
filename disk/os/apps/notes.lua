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
  local w, h = api.getSize()
  local listH = h - 3

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
    if mode == "list" then
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

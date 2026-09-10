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

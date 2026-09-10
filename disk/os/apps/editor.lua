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

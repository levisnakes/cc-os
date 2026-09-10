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

  local scrollOffset = 0 -- lines back from the newest; 0 = pinned to the tail
  local function maxScroll() return math.max(0, #out - outH) end

  local function log(text)
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
      out[#out + 1] = line
    end
    scrollOffset = 0 -- new output snaps the view back to the live tail
  end

  local function draw()
    local T = api.getTheme()
    term.setBackgroundColor(T.bg)
    term.setTextColor(T.fg)
    term.clear()
    scrollOffset = math.min(scrollOffset, maxScroll())
    local first = math.max(1, #out - outH + 1 - scrollOffset)
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
    if scrollOffset > 0 then
      local tag = " -- scrolled, " .. scrollOffset .. " -- "
      term.setTextColor(T.warn)
      term.write(tag:sub(1, w))
      term.setTextColor(T.chromeText)
    else
      local prompt = "/" .. cwd .. "> "
      local visible = prompt .. input
      if #visible > w then visible = visible:sub(#visible - w + 1) end
      term.write(visible)
      term.setCursorPos(math.min(w, #visible + 1), h)
      term.setCursorBlink(true)
    end
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
      scrollOffset = 0
    elseif kind == "key" then
      local k = ev[2]
      scrollOffset = 0
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
      scrollOffset = math.max(0, math.min(maxScroll(), scrollOffset - ev[2] * 3))
    elseif kind == "term_resize" then
      refreshSize()
    end
    draw()
  end
end

return M

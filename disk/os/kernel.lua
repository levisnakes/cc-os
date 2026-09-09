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
]]

local req = ...
local theme = req("lib.theme")
local widgets = req("lib.widgets")
local data = req("lib.data")
local appsReg = req("lib.apps")

local kernel = {}

--- opts is optional and only used by the test harness:
---   opts.maxEvents -- return after this many events instead of looping forever
---   opts.onEvent(ev) -- called after each event is fully handled and redrawn
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

  local startMenuOpen = false
  local menuRect, menuItems = nil, {}
  local startBtnRect, taskbarButtons = nil, {}

  local currentNotification, notifyTimerId = nil, nil

  ------------------------------------------------------------- forward decls
  local focus, closeProc, minimizeProc, launch, resumeProc, makeApi, notify
  local drawChrome, drawTaskbar, drawStartMenu, drawNotification, redrawFrame
  local procAt, findProc, handleMouseClick, handleMouseDrag, handleMouseUp

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
    local _, idx = findProc(p.id)
    if idx then table.remove(procs, idx) end
    if focusedId == p.id then focusedId = pickNewFocus() end
  end

  function minimizeProc(p)
    p.minimized = true
    if focusedId == p.id then focusedId = pickNewFocus() end
  end

  ------------------------------------------------------------------- events
  notify = function(msg)
    currentNotification = tostring(msg)
    notifyTimerId = os.startTimer(2.5)
  end

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
    function api.notify(msg) notify(msg) end
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
    return api
  end

  function launch(appId, args)
    local def = appsReg.byId(appId)
    if not def then notify("No such app: " .. tostring(appId)) return nil end
    local ok, mod = pcall(req, def.module)
    if not ok or type(mod) ~= "table" or type(mod.run) ~= "function" then
      notify("Could not load " .. def.name)
      return nil
    end
    local w = math.min(def.width or 40, screenW - 2)
    local h = math.min(def.height or 15, desktopH - 1)
    local x = math.random(1, math.max(1, screenW - w + 1))
    local y = math.random(1, math.max(1, desktopH - h + 1))
    local win = window.create(native, x + 1, y + 1, w - 2, h - 2, true)
    win.setBackgroundColor(currentTheme.bg)
    win.setTextColor(currentTheme.fg)
    win.clear()
    win.setCursorPos(1, 1)

    local proc = {
      id = nextId, appId = appId, title = def.name,
      x = x, y = y, w = w, h = h, win = win, minimized = false,
    }
    nextId = nextId + 1

    local ctx = { api = makeApi(proc), args = args or {}, win = win }
    proc.co = coroutine.create(function()
      local ok2, err = pcall(mod.run, ctx)
      if not ok2 and err ~= "__APP_EXIT__" then
        proc.crashError = tostring(err)
      end
    end)

    procs[#procs + 1] = proc
    resumeProc(proc, {})
    if not proc.dead then focus(proc.id) end
    return proc
  end

  function resumeProc(proc, eventArgs)
    if proc.dead then return end
    term.redirect(proc.win)
    local ok, err = pcall(coroutine.resume, proc.co, table.unpack(eventArgs or {}))
    term.redirect(native)
    if not ok then
      proc.dead = true
      proc.crashError = tostring(err)
    elseif coroutine.status(proc.co) == "dead" then
      proc.dead = true
    end
  end

  --------------------------------------------------------------- rendering
  local function titleBounds(p)
    return { minX = p.x + p.w - 7, minEnd = p.x + p.w - 5, closeX = p.x + p.w - 3, closeEnd = p.x + p.w - 1 }
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
    local titleW = p.w - 9
    if titleW > 0 then
      term.setCursorPos(p.x + 1, p.y)
      term.write(widgets.clip(p.title, titleW))
    end
    term.setCursorPos(p.x + p.w - 7, p.y)
    term.write("[_][x]")
    term.setBackgroundColor(th.bg)
    term.setTextColor(th.fg)
    for row = p.y + 1, p.y + p.h - 2 do
      term.setCursorPos(p.x, row)
      term.write("|")
      term.setCursorPos(p.x + p.w - 1, row)
      term.write("|")
    end
    term.setCursorPos(p.x, p.y + p.h - 1)
    term.write("+" .. string.rep("-", p.w - 2) .. "+")
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
      local w = #label
      if cx + w > screenW - 7 then break end
      local isFocused = (p.id == focusedId) and not p.minimized
      term.setBackgroundColor(isFocused and th.taskbarActive or th.taskbar)
      term.setTextColor(isFocused and th.taskbarActiveText or th.taskbarText)
      term.setCursorPos(cx, screenH)
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

  function drawStartMenu()
    if not startMenuOpen then return end
    local th = currentTheme
    local list = appsReg.list
    local w = 18
    for i = 1, #list do
      local need = #list[i].name + 5
      if need > w then w = need end
    end
    local h = #list
    local x, y = 1, screenH - h
    menuRect = { x = x, y = y, w = w, h = h }
    menuItems = {}
    for i = 1, #list do
      local a = list[i]
      local row = y + i - 1
      term.setBackgroundColor(th.chrome)
      term.setTextColor(th.chromeText)
      term.setCursorPos(x, row)
      term.write(widgets.clip(" " .. a.icon .. "  " .. a.name, w))
      menuItems[#menuItems + 1] = { x = x, y = row, w = w, h = 1, appId = a.id }
    end
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
    for i = 1, #procs do
      local p = procs[i]
      if not p.minimized then
        drawChrome(p)
        p.win.redraw()
      end
    end
    drawTaskbar()
    drawStartMenu()
    drawNotification()
  end

  ------------------------------------------------------------------- input
  local function forwardToClient(p, x, y, eventName, extra)
    local lx, ly = x - p.x, y - p.y
    resumeProc(p, { eventName, extra, lx, ly })
  end

  function handleMouseClick(btn, x, y)
    if startMenuOpen then
      startMenuOpen = false
      if widgets.hit(menuRect, x, y) then
        for i = 1, #menuItems do
          if widgets.hit(menuItems[i], x, y) then launch(menuItems[i].appId) break end
        end
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
    if not p then return end
    focus(p.id)

    if y == p.y then
      local tb = titleBounds(p)
      if x >= tb.minX and x <= tb.minEnd then
        minimizeProc(p)
        return
      end
      if x >= tb.closeX and x <= tb.closeEnd then
        closeProc(p)
        return
      end
      dragState = { id = p.id, offX = x - p.x, offY = y - p.y }
      return
    end

    if x == p.x or x == p.x + p.w - 1 or y == p.y + p.h - 1 then
      return -- border, not clickable
    end

    mouseCapture = p.id
    forwardToClient(p, x, y, "mouse_click", btn)
  end

  function handleMouseDrag(btn, x, y)
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
    if dragState then
      dragState = nil
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
      out[i] = { id = p.id, appId = p.appId, title = p.title, x = p.x, y = p.y, w = p.w, h = p.h, minimized = p.minimized }
    end
    return out, focusedId
  end

  ------------------------------------------------------------------ reaping
  local function reap()
    local i = 1
    while i <= #procs do
      local p = procs[i]
      if p.dead then
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

  ---------------------------------------------------------------- main loop
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
    elseif kind == "key" or kind == "key_up" or kind == "char" or kind == "paste" then
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

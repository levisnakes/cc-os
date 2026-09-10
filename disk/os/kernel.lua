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

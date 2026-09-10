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

--- Splits `text` into lines no wider than `width`, breaking on spaces
--- (never mid-word, except a single word wider than `width` on its own).
function widgets.wrap(text, width)
  local lines, cur = {}, ""
  for word in tostring(text):gmatch("%S+") do
    local candidate = (cur == "" and word) or (cur .. " " .. word)
    if #candidate <= width then
      cur = candidate
    else
      if cur ~= "" then lines[#lines + 1] = cur end
      cur = (#word <= width) and word or word:sub(1, width)
    end
  end
  if cur ~= "" then lines[#lines + 1] = cur end
  if #lines == 0 then lines = { "" } end
  return lines
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

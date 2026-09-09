--[[ cc-OS boot loader -- sets up the module loader and hands off to the kernel. ]]

local BASE = "/os"

local function makeLoader(base)
  local cache = {}
  local loading = {}
  local req
  req = function(name)
    local hit = cache[name]
    if hit ~= nil then return hit end
    if loading[name] then error("circular require: " .. name, 0) end
    local path = base .. "/" .. (name:gsub("%.", "/")) .. ".lua"
    local chunk, err = loadfile(path)
    if not chunk then error("module not found: " .. name .. " (" .. tostring(err) .. ")", 0) end
    loading[name] = true
    local mod = chunk(req, name)
    loading[name] = nil
    if mod == nil then mod = true end
    cache[name] = mod
    return mod
  end
  return req
end

local req = makeLoader(BASE)

local prevTerm = term.current()
local ok, err = pcall(function()
  local kernel = req("kernel")
  kernel.run()
end)

term.redirect(prevTerm)
term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
term.setCursorPos(1, 1)

if not ok then
  printError("cc-OS stopped: " .. tostring(err))
else
  print("cc-OS shut down.")
end

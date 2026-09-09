-- t_load.lua -- every registered app module must load and expose run().
local apps = require_os("lib.apps")

for i = 1, #apps.list do
  local a = apps.list[i]
  local ok, mod = pcall(require_os, a.module)
  if not check(ok, a.id .. " loaded: " .. tostring(mod)) then
    -- already logged
  else
    check(type(mod) == "table", a.id .. " returns a table")
    check(type(mod.run) == "function", a.id .. " has run()")
  end
end

finish("load")

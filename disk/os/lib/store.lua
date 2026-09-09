--[[ store -- tiny serialised key-value file helper shared by settings and apps. ]]

local store = {}

function store.load(path, default)
  if fs.exists(path) and not fs.isDir(path) then
    local h = fs.open(path, "r")
    if h then
      local raw = h.readAll()
      h.close()
      if raw and #raw > 0 then
        local ok, t = pcall(textutils.unserialize, raw)
        if ok and t ~= nil then return t end
      end
    end
  end
  return default
end

function store.save(path, value)
  local dir = fs.getDir(path)
  if dir ~= "" and not fs.exists(dir) then
    local ok = pcall(fs.makeDir, dir)
    if not ok then return false end
  end
  local h = fs.open(path, "w")
  if not h then return false end
  h.write(textutils.serialize(value))
  h.close()
  return true
end

return store

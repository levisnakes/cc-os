--[[ data -- system settings, persisted at /os/data/settings.dat. ]]

local req = ...
local store = req("lib.store")

local PATH = "/os/data/settings.dat"

local DEFAULTS = {
  theme = "slate",
  volume = 7,
  clock24h = false,
  wallpaper = "cc-OS",
  username = "user",
}

local data = {}
local state = nil

local function ensure()
  if state then return end
  local loaded = store.load(PATH, nil)
  state = {}
  for k, v in pairs(DEFAULTS) do state[k] = v end
  if type(loaded) == "table" then
    for k, v in pairs(loaded) do state[k] = v end
  end
end

function data.get(key)
  ensure()
  return state[key]
end

function data.set(key, value)
  ensure()
  state[key] = value
end

function data.save()
  ensure()
  return store.save(PATH, state)
end

function data.all()
  ensure()
  return state
end

return data

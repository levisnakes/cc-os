--[[ sound -- tiny UI sound effects played on the attached speaker, if any.
  Volume comes from the shared settings (lib.data's "volume", 0-10). ]]

local req = ...
local data = req("lib.data")

local sound = {}
local speaker = peripheral.find("speaker")

local EFFECTS = {
  click = { inst = "hat", pitch = 14, vol = 0.6 },
  open = { inst = "pling", pitch = 16, vol = 0.8 },
  close = { inst = "pling", pitch = 8, vol = 0.8 },
  minimize = { inst = "hat", pitch = 6, vol = 0.6 },
  error = { inst = "bass", pitch = 2, vol = 1.0 },
  notify = { inst = "bell", pitch = 18, vol = 0.7 },
  boot = { inst = "chime", pitch = 12, vol = 1.0 },
}

function sound.play(name)
  if not speaker then return end
  local e = EFFECTS[name]
  if not e then return end
  local vol = ((data.get("volume") or 7) / 10) * e.vol
  pcall(speaker.playNote, e.inst, vol, e.pitch)
end

return sound

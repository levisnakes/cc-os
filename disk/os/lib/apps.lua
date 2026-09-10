--[[ apps -- registry of installed applications, shown in the Start menu. ]]

local apps = {}

apps.list = {
  { id = "about",   name = "About",      icon = "i", module = "apps.about",      width = 36, height = 12 },
  { id = "files",   name = "Files",      icon = "F", module = "apps.files",      width = 46, height = 17 },
  { id = "editor",  name = "Editor",     icon = "E", module = "apps.editor",     width = 48, height = 18 },
  { id = "terminal",name = "Terminal",   icon = "T", module = "apps.terminal",   width = 46, height = 17 },
  { id = "settings",name = "Settings",   icon = "S", module = "apps.settings",   width = 40, height = 15 },
  { id = "chat",    name = "Chat",       icon = "C", module = "apps.chat",       width = 42, height = 16 },
  { id = "share",   name = "Share",      icon = "H", module = "apps.share",      width = 42, height = 16 },
  { id = "calc",    name = "Calc",       icon = "+", module = "apps.calculator", width = 24, height = 16 },
  { id = "clock",   name = "Clock",      icon = "O", module = "apps.clock",      width = 32, height = 14 },
  { id = "notes",   name = "Notes",      icon = "N", module = "apps.notes",      width = 38, height = 17 },
  { id = "piano",   name = "Piano",      icon = "P", module = "apps.piano",      width = 44, height = 12 },
  { id = "snake",   name = "Snake",      icon = "G", module = "apps.snake",      width = 36, height = 19 },
}

function apps.byId(id)
  for i = 1, #apps.list do
    if apps.list[i].id == id then return apps.list[i] end
  end
  return nil
end

return apps

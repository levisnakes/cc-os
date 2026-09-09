--[[ theme -- named colour presets shared by the kernel chrome and every app. ]]

local theme = {}

theme.presets = {
  {
    id = "slate", name = "Slate",
    bg = colors.black, fg = colors.white,
    accent = colors.cyan, accent2 = colors.blue,
    chrome = colors.gray, chromeText = colors.white,
    chromeFocus = colors.cyan, chromeFocusText = colors.black,
    taskbar = colors.gray, taskbarText = colors.white,
    taskbarActive = colors.cyan, taskbarActiveText = colors.black,
    desktop = colors.blue, desktopText = colors.white,
    field = colors.lightGray, fieldText = colors.black,
    ok = colors.lime, warn = colors.yellow, err = colors.red,
  },
  {
    id = "paper", name = "Paper",
    bg = colors.white, fg = colors.black,
    accent = colors.blue, accent2 = colors.lightBlue,
    chrome = colors.lightGray, chromeText = colors.black,
    chromeFocus = colors.blue, chromeFocusText = colors.white,
    taskbar = colors.lightGray, taskbarText = colors.black,
    taskbarActive = colors.blue, taskbarActiveText = colors.white,
    desktop = colors.cyan, desktopText = colors.black,
    field = colors.white, fieldText = colors.black,
    ok = colors.green, warn = colors.orange, err = colors.red,
  },
  {
    id = "amber", name = "Amber CRT",
    bg = colors.black, fg = colors.orange,
    accent = colors.orange, accent2 = colors.yellow,
    chrome = colors.brown, chromeText = colors.orange,
    chromeFocus = colors.orange, chromeFocusText = colors.black,
    taskbar = colors.brown, taskbarText = colors.orange,
    taskbarActive = colors.orange, taskbarActiveText = colors.black,
    desktop = colors.black, desktopText = colors.orange,
    field = colors.gray, fieldText = colors.orange,
    ok = colors.lime, warn = colors.yellow, err = colors.red,
  },
  {
    id = "midnight", name = "Midnight",
    bg = colors.black, fg = colors.lightGray,
    accent = colors.purple, accent2 = colors.magenta,
    chrome = colors.gray, chromeText = colors.lightGray,
    chromeFocus = colors.purple, chromeFocusText = colors.white,
    taskbar = colors.black, taskbarText = colors.lightGray,
    taskbarActive = colors.purple, taskbarActiveText = colors.white,
    desktop = colors.gray, desktopText = colors.white,
    field = colors.gray, fieldText = colors.white,
    ok = colors.lime, warn = colors.yellow, err = colors.red,
  },
}

function theme.byId(id)
  for i = 1, #theme.presets do
    if theme.presets[i].id == id then return theme.presets[i] end
  end
  return theme.presets[1]
end

function theme.list()
  return theme.presets
end

return theme

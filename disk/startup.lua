-- cc-OS startup: hands control to the windowed desktop on boot.
if fs.exists("/os/boot.lua") then
  shell.run("/os/boot.lua")
else
  print("cc-OS: /os/boot.lua is missing.")
  print("Re-run the installer.")
end

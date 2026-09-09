-- cc-os -- manually launch the desktop without rebooting.
if not fs.exists("/os/boot.lua") then
  print("cc-OS is not installed.")
  print("Expected to find /os/boot.lua")
  return
end
shell.run("/os/boot.lua")

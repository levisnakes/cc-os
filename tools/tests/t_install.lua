-- t_install.lua -- runs the single-file installer against an empty
-- filesystem, checks every extracted file is byte-identical to the source,
-- then boots the kernel from what it unpacked.

local bundle = __rootRead("install.lua")
check(bundle ~= nil, "install.lua exists -- run tools/build_bundle.py")
LOG(string.format("  bundle is %d bytes (%.0f KB)", #bundle, #bundle / 1024))
check(#bundle < 480 * 1024, "bundle fits inside a pastebin paste")

local originals = {}
local count = 0
for name in tostring(__diskList()):gmatch("[^\n]+") do
  originals[name] = __diskRead(name)
  count = count + 1
end
for key in pairs(MOCK.files) do MOCK.files[key] = nil end
eq(next(MOCK.files), nil, "filesystem starts empty")

------------------------------------------------------------------- unpack
local chunk, err = load(bundle, "@install.lua", "t", _G)
check(chunk ~= nil, "installer compiles: " .. tostring(err))

local ok, runErr = pcall(chunk)
check(ok, "installer runs: " .. tostring(runErr))

--------------------------------------------------------------- verify files
local missing, differing, extra = 0, 0, 0
for name, body in pairs(originals) do
  local handle = fs.open("/" .. name, "r")
  if not handle then
    missing = missing + 1
    LOG("  missing: " .. name)
  else
    local written = handle.readAll() or ""
    handle.close()
    if written ~= body then
      differing = differing + 1
      LOG(string.format("  differs: %s (%d bytes written, %d expected)", name, #written, #body))
    end
  end
end
for name in pairs(MOCK.files) do
  if originals[name] == nil then
    extra = extra + 1
    LOG("  unexpected file: " .. name)
  end
end

eq(missing, 0, "every file was unpacked")
eq(differing, 0, "every file is byte-identical to the source")
eq(extra, 0, "the installer wrote nothing unexpected")
LOG("  verified " .. count .. " files")

--------------------------------------------------- boot what was unpacked
local kernel = require_os("kernel")
local booted, bootErr = pcall(kernel.run, { maxEvents = 1 })
check(booted, "kernel boots from the freshly-unpacked disk: " .. tostring(bootErr))
SHOT("fresh_install_desktop")

finish("install")

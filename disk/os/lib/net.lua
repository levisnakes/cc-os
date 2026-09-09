--[[ net -- a tiny shared-channel protocol over the modem peripheral, used by
  the Chat and File Share apps. Not rednet: a fixed broadcast channel keeps
  every cc-OS computer within radio range able to see every message, with a
  `from`/`id` envelope so apps can filter out their own transmissions.
]]

local net = {}
net.CHANNEL = 6060
net.REPLY = 6061
net.CHUNK_SIZE = 900

local modem

function net.open()
  modem = peripheral.find("modem")
  if not modem then return nil, "no modem attached" end
  if not modem.isOpen(net.CHANNEL) then modem.open(net.CHANNEL) end
  return modem
end

function net.myName()
  local label = os.getComputerLabel()
  if label and label ~= "" then return label end
  return "PC-" .. os.getComputerID()
end

function net.send(kind, data)
  if not modem then return false end
  modem.transmit(net.CHANNEL, net.REPLY, { t = kind, from = net.myName(), id = os.getComputerID(), data = data })
  return true
end

--- Call with a raw event table. Returns the message payload table if this
--- event is one of ours (and not our own echo), else nil.
function net.parse(ev)
  if ev[1] ~= "modem_message" then return nil end
  local channel, msg = ev[3], ev[5]
  if channel ~= net.CHANNEL then return nil end
  if type(msg) ~= "table" or type(msg.t) ~= "string" then return nil end
  if msg.id == os.getComputerID() then return nil end
  return msg
end

--- Splits `content` into net.send "file_start"/"file_chunk"/"file_end" calls.
function net.sendFile(name, content)
  local id = tostring(os.getComputerID()) .. "-" .. tostring(os.epoch and os.epoch() or math.random(1, 1e9))
  net.send("file_start", { id = id, name = name, size = #content })
  local i = 1
  while i <= #content do
    net.send("file_chunk", { id = id, part = content:sub(i, i + net.CHUNK_SIZE - 1) })
    i = i + net.CHUNK_SIZE
  end
  net.send("file_end", { id = id })
  return id
end

return net

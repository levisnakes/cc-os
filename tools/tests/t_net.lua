-- t_net.lua -- chat send/receive and chunked file transfer, over the mocked modem.

local kernel = require_os("kernel")
local net = require_os("lib.net")

local phase = "start"

local function closeFocused(procs, focusedId)
  local p = nil
  for i = 1, #procs do if procs[i].id == focusedId then p = procs[i] end end
  if not p then return end
  click(1, p.x + p.w - 2, p.y)
end

local function onEvent(ev, procs, focusedId)
  ------------------------------------------------------------------- chat
  if phase == "start" then
    phase = "chat_wait"
    kernel.launch("chat")

  elseif phase == "chat_wait" then
    check(#procs == 1, "chat window open")
    phase = "chat_send"
    for ch in ("hi there"):gmatch(".") do MOCK.push("char", ch) end
    MOCK.push("key", keys.enter)

  elseif phase == "chat_send" and ev[1] == "key" and ev[2] == keys.enter then
    local sent = MOCK.lastSent("chat")
    check(sent ~= nil, "chat sent a message over the modem")
    if sent then eq(sent.body.data.text, "hi there", "sent chat text matches what was typed") end
    phase = "chat_receive"
    MOCK.deliver(net.CHANNEL, net.REPLY, { t = "chat", from = "Bob", id = 999, data = { text = "yo" } })

  elseif phase == "chat_receive" and ev[1] == "modem_message" then
    check(#procs == 1, "chat window survived an incoming message")
    SHOT("chat")
    phase = "chat_close"
    closeFocused(procs, focusedId)

  ------------------------------------------------------------------ share
  elseif phase == "chat_close" and ev[1] == "mouse_up" then
    check(#procs == 0, "chat closed")
    local h = fs.open("outgoing.txt", "w")
    h.write(string.rep("payload-", 200)) -- long enough to force multiple chunks
    h.close()
    phase = "share_wait"
    kernel.launch("share")

  elseif phase == "share_wait" then
    check(#procs == 1, "share window open")
    phase = "share_send"
    for ch in ("outgoing.txt"):gmatch(".") do MOCK.push("char", ch) end
    MOCK.push("key", keys.enter)

  elseif phase == "share_send" and ev[1] == "key" and ev[2] == keys.enter then
    local endMsg = MOCK.lastSent("file_end")
    check(endMsg ~= nil, "share finished sending (saw a file_end)")
    local chunkCount = 0
    for i = 1, #MOCK.ether do
      if type(MOCK.ether[i].body) == "table" and MOCK.ether[i].body.t == "file_chunk" then chunkCount = chunkCount + 1 end
    end
    check(chunkCount > 1, "a 1600-byte file was split into more than one chunk (got " .. chunkCount .. ")")
    SHOT("share_sent")

    -- now simulate someone else sending *us* a file
    phase = "share_receive"
    local content = "incoming file contents, round trip check"
    MOCK.deliver(net.CHANNEL, net.REPLY, { t = "file_start", from = "Bob", id = 999, data = { id = "x1", name = "note.txt", size = #content } })
    MOCK.deliver(net.CHANNEL, net.REPLY, { t = "file_chunk", from = "Bob", id = 999, data = { id = "x1", part = content } })
    MOCK.deliver(net.CHANNEL, net.REPLY, { t = "file_end", from = "Bob", id = 999, data = { id = "x1" } })

  elseif phase == "share_receive" and ev[1] == "modem_message" then
    -- three deliveries were queued; wait for the last (file_end) before checking
    if ev[5] and ev[5].t == "file_end" then
      check(fs.exists("os/data/received/note.txt"), "received file was written to disk")
      if fs.exists("os/data/received/note.txt") then
        local fh = fs.open("os/data/received/note.txt", "r")
        local got = fh.readAll() fh.close()
        eq(got, "incoming file contents, round trip check", "received file content matches what was sent")
      end
      SHOT("share_received")
      phase = "done"
      error("TEST_DONE", 0)
    end
  end
end

MOCK.push("mouse_up", 1, 1, 1) -- harmless kick-off event

local ok, err = pcall(kernel.run, { onEvent = onEvent })
if not ok then
  check(tostring(err):find("TEST_DONE", 1, true) ~= nil, "kernel stopped cleanly: " .. tostring(err))
end
eq(phase, "done", "reached the end of the script")

finish("net")

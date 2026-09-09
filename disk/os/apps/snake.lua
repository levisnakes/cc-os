--[[ snake -- classic snake, arrow keys to steer, R to restart after death. ]]

local M = {}
M.id = "snake"
M.name = "Snake"

function M.run(ctx)
  local api = ctx.api
  local w, h = api.getSize()
  local gx, gy = w, h - 1 -- playfield size; row 1 is the score bar

  local snake, dir, pending, food, score, over, tickId

  local function place(x, y)
    term.setCursorPos(x, y + 1)
  end

  local function randomFood()
    while true do
      local fx, fy = math.random(1, gx), math.random(1, gy)
      local hit = false
      for i = 1, #snake do
        if snake[i].x == fx and snake[i].y == fy then hit = true break end
      end
      if not hit then return { x = fx, y = fy } end
    end
  end

  local function reset()
    local cx, cy = math.ceil(gx / 2), math.ceil(gy / 2)
    snake = { { x = cx, y = cy }, { x = cx - 1, y = cy }, { x = cx - 2, y = cy } }
    dir = { x = 1, y = 0 }
    pending = dir
    score = 0
    over = false
    food = randomFood()
    tickId = os.startTimer(0.3)
  end

  local function draw()
    local T = api.getTheme()
    term.setBackgroundColor(T.bg)
    term.setTextColor(T.fg)
    term.clear()
    term.setCursorPos(2, 1)
    term.write("Score: " .. score .. (over and "   GAME OVER - press R" or ""))

    term.setBackgroundColor(T.ok)
    for i = 1, #snake do
      place(snake[i].x, snake[i].y)
      term.write(" ")
    end
    term.setBackgroundColor(T.err)
    place(food.x, food.y)
    term.write(" ")
  end

  local function step()
    if over then return end
    dir = pending
    local head = snake[1]
    local nx, ny = head.x + dir.x, head.y + dir.y
    if nx < 1 then nx = gx elseif nx > gx then nx = 1 end
    if ny < 1 then ny = gy elseif ny > gy then ny = 1 end

    for i = 1, #snake do
      if snake[i].x == nx and snake[i].y == ny then over = true return end
    end

    table.insert(snake, 1, { x = nx, y = ny })
    if nx == food.x and ny == food.y then
      score = score + 1
      food = randomFood()
    else
      table.remove(snake)
    end
    tickId = os.startTimer(math.max(0.08, 0.3 - score * 0.01))
  end

  reset()
  draw()
  while true do
    local ev = { api.pullEvent() }
    local kind = ev[1]
    if kind == "timer" and ev[2] == tickId then
      step()
    elseif kind == "key" then
      local k = ev[2]
      if k == keys.up and dir.y == 0 then pending = { x = 0, y = -1 }
      elseif k == keys.down and dir.y == 0 then pending = { x = 0, y = 1 }
      elseif k == keys.left and dir.x == 0 then pending = { x = -1, y = 0 }
      elseif k == keys.right and dir.x == 0 then pending = { x = 1, y = 0 }
      elseif k == keys.r and over then reset()
      end
    end
    draw()
  end
end

return M

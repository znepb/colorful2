local bigfont = require("bigfont")
local sha256 = require("sha256")
local logger = require("logger")
local v = "2.0.0"

local x, y, z = gps.locate()

local configFile = fs.open("config.json", "r")
local config = textutils.unserialiseJSON(configFile.readAll())
configFile.close()

local speaker = peripheral.find("speaker")

local seq = 0
local locationCheck
local interactionTimer
local isEnderStorageBusy = false

local m = peripheral.wrap(config.monitor)
local modem = peripheral.wrap(config.modem)
modem.open(config.channel)
local keyFile = fs.open("key", "r")
local key = keyFile.readAll()
keyFile.close()

local net = require("colorfulnet")
local colorNames = {"white", "orange", "magenta", "light_blue", "yellow", "lime", "pink", "gray", "light_gray", "cyan", "purple", "blue", "brown", "green", "red", "black"}
local outlineSelection = {"light_gray", "yellow", "purple", "blue", "orange", "green", "purple", "black", "gray", "blue", "magenta", "light_blue", "orange", "lime", "pink", "gray"}

local function getCCColorName(color)
  if color == "light_blue" then
    return "lightBlue"
  elseif color == "light_gray" then
    return "lightGray"
  end

  return color
end

local function getPrettyName(color)
  color = getCCColorName(color)

  local name = color:match("%u") and color:gsub("%u", " " .. color:match("%u")) or color
  name = name:gsub("^%l", name:match("^%l"):upper())

  return name
end

local function transmit(e, data)
  data.e = e
  data.client = config.name
  data.seq = seq

  modem.transmit(config.channel, config.channel, net.prepareMessage(textutils.serialiseJSON(data), key))
  seq = seq + 1
end

local function awaitEnderStorage()
  if not isEnderStorageBusy then return end
  repeat sleep() until not isEnderStorageBusy
end

m.setCursorPos(2, 2)
m.setBackgroundColor(colors.white)
m.setTextColor(colors.black)
m.setTextScale(0.5)
m.clear()
bigfont.writeOn(m, 1, "Snowflake Colorful", 2, 2)
m.setCursorPos(2, 5)
m.write("Initalizing")
m.setCursorPos(2, 6)
m.write("Net Protocol version: " .. tostring(net.PROTOCOL_VERSION))
m.setCursorPos(2, 7)
m.write("Net Identifier: " .. tostring(net.IDENTIFIER))
m.setCursorPos(2, 8)
m.write("Net Name: " .. config.name)
m.setCursorPos(2, 9)
m.write("Key hash: " .. sha256(key))
m.setCursorPos(2, 10)
m.write("GPS: " .. x .. ", " .. y .. ", " .. z)

m.setCursorPos(2, 11)
for i = 1, 50 do
  m.write(".")
  sleep(0.05)
end

local connected = false
local state = {
  screen = "loading",
  selected = nil,
  color = nil,
  stock = {},
  stacks = 1
}

local function renderHeader()
  local w, h = m.getSize()

  for i = 1, 5 do
    m.setBackgroundColor(colors.gray)
    m.setCursorPos(1, i)
    m.clearLine()
  end
  m.setTextColor(colors.brown)
  bigfont.writeOn(m, 1, "c", 2, 2)
  m.setTextColor(colors.red)
  bigfont.writeOn(m, 1, "o", 5, 2)
  m.setTextColor(colors.orange)
  bigfont.writeOn(m, 1, "l", 8, 2)
  m.setTextColor(colors.yellow)
  bigfont.writeOn(m, 1, "o", 11, 2)
  m.setTextColor(colors.lime)
  bigfont.writeOn(m, 1, "r", 14, 2)
  m.setTextColor(colors.green)
  bigfont.writeOn(m, 1, "f", 17, 2)
  m.setTextColor(colors.cyan)
  bigfont.writeOn(m, 1, "u", 20, 2)
  m.setTextColor(colors.blue)
  bigfont.writeOn(m, 1, "l", 23, 2)
  m.setTextColor(colors.purple)
  bigfont.writeOn(m, 1, ".", 25, 2)
  bigfont.writeOn(m, 1, "k", 27, 2)
  m.setTextColor(colors.magenta)
  bigfont.writeOn(m, 1, "s", 30, 2)
  m.setTextColor(colors.pink)
  bigfont.writeOn(m, 1, "t", 33, 2)

  if state.loggedInUser then
    m.setTextColor(colors.white)
    m.setCursorPos(w - 9 - #state.loggedInUser, 2)
    m.write("Hello, " .. state.loggedInUser .. "!")
    m.setCursorPos(w - #tostring(state.loggedInBalance) - 11, 3)
    m.write("Balance: \164" .. tostring(state.loggedInBalance))

    m.setTextColor(colors.lightGray)
    m.setCursorPos(w - #config.name - #v - 4, 4)
    m.write(config.name .. " @ " .. v)
  else
    m.setTextColor(colors.lightGray)
    m.setCursorPos(w - #config.name - #v - 4, 3)
    m.write(config.name .. " @ " .. v)
  end
end

local function writeCenter(t, offset, y)
  local w, h = m.getSize()
  m.setCursorPos(math.ceil(w / 2 - #t / 2) + offset, y)
  m.write(t)
end

local screens = {
  loading = function()
    renderHeader()
  end,
  select = function(part)
    if part == "header" or part == nil then
      renderHeader()
    end

    local w, h = m.getSize()

    if part == "sidebar" or part == nil then
      for i = 1, math.ceil((h - 6) / 3) do
        m.setBackgroundColor(state.selected == i and colors.white or colors.gray)
        m.setTextColor(state.selected == i and colors.gray or colors.white)
        for y = 1, 3 do
          m.setCursorPos(1, (i * 3) + 2 + y)
          m.write((" "):rep(15))

          if y == 2 and state.stock[i] then
            m.setCursorPos(2, (i * 3) + 2 + y)
            m.write(state.stock[i].nameSidebar)
          end
        end
      end

      if state.hasShulker then
        m.setCursorPos(1, h - 2)
        m.setBackgroundColor(colors.purple)
        m.write((" "):rep(15))

        m.setCursorPos(1, h - 1)
        m.write(" Eject Shulker ")

        m.setCursorPos(1, h)
        m.write((" "):rep(15))
      end
    end

    if part == "selection" or part == "count" or part == nil then
      if state.selected then
        local selected = state.stock[state.selected]

        local anyAvailable = false

        for i, v in pairs(selected.items) do
          if v.count >= 64 then
            anyAvailable = true
            break
          end
        end

        if part == "selection" or part == nil then
          m.setBackgroundColor(colors.white)
          m.setTextColor(colors.gray)
          bigfont.writeOn(m, 1, selected.nameSidebar, (w / 2 - (#selected.nameSidebar * 3) / 2) + 10, 8)

          for i = 0, 15 do
            local x = i % 4
            local y = math.floor(i / 4)

            local topX = w / 2 + x * 8 - 6
            local topY = 11 + (y * 4)

            -- Find item
            local item

            for _, v in pairs(selected.items) do
              if v.item == selected.item:format(colorNames[i + 1]) then
                item = v
              end
            end

            -- Draw background for block
            for y2 = 1, 4 do
              m.setCursorPos(topX, topY + y2)
              m.setBackgroundColor(2 ^ i)
              m.setTextColor(getCCColorName(item.color) == "white" and colors.lightGray or colors.white)
              m.write(item.count < 64 and ("\127"):rep(8) or (" "):rep(8))
            end

            -- Draw selection border if needed

            if state.color and state.color == colors[getCCColorName(item.color)] and item.count >= 64 then
              for y2 = 1, 4 do
                if y2 == 1 then
                  m.setCursorPos(topX, topY + y2)
                  m.setBackgroundColor(2 ^ i)
                  m.setTextColor(colors[getCCColorName(outlineSelection[i + 1])])
                  m.write("\151" .. ("\131"):rep(6))
                  m.setTextColor(2 ^ i)
                  m.setBackgroundColor(colors[getCCColorName(outlineSelection[i + 1])])
                  m.write("\148")
                elseif y2 == 4 then
                  m.setCursorPos(topX, topY + y2)
                  m.setTextColor(2 ^ i)
                  m.setBackgroundColor(colors[getCCColorName(outlineSelection[i + 1])])
                  m.write("\138" .. ("\143"):rep(6) .. "\133")
                else
                  m.setCursorPos(topX, topY + y2)
                  m.setBackgroundColor(2 ^ i)
                  m.setTextColor(colors[getCCColorName(outlineSelection[i + 1])])
                  m.write("\149")

                  m.setCursorPos(topX + 7, topY + y2)
                  m.setTextColor(2 ^ i)
                  m.setBackgroundColor(colors[getCCColorName(outlineSelection[i + 1])])
                  m.write("\149")
                end
              end
            end

            m.setBackgroundColor(2 ^ i)

            -- Set text color depending on background
            if i < 7 then m.setTextColor(colors.black) else m.setTextColor(colors.white) end

            -- Draw stock/cost text
            if item and item.count >= 64 then
              local text = tostring(math.floor(item.count / 64)) .. "s"
              m.setCursorPos(topX + 4 - (#text / 2), topY + 2)
              m.write(text)
              local price = item.cost < 0 and "??" or "\164" .. tostring(math.floor((item.cost * 64) * 10) / 10)
              m.setCursorPos(topX + 4 - (#price / 2), topY + 3)
              m.write(price)
            end
          end
        end

        if part == "count" or part == nil then
          if not anyAvailable then
            m.setBackgroundColor(colors.white)
            m.setTextColor(colors.gray)
            local text = "This item is currently out of stock. Sorry!"
            m.setCursorPos(w / 2 - (#text / 2) + 10, h / 2 + 11)
            m.write(text)
          else
            local selectedColor

            for i, v in pairs(selected.items) do
              if colors[getCCColorName(v.color)] == state.color then
                selectedColor = v
              end
            end

            m.setBackgroundColor(colors.white)
            m.setTextColor(colors.black)
            if selectedColor and selectedColor.count >= 64 then
              local text = (" "):rep(30)
              m.setCursorPos(w / 2 - (#text / 2) + 10, h / 2 + 10)
              m.write(text)
              local text = "Selected item: " .. selected.nameSingle:format(getPrettyName(selectedColor.color))
              m.setCursorPos(w / 2 - (#text / 2) + 10, h / 2 + 10)
              m.write(text)

              m.setBackgroundColor(colors.gray)
              m.setTextColor(colors.white)
              local bgColor = "eee666" .. ("7"):rep(14) .. "555ddd"

              m.setCursorPos(w / 2 - 3, h / 2 + 12)
              m.blit((" "):rep(26), ("f"):rep(26), bgColor)

              m.setCursorPos(w / 2 - 3, h / 2 + 13)
              m.blit(" -  - " .. (" "):rep(14) .. " +  + ", ("0"):rep(26), bgColor)

              m.setCursorPos(w / 2 - 3, h / 2 + 14)
              m.blit((" "):rep(26), ("f"):rep(26), bgColor)

              m.setCursorPos(w / 2 - #(tostring(state.stacks) .. " stacks") / 2 + 10, h / 2 + 13)
              m.write(tostring(state.stacks) .. " stacks")

              m.setTextColor(colors.gray)
              m.setBackgroundColor(colors.white)
              local text = (" "):rep(50)
              m.setCursorPos(w / 2 - (#text / 2) + 10, h / 2 + 16)
              m.write(text)

              local text =  selectedColor.cost == 0 and "Buy now with \\colorful buy" or "Buy now with /pay colorful.kst " .. math.ceil(math.floor((selectedColor.cost * state.stacks * 64) * 10) / 10)
              m.setCursorPos(w / 2 - (#text / 2) + 10, h / 2 + 16)
              m.write(text)

              local canUseBuy = state.loggedInUUID and state.loggedInBalance >= math.floor((selectedColor.cost * state.stacks * 64) * 10) / 10

              if canUseBuy and selectedColor.cost > 0 then
                local text = "Use your balance by using \\colorful buy"
                m.setCursorPos(w / 2 - (#text / 2) + 10, h / 2 + 17)
                m.write(text)
              end

              --m.setBackgroundColor(colors.white)
              --local text = "Or add to cart"
              --m.setCursorPos(w / 2 - (#text / 2) + 10, h / 2 + 17 + (canUseBuy and 1 or 0))
              --m.blit(text, "777bbbbbbbbbbb", "00000000000000")
            end
          end
        end
      else
        m.setTextColor(colors.black)
        m.setBackgroundColor(colors.white)
        writeCenter("Welcome to colorful.kst" .. (state.loggedInUser and ", " .. state.loggedInUser .. "!" or "!"), 9, h / 2)
        m.setTextColor(colors.gray)
        m.setBackgroundColor(colors.white)
        writeCenter("Please select an item from the left.", 8, h / 2 + 1)

        m.setTextColor(colors.lightGray)
        if state.loggedInUser == nil then
          writeCenter("To use Krist from a previous session, use \\colorful login.", 9, h / 2 + 3)
        else
          writeCenter("Deposit by using /pay colorful.kst <amount> deposit=true", 9, h / 2 + 3)
        end
      end
    end
  end,
  pending = function()
    m.setBackgroundColor(colors.white)
    m.clear()
    local w, h = m.getSize()
    renderHeader()
    m.setTextColor(colors.black)
    m.setBackgroundColor(colors.white)
    writeCenter("Your order has been submitted!", 0, h / 2)
    m.setTextColor(colors.gray)
    writeCenter("Please wait here while we prepare your items. This shouldn't take long!", 0, h / 2 + 1)
    writeCenter("Notice: Do not leave the area.", 0, h / 2 + 3)
    writeCenter("The shop may reboot and your items will be lost.", 0, h / 2 + 4)

    if state.queue then
      writeCenter("Position in queue: " .. tostring(state.queue), 0, h / 2 + 6)
    end
  end
}

local function render(part)
  logger.debug("Rendering", tostring(connected))
  if part == nil then
    m.setBackgroundColor(colors.white)
    m.clear()
  end

  if connected == false then
    renderHeader()
    local w, h = m.getSize()
    local t = "Cannot connect to ColorfulNet."
    local t2 = "Attempting to reconnect..."
    m.setBackgroundColor(colors.white)
    m.setTextColor(colors.red)
    m.setCursorPos((w / 2) - (#t / 2), h / 2)
    m.write(t)
    m.setTextColor(colors.lightGray)
    m.setCursorPos((w / 2) - (#t2 / 2), h / 2 + 1)
    m.write(t2)
  elseif state.restocking then
    renderHeader()
    local w, h = m.getSize()
    local t = "colorful.kst is currently restocking"
    local t2 = "This should only take a couple minutes. Sorry about the wait!"
    m.setBackgroundColor(colors.white)
    m.setTextColor(colors.black)
    m.setCursorPos((w / 2) - (#t / 2), h / 2)
    m.write(t)
    m.setTextColor(colors.lightGray)
    m.setCursorPos((w / 2) - (#t2 / 2), h / 2 + 1)
    m.write(t2)

    if state.restockProgress then
      m.setCursorPos((w / 2) - 16, h / 2 + 3)
      m.setTextColor(colors.gray)
      m.write(("\140"):rep(32))
      m.setCursorPos((w / 2) - 16, h / 2 + 3)
      m.setTextColor(colors.green)
      m.write(("\140"):rep(32 * state.restockProgress))
      m.setTextColor(colors.lightGray)
      local t3 = tostring(math.floor(state.restockProgress * 100)) .. "% complete"
      m.setCursorPos((w / 2) - (#t3 / 2), h / 2 + 4)
      m.setTextColor(colors.gray)
      m.write(t3)
    end
  else
    screens[state.screen](part)
  end
end

logger.info("Connecting...")
transmit("login", {
  x = x,
  y = y,
  z = z
})

local lastPing = nil
local checkLastPing = nil
local attemptReconnect = os.startTimer(5)
local isDropping = false

local function disconnect()
  state.loggedInUser = nil
  state.loggedInUUID = nil
  state.loggedInBalance = nil
  if locationCheck then os.cancelTimer(locationCheck) end
  if checkLastPing then os.cancelTimer(checkLastPing) end
  connected = false
  render()
end

local function transmitCurrentSelection()
  if state.selected == nil or state.color == nil or state.stacks == nil then return end

  transmit("selection", {
    color = state.color,
    stacks = state.stacks,
    selected = state.selected
  })
end

local events = {
  ["welcome"] = function(data)
    logger.success("Logged in!")
    transmit("getStock", {})
    lastPing = os.epoch("utc")
    checkLastPing = os.startTimer(20)
    connected = true
    os.cancelTimer(attemptReconnect)
    state.screen = "select"
    state.restocking = data.restocking
    transmitCurrentSelection()
    render()
  end,
  ["ping"] = function()
    logger.debug("Pinged")
    lastPing = os.epoch("utc")
    transmit("pong", {})
  end,
  ["stock"] = function(data)
    state.stock = data.stock
    render()
  end,
  ["close"] = function(data)
    disconnect()
    logger.error("Disconnected by remote: ", data.reason)
    attemptReconnect = os.startTimer(5)
  end,
  ["restockCycle"] = function(data)
    state.restocking = data.restocking
    state.restockProgress = data.restocking and data.progress or false
    render()
  end,
  ["userLogin"] = function(data)
    state.loggedInUser = data.name
    state.loggedInUUID = data.uuid
    state.loggedInBalance = data.balance
    locationCheck = os.startTimer(1)
    render()
  end,
  ["loggedInUpdate"] = function(data)
    state.loggedInBalance = data.balance
    render()
  end,
  ["userLogout"] = function(data)
    state.loggedInUser = nil
    state.loggedInUUID = nil
    state.loggedInBalance = nil
    os.cancelTimer(locationCheck)
    renderHeader()
  end,
  ["purchaseSubmitted"] = function(data)
    state.screen = "pending"
    state.queue = data.queuePos
    render()
  end,
  ["delivery"] = function(data)
    logger.info("Delivery")
    isDropping = true
    local enderStorage = peripheral.wrap(config.enderStorage)
    enderStorage.setFrequency(colors.red, colors.green, colors.blue)

    local function attemptDrop(i)
      turtle.select(i)
      local didDrop = turtle.drop()
      print(didDrop)

      if not didDrop then
        local slotAvailable = -1
        for i = 1, 16 do
          if turtle.getItemCount(i) == 0 then
            slotAvailable = i
            break
          end
        end

        if slotAvailable ~= -1 then
          turtle.select(slotAvailable)
        end

        turtle.dig()
        turtle.drop()
      end
    end

    if state.hasShulker then
      peripheral.wrap(config.cache).pushItems(config.self, 108, 1, 1)
      turtle.select(1)
      turtle.place()
    end

    local storage = peripheral.wrap(config.enderStorage)
    local stacks = data.stacks
    local stacksTransferred = 0
    local slotsFilled = 0

    repeat
      for i, v in pairs(storage.list()) do
        stacksTransferred = stacksTransferred + (storage.pushItems(config.self, i, 64, slotsFilled + 1) / 64)
        slotsFilled = slotsFilled + 1

        if slotsFilled == 16 then
          for i = 1, 16 do
            attemptDrop(i)
          end
          slotsFilled = 0
        end
      end
    until stacksTransferred >= stacks

    for i = 1, 16 do
      attemptDrop(i)
    end

    if state.hasShulker then
      turtle.select(1)
      turtle.dig()
      turtle.drop()
    end

    state.hasShulker = false
    state.screen = "select"
    checkLastPing = os.startTimer(20)
    interactionTimer = os.startTimer(30)
    isDropping = false
    render()
  end
}

state.hasShulker = peripheral.call(config.cache, "list")[108] ~= nil

xpcall(function()
  parallel.waitForAll(function()
    while true do
      local e = {os.pullEvent()}

      if e[1] == "modem_message" then
        local s, channel, replyChannel, message, distance = e[2], e[3], e[4], e[5], e[6]

        if s == config.modem and channel == config.channel then
          local content, err = net.readMessage(message, key)
          if content then
            local data = textutils.unserializeJSON(content.data)
            if data.target == config.name then
              if events[data.e] then
                events[data.e](data)
              else
                logger.warn("Unknown event", data.e)
              end
            end
          else
            logger.info(err)
          end
        end
      elseif e[1] == "timer" then
        if e[2] == checkLastPing then
          if os.epoch("utc") - lastPing > 17500 then
            disconnect()
            transmit("logout", { reason = "no_ping" })
            logger.error("Disconnected: no ping (local, " .. tostring(os.epoch("utc") - lastPing) .. "ms)")
            attemptReconnect = os.startTimer(5)
          end
          checkLastPing = os.startTimer(20)
        elseif e[2] == attemptReconnect then
          logger.info("Connecting...")
          seq = 0
          transmit("login", {
            x = x,
            y = y,
            z = z
          })
          attemptReconnect = os.startTimer(5)
          render()
        elseif e[2] == locationCheck then
          local entities = peripheral.find("manipulator").sense()
          local isUserNearby = false

          for i, v in pairs(entities) do
            if v.id == state.loggedInUUID and math.abs(v.x) < 16 and math.abs(v.y) < 8 and math.abs(v.z) < 16 then
              isUserNearby = true
            end
          end

          if not isUserNearby then
            transmit("userLeft", {})
            state.loggedInBalance = nil
            state.loggedInUser = nil
            state.loggedInUUID = nil
            render("header")
          else
            locationCheck = os.startTimer(1)
          end
        elseif e[2] == interactionTimer then
          state.selected = nil
          render()
        end
      elseif e[1] == "monitor_touch" then
        local s, x, y = e[2], e[3], e[4]
        local w, h = m.getSize()

        interactionTimer = os.startTimer(30)

        if s == config.monitor then
          if x == w and y == h then
            m.setCursorPos(1, 1)
            m.setBackgroundColor(colors.black)
            m.setTextColor(colors.white)
            m.write("State Dump")
            m.setCursorPos(1, 2)
            local y = 3
            for i, v in pairs(state) do
              m.setCursorPos(1, y)
              m.write(tostring(i) .. ": " .. tostring(v))
              y = y + 1
            end
            m.setCursorPos(1, h)
            m.write("Tap to continue")
            os.pullEvent("monitor_touch")
            render()
          elseif x == 1 and y == 1 then
            render()
          end

          if y <= 5 and x <= 35 then
            state.selected = nil
            state.color = nil
            render()
          end

          if state.screen == "select" and x <= 15 then
            for i = 1, math.ceil((h - 6) / 3) do
              if y >= (i * 3) + 3 and y <= (i * 3) + 5 and state.stock[i] then
                state.selected = i
                transmitCurrentSelection()
                render()
              end
            end

            if x >= 1 and x <= 15 and y >= h - 2 and y <= h then
              state.hasShulker = false
              isDropping = true
              peripheral.wrap(config.cache).pushItems(config.self, 108, 1, 1)
              turtle.select(1)
              turtle.drop()
              speaker.playSound("minecraft:entity.item.pickup", 1, 1)
              render()
              sleep(0.55)
              isDropping = false
            end

          elseif state.screen == "select" and state.selected ~= nil then
            for i = 0, 15 do
              local _x = i % 4
              local _y = math.floor(i / 4)

              local topX = math.floor(w / 2 + _x * 8 - 6)
              local topY = 12 + (_y * 4)

              if x >= topX and x <= topX + 8 and y >= topY and y <= topY + 3 then
                state.color = 2 ^ i
                render("selection")
                render("count")
                transmitCurrentSelection()
              end
            end

            m.setCursorPos(w / 2 - 3, h / 2 + 12)
            local bX, bY = math.floor(w / 2 - 3), h / 2 + 12

            local selectedColor
            for i, v in pairs(state.stock[state.selected].items) do
              if colors[getCCColorName(v.color)] == state.color then
                selectedColor = v
              end
            end

            if y >= bY and y <= bY + 2 and selectedColor then
              if x >= bX and x <= bX + 2 then
                state.stacks = math.max(1, state.stacks - 8)
                render("count")
                transmitCurrentSelection()
              elseif x >= bX + 3 and x <= bX + 5 then
                state.stacks = math.max(1, state.stacks - 1)
                render("count")
                transmitCurrentSelection()
              elseif x >= bX + 20 and x <= bX + 22 then
                state.stacks = math.min(state.stacks + 1, 64, selectedColor.count / 64)
                render("count")
                transmitCurrentSelection()
              elseif x >= bX + 23 and x <= bX + 25 then
                state.stacks = math.min(state.stacks + 8, 64, selectedColor.count / 64)
                render("count")
                transmitCurrentSelection()
              end
            end
          end
        end
      end
    end
  end, function()
    while true do
      if isDropping then
        repeat sleep() until not isDropping
        sleep(1.5)
      end

      turtle.select(1)
      turtle.suck()

      local detail = turtle.getItemDetail(1)
      if detail then
        if detail.name == "sc-peripherals:empty_ink_cartridge" then
          local cache = peripheral.wrap(config.cache)
          local found = false
          for i, v in pairs(cache.list()) do
            if v.name == "sc-peripherals:ink_cartridge" then
              cache.pushItems(config.self, i, 1, 2)
              turtle.select(2)
              turtle.drop()
              speaker.playNote("pling", 1, 24)
              found = true
              break
            end
          end

          if not found then
            speaker.playSound("minecraft:entity.villager.no", 1, 1)
            turtle.drop()
            sleep(1)
          end

          if found then
            awaitEnderStorage()
            isEnderStorageBusy = true
            local enderStorage = peripheral.wrap(config.enderStorage)
            enderStorage.setFrequency(colors.magenta, colors.yellow, colors.cyan)
            enderStorage.pullItems(config.self, 1, 1)
            local hasBeenReplenished = false
            local attempts = 0

            while (not hasBeenReplenished and attempts < 5) do
              local list = enderStorage.list()
              for i, v in pairs(list) do
                if v.name == "sc-peripherals:ink_cartridge" then
                  enderStorage.pushItems(config.cache, i, 1)
                  hasBeenReplenished = true
                  speaker.playSound("minecraft:entity.egg.throw", 1, 2)
                  break
                end
              end
              sleep(1)
              attempts = attempts + 1
            end

            isEnderStorageBusy = false
          end
        elseif detail.name:find("shulker_box") then
          speaker.playSound("minecraft:entity.item.pickup", 1, 1)
          peripheral.call(config.cache, "pullItems", config.self, 1, 1, 108)
          state.hasShulker = true
          render()
        else
          turtle.drop(64)
          speaker.playSound("minecraft:entity.villager.no", 1, 1)
          sleep(1)
        end
      end

      sleep(0.5)
    end
  end)
end, function(err)
  m.setBackgroundColor(colors.red)
  m.clear()
  m.setTextColor(colors.white)
  local w, h = m.getSize()
  local win = window.create(m, 2, 2, w - 2, h - 2)
  win.setBackgroundColor(colors.red)
  win.clear()
  win.setTextColor(colors.white)
  term.redirect(win)
  print("colorful.kst has crashed!\n")
  print(err)
  print(debug.traceback())
  print("\nPlease contact znepb or a Snowflake represenative.")
  term.redirect(m)
end)


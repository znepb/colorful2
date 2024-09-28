local logger = require("logger")
local net = require("colorfulnet")
local ail = require("abstractInvLib")
local craftlib = require("craftlib")
local ktwsl = require("ktwsl")
local userdata = require("userdata")
local monitor = peripheral.wrap("left")
monitor.setTextScale(0.5)
local strings = require('cc.strings')
local mW, mH = monitor.getSize()

monitor.setBackgroundColor(colors.white)
monitor.setTextColor(colors.black)
monitor.setCursorPos(mW / 2 - #("Booting...") / 2, mH / 2)
monitor.write("Booting...")

local restockCycle = false
local kristConnected = false
local enderStorageInUse = false
local publicEnderStorageInUse = false

local colorNames = {
  "white", "orange", "magenta", "light_blue",
  "yellow", "lime", "pink", "gray",
  "light_gray", "cyan", "purple", "blue",
  "brown", "green", "red", "black"
}

local function getCCColorName(color)
  if color == "light_blue" then
    return "lightBlue"
  elseif color == "light_gray" then
    return "lightGray"
  end

  return color
end

logger.info("colorful.kst 2.0 coordinator starting...")

local configFile = fs.open("config.json", "r")
local config = textutils.unserializeJSON(configFile.readAll())
configFile.close()
logger.success("configuration loaded")

local keyFile = fs.open("key", "r")
local key = keyFile.readAll()
keyFile.close()
logger.success("key loaded")

local recipiesFile = fs.open("recipies.json", "r")
local recipies = textutils.unserializeJSON(recipiesFile.readAll())
recipiesFile.close()
logger.success("recipies loaded")

local costsFile = fs.open("costs.json", "r")
local costs = textutils.unserializeJSON(costsFile.readAll())
costsFile.close()
logger.success("costs loaded")

local storage = ail(config.storage)
logger.success("storage loaded")
logger.info("storage capacity:", storage.size())

local krist = ktwsl(config.krist.endpoint, config.krist.key)

local modem = peripheral.wrap(config.modem)

local clients = {}

local function awaitEnderStorage()
  if not enderStorageInUse then return end
  repeat sleep() until not enderStorageInUse
end

local function awaitPublicEnderStorage()
  if not publicEnderStorageInUse then return end
  repeat sleep() until not publicEnderStorageInUse
end

local function transmit(e, data, client)
  data.e = e
  data.target = client.name
  data.seq = client.seq

  modem.transmit(config.channel, config.channel, net.prepareMessage(textutils.serialiseJSON(data), key))
  client.seq = client.seq + 1
end

local function broadcast(e, data)
  for i, v in pairs(clients) do
    transmit(e, data, v)
  end
end

local function getClient(client)
  for i, v in pairs(clients) do
    if v.name == client then
      return v, i
    end
  end
end

local function getCost(item)
  if costs[item] then
    return costs[item]
  else
    for i, v in pairs(costs) do
      if item:match(i) then
        return v
      end
    end

    if craftlib.hasRecipeFor(item, recipies) then
      return craftlib.calculateCostPer(item, costs, recipies)
    else
      return -1
    end
  end
end

local function userLogout(client, index)
  if client.loggedInUUID == nil then return end
  local name = userdata.getKey(client.loggedInUUID, "name")
  local ok, err
  if client.loggedInBalance > 1 then
    ok, err = krist.makeTransaction(userdata.getKey(client.loggedInUUID, "name") .. "@switchcraft.kst", math.floor(client.loggedInBalance), "useruuid=" .. client.loggedInUUID .. ";username=" .. userdata.getKey(client.loggedInUUID, "name"))
    if ok then
      userdata.setKey(client.loggedInUUID, "balance", client.loggedInBalance - math.floor(client.loggedInBalance))
    else
      logger.warn("Could not transfer Krist:", err)
    end
  end

  chatbox.tell(name,
    "You have been logged out from colorful.kst. " ..
    ((math.floor(client.loggedInBalance) < 1) and " " or
      (ok and "K" .. math.floor(clients[index].loggedInBalance) .. " has been transferred into your account."
        or "The remaining Krist in your account could not be transferred."))
  )
  clients[index].loggedInUUID = nil
  clients[index].loggedInBalance = nil
end

local function getStock()
  local categories = {}
  local items = storage.listItemAmounts()

  for i, v in pairs(config.stock) do
    local category = {
      item = v.item,
      colors = v.colors,
      nameSidebar = v.nameSidebar,
      nameSingle = v.nameSingle,
      namePlural = v.namePlural,
      items = {}
    }

    local colors = v.colors == "all" and colorNames or v.colors

    for i, c in pairs(colorNames) do
      local itemId = v.item:format(c)
      local count = items[itemId] or 0

      if craftlib.hasRecipeFor(itemId, recipies) then
        local available = craftlib.calculateCountAvailable(itemId, items, recipies)
        count = count + available
      end

      local cost = getCost(itemId)

      local item = {
        item = itemId,
        count = count,
        cost = cost,
        color = c
      }
      table.insert(category.items, item)
    end

    table.insert(categories, category)
  end

  return categories
end

local nonevents = {}
local events = {
  ["login"] = function(data)
    local client = data.client
    logger.info(client, "logged in")

    for i, v in pairs(clients) do
      if v.name == data.client then
        clients[i] = nil
        logger.warn("Client", v.name, "logged in without logging out, resetting")
      end
    end

    table.insert(clients, {
      name = client,
      seq = 1,
      pingTimer = os.startTimer(15),
      pos = {
        data.x, data.y, data.z
      }
    })

    transmit("welcome", {
      restocking = restockCycle
    }, getClient(client))
  end,
  ["getStock"] = function(data)
    transmit("stock", {
      stock = getStock()
    }, getClient(data.client))
  end,
  ["selection"] = function(data)
    local client, index = getClient(data.client)
    clients[index].selection = {
      time = os.epoch("utc"),
      color = data.color,
      stacks = data.stacks,
      selected = data.selected
    }
  end,
  ["pong"] = function(data)
    local client, index = getClient(data.client)
    clients[index].pongReceived = true
  end,
  ["userLeft"] = function(data)
    userLogout(getClient(data.client))
  end
}

modem.open(config.channel)

local function setEnderstorage(item)
  local chest
  local ender = peripheral.wrap(config.enderStorage)

  -- Check to see if this chest already has the item we need
  local list = ender.list()
  local alreadySet = false
  for i, v in pairs(list) do
    if v.name == item then
      alreadySet = true
      break
    end
  end

  -- If not, set it to
  if not alreadySet then
    for i, v in pairs(config.enderStorageConnections) do
      for _, pattern in pairs(v) do
        if item == pattern or item:match(pattern) then
          chest = i
        end
      end
    end

    if not chest then return 0 end

    local color1, color2, color3 = colors.fromBlit(chest:sub(1, 1)), colors.fromBlit(chest:sub(2, 2)), colors.fromBlit(chest:sub(3, 3))
    ender.setFrequency(color1, color2, color3)

    list = ender.list()
  end

  return chest, list
end

local function importFromEnderStorage(item, count)
  local chest, list = setEnderstorage(item)
  local ender = peripheral.wrap(config.enderStorage)

  -- Pull the most items we can / need
  local pulled = 0

  for i, v in pairs(list) do
    if v.name == item then
      pulled = pulled + storage.pullItems(config.enderStorage, i, math.min(64, count - pulled))
    end

    if pulled >= count then break end
  end

  return pulled
end

local function restockItemTo(item, value)
  logger.info("Restocking", value, item)
  awaitEnderStorage()
  enderStorageInUse = true

  local ender = peripheral.wrap(config.enderStorage)

  local maxAttempts = math.ceil(value / 64) + 1
  local totalPulled = 0

  for i = 1, maxAttempts do
    totalPulled = totalPulled + importFromEnderStorage(item, value - totalPulled)
    local waitedTime = 0

    if totalPulled >= value then break end

    repeat
      waitedTime = waitedTime + 0.5
      local list = ender.list()
      for i, v in pairs(list) do
        if v.name == item then break end
      end
      sleep(0.5)
    until waitedTime >= 5
  end

  enderStorageInUse = false

  if totalPulled >= value then
    logger.success("Restocked", item .. ", now at", value)
  else
    logger.warn("Could not fully restock", item .. ":", value - totalPulled, "items short")
  end
end

local function restock()
  logger.info("Beginning restock cycle")
  restockCycle = true
  broadcast("restockCycle", { restocking = restockCycle })

  local totalItemsNeedingRestocked = 0
  local totalRestocked = 0

  for i, v in pairs(config.minimums) do
    if i:match(":%*_") then
      totalItemsNeedingRestocked = totalItemsNeedingRestocked + 16
    else
      totalItemsNeedingRestocked = totalItemsNeedingRestocked + 1
    end
  end

  broadcast("restockCycle", { restocking = restockCycle, progress = 0 / totalItemsNeedingRestocked })

  for i, v in pairs(config.minimums) do
    if i:match(":%*_") then
      for _, c in pairs(colorNames) do
        local item = i:gsub("%*", c)
        local countAvailable = storage.getCount(item)

        if countAvailable < v then
          restockItemTo(item, v - countAvailable)
        end

        totalRestocked = totalRestocked + 1

        broadcast("restockCycle", { restocking = restockCycle, progress = totalRestocked / totalItemsNeedingRestocked })
      end
    else
      local countAvailable = storage.getCount(i)

      if countAvailable < v then
        restockItemTo(i, v - countAvailable)
      end

      totalRestocked = totalRestocked + 1

      broadcast("restockCycle", { restocking = restockCycle, progress = totalRestocked / totalItemsNeedingRestocked })
    end
  end

  logger.success("Restock cycle complete!")
  restockCycle = false
  broadcast("restockCycle", { restocking = restockCycle })
end

local function findShopPlayerIsAt(player)
  local h = http.get("https://dynmap.sc3.io/up/world/SwitchCraft/" .. os.epoch("utc"))
  local data = textutils.unserialiseJSON(h.readAll())
  h.close()

  for i, v in pairs(clients) do
    for _, p in pairs(data.players) do
      if #v.pos == 3 and p.x and p.y and p.z
        and p.world == "SwitchCraft"
        and p.x >= v.pos[1] - 16
        and p.y >= v.pos[2] - 8
        and p.z >= v.pos[3] - 16
        and p.x <= v.pos[1] + 16
        and p.y <= v.pos[2] + 8
        and p.z <= v.pos[3] + 16
      then
        if p.name == player then
          return v.name
        end
      end
    end
  end
end

local function getShopsWithPlayers()
  local h = http.get("https://dynmap.sc3.io/up/world/SwitchCraft/" .. os.epoch("utc"))
  local data = textutils.unserialiseJSON(h.readAll())
  h.close()

  local shops = {}

  for i, v in pairs(clients) do
    for _, p in pairs(data.players) do
      if #v.pos == 3 and p.x and p.y and p.z
        and p.world == "SwitchCraft"
        and p.x >= v.pos[1] - 16
        and p.y >= v.pos[2] - 8
        and p.z >= v.pos[3] - 16
        and p.x <= v.pos[1] + 16
        and p.y <= v.pos[2] + 8
        and p.z <= v.pos[3] + 16
      then
        table.insert(shops, v.name)
        break
      end
    end
  end

  return shops
end

-- Crafting

local jobQueue = {}
local turtleSlotLUT = {1, 2, 3, 5, 6, 7, 9, 10, 11}
local concreteTurtles = {}
local lastId = 0
local stockResendTimer = 0

-- Discover concrete turtles
logger.info("Finding concrete turtles")
peripheral.wrap("back").transmit(2, 2, "discover_concrete")
parallel.waitForAny(function()
  peripheral.wrap("back").open(2)
  while true do
    local _, _, c, _, m = os.pullEvent("modem_message")
    if c == 2 and m:match("concrete%*") then
      local turtle = m:match("concrete%*(turtle_%d+)")
      table.insert(concreteTurtles, turtle)
    end
  end
end, function() sleep(1) end)
peripheral.wrap("back").close(2)
logger.success("Discovered", #concreteTurtles, "turtles")

local function addCraftingJob(store, item, count, priority)
  local job = {
    type = "craft",
    id = lastId + 1,
    deliverTo = store,
    item = item,
    count = count,
    priority = priority
  }

  local insertAt = 1

  for i, v in pairs(jobQueue) do
    if v.priority > priority then
      insertAt = math.max(i, insertAt)
      break
    end
  end

  lastId = lastId + 1
  table.insert(jobQueue, insertAt, job)

  return insertAt
end

local function craftShapeless(delivery, recipe, count)
  local totalItemsShouldPull = math.ceil(count / recipe.result)
  local stacksWillBeCrafted = math.ceil((totalItemsShouldPull * recipe.result) / 64)
  if recipe.craftOneByOne then
    stacksWillBeCrafted = totalItemsShouldPull * recipe.result
  end

  logger.info("Total items should be pulled:", totalItemsShouldPull)
  logger.info("Total stacks that will be crafted:", stacksWillBeCrafted)

  for i = 1, stacksWillBeCrafted do
    logger.info("Crafting stack", i, "of", stacksWillBeCrafted, "one by one:", recipe.craftOneByOne)
    local itemsToPullThisRound = totalItemsShouldPull - ((i - 1) * 64)
    if recipe.craftOneByOne then itemsToPullThisRound = 1 end

    local slot = 1
    for i, v in pairs(recipe.ingredients) do
      for _ = 1, v do
        storage.pushItems(config.crafter, i, itemsToPullThisRound, turtleSlotLUT[slot])
        slot = slot + 1
      end
    end

    peripheral.wrap("back").transmit(2, 2, "craft")
    peripheral.wrap("back").open(2)
    local c, m = nil, nil

    repeat
      _, _, c, _, m = os.pullEvent("modem_message")
    until c == 2 and m == "done"

    peripheral.wrap("back").close(2)

    for i = 1, math.ceil((itemsToPullThisRound * recipe.result) / 64) do
      storage.pullItems(config.crafter, i)
    end
  end

  logger.success("Completed shapeless craft")
end

local function craftConcrete(delivery, recipe, count)
  local powderName = recipe.ingredient

  local roundsNeeded = math.ceil((count / #concreteTurtles) / 64)

  logger.info("Powder:", powderName)
  logger.info("Rounds:", roundsNeeded)

  for i = 1, roundsNeeded do
    local remaining = math.min(count, #concreteTurtles * 64)
    local amountNeededPer = {}

    for i = 1, remaining do
      amountNeededPer[(i % #concreteTurtles) + 1] = (amountNeededPer[(i % #concreteTurtles) + 1] or 0) + 1
    end

    local maxNeeded = 0

    for i, v in pairs(amountNeededPer) do
      storage.pushItems(concreteTurtles[i], powderName, v, 1)
      maxNeeded = math.max(maxNeeded, v)
    end

    logger.info("[CR" .. tostring(i) .. "] Max needed:", maxNeeded)

    for i = 1, maxNeeded do
      peripheral.wrap("back").transmit(2, 2, "place")
      sleep(1)
    end

    for i, v in pairs(concreteTurtles) do
      storage.pullItems(v, 2)
    end
  end

  logger.info("Concrete donesies")
end

local function acquire(delivery, item, count)
  logger.info("Acquiring", count, item)
  local recipe, color = craftlib.findRecipe(item, recipies)

  local amountAvilable = storage.getCount(item)
  local amountNeedToCraft = count - amountAvilable

  -- we already enough
  if amountNeedToCraft <= 0 then return true end

  if recipe == nil then return false end

  -- acquite precursors
  local amountNeeded = amountNeedToCraft / recipe.result
  if recipe.ingredients then
    for i, v in pairs(recipe.ingredients) do
      local success = acquire(delivery, i, math.ceil(amountNeeded * v))
      if not success then return false end
    end
  elseif recipe.ingredient then
    local success = acquire(delivery, recipe.ingredient, math.ceil(amountNeeded))
    if not success then return false end
  end

  logger.info("[" .. item .. "] Precursors acquired")

  -- actually craft the thing
  if recipe.type == "shapeless" then
    craftShapeless(delivery, recipe, amountNeedToCraft)
  elseif recipe.type == "concrete" then
    craftConcrete(delivery, recipe, amountNeedToCraft)
  end

  -- we did it, yay!
  return true
end

local function executeCraftingJob(job)
  logger.info("Started job", job.id)

  acquire(job.deliverTo, job.item, job.count)

  if job.deliverTo then
    awaitEnderStorage()
    enderStorageInUse = true

    local ender = peripheral.wrap(config.enderStorage)
    ender.setFrequency(colors.red, colors.green, colors.blue)

    local c, i = getClient(job.deliverTo)
    clients[i].dontPing = true
    transmit("delivery", {
      stacks = job.count / 64
    }, getClient(job.deliverTo))
    local roundsToDo = math.ceil(job.count / (64 * 27))
    local remaining = job.count
    logger.info("Delivering", roundsNeeded)
    for i = 1, roundsToDo + 1 do
      for j = 1, 27 do
        remaining = remaining - storage.pushItems(config.enderStorage, job.item, math.min(remaining, 64))
        if remaining <= 0 then break end
      end

      repeat sleep() until #ender.list() < 11
    end

    clients[i].dontPing = false
    clients[i].pingTimer = os.startTimer(15)
    logger.info("Job complete!", job.id)

    enderStorageInUse = false
  end

  stockResendTimer = os.startTimer(5)
end

-- Monitoring
-- TODO: make this set in the configuration
local monitor = peripheral.wrap("left")
local recentLogMessages = {}
local logWindow = window.create(monitor, 1, 20, mW, mH - 20)

local function renderMonitoring()
  monitor.setCursorPos(2, 1)
  monitor.setBackgroundColor(colors.lightGray)
  monitor.clearLine()
  monitor.write("colorful.kst v2 Coordinator")

  local y = 1
  logWindow.setBackgroundColor(colors.black)
  logWindow.clear()
  for i, v in pairs(recentLogMessages) do
    local lines = strings.wrap(v.msg, mW)
    logWindow.setTextColor(v.color)
    for i = 1, #lines do
      logWindow.setCursorPos(1, y)
      logWindow.write(lines[i])
      y = y + 1
    end
  end
end

local function checkCartridges()
  local cartridgeCount = storage.getCount("sc-peripherals:ink_cartridge")
  local need = 8 - cartridgeCount

  if need >= 4 then
    local emptyCartCount = storage.getCount("sc-peripherals:empty_ink_cartridge")

    if emptyCartCount > 0 then
      local queuePos = addCraftingJob(nil, "sc-peripherals:ink_cartridge", math.min(need, emptyCartCount), 3)
      logger.info("Added ink cartridge crafting job (queue", queuePos .. ")")
    else
      logger.warn("No empty ink cartridges. Cannot create more")
    end
  end
end

local function checkCartridgeChest(pending, id, colors)
  local enderStorage = peripheral.wrap(id)
  enderStorage.setFrequency(unpack(colors))

  local list = enderStorage.list()
  for i, v in pairs(list) do
    if v and v.name == "sc-peripherals:empty_ink_cartridge" then
      storage.pullItems(id, i)
      pending = pending + 1
    end
  end

  local maxMoveable = storage.getCount("sc-peripherals:ink_cartridge")
  if maxMoveable <= 2 then
    checkCartridges()
  end

  if pending > 0 and maxMoveable > 0 then
    local filled = 0
    for i = 1, math.min(maxMoveable, pending) do
      storage.pushItems(id, "sc-peripherals:ink_cartridge", 1)
      filled = filled + 1
      pending = pending - 1
    end
    logger.info("Refilled", filled, "cartridges")
  elseif pending > 0 and maxMoveable == 0 then
    logger.warn("Not enough ink cartridges for ink filler!")
  end

  publicEnderStorageInUse = false

  return pending
end

stockResendTimer = os.startTimer(5 * 60)

xpcall(function()
  parallel.waitForAll(function()
    while true do
      local e = {os.pullEvent()}

      if e[1] == "modem_message" then
        local s, channel, replyChannel, message, distance = e[2], e[3], e[4], e[5], e[6]

        if channel == 2 then
          os.queueEvent("crafter", message)
        end

        if s == config.modem and channel == config.channel then
          local content, err = net.readMessage(message, key)
          if content then
            local data = textutils.unserializeJSON(content.data)
            if getClient(data.client) then
              getClient(data.client).seq = getClient(data.client).seq + 1
            end

            local isNonEvent = false

            for i, v in pairs(nonevents) do
              if v == data.e then
                isNonEvent = true
                break
              end
            end

            if not isNonEvent then
              if events[data.e] then
                events[data.e](data)
              else
                logger.warn("Unknown event", data.e)
              end
            else
              os.queueEvent("colorful_message", data)
            end
          else
            logger.info(err)
          end
        end
      elseif e[1] == "timer" then
        local timer = e[2]
        for i, v in pairs(clients) do
          if v.pingTimer == timer then
            logger.debug("Pinging", v.name)
            clients[i].pingTimer = os.startTimer(15)

            if v.dontPing ~= true then
              transmit("ping", {ping="hi"}, clients[i])
              clients[i].lastPingSent = os.epoch("utc")
              clients[i].pongByTimer = os.startTimer(2)
              clients[i].pongReceived = false
            end
          elseif v.pongByTimer == timer and not v.pongReceived and v.dontPing ~= true then
            logger.warn("Client", v.name, "disconnected: no ping")
            transmit("close", {
              reason = "no_pong"
            }, v)
            clients[i] = nil
          end
        end

        if timer == stockResendTimer then
          broadcast("stock", {
            stock = getStock()
          })
          stockResendTimer = os.startTimer(5 * 60)
        end
      elseif e[1] == "websocket_success" then
        if e[2]:find("/ws.krist.dev/ws/gateway") then
          logger.success("Krist connected!")
          kristConnected = true
          broadcast("krist", { connected = kristConnected })
        end
      elseif e[1] == "krist_stop" then
        logger.warn("Krist disconnected")
        kristConnected = false
        broadcast("krist", { connected = kristConnected })
      elseif e[1] == "krist_transaction" then
        -- 2: name, 3: sender, 4: value,
        local returnAddress, value, ev = e[3], e[4], e[5]

        if ev.to == config.krist.address then
          local data = krist.parseMetadata(ev.metadata)
          local shopsWithPlayers = getShopsWithPlayers()

          local uuid
          local username

          -- Find UUID or username
          if data.useruuid or data.username or data.recipient then
            uuid = data.useruuid
            if (data.username or data.recipient) and uuid == nil then
              uuid = userdata.getUUIDFromUsername(data.username or data.recipient:gsub("@colo[u]?rful.kst$", ""))
            end

            if uuid == nil then
              krist.makeTransaction(returnAddress, value, "message=Could not find a user to deposit to. Please try providing a useruuid field instead of a username field.")
            else
              username = (data.username or data.recipient):match("^([%a%d%-%_]+)@") or userdata.getKey(uuid, "name")
            end
          end

          -- If nethier were found, throw an error
          if not uuid or not username then
            krist.makeTransaction(returnAddress, value, "message=Could not find a user to deposit to. If you are trying to deposit, please provide a useruuid or username field, or provide a username in the recipient field (e.g. znepb@colorful.kst). Direct purchases may only be done in-game.")
          end

          -- Update username & uuid if necessary (only trust SwitchCraft)
          if uuid and username and returnAddress:match("switchcraft.kst$") then
            userdata.setKey(uuid, "name", username)
          end

          -- Check that this was sent from a SwitchCraft address, and it was not a deposit
          if returnAddress:match("switchcraft.kst$") and data.deposit == nil then
            local shop = findShopPlayerIsAt(username)

            -- Find if the user is at a shop.
            if shop then
              local client, index = getClient(shop)

              if client.selection then
                local stock = getStock()

                local selectedColor
                for i, v in pairs(stock[client.selection.selected].items) do
                  if colors[getCCColorName(v.color)] == client.selection.color then
                    selectedColor = v
                  end
                end

                local minimumCost = (math.floor((selectedColor.cost * 64) * 10) / 10) * client.selection.stacks
                if value >= minimumCost then
                  local remaining = value - minimumCost

                  if remaining >= 1 then
                    krist.makeTransaction(returnAddress, math.floor(remaining), "message=Here are the remaining funds from your purchase!")
                    remaining = remaining - math.floor(remaining)
                  end

                  if remaining > 0 then
                    userdata.setKey(uuid, "balance", function(balance)
                      return (balance or 0) + remaining
                    end)
                  end

                  local queuePos = addCraftingJob(shop, selectedColor.item, client.selection.stacks * 64, 5)
                  transmit("purchaseSubmitted", { queuePos = queuePos }, client)

                  clients[index].loggedInBalance = remaining
                  userLogout(client, index)
                  transmit("userLogout", {}, client)
                else
                  krist.makeTransaction(returnAddress, value, "message=You paid too little for this item. Please pay the full amount of K" .. math.ceil(minimumCost) .. ".")
                end
              else
                krist.makeTransaction(returnAddress, value, "message=Nothing is selected. Please choose an item and try again. If you are trying to deposit, please pass `deposit=true` in the metadata field.")
              end
            else
              krist.makeTransaction(returnAddress, value, "message=It looks like you're not near any colorful.kst locations right now. If you are trying to deposit, please pass `deposit=true` in the metadata field.")
            end
          else
            -- Deposits - may be done by in-game players by setting deposit=true, or by external wallets.
            if uuid then
              userdata.setKey(uuid, "balance", function(balance)
                return (balance or 0) + value
              end)

              local wasLoggedIn = false
              for i, v in pairs(clients) do
                if v.loggedInUUID == uuid then
                  clients[i].loggedInBalance = clients[i].loggedInBalance + value
                  transmit("loggedInUpdate", {
                    uuid = uuid,
                    name = username,
                    balance = clients[i].loggedInBalance
                  }, v)
                  wasLoggedIn = true
                  break
                end
              end

              if wasLoggedIn == false and returnAddress:match("switchcraft.kst$") == nil then
                chatbox.tell(username, "K" .. value .. " was deposited into your colorful.kst account by " .. returnAddress)
              end

              logger.info(returnAddress, "deposited", value, "Krist (" .. username .. ")")
            end
          end
        end
      elseif e[1] == "command" then
        local user, command, args, data = e[2], e[3], e[4], e[5]
        local uuid = data.user.uuid

        if command == "colorful" then
          if args[1] == nil then
            chatbox.tell(user, "**Welcome to colorful.kst!** Please log in with \\colorful login.")
          elseif args[1] == "login" then
            local shop = findShopPlayerIsAt(user)

            if shop then
              local client, index = getClient(shop)

              if client.loggedInUUID then
                chatbox.tell(user, "Another user is currently using this shop. Please try again later.")
              else
                chatbox.tell(user, "You are now logged in at " .. shop .. ".")

                if userdata.getKey(uuid, "name") == nil or userdata.getKey(uuid, "name") ~= user then
                  userdata.setKey(uuid, "name", user)
                end

                transmit("userLogin", {
                  uuid = uuid,
                  name = user,
                  balance = userdata.getKey(uuid, "balance") or 0
                }, client)

                clients[index].loggedInUUID = uuid
                clients[index].loggedInBalance = userdata.getKey(uuid, "balance") or 0
              end
            else
              chatbox.tell(user, "It doesn't appear you're near a shop. Please visit one of our colorful.kst locations, and try again.")
            end
          elseif args[1] == "logout" or args[1] == "exit" then
            for i, v in pairs(clients) do
              if v.loggedInUUID == uuid then
                userLogout(v, i)
                transmit("userLogout", {}, v)
              end
            end
          elseif args[1] == "buy" then
            local shop = findShopPlayerIsAt(user)

            -- Find if the user is at a shop.
            if shop then
              local client, index = getClient(shop)

              if client.selection then
                local stock = getStock()

                local selectedColor
                for i, v in pairs(stock[client.selection.selected].items) do
                  if colors[getCCColorName(v.color)] == client.selection.color then
                    selectedColor = v
                  end
                end

                local accountBalance = userdata.getKey(uuid, "balance") or 0
                local minimumCost = (math.floor((selectedColor.cost * 64) * 10) / 10) * client.selection.stacks

                if accountBalance >= minimumCost then
                  local remaining = accountBalance - minimumCost
                  userdata.setKey(uuid, "balance", function(balance)
                    return remaining
                  end)

                  local queuePos = addCraftingJob(shop, selectedColor.item, client.selection.stacks * 64, 5)
                  transmit("purchaseSubmitted", { queuePos = queuePos }, client)

                  clients[index].loggedInBalance = remaining
                  userLogout(client, index)
                  transmit("userLogout", {}, client)
                else
                  chatbox.tell(user, "There are insufficent funds on your account, you need K" .. minimumCost - accountBalance .. " more. You can deposit this amount by using `/pay colorful.kst " .. tostring(math.ceil(minimumCost - accountBalance)) .. " deposit=true`.")
                end
              else
                chatbox.tell(user, "There isn't anything selected. Please choose an item and try again.")
              end
            else
              chatbox.tell(user, "It doesn't appear you're near a shop. Please visit one of our colorful.kst locations, and try again.")
            end
          end
        end
      elseif e[1] == "log" then
        table.insert(recentLogMessages, 1, {
          color = e[2],
          msg = e[3]
        })

        if #recentLogMessages == 50 then
          table.remove(recentLogMessages, 50)
        end
      end
    end
  end, function()
    restock()
  end, function()
    krist.subscribeAddress("ka60tvi5xe")
    krist.subscribeAddress("colorful.kst")
    krist.subscribeAddress("colourful.kst")
    while true do
      krist.start()
      sleep(10)
    end
  end, function()
    local s = 0
    while true do
      renderMonitoring()

      if s % 30 == 0 then
        checkCartridges()
      end

      if jobQueue[1] and jobQueue[1].type == "craft" then
        local id = jobQueue[1].id
        executeCraftingJob(jobQueue[1])
        for i, v in pairs(jobQueue) do
          if v.id == id then
            table.remove(jobQueue, i)
            break
          end
        end
      end
      s = s + 0
      sleep(1)
    end
  end, function()
    -- Public
    local cartridgesPending = 0
    while true do
      awaitPublicEnderStorage()
      publicEnderStorageInUse = true
      cartridgesPending = checkCartridgeChest(cartridgesPending, config.publicEnderStorage, {colors.cyan, colors.magenta, colors.yellow})
      publicEnderStorageInUse = false
      sleep(1)
    end
  end, function()
    -- Internal
    local cartridgesPending = 0
    while true do
      awaitEnderStorage()
      enderStorageInUse = true
      cartridgesPending = checkCartridgeChest(cartridgesPending, config.enderStorage, {colors.magenta, colors.yellow, colors.cyan})
      enderStorageInUse = false
      sleep(1)
    end
  end)

end, function(err)
  logger.fatal(err)
  print(debug.traceback())

  broadcast("close", {})
  krist.stop()
  os.pullEvent("krist_stop")
  logger.info("Closed krist")
  monitor.setBackgroundColor(colors.red)
  monitor.setTextColor(colors.black)
  monitor.setCursorPos(mW / 2 - #("Stopped") / 2, mH / 2)
  monitor.write("Stopped")
end)


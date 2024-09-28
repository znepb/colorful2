local chest = "minecraft:chest_4774"
local name = peripheral.wrap("back").getNameLocal()
local modem = peripheral.wrap("back")

modem.open(1000)

while true do
  local _, _, _, _, m = os.pullEvent("modem_message")

  if m.act == "pull" then
    peripheral.call(chest, "pushItems", name, 1, 1, 1)
  elseif m.act == "place" then
    turtle.select(1)
    turtle.place()
  elseif m.act == "dig" then
    turtle.select(2)
    turtle.dig()
  elseif m.act == "push" then
    peripheral.call(chest, "pullItems", name, 2, nil, 2)
  elseif m.act == "update" then
    local f = fs.open("concrete.new.lua", "w")
    f.write(m.data)
    f.close()
    os.reboot()
  end
end

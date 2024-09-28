local modem = peripheral.wrap("back")
modem.open(2)

while true do
  local c, m
  repeat
    _, _, c, _, m = os.pullEvent("modem_message")
  until c == 2 and m == "craft"
  turtle.select(1)
  turtle.craft()
  sleep(0.1)
  print("Crafted")
  modem.transmit(2, 2, "done")
end
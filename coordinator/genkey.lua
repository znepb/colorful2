local key = ""

for i = 1, 32 do
  key = key .. string.char(math.random(0, 255))
end

local f = fs.open("key", "w")
f.write(key)
f.close()
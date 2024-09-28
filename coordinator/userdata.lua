local function readUserdata()
  if fs.exists("userdata.json") then
    local f = fs.open("userdata.json", "r")
    local data = textutils.unserialiseJSON(f.readAll())
    f.close()
    return data
  else
    return {}
  end
end

local function getUUIDFromUsername(username)
  local data = readUserdata()

  for i, v in pairs(data) do
    if v.name == username then
      return i
    end
  end
end

local function getKey(uuid, key)
  local data = readUserdata()

  if data[uuid] then
    return data[uuid][key]
  else
    return nil
  end
end

local function setKey(uuid, key, value)
  local data = readUserdata()

  if data[uuid] == nil then
    data[uuid] = {}
  end

  if type(value) == "function" then
    value = value(getKey(uuid, key))
  end

  data[uuid][key] = value

  local f = fs.open("userdata.json", "w")
  f.write(textutils.serialiseJSON(data))
  f.close()

  return data
end

local function listKeys(uuid)
  local data = readUserdata()
  if data[uuid] then
    return data[uuid]
  end

  return {}
end

return {
  getKey = getKey,
  setKey = setKey,
  listKeys = listKeys,
  getUUIDFromUsername = getUUIDFromUsername
}
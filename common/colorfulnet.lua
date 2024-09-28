local chacha = require('chacha20')
local sha256 = require('sha256')
local PROTOCOL_VERSION = 1
local IDENTIFIER = "SFCOLORFULNET2"
local timeAllowance = 1000

local function stringToTable(s)
  local t = {}
  for i = 1, #s do
    table.insert(t, string.byte(s:sub(i, i)))
  end
  return t
end

local function tableToString(t)
  local s = ""
  for i, v in pairs(t) do
    s = s .. string.char(v)
  end
  return s
end

local function generateNonce()
  local n = {}
  for i = 1, 12 do n[#n+1] = math.random(0, 255) end
  return n
end

local function reduceHash(s)
  return s:gsub("%x%x", function(c) return string.char(tonumber(c, 16)) end)
end

local function expandHash(s)
  return ("%02x"):rep(32):format(s:byte(1, 32))
end

local function prepareMessage(msg, key)
  local time = os.epoch('utc')
  local nonce = generateNonce()
  local keyHash = reduceHash(sha256(tostring(time) .. key .. tableToString(nonce)))

  local final = IDENTIFIER .. string.pack("<I2", PROTOCOL_VERSION) .. string.pack("<I8", time) .. tableToString(nonce) .. keyHash
  final = final .. tableToString(chacha.crypt(msg, stringToTable(key), nonce))
  final = reduceHash(sha256(final)) .. final
  return final
end

local function readMessage(msg, key)
  local received = os.epoch("utc")

  -- Check identifier
  local identifier = msg:sub(33, 46)
  if identifier ~= IDENTIFIER then return false, "Invalid identifier" end

  -- Check version
  local version = string.unpack("<I2", msg:sub(47, 48))
  if version ~= PROTOCOL_VERSION then return false, "Invalid protocol version " .. (version < PROTOCOL_VERSION and "(too old)" or "(new)") end

  -- Check time
  local time = string.unpack("<I8", msg:sub(49, 56))
  if os.epoch("utc") - time > timeAllowance then return false, "Too late (" .. (os.epoch("utc") - time) .. ")" end

  -- Get nonce
  local nonceString = msg:sub(57, 68)

  -- Check key
  local keyHash = expandHash(msg:sub(69, 100))
  if sha256(tostring(time) .. key .. nonceString) ~= keyHash then return false, "Bad key hash" end

  -- Check first 32 bytes data hash
  local data = msg:sub(101, -1)
  local main = msg:sub(33, -1)
  if sha256(main) ~= expandHash(msg:sub(1, 32)) then return false, "Bad main hash" end

  return {
    identifier = identifier,
    version = version,
    sent = time,
    received = received,
    delay = received - time,
    nonce = nonceString,
    data = tableToString(chacha.crypt(data, stringToTable(key), stringToTable(nonceString)))
  }
end

return {
  prepareMessage = prepareMessage,
  readMessage = readMessage,
  PROTOCOL_VERSION = PROTOCOL_VERSION,
  IDENTIFIER = IDENTIFIER
}
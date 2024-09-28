local function log(text, t, color)
  term.setTextColor(color)
  print(("[%s] [%s] %s"):format(t, os.date("%X"), text))
end

local function success(...)
  log(table.concat({...}, " "), "YIPPEE", colors.lime)
end

local function warn(...)
  log(table.concat({...}, " "), "BOO", colors.yellow)
end

local function error(...)
  log(table.concat({...}, " "), "BOOO", colors.red)
end

local function fatal(...)
  log(table.concat({...}, " "), "BOOOO", colors.purple)
end

local function info(...)
  log(table.concat({...}, " "), "INFO", colors.white)
end

local function debug(...)
  if settings.get("colorful.debugDisabled") == true then return end
  log(table.concat({...}, " "), "DBG", colors.gray)
end

return {
  success = success,
  warn = warn,
  error = error,
  info = info,
  debug = debug
}
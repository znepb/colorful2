local function log(texts, t, color)
  term.setTextColor(color)
  local msg = ("[%s] [%s]"):format(t, os.date("%X"))
  print(msg, unpack(texts))
  os.queueEvent("log", color, msg)
end

local function success(...)
  log({ ... }, "YIPPEE", colors.lime)
end

local function warn(...)
  log({ ... }, "BOO", colors.yellow)
end

local function error(...)
  log({ ... }, "BOOO", colors.red)
end

local function fatal(...)
  log({ ... }, "BOOOO", colors.purple)
end

local function info(...)
  log({ ... }, "INFO", colors.white)
end

local function debug(...)
  if settings.get("colorful.debugDisabled") == true then return end
  log({ ... }, "DBG", colors.gray)
end

return {
  success = success,
  warn = warn,
  error = error,
  info = info,
  debug = debug,
  fatal = fatal
}
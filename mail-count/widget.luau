--!strict
-- Unread mail count from an arbitrary shell command.

local count = 0
local state = "loading" -- "loading" | "ok" | "error"
local errorText = ""
local running = false
local nextPoll = 0

local function cfgString(key: string): string
  local v = noctalia.getConfig(key)
  return if type(v) == "string" then v else ""
end

local function render()
  local hide = noctalia.getConfig("hideWhenZero") and count == 0 and state ~= "error"
  barWidget.setVisible(not hide)
  if hide then
    return
  end
  local color = if state == "error" then "error" else cfgString("iconColor")
  barWidget.setGlyph(if state == "error" then "mail-exclamation" elseif count > 0 then "mail" else "mail-opened")
  barWidget.setGlyphColor(color)
  barWidget.setColor(color)
  -- Like v4's auto-hiding pill: the number only shows with unread mail.
  barWidget.setText(if count > 0 then tostring(count) else "")
  if state == "error" then
    barWidget.setTooltip(errorText)
  else
    barWidget.clearTooltip()
  end
end

local function refresh()
  if running then
    return
  end
  running = true
  nextPoll = os.time() + noctalia.getConfig("pollInterval")
  noctalia.runAsync(cfgString("countCommand"), function(res: CommandResult)
    running = false
    local n = tonumber(noctalia.string.trim(res.stdout))
    if res.exitCode ~= 0 then
      state = "error"
      errorText = noctalia.string.trim(res.stderr)
      if errorText == "" then
        errorText = "exit " .. tostring(res.exitCode)
      end
    elseif n == nil then
      state = "error"
      errorText = "non-numeric output: " .. res.stdout
    else
      state = "ok"
      count = n
    end
    if state == "error" then
      noctalia.log("mail-count: " .. errorText)
    end
    render()
  end, 30000)
end

function update()
  if os.time() >= nextPoll then
    refresh()
  end
end

function onClick()
  local cmd = cfgString("clickCommand")
  if noctalia.string.trim(cmd) ~= "" then
    noctalia.runAsync({ "sh", "-lc", cmd })
  end
end

function onRightClick()
  refresh()
end

function onIpc(event: string, _payload: string?)
  if event == "refresh" then
    refresh()
  end
end

noctalia.setUpdateInterval(1000)
render()
refresh()

--!strict
-- Takes views from the assistant over IPC and drives the panel through
-- noctalia.state "view". The view comes as a file path: a route does not fit
-- an IPC payload.

local types = require("./types.luau")
type View = types.View

local PANEL = "mic92/voice-assistant:view"

local view: View? = nil
local expiresAt = 0
local opening = false

local function publish(next: View?)
  view = next
  local timeout = noctalia.getConfig("timeoutSec")
  expiresAt = os.time() + (if type(timeout) == "number" then timeout else 45)
  noctalia.state.set("view", next)
  -- The panel closes itself when the view goes away; only open it here.
  if next ~= nil and not noctalia.state.get("open") and not opening then
    opening = true
    noctalia.togglePanel(PANEL)
  end
end

local function show(path: string)
  local raw, err = noctalia.readFile(path)
  if raw == nil then
    noctalia.log("voice-assistant: " .. tostring(err))
    return
  end
  local decoded: any, jsonErr = noctalia.json.decode(raw)
  if type(decoded) ~= "table" or type(decoded.title) ~= "string" or type(decoded.items) ~= "table" then
    noctalia.log("voice-assistant: not a view: " .. tostring(jsonErr))
    return
  end
  publish(decoded)
end

noctalia.state.watch("open", function(open: any)
  if open then
    opening = false
  end
end)

-- Reading the panel keeps it: the timeout restarts when the pointer leaves.
noctalia.state.watch("hover", function(hover: any)
  if view ~= nil and not hover then
    publish(view)
  end
end)

function onIpc(event: string, payload: string?)
  if event == "show" and payload ~= nil then
    show(noctalia.string.trim(payload))
  elseif event == "hide" then
    publish(nil)
  end
end

noctalia.setUpdateInterval(1000)

function update()
  if view ~= nil and os.time() >= expiresAt and not noctalia.state.get("hover") then
    publish(nil)
  end
end

--!strict
-- Watches fprintd on the system bus and drives the cue panel through
-- noctalia.state "cue". gdbus monitor lines look like:
--   /net/reactivated/Fprint/Device/0: net.reactivated.Fprint.Device.VerifyFingerSelected ('right-index-finger',)
--   /net/reactivated/Fprint/Device/0: net.reactivated.Fprint.Device.VerifyStatus ('verify-match', true)

local PANEL = "mic92/fprint-notify:cue"
-- Long enough to read, short enough not to linger over the next prompt.
local RESULT_SEC = 2

type Cue = { kind: string, title: string, body: string }

local cue: Cue? = nil
local expiresAt = 0
local opening = false
local restartAt: number? = nil

local function pretty(s: string): string
  return (s:gsub("^verify%-", ""):gsub("%-", " "))
end

local function publish(next: Cue?, ttl: number)
  cue = next
  expiresAt = os.time() + ttl
  noctalia.state.set("cue", next)
  -- The panel closes itself when the cue goes away; only open it here.
  if next ~= nil and not noctalia.state.get("open") and not opening then
    opening = true
    noctalia.togglePanel(PANEL)
  end
end

noctalia.state.watch("open", function(open: any)
  if open then
    opening = false
  end
end)

local function onStarted(finger: string)
  publish(
    { kind = "waiting", title = noctalia.tr("touch-sensor"), body = pretty(finger) },
    noctalia.getConfig("staleTimeoutSec")
  )
end

local function onStatus(result: string, done: boolean)
  if not done then
    -- Retryable: swipe too short, finger not centered, ...
    publish(
      { kind = "retry", title = pretty(result), body = noctalia.tr("try-again") },
      noctalia.getConfig("staleTimeoutSec")
    )
  elseif result == "verify-match" then
    if noctalia.getConfig("showSuccessToast") then
      publish({ kind = "success", title = noctalia.tr("authenticated"), body = "" }, RESULT_SEC)
    else
      publish(nil, 0)
    end
  elseif result == "verify-no-match" then
    publish({ kind = "fail", title = noctalia.tr("not-recognized"), body = "" }, RESULT_SEC)
  else
    -- disconnected / unknown error: PAM reports it in the terminal.
    publish(nil, 0)
  end
end

local function onLine(line: string)
  if line == "__exit" then
    -- fprintd restarted or the bus dropped; reconnect from update().
    restartAt = os.time() + 1
    return
  end
  if line:find("VerifyFingerSelected", 1, true) then
    onStarted(line:match("%('([^']+)'") or "")
  elseif line:find("VerifyStatus", 1, true) then
    local result, done = line:match("%('([^']+)',%s*(%a+)%)")
    if result ~= nil then
      onStatus(result, done == "true")
    end
  end
end

local function startMonitor()
  restartAt = nil
  -- No --object-path: watch every reader without enumerating devices first.
  noctalia.runStream("gdbus monitor --system --dest net.reactivated.Fprint; echo __exit", onLine)
end

noctalia.setUpdateInterval(500)

function update()
  local now = os.time()
  if restartAt ~= nil and now >= restartAt then
    startMonitor()
  end
  -- A PAM client that dies without a final VerifyStatus would leave the
  -- cue stuck.
  if cue ~= nil and now >= expiresAt then
    if cue.kind == "waiting" or cue.kind == "retry" then
      noctalia.log("fprint-notify: verify stuck in progress, clearing")
    end
    publish(nil, 0)
  end
end

startMonitor()

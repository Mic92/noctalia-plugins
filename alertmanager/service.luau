--!strict
-- Polls Alertmanager and publishes a pre-sorted, pre-filtered snapshot in
-- noctalia.state "alerts" for the widget and panel.
-- IPC: noctalia msg plugin mic92/alertmanager:service all refresh|toggle

type Alert = { name: string, severity: string, host: string, text: string, url: string }
type Snapshot = { state: string, error: string, active: { Alert }, silenced: { Alert } }

local PANEL = "mic92/alertmanager:panel"

local inFlight = false
local nextPoll = 0

local function cfgString(key: string): string
  local v = noctalia.getConfig(key)
  return if type(v) == "string" then v else ""
end

local function baseUrl(): string
  return (cfgString("alertmanagerUrl"):gsub("/+$", ""))
end

-- generatorURL points at Prometheus' internal address; rewrite its origin.
local function rewriteUrl(url: string): string
  local prom = cfgString("prometheusUrl"):gsub("/+$", "")
  if prom == "" then
    return url
  end
  return (url:gsub("^https?://[^/]+", prom, 1))
end

local function isMuted(status: any): boolean
  local function nonEmpty(t: any): boolean
    return type(t) == "table" and #t > 0
  end
  return nonEmpty(status.silencedBy) or nonEmpty(status.inhibitedBy) or nonEmpty(status.mutedBy)
end

local function byNameHost(a: Alert, b: Alert): boolean
  local an, bn = a.name:lower(), b.name:lower()
  if an ~= bn then
    return an < bn
  end
  return a.host:lower() < b.host:lower()
end

local function publish(snap: Snapshot)
  noctalia.state.set("alerts", snap)
end

local function previous(): Snapshot
  local s = noctalia.state.get("alerts")
  if s ~= nil then
    return s
  end
  return { state = "loading", error = "", active = {}, silenced = {} }
end

local function fail(msg: string)
  local snap = previous()
  noctalia.log("alertmanager: " .. msg)
  publish({ state = "error", error = msg, active = snap.active, silenced = snap.silenced })
end

local function parse(body: string)
  local raw: any, err = noctalia.json.decode(body)
  if type(raw) ~= "table" then
    fail("parse error: " .. tostring(err))
    return
  end
  local ignored: { [string]: boolean } = {}
  local list = noctalia.getConfig("ignoreAlerts")
  if type(list) == "table" then
    for _, n in ipairs(list) do
      ignored[n] = true
    end
  end
  local active: { Alert } = {}
  local silenced: { Alert } = {}
  for _, a in ipairs(raw) do
    local labels = a.labels or {}
    local ann = a.annotations or {}
    local status = a.status or {}
    local name = labels.alertname or "Unknown"
    if not ignored[name] and status.state ~= "unprocessed" then
      local alert: Alert = {
        name = name,
        severity = labels.severity or "warning",
        host = labels.host or labels.instance or "",
        text = ann.description or ann.summary or "",
        url = if type(a.generatorURL) == "string" then rewriteUrl(a.generatorURL) else "",
      }
      if isMuted(status) then
        table.insert(silenced, alert)
      elseif status.state == "active" then
        table.insert(active, alert)
      end
    end
  end
  table.sort(active, byNameHost)
  table.sort(silenced, byNameHost)
  publish({ state = "ok", error = "", active = active, silenced = silenced })
end

local function fetch()
  if inFlight then
    return
  end
  inFlight = true
  nextPoll = os.time() + noctalia.getConfig("pollInterval")
  local ok = noctalia.http({ url = baseUrl() .. "/api/v2/alerts" }, function(resp: HttpResponse)
    inFlight = false
    if not resp.ok then
      fail("cannot reach " .. baseUrl())
    elseif resp.status ~= 200 then
      fail("HTTP " .. tostring(resp.status))
    else
      parse(resp.body)
    end
  end)
  if not ok then
    inFlight = false
    fail("request not started (offline mode?)")
  end
end

function update()
  if os.time() >= nextPoll then
    fetch()
  end
end

function onConfigChanged()
  fetch()
end

function onIpc(event: string, _payload: string?)
  if event == "refresh" then
    fetch()
  elseif event == "toggle" then
    noctalia.togglePanel(PANEL)
  end
end

-- Widget and panel ask for a refresh through state; entries can't call
-- each other directly.
noctalia.state.watch("refresh", function(_v: any)
  fetch()
end)

noctalia.setUpdateInterval(1000)
publish(previous())
fetch()

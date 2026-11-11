--!strict
-- Bar icon with the number of lit outputs. Shows the revert countdown while
-- a change is unconfirmed and flashes after a hotplug so a dock connect is
-- noticed.

local types = require("./types.luau")
type Snap = types.Snap

local HOTPLUG_FLASH_MS = 4000

local snap: Snap? = nil

local function send(op: string, arg: any?)
  noctalia.state.set("cmd", { op = op, arg = arg, seq = noctalia.nowMs() })
end

local function render()
  local s = snap
  if s == nil then
    barWidget.setGlyph("loader")
    return
  end
  local lit = 0
  local rows = {}
  for _, o in s.outputs do
    if o.enabled then
      lit += 1
      table.insert(rows, { key = o.name, value = `{o.mode} ×{o.scale}` })
    else
      table.insert(rows, { key = o.name, value = noctalia.tr("panel.off") })
    end
  end
  if s.kanshi.enabled and s.kanshi.active ~= "" then
    table.insert(rows, { key = noctalia.tr("panel.kanshi"), value = s.kanshi.active })
  end

  local color = noctalia.getConfig("iconColor")
  local flashing = noctalia.nowMs() - s.hotplugMs < HOTPLUG_FLASH_MS
  if s.state == "error" then
    barWidget.setGlyph("device-desktop-exclamation")
    color = "error"
    barWidget.setTooltip(s.error)
  else
    barWidget.setGlyph(if lit > 1 then "devices-pc" else "device-desktop")
    barWidget.setTooltip(rows)
  end
  if s.revertLeft > 0 then
    color = "error"
    barWidget.setText(`{s.revertLeft}s`)
  else
    if flashing then
      color = "tertiary"
    end
    barWidget.setText(if lit > 1 then tostring(lit) else "")
  end
  barWidget.setGlyphColor(color)
  barWidget.setColor(color)
end

noctalia.state.watch("snap", function(v: any)
  snap = v
  render()
end)

function onClick()
  send("toggle")
end

function onRightClick()
  -- While a change is pending this is the fastest way to confirm it.
  if snap ~= nil and snap.revertLeft > 0 then
    send("keep")
  else
    send("refresh")
  end
end

-- Ends the hotplug flash without waiting for the next snapshot.
function update()
  render()
end

noctalia.setUpdateInterval(1000)
snap = noctalia.state.get("snap")
render()

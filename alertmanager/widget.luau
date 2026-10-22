--!strict
-- Bar pill: glyph plus active-alert count, red while anything fires.

local snap: any = nil

local function render()
  local state = if snap ~= nil then snap.state else "loading"
  local count = if snap ~= nil then #snap.active else 0

  local hide = noctalia.getConfig("hideWhenZero") and count == 0 and state ~= "error"
  barWidget.setVisible(not hide)
  if hide then
    return
  end

  if state == "loading" then
    barWidget.setGlyph("loader")
  elseif state == "error" then
    barWidget.setGlyph("alert-triangle")
  elseif count > 0 then
    barWidget.setGlyph("alert-circle")
  else
    barWidget.setGlyph("circle-check")
  end
  local color = if state == "error" or count > 0 then "error" else noctalia.getConfig("iconColor")
  barWidget.setGlyphColor(color)
  barWidget.setColor(color)
  -- Like v4's auto-hiding pill: the number only shows while something fires.
  barWidget.setText(if noctalia.getConfig("showCount") and count > 0 then tostring(count) else "")

  if state == "error" then
    barWidget.setTooltip(snap.error)
  elseif count == 0 then
    barWidget.setTooltip(noctalia.tr("panel.header-all-clear"))
  else
    local rows = {}
    for _, a in ipairs(snap.active) do
      table.insert(rows, { key = a.name, value = a.host })
    end
    barWidget.setTooltip(rows)
  end
end

noctalia.state.watch("alerts", function(v: any)
  snap = v
  render()
end)

function onClick()
  noctalia.togglePanel("mic92/alertmanager:panel")
end

function onRightClick()
  noctalia.state.set("refresh", noctalia.nowMs())
end

snap = noctalia.state.get("alerts")
render()

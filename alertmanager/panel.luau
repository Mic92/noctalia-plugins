--!strict
-- Alerts grouped by alertname, critical first. Critical groups and a lone
-- group start expanded; silenced/inhibited alerts sit in a folded section.

type Alert = { name: string, severity: string, host: string, text: string, url: string }
type Group = { name: string, severity: string, alerts: { Alert } }

local snap: any = nil
-- Fold state survives refreshes; nil means "use the default".
local expanded: { [string]: boolean } = {}

local function rank(sev: string): number
  if sev == "critical" then
    return 0
  elseif sev == "warning" then
    return 1
  end
  return 2
end

local function sevColor(sev: string): string
  if sev == "critical" then
    return "error"
  elseif sev == "warning" then
    return "tertiary"
  end
  return "primary"
end

local function sevGlyph(sev: string): string
  if sev == "critical" then
    return "alert-octagon"
  elseif sev == "warning" then
    return "alert-triangle"
  end
  return "info-circle"
end

local function group(alerts: { Alert }): { Group }
  local byName: { [string]: Group } = {}
  local out: { Group } = {}
  for _, a in ipairs(alerts) do
    local g = byName[a.name]
    if g == nil then
      g = { name = a.name, severity = a.severity, alerts = {} }
      byName[a.name] = g
      table.insert(out, g)
    end
    table.insert(g.alerts, a)
    if rank(a.severity) < rank(g.severity) then
      g.severity = a.severity
    end
  end
  table.sort(out, function(a: Group, b: Group): boolean
    if rank(a.severity) ~= rank(b.severity) then
      return rank(a.severity) < rank(b.severity)
    end
    if #a.alerts ~= #b.alerts then
      return #a.alerts > #b.alerts
    end
    return a.name:lower() < b.name:lower()
  end)
  return out
end

local function openUrl(url: string)
  if url ~= "" then
    noctalia.runAsync({ "xdg-open", url })
  end
end

local render: () -> ()

local function toggle(key: string, default: boolean)
  local cur = expanded[key]
  if cur == nil then
    cur = default
  end
  expanded[key] = not cur
  render()
end

local function alertRow(a: Alert, muted: boolean): UiNode
  local text = {
    ui.row({ gap = 8, align = "center" }, {
      ui.glyph({
        name = if muted then "volume-off" else sevGlyph(a.severity),
        size = 16,
        color = if muted then "on_surface_variant" else sevColor(a.severity),
      }),
      ui.label({
        text = a.host,
        fontSize = 13,
        flexGrow = 1,
        color = if muted then "on_surface_variant" else "on_surface",
      }),
    }),
  }
  if a.text ~= "" then
    table.insert(
      text,
      ui.label({ text = a.text, fontSize = 12, color = "on_surface_variant", maxLines = 3, maxWidth = 380 })
    )
  end
  return ui.column({
    key = "a-" .. a.name .. "-" .. a.host,
    gap = 4,
    padding = 10,
    radius = 10,
    fill = if muted then "surface_variant/0.5" else "surface_variant",
    onClick = function()
      openUrl(a.url)
    end,
    tooltip = if a.url ~= "" then noctalia.tr("panel.open-graph") else nil,
  }, text)
end

local function groupNodes(groups: { Group }, muted: boolean, nodes: { UiNode })
  for _, g in ipairs(groups) do
    local key = (if muted then "s:" else "a:") .. g.name
    local default = not muted and (g.severity == "critical" or #groups == 1)
    local open = expanded[key]
    if open == nil then
      open = default
    end
    local header = {
      ui.glyph({
        name = if open then "chevron-down" else "chevron-right",
        size = 14,
        color = "on_surface_variant",
      }),
    }
    if not muted then
      table.insert(header, ui.box({ width = 9, height = 9, radius = 5, fill = sevColor(g.severity) }))
    end
    table.insert(
      header,
      ui.label({
        text = g.name,
        fontSize = 14,
        fontWeight = "bold",
        flexGrow = 1,
        color = if muted then "on_surface_variant" else "on_surface",
      })
    )
    table.insert(header, ui.label({ text = tostring(#g.alerts), fontSize = 12, color = "on_surface_variant" }))
    table.insert(
      nodes,
      ui.row({
        key = "h-" .. key,
        gap = 8,
        paddingH = 8,
        paddingV = 6,
        radius = 8,
        align = "center",
        opacity = if muted then 0.6 else 1,
        onClick = function()
          toggle(key, default)
        end,
      }, header)
    )
    if open then
      for _, a in ipairs(g.alerts) do
        table.insert(nodes, alertRow(a, muted))
      end
    end
  end
end

render = function()
  local state = if snap ~= nil then snap.state else "loading"
  local active: { Alert } = if snap ~= nil then snap.active else {}
  local silenced: { Alert } = if snap ~= nil then snap.silenced else {}
  local count = #active

  local title
  if state == "error" then
    title = noctalia.tr("panel.header-error")
  elseif count == 0 then
    title = noctalia.tr("panel.header-all-clear")
  else
    title = noctalia.trp("panel.header-active", count)
  end

  local body: { UiNode } = {}
  if state == "error" then
    table.insert(body, ui.label({ text = snap.error, color = "error", maxWidth = 400 }))
  elseif state == "ok" and count == 0 then
    table.insert(
      body,
      ui.label({
        text = noctalia.tr("panel.no-active-alerts"),
        fontSize = 15,
        color = "on_surface_variant",
        textAlign = "center",
      })
    )
  end
  groupNodes(group(active), false, body)
  if #silenced > 0 then
    table.insert(body, ui.separator({ spacing = 8 }))
    table.insert(
      body,
      ui.label({
        text = noctalia.tr("panel.silenced-header"),
        fontSize = 12,
        fontWeight = "bold",
        color = "on_surface_variant",
        opacity = 0.6,
      })
    )
    groupNodes(group(silenced), true, body)
  end

  panel.render(ui.column({ gap = 10, padding = 16, flexGrow = 1 }, {
    ui.row({ gap = 10, align = "center" }, {
      ui.glyph({
        name = if count > 0 then "alert-circle" else "circle-check",
        size = 22,
        color = if count > 0 or state == "error" then "error" else "primary",
      }),
      ui.label({ text = title, fontSize = 16, fontWeight = "bold", flexGrow = 1 }),
      ui.button({
        glyph = "refresh",
        variant = "ghost",
        controlSize = "sm",
        tooltip = noctalia.tr("panel.refresh"),
        onClick = function()
          noctalia.state.set("refresh", noctalia.nowMs())
        end,
      }),
      ui.button({
        glyph = "external-link",
        variant = "ghost",
        controlSize = "sm",
        tooltip = noctalia.tr("panel.open-alertmanager"),
        onClick = function()
          local url = noctalia.getConfig("alertmanagerUrl")
          openUrl(if type(url) == "string" then url else "")
        end,
      }),
      ui.button({
        glyph = "settings",
        variant = "ghost",
        controlSize = "sm",
        tooltip = noctalia.tr("panel.settings"),
        onClick = function()
          noctalia.openSettings()
        end,
      }),
    }),
    ui.separator({}),
    ui.scroll({ gap = 6, flexGrow = 1 }, body),
  }))
end

noctalia.state.watch("alerts", function(v: any)
  snap = v
  render()
end)

function onOpen()
  snap = noctalia.state.get("alerts")
  render()
end

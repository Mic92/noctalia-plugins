--!strict
-- Per-output controls, two-monitor arrangements, kanshi profiles and the
-- keep/revert bar. All changes go through the service via the "cmd" key.

local types = require("./types.luau")
type Output = types.Output
type Snap = types.Snap
type Profile = types.Profile

local SCALES = { 0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 3 }
local TRANSFORMS = { "normal", "90", "180", "270", "flipped", "flipped-90", "flipped-180", "flipped-270" }
local ARRANGEMENTS = {
  { "extend-right", "layout-columns" },
  { "extend-left", "layout-columns" },
  { "stack-above", "layout-rows" },
  { "stack-below", "layout-rows" },
  { "external-only", "device-desktop" },
  { "internal-only", "device-laptop" },
}

local tr = noctalia.tr
local snap: Snap? = nil
local isOpen = false
local newName = ""
-- Bumped after a save so the uncontrolled name input is recreated empty.
local inputGen = 0

local function send(op: string, arg: any?)
  noctalia.state.set("cmd", { op = op, arg = arg, seq = noctalia.nowMs() })
end

local function fmtNum(n: number): string
  return (string.format("%.2f", n):gsub("0+$", ""):gsub("%.$", ""))
end

local function section(title: string, children: { UiNode }): UiNode
  table.insert(
    children,
    1,
    ui.label({ text = title, fontSize = 12, fontWeight = "bold", color = "on_surface_variant" })
  )
  return ui.column({ gap = 8, padding = 10, radius = 10, fill = "surface_variant/0.4" }, children)
end

local function field(label: string, control: UiNode): UiNode
  return ui.row({ gap = 8, align = "center" }, {
    ui.column({ width = 70 }, { ui.label({ text = label, fontSize = 12, color = "on_surface_variant" }) }),
    ui.column({ flexGrow = 1 }, { control }),
  })
end

local function litCount(s: Snap): number
  local n = 0
  for _, o in s.outputs do
    if o.enabled then
      n += 1
    end
  end
  return n
end

local function outputCard(s: Snap, o: Output): UiNode
  local title = o.name
  local desc = noctalia.string.trim(o.make .. " " .. o.model)
  -- Refuse to switch off the last lit output; that would leave no screen.
  local isLast = o.enabled and litCount(s) <= 1

  local header = ui.row({ gap = 8, align = "center" }, {
    ui.glyph({
      name = if o.name:lower():match("^edp") then "device-laptop" else "device-desktop",
      size = 18,
      color = if o.enabled then "primary" else "on_surface_variant",
    }),
    ui.column({ gap = 0, flexGrow = 1 }, {
      ui.label({ text = title, fontSize = 14, fontWeight = "bold" }),
      ui.label({ text = desc, fontSize = 11, color = "on_surface_variant", maxLines = 1, maxWidth = 300 }),
    }),
    ui.toggle({
      checked = o.enabled,
      enabled = not isLast,
      onChange = function(v: string)
        send("set", { name = o.name, enabled = v == "true" })
      end,
    }),
  })
  if not o.enabled then
    return ui.column({ gap = 8, padding = 10, radius = 10, fill = "surface_variant/0.4", opacity = 0.7 }, { header })
  end

  local modeOpts, modeIdx = {}, 0
  for i, m in o.modes do
    local hz = math.round(m.refresh * 100) / 100
    table.insert(modeOpts, `{m.width}×{m.height} @ {hz} Hz` .. (if m.preferred then " ★" else ""))
    if m.key == o.mode then
      modeIdx = i - 1
    end
  end

  local scales = table.clone(SCALES)
  if not table.find(scales, o.scale) then
    table.insert(scales, o.scale)
    table.sort(scales)
  end
  local scaleOpts, scaleIdx = {}, 0
  for i, v in scales do
    table.insert(scaleOpts, fmtNum(v) .. "×")
    if v == o.scale then
      scaleIdx = i - 1
    end
  end

  local rotOpts = {}
  for _, t in TRANSFORMS do
    table.insert(rotOpts, tr("transform." .. t))
  end

  return ui.column({ key = "out-" .. o.name, gap = 8, padding = 10, radius = 10, fill = "surface_variant/0.4" }, {
    header,
    field(
      tr("panel.mode"),
      ui.select({
        options = modeOpts,
        selectedIndex = modeIdx,
        onChange = function(i: string)
          local m = o.modes[(tonumber(i) or 0) + 1]
          if m ~= nil then
            send("set", { name = o.name, mode = m.key })
          end
        end,
      })
    ),
    field(
      tr("panel.scale"),
      ui.select({
        options = scaleOpts,
        selectedIndex = scaleIdx,
        onChange = function(i: string)
          local v = scales[(tonumber(i) or 0) + 1]
          if v ~= nil then
            send("set", { name = o.name, scale = v })
          end
        end,
      })
    ),
    field(
      tr("panel.rotation"),
      ui.select({
        options = rotOpts,
        selectedIndex = (table.find(TRANSFORMS, o.transform) or 1) - 1,
        onChange = function(i: string)
          local t = TRANSFORMS[(tonumber(i) or 0) + 1]
          if t ~= nil then
            send("set", { name = o.name, transform = t })
          end
        end,
      })
    ),
    ui.label({ text = tr("panel.position", { x = o.x, y = o.y } :: any), fontSize = 11, color = "on_surface_variant" }),
  })
end

local function arrangeSection(s: Snap): UiNode?
  local n = #s.outputs
  if n < 2 then
    return nil
  end
  if n > 2 then
    local children: { UiNode } = {
      ui.label({ text = tr("panel.many-monitors"), fontSize = 12, color = "on_surface_variant", maxWidth = 400 }),
    }
    if noctalia.commandExists("wdisplays") then
      table.insert(
        children,
        ui.button({
          text = tr("panel.open-wdisplays"),
          glyph = "layout-dashboard",
          onClick = function()
            send("wdisplays")
          end,
        })
      )
    end
    return section(tr("panel.arrange"), children)
  end
  local rows: { UiNode } = {}
  for i = 1, #ARRANGEMENTS, 2 do
    local cells: { UiNode } = {}
    for j = i, i + 1 do
      local a = ARRANGEMENTS[j]
      table.insert(
        cells,
        ui.button({
          text = tr("arrange." .. a[1]),
          glyph = a[2],
          variant = "outline",
          controlSize = "sm",
          contentAlign = "start",
          flexGrow = 1,
          onClick = function()
            send("arrange", a[1])
          end,
        })
      )
    end
    table.insert(rows, ui.row({ gap = 6 }, cells))
  end
  return section(tr("panel.arrange"), rows)
end

-- Context-menu callbacks are looked up by global name.
function onProfileMenu(action: string, name: any)
  if type(name) ~= "string" then
    return
  end
  if action == "switch" then
    send("kanshiSwitch", name)
  elseif action == "update" then
    send("kanshiSave", name)
  elseif action == "delete" then
    send("kanshiDelete", name)
  end
end

local function profileRow(s: Snap, p: Profile): UiNode
  local active = p.name == s.kanshi.active
  return ui.button({
    key = "p-" .. p.name,
    text = p.name .. (if p.managed then "" else "  (" .. tr("panel.from-config") .. ")"),
    glyph = if active then "check" else "point",
    variant = if active then "primary" else "ghost",
    contentAlign = "start",
    tooltip = tr("panel.profile-tooltip"),
    onClick = function()
      send("kanshiSwitch", p.name)
    end,
    onRightClick = function()
      panel.openContextMenu({
        items = {
          { kind = "header", label = p.name },
          { id = "switch", label = tr("menu.switch") },
          -- Only touch profiles we own; the main config is the user's.
          { id = "update", label = tr("menu.update"), enabled = p.managed },
          { id = "delete", label = tr("menu.delete"), enabled = p.managed },
        },
        onActivate = "onProfileMenu",
        context = p.name,
      })
    end,
  })
end

local function kanshiSection(s: Snap): UiNode?
  local k = s.kanshi
  if not k.enabled then
    return nil
  end
  local children: { UiNode } = {}
  if not k.available then
    table.insert(children, ui.label({ text = tr("panel.kanshi-down"), fontSize = 12, color = "error", maxWidth = 400 }))
  end
  if not k.included then
    table.insert(
      children,
      ui.label({ text = tr("panel.kanshi-include"), fontSize = 12, color = "tertiary", maxWidth = 400 })
    )
  end
  for _, p in k.profiles do
    table.insert(children, profileRow(s, p))
  end
  local function save()
    local name = noctalia.string.trim(newName)
    if name ~= "" then
      send("kanshiSave", name)
      newName = ""
      inputGen += 1
    end
  end
  table.insert(
    children,
    ui.row({ gap = 6, align = "center" }, {
      ui.input({
        key = "name-" .. inputGen,
        placeholder = tr("panel.profile-name"),
        controlSize = "sm",
        flexGrow = 1,
        onChange = function(v: string)
          newName = v
        end,
        onSubmit = function(v: string)
          newName = v
          save()
        end,
      }),
      ui.button({ text = tr("panel.save"), glyph = "device-floppy", controlSize = "sm", onClick = save }),
    })
  )
  return section(tr("panel.kanshi"), children)
end

local function revertBar(s: Snap): UiNode
  return ui.row({ gap = 8, align = "center", padding = 10, radius = 10, fill = "error/0.15" }, {
    ui.glyph({ name = "clock-exclamation", size = 18, color = "error" }),
    ui.label({ text = tr("panel.revert-in", { n = s.revertLeft } :: any), fontSize = 13, flexGrow = 1 }),
    ui.button({
      text = tr("panel.revert"),
      variant = "secondary",
      controlSize = "sm",
      onClick = function()
        send("revert")
      end,
    }),
    ui.button({
      text = tr("panel.keep"),
      variant = "primary",
      controlSize = "sm",
      onClick = function()
        send("keep")
      end,
    }),
  })
end

local function render()
  if not isOpen then
    return
  end
  local s = snap
  local body: { UiNode } = {}
  if s == nil or s.state == "loading" then
    table.insert(body, ui.label({ text = tr("panel.loading"), color = "on_surface_variant" }))
  else
    if s.state == "error" then
      table.insert(body, ui.label({ text = s.error, color = "error", maxWidth = 420 }))
    end
    local arrange = arrangeSection(s)
    if arrange ~= nil then
      table.insert(body, arrange)
    end
    for _, o in s.outputs do
      table.insert(body, outputCard(s, o))
    end
    local kanshi = kanshiSection(s)
    if kanshi ~= nil then
      table.insert(body, kanshi)
    end
  end

  local headerButtons: { UiNode } = {
    ui.glyph({ name = "device-desktop", size = 22, color = "primary" }),
    ui.label({ text = tr("panel.title"), fontSize = 16, fontWeight = "bold", flexGrow = 1 }),
  }
  if noctalia.commandExists("wdisplays") then
    table.insert(
      headerButtons,
      ui.button({
        glyph = "layout-dashboard",
        variant = "ghost",
        controlSize = "sm",
        tooltip = tr("panel.open-wdisplays"),
        onClick = function()
          send("wdisplays")
        end,
      })
    )
  end
  table.insert(
    headerButtons,
    ui.button({
      glyph = "refresh",
      variant = "ghost",
      controlSize = "sm",
      tooltip = tr("panel.refresh"),
      onClick = function()
        send("refresh")
      end,
    })
  )
  table.insert(
    headerButtons,
    ui.button({
      glyph = "settings",
      variant = "ghost",
      controlSize = "sm",
      tooltip = tr("panel.settings"),
      onClick = function()
        noctalia.openSettings()
      end,
    })
  )

  local root: { UiNode } = { ui.row({ gap = 10, align = "center" }, headerButtons) }
  if s ~= nil and s.revertLeft > 0 then
    table.insert(root, revertBar(s))
  end
  table.insert(root, ui.scroll({ gap = 10, flexGrow = 1 }, body))
  panel.render(ui.column({ gap = 10, padding = 16, flexGrow = 1 }, root))
end

noctalia.state.watch("snap", function(v: any)
  snap = v
  render()
end)

function onOpen()
  isOpen = true
  snap = noctalia.state.get("snap")
  send("refresh")
  render()
end

function onClose()
  isOpen = false
end

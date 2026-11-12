--!strict
-- Renders the service's "view" and closes itself when it is cleared.

local types = require("./types.luau")
type Item = types.Item
type View = types.View

local GUTTER = 28

local function openUrl(url: string?)
  if url ~= nil and url ~= "" then
    noctalia.runAsync({ "xdg-open", url })
  end
end

local function text(item: Item): UiNode
  local lines = { ui.label({ text = item.title, fontSize = 14, fontWeight = "bold", maxLines = 2, maxWidth = 300 }) }
  if item.detail ~= nil and item.detail ~= "" then
    table.insert(
      lines,
      ui.label({ text = item.detail, fontSize = 12, color = "on_surface_variant", maxLines = 2, maxWidth = 300 })
    )
  end
  return ui.column({ gap = 2, flexGrow = 1 }, lines)
end

local function meta(item: Item): UiNode
  return ui.label({ text = item.meta or "", fontSize = 13, color = "on_surface_variant" })
end

-- A stop on the line: rides stand out, walks and turns recede.
local function timelineRow(i: number, item: Item): UiNode
  local ride = item.detail ~= nil and item.detail ~= ""
  return ui.row({ key = "t-" .. tostring(i), gap = 10, align = "center", paddingV = 2 }, {
    ui.row({ width = GUTTER, justify = "center" }, {
      ui.glyph({
        name = item.glyph or "point",
        size = if ride then 20 else 16,
        color = if ride then "primary" else "on_surface_variant",
      }),
    }),
    text(item),
    meta(item),
  })
end

local function connector(i: number): UiNode
  return ui.row({ key = "c-" .. tostring(i) }, {
    ui.row({ width = GUTTER, justify = "center" }, {
      ui.box({ width = 2, height = 12, radius = 1, fill = "outline_variant" }),
    }),
  })
end

local function card(i: number, item: Item): UiNode
  return ui.row({
    key = "l-" .. tostring(i),
    gap = 10,
    padding = 10,
    radius = 10,
    align = "center",
    fill = "surface_container",
    onClick = function()
      openUrl(item.url)
    end,
    tooltip = if item.url ~= nil then noctalia.tr("open-in-maps") else nil,
  }, {
    ui.glyph({ name = item.glyph or "point", size = 18, color = "primary" }),
    text(item),
    meta(item),
  })
end

local function render(view: View?)
  if view == nil then
    panel.close()
    return
  end
  local body: { UiNode } = {}
  for i, item in ipairs(view.items) do
    if view.kind == "timeline" then
      if i > 1 then
        table.insert(body, connector(i))
      end
      table.insert(body, timelineRow(i, item))
    else
      table.insert(body, card(i, item))
    end
  end

  local heading = { ui.label({ text = view.title, fontSize = 16, fontWeight = "bold", maxLines = 1, maxWidth = 280 }) }
  if view.subtitle ~= nil and view.subtitle ~= "" then
    table.insert(heading, ui.label({ text = view.subtitle, fontSize = 12, color = "on_surface_variant" }))
  end
  local header = {
    ui.glyph({ name = view.icon or "microphone", size = 24, color = "primary" }),
    ui.column({ gap = 2, flexGrow = 1 }, heading),
  }
  if view.url ~= nil and view.url ~= "" then
    table.insert(
      header,
      ui.button({
        glyph = "external-link",
        variant = "ghost",
        controlSize = "sm",
        tooltip = noctalia.tr("open-in-maps"),
        onClick = function()
          openUrl(view.url)
        end,
      })
    )
  end
  table.insert(
    header,
    ui.button({
      glyph = "x",
      variant = "ghost",
      controlSize = "sm",
      tooltip = noctalia.tr("close"),
      onClick = function()
        noctalia.state.set("view", nil)
      end,
    })
  )

  panel.render(ui.column({
    gap = 10,
    padding = 16,
    flexGrow = 1,
    onHover = function(state: string)
      noctalia.state.set("hover", state == "true")
    end,
  }, {
    ui.row({ gap = 10, align = "center" }, header),
    ui.separator({}),
    ui.scroll({ gap = if view.kind == "timeline" then 0 else 6, flexGrow = 1 }, body),
  }))
end

noctalia.state.watch("view", render)

function onOpen()
  noctalia.state.set("open", true)
  render(noctalia.state.get("view"))
end

function onClose()
  noctalia.state.set("open", false)
  noctalia.state.set("hover", false)
end

--!strict
-- Renders the service's "cue" and closes itself when it is cleared.

local function glyphFor(kind: string): (string, string)
  if kind == "success" then
    return "circle-check", "primary"
  elseif kind == "fail" then
    return "circle-x", "error"
  elseif kind == "retry" then
    return "alert-triangle", "tertiary"
  end
  return "fingerprint", "primary"
end

local function render(cue: any)
  if cue == nil then
    panel.close()
    return
  end
  local glyph, color = glyphFor(cue.kind)
  local text = { ui.label({ text = cue.title, fontSize = 15, fontWeight = "bold" }) }
  if cue.body ~= "" then
    table.insert(text, ui.label({ text = cue.body, fontSize = 13, color = "on_surface_variant" }))
  end
  panel.render(ui.row({ gap = 12, padding = 14, align = "center", flexGrow = 1 }, {
    ui.glyph({ name = glyph, size = 30, color = color }),
    ui.column({ gap = 2, flexGrow = 1 }, text),
  }))
end

noctalia.state.watch("cue", render)

function onOpen()
  noctalia.state.set("open", true)
  render(noctalia.state.get("cue"))
end

function onClose()
  noctalia.state.set("open", false)
end

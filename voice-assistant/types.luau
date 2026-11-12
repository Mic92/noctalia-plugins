--!strict
-- The view file the assistant writes. `kind` picks the layout: "timeline"
-- joins the items with a line, "list" makes each a card.

export type Item = { glyph: string?, title: string, detail: string?, meta: string?, url: string? }
export type View = {
  kind: string,
  icon: string?,
  title: string,
  subtitle: string?,
  url: string?,
  items: { Item },
}

return {}

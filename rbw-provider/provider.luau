--!strict
-- `/rbw <query>` searches a cached `rbw list`; selecting an entry drills into
-- `/rbw :<id>` with type/copy actions. Secrets are piped from rbw straight
-- into `wl-copy --sensitive` and never pass through Luau or argv.

type Entry = { id: string, name: string, user: string, folder: string, key: string }

local PREFIX = "/rbw "
local MAX_RESULTS = 50

local entries: { Entry } = {}
local byId: { [string]: Entry } = {}
local status = "loading" -- "loading" | "ok" | "error"
local loadError = ""
local lastQuery = ""

local refreshResults: () -> ()

local function load()
  status = "loading"
  noctalia.runAsync({ "rbw", "list", "--fields", "id,name,user,folder" }, function(res: CommandResult)
    if res.exitCode ~= 0 then
      status = "error"
      loadError = noctalia.string.trim(res.stderr)
      if loadError == "" then
        loadError = noctalia.tr("error.list-failed")
      end
    else
      entries = {}
      byId = {}
      for line in res.stdout:gmatch("[^\n]+") do
        local id, name, user, folder = line:match("^([^\t]*)\t?([^\t]*)\t?([^\t]*)\t?([^\t]*)$")
        if id ~= nil and id:match("^[%w%-]+$") then
          local n, u, f = name or "", user or "", folder or ""
          local e: Entry = { id = id, name = n, user = u, folder = f, key = n .. " " .. u .. " " .. f }
          table.insert(entries, e)
          byId[id] = e
        end
      end
      status = "ok"
    end
    refreshResults()
  end, 60000)
end

-- tr() substitutions are typed as a mixed-value map.
local function arg(k: string, v: string): { [string]: string | number | boolean }
  return { [k] = v }
end

local function scheduleClear()
  local secs = noctalia.getConfig("clearAfterSeconds")
  -- Detached, so it outlives a plugin reload. Clears unconditionally:
  -- leaving a secret behind is worse than wiping something newer.
  noctalia.runAsync({ "sh", "-c", 'sleep "$1"; wl-copy --clear', "sh", tostring(secs) })
end

-- what: "get" | "code" | "user"; paste: simulate Ctrl+Shift+V afterwards.
local function deliver(e: Entry, what: string, paste: boolean, label: string)
  -- Pasting a key combo instead of typing the text works around niri #2314
  -- (wtype's virtual keyboard corrupts the keymap on arbitrary text). The
  -- short sleep lets the launcher surface close and focus return first.
  local script = [[
set -o pipefail
if [ "$1" = user ]; then
  printf %s "$3" | wl-copy --sensitive
else
  rbw "$1" "$2" | head -c -1 | wl-copy --sensitive
fi
if [ "$4" = 1 ]; then
  sleep 0.15
  wtype -M ctrl -M shift -k v -m shift -m ctrl
fi
]]
  noctalia.runAsync(
    { "bash", "-c", script, "bash", what, e.id, e.user, if paste then "1" else "0" },
    function(res: CommandResult)
      if res.exitCode ~= 0 then
        local err = noctalia.string.trim(res.stderr)
        noctalia.notifyError("rbw", if err ~= "" then err else noctalia.tr("error.command-failed"))
        return
      end
      scheduleClear()
      noctalia.notify(noctalia.tr(if paste then "toast.typed" else "toast.copied", arg("label", label)))
    end,
    60000
  )
end

local function actionResults(e: Entry): { LauncherResult }
  local title = e.name .. (if e.user ~= "" then " — " .. e.user else "")
  return {
    {
      id = "get:" .. e.id,
      title = noctalia.tr("actions.type-password"),
      subtitle = title,
      glyph = "key",
      score = 5,
    },
    {
      id = "user:" .. e.id,
      title = noctalia.tr("actions.type-username"),
      subtitle = if e.user ~= "" then e.user else noctalia.tr("actions.no-username"),
      glyph = "user",
      score = 4,
    },
    {
      id = "code:" .. e.id,
      title = noctalia.tr("actions.type-totp"),
      subtitle = e.name,
      glyph = "clock",
      score = 3,
    },
    {
      id = "copy:" .. e.id,
      title = noctalia.tr("actions.copy-password"),
      subtitle = noctalia.tr("actions.copy-password-description"),
      glyph = "clipboard",
      score = 2,
    },
    {
      title = noctalia.tr("actions.back"),
      subtitle = noctalia.tr("actions.back-description"),
      glyph = "arrow-left",
      query = "",
      score = 1,
    },
  }
end

local function searchResults(query: string): { LauncherResult }
  local out: { LauncherResult } = {}
  local q = noctalia.string.trim(query)
  for _, e in ipairs(entries) do
    local score: number? = if q == "" then 0 else noctalia.fuzzyScore(q, e.key)
    if score ~= nil then
      local sub = {}
      if e.user ~= "" then
        table.insert(sub, e.user)
      end
      if e.folder ~= "" then
        table.insert(sub, e.folder)
      end
      table.insert(out, {
        title = e.name,
        subtitle = table.concat(sub, " · "),
        glyph = "key",
        query = ":" .. e.id,
        score = score,
      })
    end
  end
  table.sort(out, function(a: LauncherResult, b: LauncherResult): boolean
    return (a.score or 0) > (b.score or 0)
  end)
  while #out > MAX_RESULTS do
    table.remove(out)
  end
  return out
end

local function results(text: string): { LauncherResult }
  if status == "loading" then
    return {
      {
        id = "noop",
        title = noctalia.tr("loading.name"),
        subtitle = noctalia.tr("loading.description"),
        glyph = "loader",
      },
    }
  elseif status == "error" then
    return {
      {
        id = "unlock",
        title = noctalia.tr("error.name"),
        subtitle = noctalia.tr("error.description", arg("error", loadError)),
        glyph = "alert-circle",
      },
    }
  end
  local id = text:match("^:([%w%-]+)%s*$")
  if id ~= nil and byId[id] ~= nil then
    return actionResults(byId[id])
  end
  if noctalia.string.trim(text) == "!" then
    return {
      {
        id = "refresh",
        title = noctalia.tr("refresh.name"),
        subtitle = noctalia.tr("refresh.description"),
        glyph = "refresh",
      },
    }
  end
  return searchResults(text)
end

refreshResults = function()
  launcher.setResults(lastQuery, results(lastQuery))
end

function onQuery(text: string)
  lastQuery = text
  launcher.setResults(text, results(text))
end

function onActivate(id: string)
  if id == "refresh" then
    load()
    launcher.setQuery(PREFIX)
    return
  elseif id == "unlock" then
    -- rbw unlock may show pinentry; list again once it is done.
    noctalia.runAsync({ "rbw", "unlock" }, function(res: CommandResult)
      if res.exitCode ~= 0 then
        noctalia.notifyError(noctalia.tr("error.unlock-failed", arg("error", noctalia.string.trim(res.stderr))))
      end
      load()
    end, 60000)
    return
  end
  local action, eid = id:match("^(%a+):([%w%-]+)$")
  local e = if eid ~= nil then byId[eid] else nil
  if action == nil or e == nil then
    return
  end
  if action == "get" then
    deliver(e, "get", true, noctalia.tr("labels.password"))
  elseif action == "code" then
    deliver(e, "code", true, noctalia.tr("labels.totp"))
  elseif action == "copy" then
    deliver(e, "get", false, noctalia.tr("labels.password"))
  elseif action == "user" then
    if e.user == "" then
      noctalia.notify(noctalia.tr("actions.no-username-warning", arg("name", e.name)))
    else
      deliver(e, "user", true, noctalia.tr("labels.username"))
    end
  end
end

-- The vault list is cached; `/rbw !` refreshes after rbw add/sync.
load()

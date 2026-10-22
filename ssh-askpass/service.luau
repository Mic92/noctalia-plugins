--!strict
-- Receives askpass requests from the stub (stub/main.go) via
--   noctalia msg plugin mic92/ssh-askpass:service all ask <json>
-- and shows them one at a time in the dialog panel. Several ssh processes
-- can prompt concurrently and their stubs can't coordinate, so they queue
-- here. The dialog answers by writing the request's reply file.

local PANEL = "mic92/ssh-askpass:dialog"

type Request = { id: string, mode: string, prompt: string, reply: string }

local queue: { Request } = {}
local showing = false

-- Only accept reply paths inside the stub's runtime dir, so an IPC caller
-- can't make the shell write elsewhere.
local function replyDirOk(reply: any): boolean
  local rt = noctalia.getenv("XDG_RUNTIME_DIR")
  if rt == nil or type(reply) ~= "string" then
    return false
  end
  local prefix = rt .. "/noctalia-ssh-askpass/"
  return reply:sub(1, #prefix) == prefix and reply:match("^[%w/_.-]+$") ~= nil and not reply:find("%.%.")
end

local function dirOf(path: string): string
  return path:match("^(.*)/[^/]*$") or path
end

local function showNext()
  if showing then
    return
  end
  while #queue > 0 do
    local req = table.remove(queue, 1) :: Request
    -- The stub removes its dir when it gives up; skip those.
    if noctalia.fileExists(dirOf(req.reply)) then
      showing = true
      noctalia.state.set("request", req)
      noctalia.togglePanel(PANEL)
      return
    end
  end
  noctalia.state.set("request", nil)
end

-- The dialog bumps this from onClose, whether it answered or was dismissed.
noctalia.state.watch("closed", function(id)
  local cur = noctalia.state.get("request")
  if cur ~= nil and cur.id == id then
    showing = false
    showNext()
  end
end)

function onIpc(event: string, payload: string)
  if event ~= "ask" then
    return
  end
  local raw: any, err = noctalia.json.decode(payload)
  if type(raw) ~= "table" or type(raw.id) ~= "string" or not replyDirOk(raw.reply) then
    noctalia.log("ssh-askpass: rejecting bad request: " .. tostring(err or payload))
    return
  end
  table.insert(queue, {
    id = raw.id,
    mode = if raw.mode == "confirm" then "confirm" else "prompt",
    prompt = tostring(raw.prompt or ""),
    reply = raw.reply,
  })
  showNext()
end

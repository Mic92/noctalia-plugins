--!strict
-- Askpass dialog. mode == "confirm": Allow/Deny (or a fingerprint scan),
-- mode == "prompt": passphrase field. Enter answers, Escape (host-owned)
-- closes the panel, and any close without an answer denies.

type Request = { id: string, mode: string, prompt: string, reply: string }

local req: Request? = nil
local answered = false
local passphrase = ""
local deadline = 0
local fprintStatus = ""

local function useFingerprint(): boolean
  return req ~= nil and req.mode == "confirm" and noctalia.getConfig("confirmMethod") == "fingerprint"
end

local function dirOf(path: string): string
  return path:match("^(.*)/[^/]*$") or path
end

local function pidFile(r: Request): string
  return dirOf(r.reply) .. "/fprint.pid"
end

local function stopFprint()
  if req ~= nil and useFingerprint() then
    -- Release the reader right away so the next PAM client can claim it.
    noctalia.runAsync({ "sh", "-c", 'kill "$(cat "$1")" 2>/dev/null', "sh", pidFile(req) })
  end
end

-- Write to a temp name and rename, so the stub never reads half a reply.
local function writeReply(r: Request, ok: boolean, value: string)
  local tmp = r.reply .. ".tmp"
  local body = noctalia.json.encode({ ok = ok, value = value }) or '{"ok":false}'
  local written, err = noctalia.writeFile(tmp, body)
  if not written then
    noctalia.log("ssh-askpass: cannot write reply: " .. tostring(err))
    return
  end
  noctalia.renameFile(tmp, r.reply)
end

local function answer(ok: boolean, value: string)
  if answered or req == nil then
    return
  end
  answered = true
  stopFprint()
  writeReply(req, ok, value)
  panel.close()
end

local render: () -> ()

local function startFprint(r: Request)
  -- runStream has no exit status, so the wrapper reports it as a line.
  local cmd = "fprintd-verify 2>&1 & echo $! > '" .. pidFile(r) .. '\'; wait $!; echo "__exit $?"'
  noctalia.runStream(cmd, function(line: string)
    if answered then
      return
    end
    local code = line:match("^__exit (%d+)$")
    if code ~= nil then
      -- 0 is verify-match; no-match, busy device etc. deny (fail closed).
      answer(code == "0", "")
    elseif line ~= "" then
      fprintStatus = line
      render()
    end
  end)
end

local function promptLines(r: Request)
  local nodes = {}
  for line in (r.prompt .. "\n"):gmatch("(.-)\n") do
    local hi = line:sub(1, 12) == "Requested by"
    table.insert(
      nodes,
      ui.label({
        text = line,
        fontSize = 13,
        color = hi and "on_surface" or "on_surface_variant",
        fontWeight = if hi then "medium" else "normal",
        maxWidth = 400,
      })
    )
  end
  return nodes
end

render = function()
  local r = req
  if r == nil then
    return
  end
  local confirm = r.mode == "confirm"
  local fp = useFingerprint()

  local text = {
    ui.label({
      text = noctalia.tr(confirm and "title-confirm" or "title-prompt"),
      fontSize = 16,
      fontWeight = "bold",
    }),
  }
  for _, n in ipairs(promptLines(r)) do
    table.insert(text, n)
  end
  if fp and fprintStatus ~= "" then
    table.insert(text, ui.label({ text = fprintStatus, fontSize = 13, color = "primary", maxWidth = 400 }))
  end

  local body = {
    ui.row({ gap = 12, align = "start" }, {
      ui.glyph({ name = fp and "fingerprint" or (confirm and "key" or "lock"), size = 32, color = "primary" }),
      ui.column({ gap = 4, flexGrow = 1 }, text),
    }),
  }
  if not confirm then
    table.insert(
      body,
      ui.input({
        key = "pass-" .. r.id,
        password = true,
        focus = true,
        placeholder = noctalia.tr("placeholder-passphrase"),
        onChange = function(v)
          passphrase = v
        end,
        onSubmit = function(v)
          if v ~= "" then
            answer(true, v)
          end
        end,
      })
    )
  end

  local buttons = {
    ui.spacer({ flexGrow = 1 }),
    ui.button({
      text = noctalia.tr(confirm and "button-deny" or "button-cancel"),
      variant = "secondary",
      onClick = function()
        answer(false, "")
      end,
    }),
  }
  -- In fingerprint mode the sensor is the Allow button.
  if not fp then
    table.insert(
      buttons,
      ui.button({
        text = noctalia.tr(confirm and "button-allow" or "button-ok"),
        variant = "primary",
        onClick = function()
          if confirm then
            answer(true, "")
          elseif passphrase ~= "" then
            answer(true, passphrase)
          end
        end,
      })
    )
  end
  table.insert(body, ui.spacer({ flexGrow = 1 }))
  table.insert(body, ui.row({ gap = 8, align = "center" }, buttons))

  panel.render(ui.column({ gap = 12, padding = 16, flexGrow = 1 }, body))
end

function onOpen()
  req = noctalia.state.get("request")
  answered = false
  passphrase = ""
  fprintStatus = ""
  if req == nil then
    panel.close()
    return
  end
  deadline = os.time() + noctalia.getConfig("confirmTimeoutSec")
  panel.setWantsSecondTicks(true)
  if useFingerprint() then
    startFprint(req)
  end
  render()
end

-- Auto-deny so a forgotten prompt doesn't wedge the agent.
function update()
  if req ~= nil and not answered and os.time() >= deadline then
    answer(false, "")
  end
end

function onKey(chord, pressed)
  if not pressed or req == nil or useFingerprint() then
    return
  end
  if req.mode == "confirm" then
    answer(true, "")
  elseif passphrase ~= "" then
    answer(true, passphrase)
  end
end

function onClose()
  if req == nil then
    return
  end
  if not answered then
    answered = true
    stopFprint()
    writeReply(req, false, "")
  end
  local id = req.id
  req = nil
  noctalia.state.set("closed", id)
end

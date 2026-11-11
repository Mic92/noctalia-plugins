--!strict
-- Shapes of the "snap" state the service publishes.

export type Mode = { key: string, width: number, height: number, refresh: number, preferred: boolean }

export type Output = {
  name: string,
  make: string,
  model: string,
  serial: string,
  enabled: boolean,
  mode: string,
  modes: { Mode },
  scale: number,
  x: number,
  y: number,
  transform: string,
}

-- What revert restores per output.
export type Saved = {
  name: string,
  enabled: boolean,
  mode: string,
  scale: number,
  x: number,
  y: number,
  transform: string,
}

export type Profile = { name: string, managed: boolean }

export type Kanshi = {
  enabled: boolean,
  available: boolean,
  active: string,
  profiles: { Profile },
  -- Whether the main kanshi config includes noctalia.conf.
  included: boolean,
}

export type Snap = {
  state: string, -- "loading" | "ok" | "error"
  error: string,
  outputs: { Output },
  hotplugMs: number,
  revertLeft: number, -- seconds until auto-revert, 0 when nothing pending
  kanshi: Kanshi,
}

return {}

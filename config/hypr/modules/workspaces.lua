-- Workspaces 1–10 split evenly between the monitors, the primary one first
-- (Settings → Display in kirin), the others left to right:
--   1 monitor: 1–10    2: 1–5 / 6–10    3: 1–4 / 5–7 / 8–10    4: 1–3 / 4–6 / 7–8 / 9–10
-- New workspaces open on their monitor (workspace rules), laid out down
-- instead of to the right on an upright monitor; and whenever the
-- monitors change the existing ones move there too: plugging the TV back
-- in brings 6–10 back to it. A monitor unplugged leaves its workspaces on
-- the others (Hyprland moves them, windows and all) until it's back.

local COUNT = 10

-- Set by kirin_apply_settings (modules/settings.lua).
kirin_primary = kirin_primary or ""

-- One rule per workspace, monitor and direction, kept: rules can only be
-- turned off, not removed, so a split seen before turns its old rules back on.
local rules = {}

-- The scrolling layout's direction for each monitor: on a monitor standing
-- upright (taller than wide, after its rotation) the tape goes down, new
-- windows below and scrolling up and down; else to the right.
local function direction(m)
	local w, h = m.width or 0, m.height or 0
	if (m.transform or 0) % 2 == 1 then w, h = h, w end
	return h > w and "down" or "right"
end

-- The direction each open workspace was laid out in, by id.
local laid_out = {}

-- A workspace whose direction changed is laid out again: its rule only
-- counts from its next relayout, which the last window of its tape gives,
-- floated and tiled again (it comes back to the end, where it was).
local function relayout(id)
	local last, best
	for _, w in ipairs(hl.get_windows()) do
		if w.workspace and w.workspace.id == id and not w.floating then
			local at = w.at or {}
			local d = (at.x or at[1] or 0) + (at.y or at[2] or 0)
			if not best or d > best then last, best = w, d end
		end
	end
	if last then
		hl.dispatch(hl.dsp.window.float({ action = "enable", window = last }))
		hl.dispatch(hl.dsp.window.float({ action = "disable", window = last }))
	end
end

-- Monitors in order: the primary, then the rest left to right, top to bottom.
local function ordered()
	local list = {}
	for _, m in ipairs(hl.get_monitors()) do
		if m.enabled ~= false and not m.is_mirror then
			table.insert(list, m)
		end
	end
	table.sort(list, function(a, b)
		if (a.name == kirin_primary) ~= (b.name == kirin_primary) then
			return a.name == kirin_primary
		end
		if a.x ~= b.x then return a.x < b.x end
		return a.y < b.y
	end)
	return list
end

-- { [workspace id] = monitor name }, and each monitor's first workspace.
local function split(monitors)
	local owner, first = {}, {}
	local n = math.min(#monitors, COUNT)
	if n == 0 then return owner, first end
	local base, extra = COUNT // n, COUNT % n
	local id = 1
	for i = 1, n do
		local size = base + (i <= extra and 1 or 0)
		first[monitors[i].name] = id
		for _ = 1, size do
			owner[id] = monitors[i].name
			id = id + 1
		end
	end
	return owner, first
end

function kirin_distribute_workspaces()
	local monitors = ordered()
	local owner, first = split(monitors)

	local dirs = {}
	for _, m in ipairs(monitors) do dirs[m.name] = direction(m) end

	-- Rules for workspaces yet to open (and the direction of open ones).
	for key, r in pairs(rules) do
		local id, name, dir = key:match("^(%d+)@(.+)@(%a+)$")
		r:set_enabled(owner[tonumber(id)] == name and dirs[name] == dir)
	end
	for id, name in pairs(owner) do
		local dir = dirs[name] or "right"
		local key = id .. "@" .. name .. "@" .. dir
		if not rules[key] then
			rules[key] = hl.workspace_rule({ workspace = tostring(id), monitor = name, layout_opts = { direction = dir } })
		end
	end

	-- Open ones whose direction changed: laid out again.
	for id, name in pairs(owner) do
		local dir = dirs[name] or "right"
		if hl.get_workspace(id) and laid_out[id] ~= dir then
			if laid_out[id] ~= nil then relayout(id) end
			laid_out[id] = dir
		end
	end

	-- Open ones on the wrong monitor go to theirs.
	local focused = hl.get_active_monitor()
	for id, name in pairs(owner) do
		local ws = hl.get_workspace(id)
		if ws and ws.monitor and ws.monitor.name ~= name then
			hl.dispatch(hl.dsp.workspace.move({ workspace = id, monitor = name }))
		end
	end

	-- A monitor left showing a numbered workspace that isn't its own (one
	-- Hyprland made up for it, or one that moved away) shows its first.
	-- Named ones (the lock screen's) are left alone.
	for _, m in ipairs(monitors) do
		local ws = hl.get_active_workspace(m.name)
		local id = ws and ws.id
		if id and id > 0 and owner[id] ~= m.name and first[m.name] then
			hl.dispatch(hl.dsp.focus({ monitor = m.name }))
			hl.dispatch(hl.dsp.focus({ workspace = first[m.name] }))
		end
	end
	if focused then
		hl.dispatch(hl.dsp.focus({ monitor = focused.name }))
	end
end

-- A monitor added is set up (mode, position) a moment after the event.
local function soon()
	hl.timer(kirin_distribute_workspaces, { timeout = 400, type = "oneshot" })
end

hl.on("monitor.added", soon)
hl.on("monitor.removed", soon)
-- Rotated (or another mode): the direction may change.
hl.on("monitor.layout_changed", soon)
-- On start and every config reload (which drops the rules).
soon()

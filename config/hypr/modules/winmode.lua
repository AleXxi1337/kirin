-- Two ways to work, switched with Super+Ctrl+Shift+T:
--   tiling   the scrolling layout (look_and_feel.lua): columns, workspaces;
--   windows  a desktop as usual: one workspace per monitor, every window
--            floating, with titlebars (bars.lua); windows minimize to a
--            hidden workspace (special:minimized) and come back from there.
-- The mode survives restarts (~/.local/state/kirin/window-mode; kirin reads
-- it too, for its bar).
--
-- Into windows: every window (all workspaces, all monitors) goes to the
-- primary monitor, floating, minimized: the desktop (workspace 1 there) is
-- clear, windows come back one by one. Back to tiling: every window, minimized too, goes to
-- workspace 1 as columns, the last used first; windows that float by
-- themselves (dialogs, fixed-size ones) stay floating.

local MINIMIZED = "special:minimized"
local state_dir = (os.getenv("XDG_STATE_HOME") or (os.getenv("HOME") .. "/.local/state")) .. "/kirin"
local state_file = state_dir .. "/window-mode"

kirin_window_mode = kirin_window_mode or "tiling"

-- Windows that floated by themselves when they opened (dialogs, splash
-- screens, fixed-size windows), by address: they stay floating in tiling.
local own_floats = {}

-- The workspace each monitor keeps in windows mode, by monitor name.
local desktops = {}

-- Maximized windows' normal geometry, by address (kirin_window_maximize).
local before = {}

-- Where each minimized window was, by address: monitor, normal geometry,
-- maximized (kirin_minimize).
local minimized_from = {}

-- Windows put on a half or a quarter of the screen (snapped: dragged to an
-- edge, or Super + arrows): their normal size, by address, to come back to
-- when dragged away.
local snapped = {}

-- These are kept over config reloads (a change of the window rules
-- file reloads the config: see "Placement"), not over a logout: in
-- $XDG_RUNTIME_DIR, read back on load for the windows still there.
local runtime_dir = (os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/kirin"
local runtime_file = runtime_dir .. "/winmode.lua"
os.execute("mkdir -p '" .. runtime_dir .. "'")

local function serialize(v)
	if type(v) == "table" then
		local parts = {}
		for k, x in pairs(v) do
			parts[#parts + 1] = "[" .. (type(k) == "string" and string.format("%q", k) or tostring(k)) .. "] = " .. serialize(x)
		end
		return "{ " .. table.concat(parts, ", ") .. " }"
	elseif type(v) == "string" then
		return string.format("%q", v)
	end
	return tostring(v)
end

local function save_runtime()
	local f = io.open(runtime_file, "w")
	if not f then return end
	f:write("return ", serialize({ own_floats = own_floats, before = before, minimized_from = minimized_from, snapped = snapped }), "\n")
	f:close()
end

do
	local ok, t = pcall(dofile, runtime_file)
	if ok and type(t) == "table" then
		for name, into in pairs({ own_floats = own_floats, before = before, minimized_from = minimized_from, snapped = snapped }) do
			for address, v in pairs(type(t[name]) == "table" and t[name] or {}) do
				if hl.get_window("address:" .. address) then into[address] = v end
			end
		end
	end
end

local function save()
	os.execute("mkdir -p '" .. state_dir .. "'")
	local f = io.open(state_file, "w")
	if f then
		f:write(kirin_window_mode .. "\n")
		f:close()
	end
end

local function saved_mode()
	local f = io.open(state_file, "r")
	if not f then return "tiling" end
	local mode = f:read("l")
	f:close()
	return mode == "windows" and "windows" or "tiling"
end

local function primary()
	if kirin_primary and kirin_primary ~= "" then
		local m = hl.get_monitor(kirin_primary)
		if m then return m end
	end
	return hl.get_active_monitor()
end

-- Not on a special workspace (the scratchpad, minimized) nor the lock
-- screen's empty one.
local function on_desktop(w)
	local ws = w.workspace
	return ws and ws.id and ws.id > 0
end

local function remember_desktops()
	desktops = {}
	for _, m in ipairs(hl.get_monitors()) do
		if m.active_workspace then desktops[m.name] = m.active_workspace.id end
	end
end

local function set_bars(on)
	if kirin_set_bars then kirin_set_bars(on) end
end

-- Out of fullscreen or Hyprland's maximize: "unset" only works with the
-- mode the window is in (1 maximized, 2 fullscreen).
local function unfullscreen(w)
	local mode = w.fullscreen or 0
	if mode ~= 0 then
		pcall(hl.dispatch, hl.dsp.window.fullscreen({ window = w, mode = mode == 1 and "maximized" or "fullscreen", action = "unset" }))
	end
end

local function to_windows()
	local p = primary()
	if not p then return end
	-- The primary monitor's desktop is workspace 1, as tiling comes back to.
	local target = "1"
	local maxw, maxh = math.floor(p.width / p.scale * 0.8), math.floor(p.height / p.scale * 0.8)
	for _, w in ipairs(hl.get_windows()) do
		local ws = w.workspace
		if ws and (on_desktop(w) or ws.name == MINIMIZED) then
			unfullscreen(w)
			if not w.floating then hl.dispatch(hl.dsp.window.float({ action = "enable", window = w })) end
			-- On the primary monitor first, to be sized and centred there.
			hl.dispatch(hl.dsp.window.move({ workspace = target, window = w, follow = false }))
			local size = w.size or {}
			local width, height = size.x or size[1] or maxw, size.y or size[2] or maxh
			if width > maxw or height > maxh then
				hl.dispatch(hl.dsp.window.resize({ x = math.min(width, maxw), y = math.min(height, maxh), window = w }))
			end
			hl.dispatch(hl.dsp.window.center({ window = w }))
			hl.dispatch(hl.dsp.window.move({ workspace = MINIMIZED, window = w, follow = false }))
		end
	end
	hl.dispatch(hl.dsp.focus({ monitor = p.name }))
	hl.dispatch(hl.dsp.focus({ workspace = 1 }))
	remember_desktops()
	set_bars(true)
end

local function to_tiling()
	if kirin_remember_all_places then kirin_remember_all_places() end
	if kirin_unmaximize_all then kirin_unmaximize_all() end
	local p = primary()
	-- The last used first: they go in that order, each a new column at
	-- the end.
	local list = {}
	for _, w in ipairs(hl.get_windows()) do
		local ws = w.workspace
		if ws and (on_desktop(w) or ws.name == MINIMIZED) then list[#list + 1] = w end
	end
	table.sort(list, function(a, b) return (a.focus_history_id or 0) < (b.focus_history_id or 0) end)
	if p then hl.dispatch(hl.dsp.focus({ monitor = p.name })) end
	hl.dispatch(hl.dsp.focus({ workspace = 1 }))
	for _, w in ipairs(list) do
		unfullscreen(w)
		hl.dispatch(hl.dsp.window.move({ workspace = "1", window = w, follow = false }))
		if not own_floats[w.address] and w.floating then
			hl.dispatch(hl.dsp.window.float({ action = "disable", window = w }))
		end
	end
	if list[1] then hl.dispatch(hl.dsp.focus({ window = list[1] })) end
	desktops = {}
	set_bars(false)
end

function kirin_set_window_mode(mode)
	if mode ~= "windows" then mode = "tiling" end
	if mode == kirin_window_mode then return end
	kirin_window_mode = mode
	if mode == "windows" then to_windows() else to_tiling() end
	save()
	-- Last: it reloads the config.
	kirin_write_window_rules()
end

function kirin_toggle_window_mode()
	kirin_set_window_mode(kirin_window_mode == "windows" and "tiling" or "windows")
end

-- A window opening: whether it floats by itself is noted before anything
-- else touches it (in windows mode it's then placed: see "Placement").
-- Floated by kirin's own window rules (Placement), tagged so: not by itself.
local function placed_by_rule(w)
	for _, tag in pairs(w.tags or {}) do
		if tostring(tag):match("^kirin%-placed") then return true end
	end
	return false
end

hl.on("window.open_early", function(w)
	if w and w.floating and not placed_by_rule(w) then
		own_floats[w.address] = true
		save_runtime()
	end
end)

hl.on("window.close", function(w)
	if w and own_floats[w.address] then
		own_floats[w.address] = nil
		save_runtime()
	end
end)

-- One workspace per monitor: whatever switches a monitor to another one
-- (the three-finger swipe, an app asking for focus), it goes back. Not
-- while the screen locks (lock.lua has its own workspaces then).
hl.on("workspace.active", function()
	if kirin_window_mode ~= "windows" then return end
	for _, m in ipairs(hl.get_monitors()) do
		-- No id for a moment while the config reloads (switching modes).
		local ws = hl.get_active_workspace(m.name)
		local id = ws and ws.id
		local home = desktops[m.name]
		if id and id > 0 and home and id ~= home then
			hl.dispatch(hl.dsp.focus({ monitor = m.name }))
			hl.dispatch(hl.dsp.focus({ workspace = home }))
		elseif id and id > 0 and not home then
			desktops[m.name] = id
		end
	end
end)

-- Halves (Super + left/right) fill the same area a maximized window does:
-- the monitor's free area (the bar aside) less the outer gaps
-- (general.float_gaps, look_and_feel.lua), the titlebar inside it.
local function float_gaps()
	local g = hl.get_config("general.float_gaps")
	if type(g) == "number" then return { top = g, right = g, bottom = g, left = g } end
	if type(g) ~= "table" then return { top = 10, right = 10, bottom = 10, left = 10 } end
	return { top = g.top or 10, right = g.right or 10, bottom = g.bottom or 10, left = g.left or 10 }
end

-- The titlebar sits above the window, outside its geometry.
local function titlebar_height()
	if not (kirin_bars_enabled and kirin_bars_enabled()) then return 0 end
	local h = hl.get_config("plugin.hyprbars.bar_height")
	return type(h) == "number" and h or 0
end

local function work_area(m)
	local r = m.reserved or {}
	local g = float_gaps()
	local scale = m.scale or 1
	local bar = titlebar_height()
	return {
		x = math.floor(m.x + (r.left or 0) + g.left),
		y = math.floor(m.y + (r.top or 0) + g.top + bar),
		w = math.floor(m.width / scale - (r.left or 0) - (r.right or 0) - g.left - g.right),
		h = math.floor(m.height / scale - (r.top or 0) - (r.bottom or 0) - g.top - g.bottom - bar),
	}
end

-- Maximized in windows mode: kirin's own, not Hyprland's. Hyprland's makes
-- the window the workspace's fullscreen one: it then gets the pointer's
-- focus over any window on top of it, and those drop under it. Here the
-- window stays an ordinary floating one, sized to the work area (the gaps
-- from general.float_gaps); the app is told it's maximized (client state 1,
-- Hyprland's internal state 0), which also marks it as maximized for us,
-- over config reloads too. Its geometry before is kept to come back to
-- (centred, 70% of the area when unknown).

local function set_client_maximized(w, on)
	hl.dispatch(hl.dsp.window.fullscreen_state({ window = w, internal = 0, client = on and 1 or 0 }))
end

local function refresh_kirin()
	-- No event for a floating window's new size: kirin reads the windows
	-- again (the video wallpaper's pause rules).
	hl.dispatch(hl.dsp.exec_cmd("sleep 0.15; qs -c kirin ipc call windows changed"))
end

local function place(w, g)
	if not w.floating then hl.dispatch(hl.dsp.window.float({ action = "enable", window = w })) end
	hl.dispatch(hl.dsp.window.resize({ x = g.w, y = g.h, window = w }))
	hl.dispatch(hl.dsp.window.move({ x = g.x, y = g.y, window = w }))
	refresh_kirin()
end

local function geometry(w)
	local at, size = w.at or {}, w.size or {}
	return { x = at.x or at[1] or 0, y = at.y or at[2] or 0, w = size.x or size[1] or 0, h = size.y or size[2] or 0 }
end

function kirin_is_maximized(w)
	return w ~= nil and (w.fullscreen or 0) == 0 and (w.fullscreen_client or 0) == 1
end

-- on: true, false, or nil to toggle.
function kirin_window_maximize(w, on)
	if not w or not w.monitor then return end
	if on == nil then on = not kirin_is_maximized(w) end
	-- Hyprland's own maximize or fullscreen first undone.
	unfullscreen(w)
	if on then
		if not kirin_is_maximized(w) then
			-- A snapped window's normal size, not its half.
			local n = snapped[w.address]
			local g = geometry(w)
			before[w.address] = n and { x = g.x, y = g.y, w = n.w, h = n.h } or g
		end
		snapped[w.address] = nil
		save_runtime()
		set_client_maximized(w, true)
		place(w, work_area(w.monitor))
	else
		if not kirin_is_maximized(w) then return end
		set_client_maximized(w, false)
		local g = before[w.address]
		before[w.address] = nil
		save_runtime()
		if not g then
			local a = work_area(w.monitor)
			local bw, bh = math.floor(a.w * 0.7), math.floor(a.h * 0.7)
			g = { x = a.x + math.floor((a.w - bw) / 2), y = a.y + math.floor((a.h - bh) / 2), w = bw, h = bh }
		end
		place(w, g)
	end
end

-- A maximized or snapped window dragged by its titlebar (the kirin-bars
-- plugin calls this, synchronously, as the drag starts): back to its normal size under
-- the pointer, at the same share of the titlebar's width, as on Windows;
-- the drag then carries it.
function kirin_drag_start(address)
	local w = hl.get_window("address:" .. address)
	if not w or not w.monitor then return end
	local maximized = kirin_is_maximized(w)
	if not maximized and not snapped[w.address] then return end
	local g = geometry(w)
	local n = maximized and before[w.address] or snapped[w.address]
	if not n then
		local a = work_area(w.monitor)
		n = { w = math.floor(a.w * 0.7), h = math.floor(a.h * 0.7) }
	end
	local cur = hl.get_cursor_pos() or { x = g.x + g.w / 2, y = g.y }
	local fx = g.w > 0 and (cur.x - g.x) / g.w or 0.5
	if maximized then set_client_maximized(w, false) end
	before[w.address] = nil
	snapped[w.address] = nil
	save_runtime()
	-- The pointer stays on the titlebar: the window's top edge where it was.
	place(w, { x = math.floor(cur.x - fx * n.w + 0.5), y = g.y, w = n.w, h = n.h })
end

-- Back to an ordinary window, where it is (a half, tiling).
local function unmaximize_in_place(w)
	unfullscreen(w)
	if kirin_is_maximized(w) then set_client_maximized(w, false) end
	before[w.address] = nil
	save_runtime()
end

-- Hyprland's maximize asked for some other way (an app's own titlebar
-- button) in windows mode: kirin's instead.
hl.on("window.fullscreen", function(w)
	if kirin_window_mode ~= "windows" or not w or (w.fullscreen or 0) ~= 1 then return end
	if not on_desktop(w) then return end
	kirin_window_maximize(w, true)
end)

-- Into tiling: no window stays maximized our way.
function kirin_unmaximize_all()
	for _, w in ipairs(hl.get_windows()) do
		if kirin_is_maximized(w) then unmaximize_in_place(w) end
	end
	before = {}
	save_runtime()
end

-- Super + arrows in windows mode, as on Windows: left and right put the
-- window on that half of its monitor, up maximizes, down restores a
-- maximized window and minimizes one that isn't. (keybindings.lua calls
-- this in windows mode; in tiling the arrows move the focus.)
function kirin_window_arrow(direction)
	local w = hl.get_active_window()
	if not w or not on_desktop(w) then return end
	if direction == "down" then
		if kirin_is_maximized(w) then
			kirin_window_maximize(w, false)
		elseif (w.fullscreen or 0) ~= 0 then
			unfullscreen(w)
		else
			kirin_minimize(w)
		end
		return
	end
	if direction == "up" then
		if not kirin_is_maximized(w) then kirin_window_maximize(w, true) end
		return
	end
	if w.monitor then kirin_snap_window(w, direction, w.monitor) end
end


-- --- Placement (windows mode) -------------------------------------------------
--
-- Each app's window size and place are remembered (one record per app, by
-- class) and given back when it opens again, on the active monitor: the
-- size as it was, the place as the same share of the free room on the
-- monitor (x 0.3: 30% of the way from the left edge to the right one), so
-- it lands in the same part of a screen of another size.
-- Records: ~/.local/state/kirin/windows.lua (at most MAX_PLACES apps, the
-- least recently used dropped), updated when a window closes, minimizes,
-- and on the way to tiling.
-- They're given back by Hyprland window rules, applied before the window
-- shows (no jump): ~/.local/state/kirin/window_rules.lua, written from the
-- records and loaded with require, so Hyprland watches it and reloads its
-- config when it changes. A default rule floats every other window, centred.
-- Only move, size and center are used: they apply when a window opens and
-- not again on a config reload, as max_size would (every window shrunk and
-- centred again). A window too big for the monitor (80% of it without a
-- record) is fitted after it shows. All tagged kirin-placed, so they aren't taken
-- for windows that float by themselves (dialogs, fixed-size ones: left as
-- the app asks). In tiling the file has no rules.
-- A new window right on top of another one (same corner) is moved down and
-- right by a titlebar, as a cascade (after it shows: rules can't).
--
-- Minimized windows come back to the monitor and place they left (another
-- monitor's if that one is gone, fitted). A monitor unplugged: its windows
-- come to the primary one, fitted.

local places_file = state_dir .. "/windows.lua"
local RULES_MODULE = "window_rules"
local rules_file = state_dir .. "/" .. RULES_MODULE .. ".lua"
local MAX_PLACES = 200
local places = {}

do
	local ok, t = pcall(dofile, places_file)
	if ok and type(t) == "table" then places = t end
end

local function save_places()
	local keys = {}
	for k in pairs(places) do keys[#keys + 1] = k end
	table.sort(keys, function(a, b) return (places[a].used or 0) > (places[b].used or 0) end)
	local lines = { "-- Window sizes and places by app (kirin, hypr/modules/winmode.lua).", "return {" }
	for i, k in ipairs(keys) do
		if i > MAX_PLACES then
			places[k] = nil
		else
			local r = places[k]
			lines[#lines + 1] = string.format("\t[%q] = { w = %d, h = %d, fx = %.3f, fy = %.3f, used = %d },", k, r.w, r.h, r.fx, r.fy, r.used or 0)
		end
	end
	lines[#lines + 1] = "}"
	local f = io.open(places_file, "w")
	if not f then return end
	f:write(table.concat(lines, "\n"), "\n")
	f:close()
end

local function app_key(w)
	local c = w.class
	if not c or c == "" then c = w.initial_class end
	return (c and c ~= "") and c or nil
end

local function clamp(v, lo, hi)
	if hi < lo then return lo end
	return math.max(lo, math.min(hi, v))
end

-- Share of the free room (0..1) a window of size `size` at `pos` is at.
local function share(pos, start, room_size, size)
	if room_size <= size then return 0.5 end
	return clamp((pos - start) / (room_size - size), 0, 1)
end

-- A geometry put into an area: no bigger than it, at the given shares.
local function at_shares(a, w, h, fx, fy)
	w, h = math.min(w, a.w), math.min(h, a.h)
	return {
		w = w,
		h = h,
		x = a.x + math.floor(fx * (a.w - w) + 0.5),
		y = a.y + math.floor(fy * (a.h - h) + 0.5),
	}
end

local function centred(a, w, h)
	return at_shares(a, w, h, 0.5, 0.5)
end

local function bar_height()
	local h = hl.get_config("plugin.hyprbars.bar_height")
	return type(h) == "number" and h or 0
end

-- The room shares are measured in, as the rules' move expressions see it:
-- the monitor less the outer gaps (float_gaps) and the titlebar. The bar
-- isn't in it (the rules can't know it); Hyprland keeps windows off it.
local function room(m)
	local g = float_gaps()
	local bar = bar_height()
	local scale = m.scale or 1
	local mw, mh = m.width / scale, m.height / scale
	if (m.transform or 0) % 2 == 1 then mw, mh = mh, mw end
	return { x = m.x + g.left, y = m.y + g.top + bar, w = mw - g.left - g.right, h = mh - g.top - g.bottom - bar }
end

-- A record's geometry on a monitor, as its rule gives it, within the free
-- area (the bar aside).
local function from_record(m, r)
	local a = work_area(m)
	local g = at_shares(room(m), math.min(r.w, a.w), math.min(r.h, a.h), r.fx, r.fy)
	g.x = clamp(g.x, a.x, a.x + a.w - g.w)
	g.y = clamp(g.y, a.y, a.y + a.h - g.h)
	return g
end

-- RE2 pattern for exactly this class.
local function class_pattern(class)
	return "^" .. class:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?%{%}%|\\]", "\\%0") .. "$"
end

local function rules_text()
	local lines = {
		"-- Generated by kirin (hypr/modules/winmode.lua) from windows.lua: how each",
		"-- app's window opens in windows mode; no rules in tiling. Do not edit: it's",
		"-- rewritten on every change, and Hyprland reloads its config then.",
	}
	if kirin_window_mode == "windows" then
		local g = float_gaps()
		local bar = bar_height()
		lines[#lines + 1] = 'hl.window_rule({ name = "kirin-place-default", match = { class = ".*", modal = false }, float = true, center = true, tag = "+kirin-placed" })'
		local keys = {}
		for k in pairs(places) do keys[#keys + 1] = k end
		table.sort(keys)
		for _, k in ipairs(keys) do
			local r = places[k]
			local move = string.format("%d+%.3f*(monitor_w-window_w-%d) %d+%.3f*(monitor_h-window_h-%d)",
				g.left, r.fx, g.left + g.right, g.top + bar, r.fy, g.top + g.bottom + bar)
			lines[#lines + 1] = string.format('hl.window_rule({ name = %q, match = { class = %q, modal = false }, float = true, size = "%d %d", move = %q, tag = "+kirin-placed" })',
				"kirin-place-" .. k, class_pattern(k), r.w, r.h, move)
		end
	end
	return table.concat(lines, "\n") .. "\n"
end

-- Written only when it changes (each write reloads Hyprland's config).
-- In place, not replaced: Hyprland watches the file.
local function write_rules()
	local text = rules_text()
	local f = io.open(rules_file, "r")
	if f then
		local old = f:read("a")
		f:close()
		if old == text then return end
	end
	f = io.open(rules_file, "w")
	if not f then return end
	f:write(text)
	f:close()
end

-- Windows mode handles it: on a desktop, not one floating by itself.
local function managed(w)
	return w ~= nil and on_desktop(w) and not own_floats[w.address] and not w.pinned
end

-- `batch`: the rules file is written by the caller, once.
local function remember(w, batch)
	if not managed(w) then return end
	local key, m = app_key(w), w.monitor
	if not key or not m then return end
	local maximized = kirin_is_maximized(w)
	-- Maximized: its normal geometry, if known.
	local g = maximized and before[w.address] or (not maximized and geometry(w)) or nil
	if not g then return end
	-- Snapped: where it is, at its normal size.
	local n = snapped[w.address]
	if n and not maximized then g = { x = g.x, y = g.y, w = n.w, h = n.h } end
	local r = room(m)
	local fx = math.floor(share(g.x, r.x, r.w, g.w) * 1000 + 0.5) / 1000
	local fy = math.floor(share(g.y, r.y, r.h, g.h) * 1000 + 0.5) / 1000
	local prev = places[key]
	places[key] = { w = g.w, h = g.h, fx = fx, fy = fy, used = os.time() }
	save_places()
	if not batch and not (prev and prev.w == g.w and prev.h == g.h and prev.fx == fx and prev.fy == fy) then
		write_rules()
	end
end

function kirin_remember_all_places()
	for _, w in ipairs(hl.get_windows()) do
		if managed(w) then remember(w, true) end
	end
	write_rules()
end

-- For a mode switch (kirin_set_window_mode): the rules for that mode.
function kirin_write_window_rules()
	write_rules()
end

local function monitor_at_cursor()
	local ok, m = pcall(hl.get_monitor_at_cursor)
	if ok and m then return m end
	return hl.get_active_monitor() or primary()
end

-- The workspace a monitor shows in windows mode.
local function desktop_of(m)
	return desktops[m.name] or (m.active_workspace and m.active_workspace.id) or 1
end

-- Moved down and right by a titlebar while another window on the workspace
-- has its corner there; back to the area's corner past its edge.
local function cascade(w, g, a, ws_id)
	local step = math.max(titlebar_height(), 24)
	local others = {}
	for _, o in ipairs(hl.get_windows()) do
		if o.address ~= w.address and o.workspace and o.workspace.id == ws_id then
			others[#others + 1] = geometry(o)
		end
	end
	for _ = 1, 30 do
		local clash = false
		for _, o in ipairs(others) do
			if math.abs(o.x - g.x) <= 6 and math.abs(o.y - g.y) <= 6 then
				clash = true
				break
			end
		end
		if not clash then break end
		g.x, g.y = g.x + step, g.y + step
		if g.x + g.w > a.x + a.w or g.y + g.h > a.y + a.h then
			g.x, g.y = a.x, a.y
		end
	end
	return g
end

-- Placed at its normal geometry g, maximized over it if asked.
local function settle(w, g, a, maximized)
	if maximized then
		before[w.address] = g
		save_runtime()
		set_client_maximized(w, true)
		place(w, a)
	else
		place(w, g)
	end
end

local function to_desktop(w, m)
	local ws = desktop_of(m)
	if not (w.workspace and w.workspace.id == ws) then
		hl.dispatch(hl.dsp.window.move({ workspace = tostring(ws), window = w, follow = false }))
	end
	return ws
end

-- Shown where the rules put it; moved only if too big for the monitor, or
-- right on top of another window.
hl.on("window.open", function(w)
	if kirin_window_mode ~= "windows" or not w or not on_desktop(w) then return end
	if own_floats[w.address] then return end
	if not w.floating then hl.dispatch(hl.dsp.window.float({ action = "enable", window = w })) end
	local m = w.monitor
	if not m then return end
	local a = work_area(m)
	local g = geometry(w)
	local c = { x = g.x, y = g.y, w = g.w, h = g.h }
	local cap = places[app_key(w) or ""] and 1 or 0.8
	local maxw, maxh = math.floor(a.w * cap), math.floor(a.h * cap)
	if c.w > maxw or c.h > maxh then c = centred(a, math.min(c.w, maxw), math.min(c.h, maxh)) end
	c = cascade(w, c, a, w.workspace.id)
	if c.x ~= g.x or c.y ~= g.y or c.w ~= g.w or c.h ~= g.h then place(w, c) end
end)

hl.on("window.close", function(w)
	if not w then return end
	-- Before its normal geometry (maximized) is dropped.
	if kirin_window_mode == "windows" then remember(w) end
	if before[w.address] or minimized_from[w.address] or snapped[w.address] then
		before[w.address] = nil
		minimized_from[w.address] = nil
		snapped[w.address] = nil
		save_runtime()
	end
end)

-- --- Minimize and back ---------------------------------------------------------

function kirin_minimize(w)
	if not w or not on_desktop(w) then return end
	local maximized = kirin_is_maximized(w)
	minimized_from[w.address] = {
		monitor = w.monitor and w.monitor.name,
		area = w.monitor and work_area(w.monitor),
		g = maximized and before[w.address] or geometry(w),
		maximized = maximized,
	}
	save_runtime()
	if kirin_window_mode == "windows" then remember(w) end
	hl.dispatch(hl.dsp.window.move({ workspace = MINIMIZED, window = w, follow = false }))
end

-- Back from minimized: to the monitor and place it left; that monitor gone
-- (or not known), to the one under the pointer, fitted there.
function kirin_unminimize(w)
	if not w then return end
	local from = minimized_from[w.address]
	minimized_from[w.address] = nil
	if from then save_runtime() end
	local m = from and from.monitor and hl.get_monitor(from.monitor)
	local same = m ~= nil
	if not m then m = monitor_at_cursor() end
	if not m then return end
	local a = work_area(m)
	local g, maximized
	if from and from.g then
		maximized = from.maximized
		if same then
			g = from.g
		else
			local fa = from.area or a
			g = at_shares(a, from.g.w, from.g.h, share(from.g.x, fa.x, fa.w, from.g.w), share(from.g.y, fa.y, fa.h, from.g.h))
		end
	else
		local r = places[app_key(w) or ""]
		if r then
			g = from_record(m, r)
		else
			local size = w.size or {}
			g = centred(a, math.min(size.x or size[1] or a.w, math.floor(a.w * 0.8)), math.min(size.y or size[2] or a.h, math.floor(a.h * 0.8)))
		end
	end
	to_desktop(w, m)
	settle(w, g, a, maximized)
	hl.dispatch(hl.dsp.focus({ window = w }))
	hl.dispatch(hl.dsp.window.alter_zorder({ mode = "top", window = w }))
end

-- An app minimizing itself (its own titlebar button).
hl.on("window.minimize", function(w)
	if kirin_window_mode ~= "windows" or not w or not on_desktop(w) then return end
	kirin_minimize(w)
end)

-- --- A monitor unplugged ---------------------------------------------------------

-- Its workspaces went to the other monitors (workspaces.lua), where in
-- windows mode they aren't shown: their windows come to the primary
-- monitor's desktop, fitted, in a cascade; maximized ones stay maximized.
local function rescue_windows()
	if kirin_window_mode ~= "windows" then return end
	remember_desktops()
	local shown = {}
	for _, m in ipairs(hl.get_monitors()) do
		if m.active_workspace then shown[m.active_workspace.id] = true end
	end
	local p = primary()
	if not p then return end
	local a = work_area(p)
	for _, w in ipairs(hl.get_windows()) do
		if on_desktop(w) and not shown[w.workspace.id] then
			local ws = to_desktop(w, p)
			local maximized = kirin_is_maximized(w)
			local n = maximized and before[w.address] or geometry(w)
			local g = cascade(w, centred(a, n.w, n.h), a, ws)
			settle(w, g, a, maximized)
		end
	end
end

-- A monitor's size or place changed (scale, mode, rotation, arrangement):
-- its maximized windows fill its work area again, the others are fitted
-- into it (no bigger, not past its edges).
function kirin_fit_windows()
	if kirin_window_mode ~= "windows" then return end
	for _, w in ipairs(hl.get_windows()) do
		local m = w.monitor
		if on_desktop(w) and m and not own_floats[w.address] and (w.fullscreen or 0) == 0 then
			local a = work_area(m)
			local g = geometry(w)
			local c
			if kirin_is_maximized(w) then
				c = { x = a.x, y = a.y, w = a.w, h = a.h }
			else
				local cw, ch = math.min(g.w, a.w), math.min(g.h, a.h)
				c = { w = cw, h = ch, x = clamp(g.x, a.x, a.x + a.w - cw), y = clamp(g.y, a.y, a.y + a.h - ch) }
			end
			if math.abs(c.x - g.x) > 1 or math.abs(c.y - g.y) > 1 or math.abs(c.w - g.w) > 1 or math.abs(c.h - g.h) > 1 then
				place(w, c)
			end
		end
	end
end

hl.on("monitor.layout_changed", function()
	-- Once the monitors have settled (positions come a moment later).
	hl.timer(kirin_fit_windows, { timeout = 500, type = "oneshot" })
end)

hl.on("monitor.removed", function()
	-- After workspaces.lua has moved the workspaces (400 ms).
	hl.timer(rescue_windows, { timeout = 700, type = "oneshot" })
end)

-- --- Snapping (windows mode) ---------------------------------------------------
--
-- As on Windows: a window dragged by its titlebar to a screen edge goes on
-- that half of the screen, to a corner on that quarter, to the top edge
-- maximized. While it's held there kirin shows where (a custom Hyprland
-- event, "kirinsnap show <monitor> x y w h" or "kirinsnap hide": the
-- quickshell module snap/SnapPreview). The kirin-bars plugin tells the
-- zone (on_drag_zone) and the drop (on_drag_end); see bars.lua.
-- The halves and quarters fill the same area a maximized window does (the
-- bar aside, the outer gaps), with the inner gaps between them and each
-- titlebar inside its part.

-- The zone each dragged window is held in, by address: { zone, monitor }.
local snap_zone = {}

local function gaps_in()
	local gi = hl.get_config("general.gaps_in")
	if type(gi) == "number" then return gi * 2 end
	if type(gi) == "table" then return (gi.left or 4) + (gi.right or 4) end
	return 8
end

-- The geometry (the window's, without its titlebar) for a zone on a monitor.
local function snap_geometry(m, zone)
	local a = work_area(m)
	if zone == "top" then return a end
	local gap = gaps_in()
	local bar = titlebar_height()
	local hw = math.floor((a.w - gap) / 2)
	local hh = math.floor((a.h - gap - bar) / 2)
	local left = { x = a.x, w = hw }
	local right = { x = a.x + a.w - hw, w = hw }
	local upper = { y = a.y, h = hh }
	local lower = { y = a.y + a.h - hh, h = hh }
	local full = { y = a.y, h = a.h }
	local pick = {
		left = { left, full }, right = { right, full },
		topleft = { left, upper }, topright = { right, upper },
		bottomleft = { left, lower }, bottomright = { right, lower },
	}
	local p = pick[zone]
	if not p then return nil end
	return { x = p[1].x, y = p[2].y, w = p[1].w, h = p[2].h }
end

local function snap_event(text)
	hl.dispatch(hl.dsp.event("kirinsnap " .. text))
end

-- Snapped to a zone: its normal size kept (unless it was snapped already),
-- maximized for "top".
function kirin_snap_window(w, zone, m)
	if zone == "top" then
		snapped[w.address] = nil
		save_runtime()
		kirin_window_maximize(w, true)
		return
	end
	local g = snap_geometry(m, zone)
	if not g then return end
	local normal = kirin_is_maximized(w) and before[w.address] or snapped[w.address] or geometry(w)
	unmaximize_in_place(w)
	snapped[w.address] = { w = normal.w, h = normal.h }
	save_runtime()
	place(w, g)
end

-- The pointer, dragging a window, at a screen edge (zone) or off it ("").
function kirin_snap_zone(address, zone, monitor)
	if kirin_window_mode ~= "windows" then return end
	local m = monitor ~= "" and hl.get_monitor(monitor) or nil
	local g = m and zone ~= "" and snap_geometry(m, zone) or nil
	if not g then
		snap_zone[address] = nil
		snap_event("hide")
		return
	end
	snap_zone[address] = { zone = zone, monitor = monitor }
	-- The preview takes in the titlebar.
	local bar = titlebar_height()
	snap_event(string.format("show %s %d %d %d %d", monitor, g.x, g.y - bar, g.w, g.h + bar))
end

-- The drag over: snapped if it ended in a zone.
function kirin_snap_drop(address)
	local s = snap_zone[address]
	snap_zone[address] = nil
	if not s then return end
	snap_event("hide")
	if kirin_window_mode ~= "windows" then return end
	local w = hl.get_window("address:" .. address)
	local m = hl.get_monitor(s.monitor)
	if w and m then kirin_snap_window(w, s.zone, m) end
end

-- kirin's taskbar (windows mode). A click: a minimized window comes back
-- (kirin_unminimize), the active one minimizes, another is brought up and
-- focused. Middle click: close.
function kirin_taskbar_activate(address)
	local w = hl.get_window("address:" .. address)
	if not w then return end
	local ws = w.workspace
	if ws and ws.name == MINIMIZED then
		kirin_unminimize(w)
		return
	end
	local active = hl.get_active_window()
	if active and active.address == w.address then
		kirin_minimize(w)
		return
	end
	hl.dispatch(hl.dsp.focus({ window = w }))
	hl.dispatch(hl.dsp.window.alter_zorder({ mode = "top", window = w }))
end

-- Brought up and focused, from minimized too; never minimized (the window
-- previews, the menu).
function kirin_taskbar_focus(address)
	local w = hl.get_window("address:" .. address)
	if not w then return end
	local active = hl.get_active_window()
	local ws = w.workspace
	if (ws and ws.name == MINIMIZED) or not (active and active.address == w.address) then
		kirin_taskbar_activate(address)
	end
end

function kirin_taskbar_minimize(address)
	local w = hl.get_window("address:" .. address)
	if not w then return end
	local ws = w.workspace
	if ws and ws.name ~= MINIMIZED then kirin_minimize(w) end
end

function kirin_taskbar_close(address)
	local w = hl.get_window("address:" .. address)
	if w then hl.dispatch(hl.dsp.window.close({ window = w })) end
end

-- --- Alt+Tab ---------------------------------------------------------------------
--
-- As on Windows: Alt+Tab shows the windows, most recently used first, the
-- one before the current selected; Tab again (Alt held) selects the next,
-- Shift+Tab the one before; letting go of Alt brings the selected one up.
-- A quick Alt+Tab just goes back to the previous window (kirin shows the
-- picker only after a moment). Alt+Escape cancels; a click on a window in
-- the picker brings it up. Minimized windows (windows mode) come back to
-- where they were. Both modes.
-- The picker is kirin's (modules/switcher): a custom Hyprland event,
-- "kirinswitch show <index> <address,...>" or "kirinswitch hide".

local switch_run = nil -- { list = { addresses, most recent first }, index, at }

local function switch_candidates()
	local list = {}
	for _, w in ipairs(hl.get_windows()) do
		local ws = w.workspace
		if ws and (on_desktop(w) or ws.name == MINIMIZED) then list[#list + 1] = w end
	end
	table.sort(list, function(a, b) return (a.focus_history_id or 1e9) < (b.focus_history_id or 1e9) end)
	return list
end

local function switch_to(w)
	if w.workspace and w.workspace.name == MINIMIZED then
		kirin_unminimize(w)
		return
	end
	hl.dispatch(hl.dsp.focus({ window = w }))
	hl.dispatch(hl.dsp.window.alter_zorder({ mode = "top", window = w }))
end

local function switch_event(text)
	hl.dispatch(hl.dsp.event("kirinswitch " .. text))
end

function kirin_switch_step(dir)
	-- A run left over (Alt's release missed): a new one.
	if switch_run and os.time() - switch_run.at > 60 then switch_run = nil end
	if not switch_run then
		local list = switch_candidates()
		if #list < 2 then return end
		local addresses = {}
		for i, w in ipairs(list) do addresses[i] = w.address end
		switch_run = { list = addresses, index = 1 }
	end
	switch_run.at = os.time()
	local n = #switch_run.list
	switch_run.index = (switch_run.index - 1 + dir) % n + 1
	switch_event(string.format("show %d %s", switch_run.index, table.concat(switch_run.list, ",")))
end

-- Alt let go: the selected window comes up.
function kirin_switch_end()
	local run = switch_run
	switch_run = nil
	if not run then return end
	switch_event("hide")
	local w = hl.get_window("address:" .. run.list[run.index])
	if w and run.index ~= 1 then switch_to(w) end
end

function kirin_switch_cancel()
	if not switch_run then return end
	switch_run = nil
	switch_event("hide")
end

-- A click in the picker.
function kirin_switch_pick(address)
	switch_run = nil
	switch_event("hide")
	local w = hl.get_window("address:" .. address)
	if w then switch_to(w) end
end

hl.bind("ALT + Tab", function() kirin_switch_step(1) end)
hl.bind("ALT + SHIFT + Tab", function() kirin_switch_step(-1) end)
hl.bind("ALT + Escape", kirin_switch_cancel)

-- Alt let go: the run is over. Two ways, whichever comes: a release bind
-- on Alt itself (the usual "bindr = ALT, ALT_L" form; the key still goes to
-- apps), and the raw key events.
hl.bind("ALT + Alt_L", kirin_switch_end, { release = true, non_consuming = true, transparent = true })
hl.bind("ALT + Alt_R", kirin_switch_end, { release = true, non_consuming = true, transparent = true })

-- The raw key event: (xkb keycode, time, state), state 0 when let go;
-- Alt is 64 (left) or 108 (right).
hl.on("input.keyboard.key", function(keycode, _, state)
	if switch_run and (keycode == 64 or keycode == 108) and state == 0 then
		kirin_switch_end()
	end
end)

-- Only in tiling: a dispatcher wrapped so it does nothing in windows mode
-- (workspace switching, the column keys).
function kirin_tiling_only(dispatcher)
	return function()
		if kirin_window_mode ~= "windows" then hl.dispatch(dispatcher) end
	end
end

-- Its key: keybindings.lua (window_mode).

-- Started (or the config reloaded) in windows mode: as it was left. Nothing
-- to move (on start there are no windows; on a reload they're as they are).
if saved_mode() == "windows" and kirin_window_mode ~= "windows" then
	kirin_window_mode = "windows"
	remember_desktops()
	set_bars(true)
elseif kirin_window_mode == "windows" then
	remember_desktops()
	set_bars(true)
end

-- The window rules (Placement) for the mode, then loaded: with require, so
-- Hyprland watches the file and reloads its config when it changes.
kirin_write_window_rules()
package.path = state_dir .. "/?.lua;" .. package.path
local ok_rules, err_rules = pcall(require, RULES_MODULE)
if not ok_rules then print("kirin: window rules: " .. tostring(err_rules)) end

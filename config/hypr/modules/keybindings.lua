-- Keys. The shortcuts below can be changed in kirin (Settings → Shortcuts):
-- kirin_apply_settings() (modules/settings.lua) passes the changed ones to
-- kirin_apply_shortcuts() as { [id] = "MODS + key" } ("" turns one off).
-- What's here are the defaults; services/Shortcuts.qml in kirin has the same
-- list (ids, defaults) for the settings page.
-- Single shortcuts are a whole combination; groups (the arrows, the
-- workspace numbers, the wheel) only take their modifiers.
-- Media keys and Alt+Tab (winmode.lua) aren't changeable.
--
-- Kept to what's needed day to day: the lock, logging out and the like are
-- in kirin (the bar's power menu), not on keys.
--
-- Super + arrows: in tiling, the focus moves; in windows mode (winmode.lua)
-- the window snaps to a half, maximizes, restores or minimizes.
-- Columns (the scrolling layout, modules/look_and_feel.lua), as in niri:
-- the arrows move between windows (and scroll the strip), Ctrl moves the
-- column, Shift moves the window (into the next column, or out of its own).
-- Workspaces and columns are tiling things: in windows mode (winmode.lua,
-- one workspace per monitor, floating windows) these do nothing.

local function tiling(dispatcher)
	return function()
		if kirin_window_mode ~= "windows" then hl.dispatch(dispatcher) end
	end
end

local function arrow(direction)
	return function()
		if kirin_window_mode == "windows" and kirin_window_arrow then
			kirin_window_arrow(direction)
		else
			hl.dispatch(hl.dsp.focus({ direction = direction }))
		end
	end
end

local shots = "~/Pictures/Screenshots/$(date +%Y-%m-%d_%H-%M-%S).png"

local single = {
	{ id = "launcher", keys = "SUPER + SPACE", run = hl.dsp.exec_cmd("qs -c kirin ipc call launcher toggle") },
	{ id = "settings", keys = "SUPER + I", run = hl.dsp.exec_cmd("qs -c kirin ipc call settings toggle") },
	{ id = "terminal", keys = "SUPER + Q", run = hl.dsp.exec_cmd(terminal) },
	{ id = "files", keys = "SUPER + E", run = hl.dsp.exec_cmd(fileManager) },
	{ id = "close", keys = "SUPER + C", run = hl.dsp.window.close() },
	{ id = "fullscreen", keys = "SUPER + SHIFT + F", run = hl.dsp.window.fullscreen() },
	{ id = "window_mode", keys = "SUPER + CTRL + SHIFT + T", run = function() if kirin_toggle_window_mode then kirin_toggle_window_mode() end end },
	{ id = "column_full", keys = "SUPER + F", run = tiling(hl.dsp.layout("colresize 1.0")) },
	{ id = "column_narrower", keys = "SUPER + minus", run = tiling(hl.dsp.layout("colresize -0.1")) },
	{ id = "column_wider", keys = "SUPER + equal", run = tiling(hl.dsp.layout("colresize +0.1")) },
	{ id = "column_center", keys = "SUPER + X", run = tiling(hl.dsp.layout("center")) },
	{ id = "screenshot_area", keys = "Print", run = hl.dsp.exec_cmd("grimblast --notify --freeze copysave area " .. shots) },
	{ id = "screenshot_screen", keys = "SHIFT + Print", run = hl.dsp.exec_cmd("grimblast --notify copysave output " .. shots) },
}

local workspace_go, workspace_move = {}, {}
for i = 1, 10 do
	local key = tostring(i % 10)
	workspace_go[#workspace_go + 1] = { key, tiling(hl.dsp.focus({ workspace = i })) }
	workspace_move[#workspace_move + 1] = { key, tiling(hl.dsp.window.move({ workspace = i })) }
end

local groups = {
	{ id = "arrows", mods = "SUPER", keys = {
		{ "left", arrow("left") }, { "right", arrow("right") }, { "up", arrow("up") }, { "down", arrow("down") },
	} },
	{ id = "arrows_column", mods = "SUPER + CTRL", keys = {
		{ "left", tiling(hl.dsp.layout("swapcol l")) }, { "right", tiling(hl.dsp.layout("swapcol r")) },
	} },
	{ id = "arrows_window", mods = "SUPER + SHIFT", keys = {
		{ "left", hl.dsp.window.move({ direction = "left" }) }, { "right", hl.dsp.window.move({ direction = "right" }) },
		{ "up", hl.dsp.window.move({ direction = "up" }) }, { "down", hl.dsp.window.move({ direction = "down" }) },
	} },
	{ id = "workspace_go", mods = "SUPER", keys = workspace_go },
	{ id = "workspace_move", mods = "SUPER + SHIFT", keys = workspace_move },
	{ id = "wheel_workspaces", mods = "SUPER", keys = {
		{ "mouse_down", tiling(hl.dsp.focus({ workspace = "e+1" })) }, { "mouse_up", tiling(hl.dsp.focus({ workspace = "e-1" })) },
	} },
	-- The wheel scrolls the strip of columns.
	{ id = "wheel_columns", mods = "SUPER + SHIFT", keys = {
		{ "mouse_down", tiling(hl.dsp.layout("move +col")) }, { "mouse_up", tiling(hl.dsp.layout("move -col")) },
	} },
}

-- The binds made, to take back when the shortcuts change.
local made = {}

function kirin_apply_shortcuts(changed)
	changed = type(changed) == "table" and changed or {}
	for _, b in ipairs(made) do pcall(function() b:remove() end) end
	made = {}
	local function bind(keys, run)
		if type(keys) ~= "string" or keys == "" then return end
		local ok, b = pcall(hl.bind, keys, run)
		if ok and b then made[#made + 1] = b end
	end
	for _, a in ipairs(single) do
		local keys = changed[a.id]
		if keys == nil then keys = a.keys end
		bind(keys, a.run)
	end
	for _, g in ipairs(groups) do
		local mods = changed[g.id]
		if mods == nil then mods = g.mods end
		-- Off (no modifier: bare arrows or numbers would be taken from apps).
		if type(mods) == "string" and mods ~= "" then
			for _, k in ipairs(g.keys) do bind(mods .. " + " .. k[1], k[2]) end
		end
	end
end

kirin_apply_shortcuts(nil)

-- Recording a shortcut in kirin's settings: Hyprland's binds are set aside
-- (an empty submap), so the keys reach the settings window instead of doing
-- what they're bound to. Back after 15 s at the latest.
-- (A submap needs a bind to exist: one on a key nobody presses.)
hl.define_submap("kirin-capture", function()
	hl.bind("SUPER + CTRL + ALT + SHIFT + F24", hl.dsp.submap("reset"))
end)

function kirin_capture_start()
	hl.dispatch(hl.dsp.submap("kirin-capture"))
	hl.timer(function()
		if hl.get_current_submap() == "kirin-capture" then hl.dispatch(hl.dsp.submap("reset")) end
	end, { timeout = 15000, type = "oneshot" })
end

function kirin_capture_end()
	hl.dispatch(hl.dsp.submap("reset"))
end

-- Each also shows kirin's OSD (only key presses do, not other changes).
-- Brightness is faded by kirin; plain brightnessctl when kirin isn't running.
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+; qs -c kirin ipc call osd volume"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-; qs -c kirin ipc call osd volume"), { locked = true, repeating = true })
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle; qs -c kirin ipc call osd volume"), { locked = true, repeating = true })
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle; qs -c kirin ipc call osd mic"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("qs -c kirin ipc call osd brightnessStep 5 || brightnessctl -e4 -n2 set 5%+"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("qs -c kirin ipc call osd brightnessStep -- -5 || brightnessctl -e4 -n2 set 5%-"), { locked = true, repeating = true })

hl.bind("XF86AudioNext", hl.dsp.exec_cmd("qs -c kirin ipc call media next"), { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("qs -c kirin ipc call media playPause"), { locked = true })
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("qs -c kirin ipc call media playPause"), { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("qs -c kirin ipc call media previous"), { locked = true })

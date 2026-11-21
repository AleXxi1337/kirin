-- See https://wiki.hypr.land/Configuring/Basics/Monitors/

-- Display settings from kirin (Settings → Display), passed in by
-- kirin_apply_settings() in modules/settings.lua.
--   scale:    the primary monitor's scale; default for monitors not listed
--   monitors: { [output] = { scale = 1.5, x = 0, y = 0, mode = "1920x1080@60",
--             transform = 0, vrr = 0, mirror = "eDP-1" }, ... } for the connected
--             monitors. output is "desc:<description>", or the port name for
--             identical monitors. Without x/y Hyprland places the monitor itself
--             (the combination has no saved layout yet).
-- Logical size of a monitor (as positions use): mode size / scale, swapped
-- when rotated by 90° or 270°.
local function logical_size(m)
	local w, h = m.width / m.scale, m.height / m.scale
	if m.transform % 2 == 1 then w, h = h, w end
	return w, h
end

-- Rearranging monitors moves them under the cursor, which stays at the same
-- global coordinates and so jumps to another monitor or off-screen. Remember
-- where it is relative to its monitor, and put it back there afterwards.
local function remember_cursor()
	local ok, monitor = pcall(hl.get_monitor_at_cursor)
	if not ok then return nil end
	if not monitor then return nil end
	local pos = hl.get_cursor_pos()
	local w, h = logical_size(monitor)
	return { name = monitor.name, rx = (pos.x - monitor.x) / w, ry = (pos.y - monitor.y) / h }
end

local function restore_cursor(saved)
	if not saved then return end
	-- Monitor changes are applied after this call returns.
	hl.timer(function()
		local monitor = hl.get_monitor(saved.name)
		if not monitor then return end
		local w, h = logical_size(monitor)
		hl.dispatch(hl.dsp.cursor.move({ x = monitor.x + saved.rx * w, y = monitor.y + saved.ry * h }))
	end, { timeout = 100, type = "oneshot" })
end

function kirin_apply_display(scale, monitors)
	scale = tonumber(scale) or 1.0
	local cursor = remember_cursor()
	hl.monitor({ output = "", mode = "preferred", position = "auto", scale = scale })

	for output, m in pairs(type(monitors) == "table" and monitors or {}) do
		if type(m) == "table" then
			local position = "auto"
			if m.x and m.y then
				position = string.format("%dx%d", math.floor(tonumber(m.x)), math.floor(tonumber(m.y)))
			end
			hl.monitor({
				output = output,
				mode = type(m.mode) == "string" and m.mode or "preferred",
				position = position,
				scale = tonumber(m.scale) or scale,
				transform = tonumber(m.transform) or 0,
				vrr = tonumber(m.vrr) or 0,
				-- Port name of the monitor to copy; "" extends the desktop.
				mirror = type(m.mirror) == "string" and m.mirror or "",
			})
		end
	end

	-- The lid closed with another monitor on: the built-in screen stays off
	-- (modules/lid.lua).
	if kirin_lid_apply then kirin_lid_apply() end

	restore_cursor(cursor)
end

kirin_apply_display(1)

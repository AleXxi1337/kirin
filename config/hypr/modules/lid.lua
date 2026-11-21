-- The lid closed with another monitor connected: the built-in screen goes
-- off and work goes on on the others (logind ignores the lid when docked:
-- nixos-config modules/sleep.nix). Opened: the screen comes back where
-- kirin's display settings put it. Without another monitor logind puts the
-- machine to sleep, and this leaves the screen alone.

-- Read by kirin_apply_display (modules/monitors.lua): a monitor change
-- while closed keeps the screen off.
kirin_lid_closed = false

local function builtin()
	for _, m in ipairs(hl.get_monitors({ all = true })) do
		local name = m.name or ""
		if name:find("^eDP") or name:find("^LVDS") or name:find("^DSI") then
			return name
		end
	end
	return nil
end

local function others_than(name)
	for _, m in ipairs(hl.get_monitors()) do
		if m.name ~= name then return true end
	end
	return false
end

-- Turns the built-in screen off if the lid is closed and there's somewhere
-- else to work.
function kirin_lid_apply()
	local name = builtin()
	if name and kirin_lid_closed and others_than(name) then
		hl.monitor({ output = name, disabled = true })
	end
end

local function reopen()
	local name = builtin()
	if not name then return end
	hl.monitor({ output = name, mode = "preferred", position = "auto" })
	-- kirin's layout for it (scale, position) again.
	local state = os.getenv("XDG_STATE_HOME") or (os.getenv("HOME") .. "/.local/state")
	local ok, settings = pcall(dofile, state .. "/kirin/hyprland.lua")
	if ok and kirin_apply_settings then kirin_apply_settings(settings) end
end

hl.bind("switch:on:Lid Switch", function()
	kirin_lid_closed = true
	kirin_lid_apply()
end, { locked = true })

hl.bind("switch:off:Lid Switch", function()
	kirin_lid_closed = false
	reopen()
end, { locked = true })

-- Closed already when Hyprland starts (or reloads).
for _, path in ipairs({ "/proc/acpi/button/lid/LID/state", "/proc/acpi/button/lid/LID0/state" }) do
	local f = io.open(path, "r")
	if f then
		local text = f:read("*a") or ""
		f:close()
		kirin_lid_closed = text:find("closed") ~= nil
		break
	end
end
kirin_lid_apply()

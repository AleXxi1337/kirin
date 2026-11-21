-- kirin's lock screen is see-through (misc.session_lock_xray): the desktop
-- under it shows, and before locking every monitor moves to an empty
-- workspace (name:kirin-lock-<monitor>), so it's only the wallpaper. A
-- window an app opens meanwhile would land there, in sight: it's sent at
-- once to the workspace its monitor showed before locking.
--
-- kirin calls kirin_lock_guard({ [monitor] = workspace, ... }) on locking
-- and kirin_lock_guard(nil) on unlocking.

local homes = nil

function kirin_lock_guard(map)
	homes = map
end

local function guard(w)
	if not homes or not w then return end
	local ws = w.workspace
	if not ws or not ws.name or not ws.name:find("^kirin%-lock") then return end
	local mon = w.monitor and w.monitor.name
	local home = (mon and homes[mon]) or select(2, next(homes))
	if not home then return end
	hl.dispatch(hl.dsp.window.move({ workspace = home, window = w, follow = false }))
end

-- Focus follows a new window (or an app asking for it) to its workspace:
-- while locked, every monitor goes straight back to its empty one.
local function stay()
	if not homes then return end
	for _, m in ipairs(hl.get_monitors()) do
		local ws = hl.get_active_workspace(m.name)
		if ws and not (ws.name or ""):find("^kirin%-lock") then
			hl.dispatch(hl.dsp.focus({ monitor = m.name }))
			hl.dispatch(hl.dsp.focus({ workspace = "name:kirin-lock-" .. m.name }))
		end
	end
end

hl.on("workspace.active", stay)

-- Early, before it's drawn; again once open, in case it had no workspace yet.
hl.on("window.open_early", guard)
hl.on("window.open", guard)

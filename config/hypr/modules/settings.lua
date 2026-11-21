-- Settings made in kirin's settings window that affect Hyprland.
-- Quickshell writes them to ~/.local/state/kirin/hyprland.lua and calls
-- kirin_apply_settings() on every change; on (re)load they're applied from
-- that file. Colours have their own file and module (modules/colors.lua).

function kirin_apply_settings(s)
	if type(s) ~= "table" then return end
	if kirin_apply_display then kirin_apply_display(s.scale, s.monitors) end
	if kirin_apply_animations then kirin_apply_animations(s.animation_speed) end
	-- Keyboard, mouse and touchpad (Settings → Input), over modules/input.lua.
	if type(s.input) == "table" then hl.config({ input = s.input }) end
	-- Shortcuts changed from their defaults (Settings → Shortcuts).
	if kirin_apply_shortcuts then kirin_apply_shortcuts(s.shortcuts) end
	-- The primary monitor: where the cursor starts when Hyprland launches.
	if type(s.primary) == "string" and s.primary ~= "" then
		hl.config({ cursor = { default_monitor = s.primary } })
	end
	-- Workspaces are split from the primary monitor (modules/workspaces.lua).
	if type(s.primary) == "string" and s.primary ~= kirin_primary then
		kirin_primary = s.primary
		if kirin_distribute_workspaces then kirin_distribute_workspaces() end
	end
end

local state = os.getenv("XDG_STATE_HOME") or (os.getenv("HOME") .. "/.local/state")
local ok, settings = pcall(dofile, state .. "/kirin/hyprland.lua")
if ok then kirin_apply_settings(settings) end

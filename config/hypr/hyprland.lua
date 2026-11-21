-- kirin's Hyprland config: ~/.kirin/config/hypr, linked here by `kirin init`.

-- The titlebar plugin (kirin-bars): your own build from ~/.kirin
-- (`kirin plugins --build`) if there is one and it loads, else the
-- system's (the NixOS module writes /etc/kirin/plugins.lua; elsewhere a
-- plugins.lua next to this file).
do
	local own = (os.getenv("HOME") or "") .. "/.local/share/kirin/plugins/kirin-bars/lib/kirin-bars.so"
	local f = io.open(own, "r")
	local loaded = false
	if f then
		f:close()
		loaded = pcall(hl.plugin.load, own)
	end
	if not loaded and not pcall(dofile, "/etc/kirin/plugins.lua") then
		pcall(require, "plugins")
	end
end
require("modules.monitors")
require("modules.programs")
require("modules.autostart")
require("modules.look_and_feel")
require("modules.animations")
require("modules.input")
require("modules.keybindings")
require("modules.workspaces")
require("modules.lock")
require("modules.lid")
require("modules.window_rules")
require("modules.bars")
require("modules.colors")
require("modules.winmode")
require("modules.settings")
pcall(require, "user")

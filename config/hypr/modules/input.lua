-- Defaults only: kirin's Settings → Input sets these (services/HyprSync.qml
-- writes them, modules/settings.lua applies them over this). The gesture
-- stays here: Hyprland can't take a gesture back at runtime.
hl.config({
	input = {
		kb_layout = "us, ru",
		kb_variant = "",
		kb_model = "",
		kb_options = "grp:alt_shift_toggle",
		kb_rules = "",

		follow_mouse = 1,

		sensitivity = 1,
		accel_profile = "flat",

		touchpad = {
			natural_scroll = true,
			scroll_factor = 0.3,
			-- A two-finger click is a right click.
			clickfinger_behavior = true,
		},
	},
})

-- As in niri: three fingers sideways scroll the columns, up and down
-- switch workspaces (they're stacked up and down on the bar too).
hl.gesture({
	fingers = 3,
	direction = "horizontal",
	action = "scroll_move",
})

hl.gesture({
	fingers = 3,
	direction = "vertical",
	action = "workspace",
})

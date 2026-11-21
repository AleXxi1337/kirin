hl.window_rule({
	name = "suppress-maximize-events",
	match = { class = ".*" },
	suppress_event = "maximize",
})

hl.window_rule({
	name = "fix-xwayland-drags",
	match = {
		class = "^$",
		title = "^$",
		xwayland = true,
		float = true,
		fullscreen = false,
		pin = false,
	},
	no_focus = true,
})

hl.window_rule({
	name = "move-hyprland-run",
	match = { class = "hyprland-run" },
	move = "20 monitor_h-120",
	float = true,
})


hl.window_rule({
	name = "nautilus",
	match = { class = "org.gnome.Nautilus" },
	size = "900 600",
	center = true,
})

hl.layer_rule({
	name = "slurp-no-anim",
	match = { namespace = "^selection$" },
	no_anim = true,
})

hl.layer_rule({
	name = "grimblast-freeze-no-anim",
	match = { namespace = "^hyprpicker$" },
	no_anim = true,
})

-- kirin's settings window is an ordinary window: tiled, no rule.

-- The launcher animates itself.
hl.layer_rule({
	name = "kirin-launcher-no-anim",
	match = { namespace = "^kirin-launcher$" },
	no_anim = true,
})

-- So do the bar's cards.
hl.layer_rule({
	name = "kirin-bar-card-no-anim",
	match = { namespace = "^kirin-bar-card$" },
	no_anim = true,
})

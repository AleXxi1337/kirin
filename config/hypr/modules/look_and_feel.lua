hl.config({
	general = {
		gaps_in = 4,
		gaps_out = 10,
		-- The same for floating windows: a maximized one and the halves
		-- (windows mode, winmode.lua) keep them, as one window in tiling does.
		float_gaps = 10,

		border_size = 1,

		col = {
			active_border = "rgba(ffffff18)",
			inactive_border = "rgba(ffffff0a)",
		},

		resize_on_border = true,
		allow_tearing = false,
		-- Windows in columns on a strip that scrolls sideways, as in niri.
		layout = "scrolling",
	},

	decoration = {
		rounding = 16,
		rounding_power = 2,

		active_opacity = 1.0,
		inactive_opacity = 1.0,

		shadow = {
			enabled = true,
			range = 25,
			render_power = 3,
			color = 0x30000000,
			offset = { 0, 4 },
		},

		blur = {
			enabled = false,
			special = true,
		},
	},

	animations = {
		enabled = true,
	},

	dwindle = {
		preserve_split = true,
	},

	master = {
		new_status = "master",
	},

	scrolling = {
		-- A lone window fills the screen.
		fullscreen_on_one_column = true,
		-- New columns: half the screen; Super+minus/equal change it from there.
		column_width = 0.5,
		explicit_column_widths = "0.333, 0.5, 0.667, 1.0",
		-- A focused column is scrolled just into view (not centred).
		focus_fit_method = 1,
		follow_focus = 1,
		direction = "right",
	},

	misc = {
		force_default_wallpaper = 0,
		disable_hyprland_logo = true,
		disable_splash_rendering = true,
		background_color = 0xff000000,
		-- If kirin's lock screen crashes, a restarted one can take the lock
		-- over (qs -c kirin ipc call lock lock) instead of the session
		-- staying locked for good.
		allow_session_lock_restore = true,
		-- Keep drawing the desktop under kirin's lock screen: its windows
		-- (an animated wallpaper) stay current, so unlocking shows the
		-- frame of now, not one from before locking. The lock screen is
		-- opaque, and the workspaces under it are empty ones, so nothing
		-- shows through.
		session_lock_xray = true,
	},
})

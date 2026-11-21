-- Titlebars from the kirin-bars plugin (loaded by plugins.lua from home-manager).
if not (hl.plugin.hyprbars and hl.plugin.hyprbars.add_button) then return end

local bars_enabled = false

local function apply_bars()
	hl.config({ plugin = { hyprbars = { enabled = bars_enabled } } })
	-- Apply now instead of on each window's next redraw.
	if hl.plugin.hyprbars.refresh then hl.plugin.hyprbars.refresh() end
end

function kirin_toggle_bars()
	bars_enabled = not bars_enabled
	apply_bars()
end

function kirin_bars_enabled()
	return bars_enabled
end

-- On in windows mode, off in tiling (winmode.lua).
function kirin_set_bars(on)
	bars_enabled = on and true or false
	apply_bars()
end

local MINIMIZED = "special:minimized"

-- Titlebar buttons pass the window they belong to, not the focused one.
-- Acting on it directly avoids a focus change, which would warp the cursor.
function kirin_bar_action(action, address)
	local window = hl.get_window("address:" .. address)
	if not window then return end
	if action == "close" then
		hl.dispatch(hl.dsp.window.close({ window = window }))
	elseif action == "maximize" then
		-- kirin's own maximize in windows mode (winmode.lua).
		if kirin_window_maximize and kirin_window_mode == "windows" then
			kirin_window_maximize(window)
		else
			hl.dispatch(hl.dsp.window.fullscreen({ window = window, mode = "maximized", action = "toggle" }))
		end
	elseif action == "minimize" then
		if kirin_minimize then
			kirin_minimize(window)
		else
			hl.dispatch(hl.dsp.window.move({ window = window, workspace = MINIMIZED, follow = false }))
		end
	end
end

-- Brings a minimized window back onto the current workspace, one per call.
function kirin_restore_minimized()
	local monitor = hl.get_active_monitor()
	local workspace = monitor and monitor.active_workspace
	if not workspace then return end
	local last
	for _, window in ipairs(hl.get_windows()) do
		if window.workspace and window.workspace.name == MINIMIZED then last = window end
	end
	if not last then return end
	-- Windows mode: back to where it was (winmode.lua).
	if kirin_unminimize and kirin_window_mode == "windows" then
		kirin_unminimize(last)
		return
	end
	hl.dispatch(hl.dsp.window.move({ window = last, workspace = tostring(workspace.id), follow = false }))
	hl.dispatch(hl.dsp.focus({ window = last }))
	hl.dispatch(hl.dsp.window.alter_zorder({ mode = "top", window = last }))
end

local function bar_command(action)
	return [[hyprctl eval "kirin_bar_action(']] .. action .. [[', '$KIRIN_WINDOW_ADDRESS')"]]
end

hl.config({
	plugin = {
		hyprbars = {
			enabled = bars_enabled,
			bar_height = 32,
			bar_color = "rgb(1e1e2e)",
			col = { text = "rgb(cdd6f4)" },
			bar_text_font = "Sans",
			bar_text_size = 12,
			bar_text_align = "center",
			bar_buttons_alignment = "left",
			bar_padding = 10,
			bar_button_padding = 4,
			bar_precedence_over_border = true,
			on_double_click = bar_command("maximize"),
			-- A maximized window dragged: its normal size back (winmode.lua).
			on_drag_start = "if kirin_drag_start then kirin_drag_start('{address}') end",
			-- Dragged to a screen edge or corner: snapped there (winmode.lua).
			on_drag_zone = "if kirin_snap_zone then kirin_snap_zone('{address}', '{zone}', '{monitor}') end",
			on_drag_end = "if kirin_snap_drop then kirin_snap_drop('{address}') end",
		},
	},
})

-- Button colours as { bg, fg } hex: the traffic lights, fixed (not from the
-- colour scheme).
local default_buttons = {
	close = { "ff5f57", "1f1f28" },
	minimize = { "febc2e", "1f1f28" },
	maximize = { "28c840", "1f1f28" },
}

function kirin_set_bar_buttons(colors)
	colors = colors or default_buttons
	-- hyprbars stacks buttons from the aligned edge: first added is the outermost.
	hl.plugin.hyprbars.clear_buttons()
	for _, action in ipairs({ "close", "minimize", "maximize" }) do
		local c = colors[action] or default_buttons[action]
		hl.plugin.hyprbars.add_button({
			bg_color = "rgb(" .. c[1] .. ")",
			fg_color = "rgb(" .. c[2] .. ")",
			size = 16,
			icon = "kirin:" .. action,
			action = bar_command(action),
		})
	end
	if hl.plugin.hyprbars.refresh then hl.plugin.hyprbars.refresh() end
end

kirin_set_bar_buttons()

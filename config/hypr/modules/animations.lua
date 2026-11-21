-- Window animations with the same Material 3 (Expressive) motion tokens as the
-- Quickshell side (services/Theme.qml, components/Anim.qml), so windows and
-- shell move alike. "Spatial" curves overshoot a little (movement, size),
-- "effects" curves don't (fades, colour).
--
-- Speeds are Hyprland deciseconds (1 = 100 ms) at animation speed 1×.
-- kirin_apply_animations() divides them by the speed from Settings → Appearance.

local curves = {
	m3FastSpatial = { { 0.42, 1.67 }, { 0.21, 0.9 } },
	m3DefaultSpatial = { { 0.38, 1.21 }, { 0.22, 1 } },
	m3SlowSpatial = { { 0.39, 1.29 }, { 0.35, 0.98 } },
	m3FastEffects = { { 0.31, 0.94 }, { 0.34, 1 } },
	m3DefaultEffects = { { 0.34, 0.8 }, { 0.34, 1 } },
	m3SlowEffects = { { 0.34, 0.88 }, { 0.34, 1 } },
	m3Standard = { { 0.2, 0 }, { 0, 1 } },
	m3StandardAccel = { { 0.3, 0 }, { 1, 1 } },
	m3EmphasizedDecel = { { 0.05, 0.7 }, { 0.1, 1 } },
	m3EmphasizedAccel = { { 0.3, 0 }, { 0.8, 0.15 } },
}

for name, points in pairs(curves) do
	hl.curve(name, { type = "bezier", points = points })
end

-- Mirrors the shell: windows open like the launcher (spring in from 90%),
-- close like it (quick fade and shrink), move and resize with spatial springs.
local leaves = {
	{ leaf = "global", ds = 4, bezier = "m3Standard" },
	{ leaf = "windowsIn", ds = 5, bezier = "m3DefaultSpatial", style = "popin 90%" },
	{ leaf = "windowsOut", ds = 2, bezier = "m3StandardAccel", style = "popin 95%" },
	{ leaf = "windowsMove", ds = 5, bezier = "m3DefaultSpatial" },
	{ leaf = "fadeIn", ds = 2, bezier = "m3DefaultEffects" },
	{ leaf = "fadeOut", ds = 1.5, bezier = "m3FastEffects" },
	{ leaf = "fadeSwitch", ds = 2, bezier = "m3DefaultEffects" },
	{ leaf = "fadeShadow", ds = 2, bezier = "m3DefaultEffects" },
	{ leaf = "fadeDim", ds = 2, bezier = "m3DefaultEffects" },
	{ leaf = "border", ds = 3, bezier = "m3SlowEffects" },
	{ leaf = "borderangle", ds = 3, bezier = "m3SlowEffects" },
	{ leaf = "layersIn", ds = 5, bezier = "m3DefaultSpatial", style = "popin 90%" },
	{ leaf = "layersOut", ds = 2, bezier = "m3StandardAccel", style = "popin 95%" },
	{ leaf = "fadeLayersIn", ds = 2, bezier = "m3DefaultEffects" },
	{ leaf = "fadeLayersOut", ds = 1.5, bezier = "m3FastEffects" },
	-- Up and down: workspaces are stacked so on the bar (and the gesture),
	-- the columns go sideways (the scrolling layout).
	{ leaf = "workspaces", ds = 5, bezier = "m3DefaultSpatial", style = "slidevert" },
	{ leaf = "specialWorkspace", ds = 5, bezier = "m3DefaultSpatial", style = "slidefadevert 15%" },
}

-- speed: 1 = normal, 2 = twice as fast, 0 = no animations.
function kirin_apply_animations(speed)
	speed = tonumber(speed) or 1
	if speed <= 0 then
		hl.config({ animations = { enabled = false } })
		return
	end

	hl.config({ animations = { enabled = true } })
	for _, a in ipairs(leaves) do
		hl.animation({ leaf = a.leaf, enabled = true, speed = a.ds / speed, bezier = a.bezier, style = a.style })
	end
end

kirin_apply_animations(1)

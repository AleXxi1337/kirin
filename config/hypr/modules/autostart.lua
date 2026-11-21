hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")

hl.on("hyprland.start", function()
	-- Polkit agent (password prompts for system actions): kirin's NixOS
	-- module's (/etc/kirin/polkit-agent), else hyprpolkitagent or
	-- polkit-gnome where distributions put them (Arch, Debian/Ubuntu,
	-- Fedora, openSUSE).
	hl.exec_cmd([[sh -c 'for a in \
		/etc/kirin/polkit-agent \
		/run/current-system/sw/libexec/polkit-gnome-authentication-agent-1 \
		/usr/lib/hyprpolkitagent/hyprpolkitagent \
		/usr/libexec/hyprpolkitagent \
		/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1 \
		/usr/libexec/polkit-gnome-authentication-agent-1 \
		/usr/lib/x86_64-linux-gnu/polkit-gnome-authentication-agent-1 \
		/usr/lib/aarch64-linux-gnu/polkit-gnome-authentication-agent-1; do
		[ -x "$a" ] && exec "$a"
	done']])
	hl.exec_cmd("udiskie")
	-- The session starts locked: kirin, told it's the login by a file it
	-- reads and removes at once, starts black, behind its lock screen
	-- (modules/lock/Lock.qml). Restarted later, it doesn't lock.
	hl.exec_cmd([[sh -c 'echo 1 > "$XDG_RUNTIME_DIR/kirin-login"; exec qs -c kirin']])
end)

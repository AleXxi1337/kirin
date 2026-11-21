# kirin

A desktop shell on Hyprland and Quickshell, in the spirit of macOS: a bar
with a taskbar, a launcher, notifications, a lock screen that is also the
login, video wallpapers, Material You colours from the wallpaper, tiling
and a desktop-like windows mode.

Only NixOS is supported for now.

## Install (NixOS)

A new system from the template:

```sh
nix flake init -t github:AleXxi1337/kirin
nixos-generate-config --show-hardware-config > hardware-configuration.nix
sudo nixos-rebuild switch --flake .#kirin   # or nixos-install --flake .#kirin
```

On an existing one, add the module to your flake:

```nix
inputs.kirin.url = "github:AleXxi1337/kirin";
# in the system's modules:
kirin.nixosModules.default
# and in its config:
kirin = {
  enable = true;
  user = "you";
};
```

The module turns on what the shell runs on (Hyprland, PipeWire,
NetworkManager, Bluetooth, UPower, power profiles, polkit, portals, fonts)
as defaults your own config can override, and starts the session through
greetd: kirin's lock screen is the login. Options: `kirin.path` (the
checkout, `.kirin`), `kirin.repo` (what it's cloned from: a fork),
`kirin.hibernation.enable`, `kirin.sleep.thenHibernate`.

## Changing it

The shell isn't in the Nix store: every login runs `kirin init`, which keeps
a git checkout of this repository in `~/.kirin` (cloned on the first one)
and links it into the home directory. Change the files there, `kirin reload`
(or save: Quickshell and Hyprland pick most changes up by themselves), commit,
push to your fork.

The titlebar plugin is compiled: the system has one built for its Hyprland.
`kirin plugins --build` builds yours from `~/.kirin` and uses it instead;
`kirin plugins --reset` goes back.

## Layout

| Path | What |
|---|---|
| `config/quickshell/kirin` | The shell (Quickshell): bar, launcher, notifications, lock screen, settings… |
| `config/hypr` | Hyprland's config (Lua): keys, window modes, placement, sleep… |
| `share/` | Linked into `~/.local/share` (the settings app's desktop entry, symbols) |
| `plugins/bars` | The titlebar plugin (C++, Hyprland) |
| `plugins/video` | The video wallpaper QML module (C++, Qt) |
| `cli/` | The `kirin` command |
| `install/manifest.toml` | What kirin needs: packages, fonts, links, folders (the module and `kirin init` both read it) |
| `nix/` | The NixOS module and packages |
| `templates/default` | A whole system with kirin |

# kirin-cli

Command line for the kirin shell (`cli/` in the kirin repository; the checkout is `~/.kirin`, or `$KIRIN_DIR`).

```
kirin <command> [flags]
```

| Command | Alias | What it does |
|---|---|---|
| `init [--session]` | `i` | Sets kirin up in the home directory: the checkout in `~/.kirin` (cloned, or copied from `$KIRIN_SOURCE` offline), the links `install/manifest.toml` lists, `~/Pictures/Wallpapers` and `~/Pictures/Screenshots`, the default colours. Files in the way go to `~/.local/state/kirin/backup/<time>/`, never deleted. On NixOS the session runs it at every login (`--session`) |
| `reload [-n]` | `r` | Links the checkout again, reloads Hyprland and restarts the shell (`--no-shell`/`-n`: leaves the shell running) |
| `plugins [--build \| --reset]` | `pl` | Builds the titlebar plugin from the checkout and uses it instead of the system's (`--build`, NixOS); `--reset`: back to the system's |
| `restart` | `rs` | Restarts the shell and waits until it answers |
| `lock` | `l` | Locks the screen |
| `logs [-f] [-t N]` | `lg` | The shell's log (`--follow`, `--tail N`) |
| `cache [--clean \| --clear]` | `c` | Sizes of `~/.cache/kirin`. `--clean`: what the shell removes on its own (removed wallpapers, unused canvas sizes, videos shrunk with old settings). `--clear`: all wallpaper copies and thumbnails, then restarts the shell (it makes them again) |
| `wallpaper [-p PATH]` | `w` | Prints or sets the wallpaper |
| `settings` | `s` | Toggles the settings window |

The shell runs without `LD_LIBRARY_PATH` from the calling shell (it can break
Qt and ffmpeg).

## How it relates to the shell

The shell doesn't need the CLI. Scripts both use live in the shell, in
`~/.config/quickshell/kirin/scripts/` (e.g. `wallpaper-gc.sh`, which
`kirin cache --clean` runs with the shell's own settings), so they're always
the dotfiles' version.

## Development

```
uv sync
uv run kirin --help
```

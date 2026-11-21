import os
import subprocess
from pathlib import Path

from rich.console import Console

from kirin_cli.bin.app import App
from kirin_cli.bin.types import Flag
from kirin_cli.services.cache import CacheService
from kirin_cli.services.scheme import SchemeService
from kirin_cli.services.setup import Checkout, CheckoutError, Links, is_nixos, kirin_dir, make_folders, manifest
from kirin_cli.services.shell import ShellService
from kirin_cli.services.wallpaper import WallpaperService

app = App(name="Kirin CLI", description="CLI application for kirin")
console = Console()

# The repository cloned into the checkout when it isn't there ($KIRIN_REPO;
# the NixOS module passes kirin.repo).
DEFAULT_REPO = "https://github.com/AleXxi1337/kirin.git"


@app.command(name="hello", description="Prints hello", alias="h")
def hello_command():
    console.print("hello")


@app.command(
    name="print",
    description="Prints text into console",
    alias="p",
    flags=[Flag(name="--text", description="Text", type=str, alias="-t")],
)
def print_text(text: str | None) -> None:
    if text is None:
        raise Exception("Text must be included with --text flag")

    console.print(text)


def _link_home(quiet: bool = False) -> None:
    directory = kirin_dir()
    m = manifest(directory)
    result = Links(directory).apply(m.get("links", []))
    make_folders(m.get("folders", {}).get("home", []))
    if result.moved:
        console.print(f"Moved {len(result.moved)} files in the way aside to {result.backup_dir}", soft_wrap=True)
    if not quiet or result.made or result.removed:
        console.print(f"Links: {result.made} made, {result.kept} in place, {result.removed} stale removed")


@app.command(
    name="init",
    description="Set kirin up in the home directory: the checkout (~/.kirin), its links, the default colours",
    alias="i",
    flags=[Flag(name="--session", description="As the login does it (NixOS): quiet, never stops the session", type=bool)],
)
def init_command(session: bool) -> None:
    directory = kirin_dir()
    source = os.environ.get("KIRIN_SOURCE")
    checkout = Checkout(directory, os.environ.get("KIRIN_REPO") or DEFAULT_REPO, Path(source) if source else None)
    try:
        how = checkout.ensure()
    except CheckoutError as e:
        console.print(f"[red]{e}[/red]")
        raise SystemExit(1)
    if how != "present" or not session:
        console.print({"present": f"Checkout in {directory}", "cloned": f"Cloned kirin into {directory}", "copied": f"Copied kirin into {directory} (offline; origin set to the repository)"}[how], soft_wrap=True)

    _link_home(quiet=session)

    scheme = SchemeService()
    if scheme.create_default():
        console.print(f"Created the default colours in {scheme.json_path.parent}", soft_wrap=True)

    if not is_nixos() and not session:
        console.print("[yellow]Only NixOS is supported for now: install the packages kirin needs yourself (install/manifest.toml).[/yellow]")


def _human(size: int) -> str:
    for unit in ("B", "KB", "MB", "GB"):
        if size < 1024 or unit == "GB":
            return f"{size:.0f} {unit}" if unit == "B" else f"{size:.1f} {unit}"
        size /= 1024
    return f"{size:.1f} GB"


def _restart_shell() -> None:
    shell = ShellService()
    with console.status("Restarting the shell..."):
        ok = shell.restart()
    if ok:
        console.print("[green]Shell restarted[/green]")
    else:
        console.print("[red]The shell didn't come back up.[/red] See [bold]kirin logs[/bold].")


@app.command(
    name="reload",
    description="Link the checkout again, reload Hyprland and restart the shell",
    alias="r",
    flags=[Flag(name="--no-shell", description="Leave the shell running as it is", type=bool, alias="-n")],
)
def reload_command(no_shell: bool) -> None:
    _link_home()
    if os.environ.get("HYPRLAND_INSTANCE_SIGNATURE"):
        subprocess.run(["hyprctl", "reload"], check=False, capture_output=True)
        console.print("Hyprland reloaded")
    if not no_shell:
        _restart_shell()


@app.command(
    name="plugins",
    description="Build the titlebar plugin from your checkout (instead of the system's), or go back to the system's",
    alias="pl",
    flags=[
        Flag(name="--build", description="Build plugins/bars from the checkout and use it", type=bool),
        Flag(name="--reset", description="Back to the system's plugin", type=bool),
    ],
)
def plugins_command(build: bool, reset: bool) -> None:
    link = Path.home() / ".local" / "share" / "kirin" / "plugins" / "kirin-bars"
    if reset:
        if link.is_symlink() or link.exists():
            link.unlink()
        console.print("Using the system's plugin from the next Hyprland start (or `kirin reload`)")
        return
    if build:
        if not is_nixos():
            console.print("[red]Only on NixOS for now.[/red]")
            raise SystemExit(1)
        link.parent.mkdir(parents=True, exist_ok=True)
        # With the checkout's flake.lock: the same nixpkgs (so the same
        # Hyprland) as the system's kirin when they're in step.
        with console.status("Building the plugin..."):
            r = subprocess.run(["nix", "build", f"path:{kirin_dir()}#kirin-bars", "-o", str(link)], capture_output=True, text=True)
        if r.returncode != 0:
            console.print(r.stderr[-2000:])
            console.print("[red]The build failed.[/red]")
            raise SystemExit(1)
        console.print(f"Built into {link}; loaded from the next Hyprland start (or `kirin reload`)", soft_wrap=True)
        return
    console.print(f"Your build: {link.resolve()}" if link.exists() else "Using the system's plugin", soft_wrap=True)


@app.command(name="restart", description="Restart the shell (Quickshell)", alias="rs")
def restart_command() -> None:
    _restart_shell()


@app.command(name="lock", description="Lock the screen", alias="l")
def lock_command() -> None:
    ShellService().ipc("lock", "lock")


@app.command(
    name="logs",
    description="Print the shell's log",
    alias="lg",
    flags=[
        Flag(name="--follow", description="Keep printing new lines", type=bool, alias="-f"),
        Flag(name="--tail", description="Only the last N lines", type=int, alias="-t"),
    ],
)
def logs_command(follow: bool, tail: int | None) -> None:
    ShellService().log(follow=follow, tail=tail)


@app.command(
    name="cache",
    description="Show kirin's caches; clean or clear the wallpaper ones",
    alias="c",
    flags=[
        Flag(name="--clean", description="Remove what's no longer needed (as the shell does on its own)", type=bool),
        Flag(name="--clear", description="Remove all wallpaper copies and thumbnails (made again)", type=bool),
    ],
)
def cache_command(clean: bool, clear: bool) -> None:
    cache = CacheService()
    if clear:
        freed = cache.clear()
        console.print(f"Removed {_human(freed)} of wallpaper copies and thumbnails")
        # The shell still points at the removed copies: it starts afresh.
        if ShellService().running():
            _restart_shell()
    elif clean:
        freed, linked = cache.clean()
        console.print(f"Freed {_human(freed + linked)}" + (f" ({_human(linked)} by linking same copies)" if linked else ""))

    entries = cache.entries()
    if not entries:
        console.print(f"No cache in {cache.cache_dir}")
        return
    for entry in entries:
        console.print(f"{_human(entry.size):>10}  {entry.name}  [dim]{entry.files} files[/dim]")
    console.print(f"{_human(sum(e.size for e in entries)):>10}  [bold]total[/bold]  [dim]{cache.cache_dir}[/dim]")


@app.command(
    name="wallpaper",
    description="Set or print the current wallpaper",
    alias="w",
    flags=[Flag(name="--path", description="Image to set as wallpaper", type=Path, alias="-p")],
)
def wallpaper_command(path: Path | None) -> None:
    service = WallpaperService()
    if path is None:
        console.print(service.get(), soft_wrap=True)
        return

    service.set(path)


@app.command(name="settings", description="Toggle the settings window", alias="s")
def settings_command() -> None:
    subprocess.run(["qs", "-c", "kirin", "ipc", "call", "settings", "toggle"], check=True)


def main():
    app.run()

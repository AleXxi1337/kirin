"""Setting kirin up in a home directory, from its checkout (~/.kirin).

Shared by `kirin init` (every login on NixOS, run by the session; by hand
elsewhere) and `kirin reload`. Everything here can run again and again:
what's in place stays as it is.
"""

import os
import shutil
import stat
import subprocess
import time
import tomllib
from dataclasses import dataclass, field
from pathlib import Path

from kirin_cli.services.scheme import state_dir


def kirin_dir() -> Path:
    """The checkout: $KIRIN_DIR, else ~/.kirin."""
    return Path(os.environ.get("KIRIN_DIR") or Path.home() / ".kirin")


def manifest(directory: Path | None = None) -> dict:
    with open((directory or kirin_dir()) / "install" / "manifest.toml", "rb") as f:
        return tomllib.load(f)


class CheckoutError(Exception):
    pass


class Checkout:
    """The git checkout in ~/.kirin: cloned from the repository if it isn't
    there, or, offline, copied from a source tree (the NixOS module's copy
    of kirin, $KIRIN_SOURCE) with the repository as its origin."""

    def __init__(self, directory: Path, repo: str | None, source: Path | None) -> None:
        self.directory = directory
        self.repo = repo
        self.source = source

    def present(self) -> bool:
        return (self.directory / "install" / "manifest.toml").is_file()

    def ensure(self) -> str:
        if self.present():
            return "present"
        if self.directory.exists() and any(self.directory.iterdir()):
            raise CheckoutError(f"{self.directory} exists and isn't a kirin checkout; move it away first")
        if self.repo and shutil.which("git"):
            try:
                subprocess.run(
                    ["git", "clone", "--quiet", self.repo, str(self.directory)],
                    check=True,
                    timeout=180,
                    capture_output=True,
                )
                if self.present():
                    return "cloned"
            except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
                shutil.rmtree(self.directory, ignore_errors=True)
        if self.source and (self.source / "install" / "manifest.toml").is_file():
            shutil.copytree(self.source, self.directory, symlinks=True, ignore=shutil.ignore_patterns(".git"))
            # From the store: read-only.
            for root, dirs, files in os.walk(self.directory):
                for name in dirs + files:
                    p = Path(root) / name
                    if not p.is_symlink():
                        p.chmod(p.stat().st_mode | stat.S_IWUSR)
            self.directory.chmod(self.directory.stat().st_mode | stat.S_IWUSR)
            if shutil.which("git"):
                subprocess.run(["git", "init", "--quiet"], cwd=self.directory, check=False)
                if self.repo:
                    subprocess.run(["git", "remote", "add", "origin", self.repo], cwd=self.directory, check=False)
            return "copied"
        raise CheckoutError(f"couldn't get kirin into {self.directory}: no network for {self.repo} and no source to copy")


@dataclass
class LinkResult:
    made: int = 0
    kept: int = 0
    removed: int = 0
    moved: list[Path] = field(default_factory=list)
    backup_dir: Path | None = None


class Links:
    """The links from the checkout into the home directory, as the manifest
    lists them. Anything in the way that isn't one of them is moved aside to
    ~/.local/state/kirin/backup/<time>/, never deleted."""

    def __init__(self, directory: Path, home: Path | None = None) -> None:
        self.directory = directory.resolve()
        self.home = home or Path.home()
        self.result = LinkResult()
        self._stamp = time.strftime("%Y-%m-%d_%H-%M-%S")

    def _aside(self, path: Path) -> None:
        if self.result.backup_dir is None:
            self.result.backup_dir = state_dir() / "backup" / self._stamp
        rel = path.relative_to(self.home) if path.is_relative_to(self.home) else Path(path.name)
        target = self.result.backup_dir / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        path.rename(target)
        self.result.moved.append(rel)

    def _link(self, source: Path, target: Path) -> None:
        if target.is_symlink() and Path(os.readlink(target)) == source:
            self.result.kept += 1
            return
        if target.is_symlink() or target.exists():
            self._aside(target)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.symlink_to(source)
        self.result.made += 1

    def _real_dir(self, path: Path) -> None:
        """A folder that's a link (stow folded it before): made a real one."""
        if path.is_symlink():
            self._aside(path)
        path.mkdir(parents=True, exist_ok=True)

    def _stale(self, root: Path, source: Path) -> None:
        """Links into the checkout whose file is gone: removed."""
        if not root.is_dir() or root.is_symlink():
            return
        for p in root.rglob("*"):
            if p.is_symlink():
                dest = Path(os.readlink(p))
                if dest.is_relative_to(source) and not dest.exists():
                    p.unlink()
                    self.result.removed += 1

    def apply(self, entries: list[dict]) -> LinkResult:
        for entry in entries:
            source = self.directory / entry["source"]
            target = self.home / entry["target"]
            if not source.exists():
                continue
            if entry.get("mode") == "dir":
                self._real_dir(target.parent)
                self._link(source, target)
                continue
            self._real_dir(target)
            self._stale(target, source)
            for src in sorted(source.rglob("*")):
                if src.is_dir() and not src.is_symlink():
                    self._real_dir(target / src.relative_to(source))
                    continue
                self._link(src, target / src.relative_to(source))
        return self.result


def make_folders(names: list[str], home: Path | None = None) -> None:
    for name in names:
        ((home or Path.home()) / name).mkdir(parents=True, exist_ok=True)


def set_default_wallpaper(directory: Path, m: dict, home: Path | None = None) -> Path | None:
    """The manifest's default wallpaper, when none is chosen yet: copied into
    ~/Pictures/Wallpapers (so the picker has it) and set. The shell's colours
    follow it. A chosen one is never replaced."""
    rel = m.get("wallpaper", {}).get("default")
    state = state_dir() / "wallpaper"
    if not rel or (state.is_file() and state.read_text().strip()):
        return None
    src = directory / rel
    if not src.is_file():
        return None
    folder = (home or Path.home()) / "Pictures" / "Wallpapers"
    folder.mkdir(parents=True, exist_ok=True)
    dest = folder / src.name
    if not dest.exists():
        shutil.copyfile(src, dest)
    state.parent.mkdir(parents=True, exist_ok=True)
    state.write_text(f"{dest}\n")
    return dest


def is_nixos() -> bool:
    return Path("/etc/NIXOS").exists()

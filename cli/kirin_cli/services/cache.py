import json
import os
import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path


def _xdg(name: str, default: str) -> Path:
    return Path(os.environ.get(name) or Path.home() / default)


@dataclass(frozen=True)
class CacheEntry:
    name: str
    path: Path
    size: int
    files: int


class CacheService:
    """kirin's caches (~/.cache/kirin): what's there, and cleaning them.

    Cleaning runs the shell's own script (scripts/wallpaper-gc.sh), with the
    settings the shell would use, so both clean the same way.
    """

    def __init__(self) -> None:
        self.cache_dir = _xdg("XDG_CACHE_HOME", ".cache") / "kirin"
        self.state_dir = _xdg("XDG_STATE_HOME", ".local/state") / "kirin"
        self.config_file = _xdg("XDG_CONFIG_HOME", ".config") / "kirin" / "config.json"
        self.shell_dir = _xdg("XDG_CONFIG_HOME", ".config") / "quickshell" / "kirin"
        self.copies = self.cache_dir / "wallpapers"
        self.thumbs = self.cache_dir / "wallpaper-thumbs-960x540"

    def entries(self) -> list[CacheEntry]:
        if not self.cache_dir.is_dir():
            return []
        out = []
        for path in sorted(self.cache_dir.iterdir()):
            files = [path] if path.is_file() else [f for f in path.rglob("*") if f.is_file()]
            # Hard links counted once.
            seen: set[int] = set()
            size = 0
            for f in files:
                st = f.stat()
                if st.st_ino not in seen:
                    seen.add(st.st_ino)
                    size += st.st_size
            out.append(CacheEntry(path.name, path, size, len(files)))
        return out

    def _config(self) -> dict:
        try:
            return json.loads(self.config_file.read_text())
        except (OSError, ValueError):
            return {}

    def _state(self, name: str) -> str:
        try:
            return (self.state_dir / name).read_text().strip()
        except OSError:
            return ""

    def clean(self) -> tuple[int, int]:
        """What the shell cleans on its own, now. Returns (bytes freed, bytes linked)."""
        wallpaper = self._config().get("wallpaper", {})
        video = wallpaper.get("video", {})
        folder = str(Path(wallpaper.get("directory", "~/Pictures/Wallpapers")).expanduser())
        sizes = self._state("canvas-sizes").split()
        if not sizes:
            # No setup recorded yet: keep every size there is, only drop what
            # belongs to removed wallpapers and old video settings.
            sizes = sorted({f.stem.split("-")[1] for f in self.copies.glob("*-*.*") if "x" in f.stem.split("-")[1]})
        params = f"{video.get('resolution', 'fhd')}-{max(1, int(video.get('fps', 30)))}"
        current = self._state("wallpaper")
        script = self.shell_dir / "scripts" / "wallpaper-gc.sh"
        if not script.is_file():
            raise FileNotFoundError(f"The shell's cleanup script isn't there: {script}")
        result = subprocess.run(
            ["sh", str(script), str(self.copies), str(self.thumbs), folder, " ".join(sizes), params, *([current] if current else [])],
            capture_output=True,
            text=True,
            check=True,
        )
        freed, linked = (int(x) for x in (result.stdout.split() + ["0", "0"])[:2])
        return freed, linked

    def clear(self) -> int:
        """Everything the wallpapers made, gone (the shell makes it again). Returns bytes."""
        size = sum(e.size for e in self.entries() if e.path in (self.copies, self.thumbs))
        for path in (self.copies, self.thumbs):
            shutil.rmtree(path, ignore_errors=True)
        return size

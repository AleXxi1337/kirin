import subprocess
from pathlib import Path


class WallpaperService:
    def __init__(self, shell_config: str = "kirin") -> None:
        self._shell_config = shell_config

    def _ipc(self, *args: str) -> str:
        result = subprocess.run(
            ["qs", "-c", self._shell_config, "ipc", "call", "wallpaper", *args],
            capture_output=True,
            text=True,
            check=True,
        )
        return result.stdout.strip()

    def set(self, path: Path) -> None:
        path = path.expanduser().resolve()
        if not path.is_file():
            raise FileNotFoundError(f"Wallpaper not found: {path}")

        self._ipc("set", str(path))

    def get(self) -> str:
        return self._ipc("get")

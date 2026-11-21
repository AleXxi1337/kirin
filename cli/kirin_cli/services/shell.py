import os
import subprocess
import time


class ShellService:
    """The running kirin shell (Quickshell): start, stop, its IPC and log."""

    def __init__(self, config: str = "kirin") -> None:
        self._config = config

    @staticmethod
    def _env() -> dict[str, str]:
        # A LD_LIBRARY_PATH from the calling shell can break the shell's own
        # libraries (Qt, ffmpeg): it starts without one.
        env = dict(os.environ)
        env.pop("LD_LIBRARY_PATH", None)
        return env

    def _qs(self, *args: str, check: bool = False, capture: bool = True) -> subprocess.CompletedProcess:
        return subprocess.run(
            # The config first: `ipc` takes no -c after it.
            ["qs", "-c", self._config, *args],
            capture_output=capture,
            text=True,
            check=check,
            env=self._env(),
        )

    def running(self) -> bool:
        return "Instance" in self._qs("list").stdout

    def ready(self) -> bool:
        """Running and answering IPC (its config has loaded)."""
        return self._qs("ipc", "show").returncode == 0

    def stop(self, timeout: float = 5.0) -> None:
        if not self.running():
            return
        self._qs("kill")
        deadline = time.monotonic() + timeout
        while self.running() and time.monotonic() < deadline:
            time.sleep(0.1)

    def start(self, timeout: float = 10.0) -> bool:
        """Starts it detached; True once it answers."""
        subprocess.Popen(
            ["qs", "-c", self._config],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
            env=self._env(),
        )
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if self.ready():
                return True
            time.sleep(0.2)
        return False

    def restart(self) -> bool:
        self.stop()
        return self.start()

    def ipc(self, target: str, function: str, *args: str) -> str:
        result = self._qs("ipc", "call", target, function, *args)
        if result.returncode != 0:
            raise RuntimeError(result.stderr.strip() or f"kirin didn't answer {target}.{function}")
        return result.stdout.strip()

    def log(self, follow: bool = False, tail: int | None = None) -> None:
        """Prints the running shell's log (follows it with `follow`)."""
        args = ["log"]
        if follow:
            args.append("--follow")
        if tail:
            args += ["--tail", str(tail)]
        self._qs(*args, capture=False)

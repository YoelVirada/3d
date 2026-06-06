"""Subprocess execution with logging and clear failure messages."""

from __future__ import annotations

import subprocess
import time
from dataclasses import dataclass
from pathlib import Path


@dataclass
class CommandResult:
    command: list[str]
    returncode: int
    stdout: str
    stderr: str
    duration_s: float
    log_path: Path | None = None


class CommandError(RuntimeError):
    def __init__(self, result: CommandResult, hint: str = ""):
        self.result = result
        self.hint = hint
        msg = (
            f"Command failed (exit {result.returncode}): {' '.join(result.command)}\n"
            f"Log: {result.log_path}\n"
            f"stderr tail:\n{result.stderr[-4000:]}"
        )
        if hint:
            msg += f"\n\nHow to fix: {hint}"
        super().__init__(msg)


def run_command(
    cmd: list[str],
    *,
    cwd: Path | None = None,
    env: dict[str, str] | None = None,
    log_path: Path | None = None,
    log_header: list[str] | None = None,
    check: bool = True,
    hint: str = "",
    timeout_s: float | None = None,
) -> CommandResult:
    log_path = Path(log_path) if log_path else None
    if log_path:
        log_path.parent.mkdir(parents=True, exist_ok=True)

    start = time.perf_counter()
    proc = subprocess.run(
        cmd,
        cwd=str(cwd) if cwd else None,
        env=env,
        capture_output=True,
        text=True,
        timeout=timeout_s,
    )
    duration_s = time.perf_counter() - start
    result = CommandResult(
        command=cmd,
        returncode=proc.returncode,
        stdout=proc.stdout or "",
        stderr=proc.stderr or "",
        duration_s=duration_s,
        log_path=log_path,
    )
    if log_path:
        with open(log_path, "w", encoding="utf-8") as f:
            for line in log_header or []:
                f.write(f"{line}\n")
            f.write(f"# cmd: {' '.join(cmd)}\n")
            f.write(f"# exit: {proc.returncode}\n")
            f.write(f"# duration_s: {duration_s:.2f}\n\n")
            f.write("=== stdout ===\n")
            f.write(result.stdout)
            f.write("\n=== stderr ===\n")
            f.write(result.stderr)

    if check and proc.returncode != 0:
        raise CommandError(result, hint=hint)
    return result

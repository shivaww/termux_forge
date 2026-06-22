"""
TermuxForge Command Executor
==============================

Safe command execution with subprocess management, timeout control,
output capture, streaming, and kill support.

All commands pass through SecurityManager before execution.
"""

import asyncio
import logging
import os
import signal
import time
from dataclasses import dataclass, field
from typing import Any, AsyncIterator, Callable, Optional

from security import SafetyResult, SecurityManager

logger = logging.getLogger("termux_forge.command_executor")

# ── Default configuration ─────────────────────────────────────────────
DEFAULT_TIMEOUT = 30  # seconds
MAX_TIMEOUT = 600  # 10 minutes
DEFAULT_CWD = os.path.expanduser("~")
SHELL = os.environ.get("SHELL", "/data/data/com.termux/files/usr/bin/bash")


@dataclass
class CommandResult:
    """
    Result of a command execution.

    Attributes
    ----------
    exit_code : int
        Process exit code (0 = success).
    stdout : str
        Captured standard output.
    stderr : str
        Captured standard error.
    duration : float
        Wall-clock execution time in seconds.
    command : str
        The command that was executed.
    cwd : str
        Working directory used.
    timed_out : bool
        Whether the command was terminated due to timeout.
    killed : bool
        Whether the command was manually killed.
    """

    exit_code: int
    stdout: str
    stderr: str
    duration: float
    command: str
    cwd: str
    timed_out: bool = False
    killed: bool = False

    def to_dict(self) -> dict[str, Any]:
        """Serialize to a JSON-compatible dictionary."""
        return {
            "exitCode": self.exit_code,
            "stdout": self.stdout,
            "stderr": self.stderr,
            "duration": round(self.duration, 3),
            "command": self.command,
            "cwd": self.cwd,
            "timedOut": self.timed_out,
            "killed": self.killed,
            "success": self.exit_code == 0 and not self.timed_out,
        }


class CommandExecutor:
    """
    Executes shell commands safely with subprocess management.

    Features:
    - Security checks before every execution
    - Configurable timeouts
    - Output capture (stdout + stderr)
    - Streaming output via async iterator
    - Environment variable injection
    - Running process tracking and kill support
    - Command history recording

    Parameters
    ----------
    security : SecurityManager
        The security manager for command validation.
    default_cwd : str, optional
        Default working directory.
    default_timeout : int, optional
        Default command timeout in seconds.
    """

    def __init__(
        self,
        security: SecurityManager,
        default_cwd: str = DEFAULT_CWD,
        default_timeout: int = DEFAULT_TIMEOUT,
    ) -> None:
        self.security = security
        self.default_cwd = default_cwd
        self.default_timeout = default_timeout
        self._running_processes: dict[str, asyncio.subprocess.Process] = {}
        self._history: list[dict[str, Any]] = []

    # ── Main execute method ───────────────────────────────────────────

    async def execute(
        self,
        command: str,
        cwd: str | None = None,
        timeout: int | None = None,
        env: dict[str, str] | None = None,
        process_id: str | None = None,
    ) -> CommandResult:
        """
        Execute a command in a subprocess.

        Parameters
        ----------
        command : str
            Shell command to execute.
        cwd : str, optional
            Working directory (defaults to ``default_cwd``).
        timeout : int, optional
            Timeout in seconds (defaults to ``default_timeout``).
        env : dict, optional
            Extra environment variables merged with ``os.environ``.
        process_id : str, optional
            An identifier for tracking the running process.

        Returns
        -------
        CommandResult
            Captured output, exit code, and timing information.

        Raises
        ------
        ValueError
            If the command is blocked by security policy.
        """
        cwd = cwd or self.default_cwd
        timeout = min(timeout or self.default_timeout, MAX_TIMEOUT)

        # Security check
        safety = self.security.evaluate(command, cwd)
        if not safety.allowed:
            logger.warning("Command blocked: %s – %s", command, safety.reason)
            raise ValueError(f"Command blocked: {safety.reason}")

        # Prepare environment
        full_env = dict(os.environ)
        termux_bin = "/data/data/com.termux/files/usr/bin"
        current_path = full_env.get("PATH", "")
        if termux_bin not in current_path:
            full_env["PATH"] = f"{termux_bin}:{current_path}" if current_path else termux_bin
            
        if env:
            full_env.update(env)

        # Validate working directory
        if not os.path.isdir(cwd):
            logger.error("Working directory does not exist: %s", cwd)
            return CommandResult(
                exit_code=1,
                stdout="",
                stderr=f"Working directory does not exist: {cwd}",
                duration=0.0,
                command=command,
                cwd=cwd,
            )

        start = time.monotonic()
        timed_out = False
        killed = False

        try:
            process = await asyncio.create_subprocess_shell(
                command,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
                cwd=cwd,
                env=full_env,
                executable=SHELL,
            )

            pid = process_id or str(process.pid)
            self._running_processes[pid] = process

            try:
                stdout_bytes, stderr_bytes = await asyncio.wait_for(
                    process.communicate(),
                    timeout=timeout,
                )
            except asyncio.TimeoutError:
                timed_out = True
                logger.warning("Command timed out after %ds: %s", timeout, command)
                await self._terminate_process(process)
                stdout_bytes = b""
                stderr_bytes = f"Command timed out after {timeout}s".encode()
            finally:
                self._running_processes.pop(pid, None)

            duration = time.monotonic() - start
            exit_code = process.returncode if process.returncode is not None else -1

            result = CommandResult(
                exit_code=exit_code,
                stdout=stdout_bytes.decode("utf-8", errors="replace"),
                stderr=stderr_bytes.decode("utf-8", errors="replace"),
                duration=duration,
                command=command,
                cwd=cwd,
                timed_out=timed_out,
                killed=killed,
            )

        except Exception as exc:
            duration = time.monotonic() - start
            logger.exception("Command execution error: %s", command)
            result = CommandResult(
                exit_code=-1,
                stdout="",
                stderr=str(exc),
                duration=duration,
                command=command,
                cwd=cwd,
            )

        # Record history
        self._record(result, safety)
        return result

    # ── Streaming execute ─────────────────────────────────────────────

    async def execute_streaming(
        self,
        command: str,
        cwd: str | None = None,
        timeout: int | None = None,
        env: dict[str, str] | None = None,
        process_id: str | None = None,
        on_output: Callable[[str, str], None] | None = None,
    ) -> CommandResult:
        """
        Execute a command and stream output line-by-line.

        Parameters
        ----------
        command : str
            Shell command to execute.
        cwd : str, optional
            Working directory.
        timeout : int, optional
            Timeout in seconds.
        env : dict, optional
            Extra environment variables.
        process_id : str, optional
            Identifier for tracking.
        on_output : callable, optional
            Called with ``(stream, line)`` for each output line.
            ``stream`` is ``"stdout"`` or ``"stderr"``.

        Returns
        -------
        CommandResult
            Final result after command completes.
        """
        cwd = cwd or self.default_cwd
        timeout = min(timeout or self.default_timeout, MAX_TIMEOUT)

        safety = self.security.evaluate(command, cwd)
        if not safety.allowed:
            raise ValueError(f"Command blocked: {safety.reason}")

        full_env = dict(os.environ)
        if env:
            full_env.update(env)

        if not os.path.isdir(cwd):
            return CommandResult(
                exit_code=1, stdout="", stderr=f"Invalid cwd: {cwd}",
                duration=0.0, command=command, cwd=cwd,
            )

        start = time.monotonic()
        stdout_lines: list[str] = []
        stderr_lines: list[str] = []

        process = await asyncio.create_subprocess_shell(
            command,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            cwd=cwd,
            env=full_env,
            executable=SHELL,
        )

        pid = process_id or str(process.pid)
        self._running_processes[pid] = process

        async def _read_stream(
            stream: asyncio.StreamReader | None,
            name: str,
            collector: list[str],
        ) -> None:
            if stream is None:
                return
            while True:
                line = await stream.readline()
                if not line:
                    break
                decoded = line.decode("utf-8", errors="replace")
                collector.append(decoded)
                if on_output:
                    on_output(name, decoded)

        timed_out = False
        try:
            await asyncio.wait_for(
                asyncio.gather(
                    _read_stream(process.stdout, "stdout", stdout_lines),
                    _read_stream(process.stderr, "stderr", stderr_lines),
                    process.wait(),
                ),
                timeout=timeout,
            )
        except asyncio.TimeoutError:
            timed_out = True
            await self._terminate_process(process)
        finally:
            self._running_processes.pop(pid, None)

        duration = time.monotonic() - start
        result = CommandResult(
            exit_code=process.returncode or -1,
            stdout="".join(stdout_lines),
            stderr="".join(stderr_lines),
            duration=duration,
            command=command,
            cwd=cwd,
            timed_out=timed_out,
        )
        self._record(result, safety)
        return result

    # ── Process management ────────────────────────────────────────────

    async def kill(self, process_id: str) -> bool:
        """
        Kill a running process by its identifier.

        Returns True if the process was found and terminated.
        """
        process = self._running_processes.pop(process_id, None)
        if process is None:
            logger.warning("No running process with id: %s", process_id)
            return False
        await self._terminate_process(process)
        logger.info("Killed process: %s", process_id)
        return True

    def list_running(self) -> list[str]:
        """Return identifiers of all currently running processes."""
        return list(self._running_processes.keys())

    # ── History ───────────────────────────────────────────────────────

    def get_history(self, limit: int = 50) -> list[dict[str, Any]]:
        """Return the most recent command history entries."""
        return self._history[-limit:]

    def clear_history(self) -> None:
        """Clear all command history."""
        self._history.clear()

    # ── Private helpers ───────────────────────────────────────────────

    async def _terminate_process(
        self, process: asyncio.subprocess.Process
    ) -> None:
        """Gracefully terminate a process, escalating to SIGKILL."""
        try:
            process.terminate()
            try:
                await asyncio.wait_for(process.wait(), timeout=5)
            except asyncio.TimeoutError:
                process.kill()
                await process.wait()
        except ProcessLookupError:
            pass  # Already exited

    def _record(self, result: CommandResult, safety: SafetyResult) -> None:
        """Record a command execution in history."""
        entry = {
            **result.to_dict(),
            "riskLevel": safety.risk_level.value,
            "safetyScore": safety.score,
            "timestamp": time.time(),
        }
        self._history.append(entry)
        # Cap history at 500 entries
        if len(self._history) > 500:
            self._history = self._history[-500:]

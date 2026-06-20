#!/usr/bin/env python3
"""
TermuxForge Bridge Server
===========================

Main WebSocket + HTTP bridge server that runs on ``127.0.0.1:8765``
in Termux and provides a JSON-RPC 2.0 interface for the Flutter app.

Supports:
- Real-time WebSocket communication
- 30+ RPC methods for file I/O, git, Flutter, MCP, workflows, etc.
- Output streaming via WebSocket
- Command safety filtering
- Approval tracking
- Command history persistence
- Graceful shutdown

Usage::

    python3 termux_forge_bridge.py
    python3 termux_forge_bridge.py --host 127.0.0.1 --port 8765
"""

import argparse
import asyncio
import json
import logging
import os
import signal
import sys
import time
from pathlib import Path
from typing import Any, Optional

import websockets
from websockets.server import WebSocketServerProtocol

# ── Local imports ─────────────────────────────────────────────────────
# Add the bridge directory to the module path.
BRIDGE_DIR = os.path.dirname(os.path.abspath(__file__))
if BRIDGE_DIR not in sys.path:
    sys.path.insert(0, BRIDGE_DIR)

from protocol import (
    ErrorCode,
    JsonRpcError,
    JsonRpcRequest,
    JsonRpcResponse,
    MethodRouter,
)
from security import SecurityManager
from command_executor import CommandExecutor
from tool_discovery import ToolDiscovery
from mcp_manager import McpManager, McpServerConfig, TransportType
from workflow_runner import WorkflowRunner, WorkflowDefinition
from github_hooks import GitHubHooks
from media_hooks import MediaHooks
from checkpoint_hooks import CheckpointManager

# ── Constants ─────────────────────────────────────────────────────────
VERSION = "1.0.0"
DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 8765
LOG_DIR = os.path.expanduser("~/.termux_forge/logs")
HISTORY_FILE = os.path.expanduser("~/.termux_forge/command_history.json")
DEFAULT_CWD = os.path.expanduser("~")

# ── Logging setup ─────────────────────────────────────────────────────
os.makedirs(LOG_DIR, exist_ok=True)
log_file = os.path.join(LOG_DIR, "bridge.log")

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    handlers=[
        logging.FileHandler(log_file, encoding="utf-8"),
        logging.StreamHandler(sys.stdout),
    ],
)
logger = logging.getLogger("termux_forge.bridge")


# ══════════════════════════════════════════════════════════════════════
#  BRIDGE SERVER
# ══════════════════════════════════════════════════════════════════════

class TermuxForgeBridge:
    """
    Main bridge server orchestrating all subsystems.

    Attributes
    ----------
    host : str
        Bind address.
    port : int
        Bind port.
    security : SecurityManager
        Command safety evaluator.
    executor : CommandExecutor
        Shell command executor.
    tools : ToolDiscovery
        Installed tool scanner.
    mcp : McpManager
        MCP server manager.
    workflows : WorkflowRunner
        Workflow execution engine.
    github : GitHubHooks
        GitHub CLI integration.
    media : MediaHooks
        Media provider integration.
    checkpoints : CheckpointManager
        File/git checkpoint manager.
    """

    def __init__(self, host: str = DEFAULT_HOST, port: int = DEFAULT_PORT) -> None:
        self.host = host
        self.port = port

        # Subsystems
        self.security = SecurityManager()
        self.executor = CommandExecutor(self.security)
        self.tools = ToolDiscovery()
        self.mcp = McpManager()
        self.workflows = WorkflowRunner(self.executor)
        self.github = GitHubHooks()
        self.media = MediaHooks()
        self.checkpoints = CheckpointManager()

        # State
        self._clients: set[WebSocketServerProtocol] = set()
        self._approval_queue: dict[str, dict[str, Any]] = {}
        self._server: Any = None
        self._shutdown_event = asyncio.Event()

        # Router
        self.router = MethodRouter()
        self._register_methods()

    # ── Method registration ───────────────────────────────────────────

    def _register_methods(self) -> None:
        """Register all JSON-RPC method handlers."""
        r = self.router

        # ── Command execution ─────────────────────────────────────────
        r.register("execute_command", self._execute_command)
        r.register("execute_shell", self._execute_command)
        r.register("kill_command", self._kill_command)

        # ── File operations ───────────────────────────────────────────
        r.register("read_file", self._read_file)
        r.register("write_file", self._write_file)
        r.register("edit_file", self._edit_file)
        r.register("list_files", self._list_files)
        r.register("search_files", self._search_files)

        # ── Git operations ────────────────────────────────────────────
        r.register("git_status", self._git_status)
        r.register("git_diff", self._git_diff)
        r.register("git_commit", self._git_commit)
        r.register("git_push", self._git_push)
        r.register("git_pull", self._git_pull)

        # ── Flutter / Dart ────────────────────────────────────────────
        r.register("flutter_run", self._flutter_run)
        r.register("flutter_test", self._flutter_test)
        r.register("flutter_build", self._flutter_build)
        r.register("dart_analyze", self._dart_analyze)

        # ── Package management ────────────────────────────────────────
        r.register("install_package", self._install_package)

        # ── Tool discovery ────────────────────────────────────────────
        r.register("check_tool", self._check_tool)
        r.register("discover_tools", self._discover_tools)

        # ── History ───────────────────────────────────────────────────
        r.register("get_command_history", self._get_command_history)

        # ── Workspace / Version ───────────────────────────────────────
        r.register("ping", self._ping)
        r.register("version_check", self._version_check)
        r.register("workspace_validate", self._workspace_validate)

        # ── MCP ───────────────────────────────────────────────────────
        r.register("mcp_server_manage", self._mcp_server_manage)
        r.register("mcp_tool_discover", self._mcp_tool_discover)
        r.register("mcp_transport_handle", self._mcp_transport_handle)

        # ── Workflows ─────────────────────────────────────────────────
        r.register("workflow_execute", self._workflow_execute)

        # ── Checkpoints ───────────────────────────────────────────────
        r.register("checkpoint_create", self._checkpoint_create)
        r.register("checkpoint_rollback", self._checkpoint_rollback)

        # ── Media ─────────────────────────────────────────────────────
        r.register("media_discover", self._media_discover)

        # ── GitHub CI/CD ──────────────────────────────────────────────
        r.register("github_workflow_trigger", self._github_workflow_trigger)
        r.register("github_build_status", self._github_build_status)
        r.register("github_download_artifact", self._github_download_artifact)

    # ══════════════════════════════════════════════════════════════════
    #  METHOD HANDLERS
    # ══════════════════════════════════════════════════════════════════

    # ── execute_command ───────────────────────────────────────────────

    async def _execute_command(
        self,
        command: str,
        cwd: str = DEFAULT_CWD,
        timeout: int = 30,
        env: dict | None = None,
        stream: bool = False,
        process_id: str | None = None,
    ) -> dict:
        """Execute a shell command with safety checks."""
        try:
            if stream:
                result = await self.executor.execute_streaming(
                    command=command, cwd=cwd, timeout=timeout,
                    env=env, process_id=process_id,
                    on_output=lambda s, l: asyncio.ensure_future(
                        self._broadcast({
                            "type": "output",
                            "stream": s,
                            "line": l,
                            "processId": process_id,
                        })
                    ),
                )
            else:
                result = await self.executor.execute(
                    command=command, cwd=cwd, timeout=timeout,
                    env=env, process_id=process_id,
                )
            return result.to_dict()
        except ValueError as exc:
            raise JsonRpcError(ErrorCode.COMMAND_BLOCKED, str(exc))

    async def _kill_command(self, process_id: str) -> dict:
        """Kill a running command."""
        killed = await self.executor.kill(process_id)
        return {"killed": killed, "processId": process_id}

    # ── File operations ───────────────────────────────────────────────

    async def _read_file(self, path: str, encoding: str = "utf-8") -> dict:
        """Read a file and return its contents."""
        if not self.security.validate_path(path):
            raise JsonRpcError(ErrorCode.PERMISSION_DENIED, f"Path not allowed: {path}")
        try:
            p = Path(path)
            if not p.exists():
                raise JsonRpcError(ErrorCode.FILE_NOT_FOUND, f"File not found: {path}")
            content = p.read_text(encoding=encoding)
            return {
                "path": path,
                "content": content,
                "size": p.stat().st_size,
                "encoding": encoding,
            }
        except JsonRpcError:
            raise
        except Exception as exc:
            raise JsonRpcError(ErrorCode.INTERNAL_ERROR, str(exc))

    async def _write_file(
        self, path: str, content: str, encoding: str = "utf-8",
        create_dirs: bool = True,
    ) -> dict:
        """Write content to a file."""
        if not self.security.validate_path(path):
            raise JsonRpcError(ErrorCode.PERMISSION_DENIED, f"Path not allowed: {path}")
        try:
            p = Path(path)
            if create_dirs:
                p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(content, encoding=encoding)
            return {"path": path, "size": p.stat().st_size, "written": True}
        except Exception as exc:
            raise JsonRpcError(ErrorCode.INTERNAL_ERROR, str(exc))

    async def _edit_file(
        self, path: str, search: str, replace: str,
    ) -> dict:
        """Search-and-replace edit in a file."""
        if not self.security.validate_path(path):
            raise JsonRpcError(ErrorCode.PERMISSION_DENIED, f"Path not allowed: {path}")
        try:
            p = Path(path)
            if not p.exists():
                raise JsonRpcError(ErrorCode.FILE_NOT_FOUND, f"File not found: {path}")
            content = p.read_text()
            if search not in content:
                return {"path": path, "edited": False, "reason": "Search text not found"}
            new_content = content.replace(search, replace, 1)
            p.write_text(new_content)
            return {"path": path, "edited": True}
        except JsonRpcError:
            raise
        except Exception as exc:
            raise JsonRpcError(ErrorCode.INTERNAL_ERROR, str(exc))

    async def _list_files(
        self, path: str = DEFAULT_CWD, pattern: str = "*",
        recursive: bool = False, max_depth: int = 3,
    ) -> dict:
        """List files in a directory."""
        if not self.security.validate_path(path):
            raise JsonRpcError(ErrorCode.PERMISSION_DENIED, f"Path not allowed: {path}")
        try:
            p = Path(path)
            if not p.is_dir():
                raise JsonRpcError(ErrorCode.FILE_NOT_FOUND, f"Not a directory: {path}")

            files = []
            glob_func = p.rglob if recursive else p.glob
            for item in glob_func(pattern):
                # Limit depth for recursive searches
                if recursive:
                    rel = item.relative_to(p)
                    if len(rel.parts) > max_depth:
                        continue
                try:
                    stat = item.stat()
                    files.append({
                        "name": item.name,
                        "path": str(item),
                        "isDirectory": item.is_dir(),
                        "size": stat.st_size if item.is_file() else 0,
                        "modified": stat.st_mtime,
                    })
                except PermissionError:
                    continue
                if len(files) >= 500:
                    break

            return {"path": path, "files": files, "count": len(files)}
        except JsonRpcError:
            raise
        except Exception as exc:
            raise JsonRpcError(ErrorCode.INTERNAL_ERROR, str(exc))

    async def _search_files(
        self, query: str, path: str = DEFAULT_CWD,
        extensions: list[str] | None = None,
    ) -> dict:
        """Search for text within files using grep."""
        if not self.security.validate_path(path):
            raise JsonRpcError(ErrorCode.PERMISSION_DENIED, f"Path not allowed: {path}")
        cmd = f"grep -rnI --max-count=100 '{query}' {path}"
        if extensions:
            includes = " ".join(f"--include='*.{ext}'" for ext in extensions)
            cmd = f"grep -rnI --max-count=100 {includes} '{query}' {path}"
        result = await self.executor.execute(cmd, timeout=15)
        matches = []
        for line in result.stdout.splitlines()[:100]:
            parts = line.split(":", 2)
            if len(parts) >= 3:
                matches.append({
                    "file": parts[0],
                    "line": int(parts[1]) if parts[1].isdigit() else 0,
                    "content": parts[2].strip(),
                })
        return {"query": query, "matches": matches, "count": len(matches)}

    # ── Git operations ────────────────────────────────────────────────

    async def _git_status(self, cwd: str = DEFAULT_CWD) -> dict:
        r = await self.github.git_status(cwd)
        return r.to_dict()

    async def _git_diff(self, cwd: str = DEFAULT_CWD, staged: bool = False) -> dict:
        r = await self.github.git_diff(cwd, staged)
        return r.to_dict()

    async def _git_commit(
        self, message: str, cwd: str = DEFAULT_CWD, add_all: bool = True,
    ) -> dict:
        r = await self.github.git_commit(message, cwd, add_all)
        return r.to_dict()

    async def _git_push(
        self, message: str = "Update", branch: str | None = None,
        cwd: str = DEFAULT_CWD,
    ) -> dict:
        r = await self.github.push_code(message, branch, cwd)
        return r.to_dict()

    async def _git_pull(
        self, branch: str | None = None, cwd: str = DEFAULT_CWD,
    ) -> dict:
        r = await self.github.git_pull(branch, cwd)
        return r.to_dict()

    # ── Flutter / Dart ────────────────────────────────────────────────

    async def _flutter_run(
        self, cwd: str = DEFAULT_CWD, device: str | None = None,
        flavor: str | None = None,
    ) -> dict:
        cmd = "flutter run"
        if device:
            cmd += f" -d {device}"
        if flavor:
            cmd += f" --flavor {flavor}"
        result = await self.executor.execute(cmd, cwd=cwd, timeout=300)
        return result.to_dict()

    async def _flutter_test(
        self, cwd: str = DEFAULT_CWD, path: str | None = None,
    ) -> dict:
        cmd = "flutter test"
        if path:
            cmd += f" {path}"
        result = await self.executor.execute(cmd, cwd=cwd, timeout=120)
        return result.to_dict()

    async def _flutter_build(
        self, target: str = "apk", cwd: str = DEFAULT_CWD,
        release: bool = True, flavor: str | None = None,
    ) -> dict:
        cmd = f"flutter build {target}"
        if release:
            cmd += " --release"
        if flavor:
            cmd += f" --flavor {flavor}"
        result = await self.executor.execute(cmd, cwd=cwd, timeout=600)
        return result.to_dict()

    async def _dart_analyze(self, cwd: str = DEFAULT_CWD) -> dict:
        result = await self.executor.execute("dart analyze", cwd=cwd, timeout=60)
        return result.to_dict()

    # ── Package management ────────────────────────────────────────────

    async def _install_package(
        self, package: str, manager: str = "pkg",
    ) -> dict:
        managers = {
            "pkg": f"pkg install -y {package}",
            "pip": f"pip install {package}",
            "npm": f"npm install -g {package}",
        }
        cmd = managers.get(manager)
        if not cmd:
            raise JsonRpcError(
                ErrorCode.INVALID_PARAMS,
                f"Unknown package manager: {manager}",
            )
        result = await self.executor.execute(cmd, timeout=120)
        return result.to_dict()

    # ── Tool discovery ────────────────────────────────────────────────

    async def _check_tool(self, command: str) -> dict:
        info = await self.tools.check_tool(command)
        return info.to_dict()

    async def _discover_tools(self) -> dict:
        tools = await self.tools.scan_all()
        return {
            "tools": {k: v.to_dict() for k, v in tools.items()},
            "packageManagers": self.tools.detect_package_managers(),
            "available": len(self.tools.get_available()),
            "total": len(tools),
        }

    # ── History ───────────────────────────────────────────────────────

    async def _get_command_history(self, limit: int = 50) -> dict:
        return {"history": self.executor.get_history(limit)}

    # ── Workspace / Version ───────────────────────────────────────────

    async def _version_check(self) -> dict:
        return {
            "bridge": VERSION,
            "python": sys.version,
            "platform": sys.platform,
            "methods": self.router.list_methods(),
        }

    async def _ping(self) -> dict:
        return {"ok": True, "version": VERSION, "time": time.time()}

    async def _workspace_validate(self, path: str = DEFAULT_CWD) -> dict:
        p = Path(path)
        is_flutter = (p / "pubspec.yaml").exists()
        is_git = (p / ".git").exists()
        return {
            "path": path,
            "exists": p.exists(),
            "isDirectory": p.is_dir(),
            "isFlutterProject": is_flutter,
            "isGitRepo": is_git,
            "isApproved": self.security.validate_path(path),
        }

    # ── MCP ───────────────────────────────────────────────────────────

    async def _mcp_server_manage(
        self, action: str, name: str = "", config: dict | None = None,
    ) -> dict:
        if action == "start":
            if config:
                cfg = McpServerConfig(
                    name=config.get("name", name),
                    command=config.get("command", ""),
                    args=config.get("args", []),
                    env=config.get("env", {}),
                    transport=TransportType(config.get("transport", "stdio")),
                    url=config.get("url", ""),
                )
                return await self.mcp.start_server(cfg)
            elif name:
                return await self.mcp.start_from_preset(name)
            raise JsonRpcError(ErrorCode.INVALID_PARAMS, "Provide name or config")
        elif action == "stop":
            return await self.mcp.stop_server(name)
        elif action == "restart":
            return await self.mcp.restart_server(name)
        elif action == "status":
            return await self.mcp.health_check(name)
        elif action == "list":
            return {"servers": self.mcp.list_servers()}
        elif action == "presets":
            return {"presets": list(self.mcp.list_presets().keys())}
        raise JsonRpcError(ErrorCode.INVALID_PARAMS, f"Unknown action: {action}")

    async def _mcp_tool_discover(self, name: str = "") -> dict:
        if name:
            tools = await self.mcp.discover_tools(name)
            return {"server": name, "tools": tools}
        all_tools = await self.mcp.discover_all_tools()
        return {"tools": all_tools}

    async def _mcp_transport_handle(
        self, server: str, method: str, params: dict | None = None,
    ) -> dict:
        return await self.mcp.route_request(server, method, params)

    # ── Workflows ─────────────────────────────────────────────────────

    async def _workflow_execute(self, workflow: dict) -> dict:
        definition = WorkflowDefinition.from_dict(workflow)
        result = await self.workflows.execute(definition)
        return result.to_dict()

    # ── Checkpoints ───────────────────────────────────────────────────

    async def _checkpoint_create(
        self, name: str, paths: list[str] | None = None,
        include_git: bool = True, description: str = "",
    ) -> dict:
        cp = await self.checkpoints.create(name, paths, include_git, description)
        return cp.to_dict()

    async def _checkpoint_rollback(
        self, checkpoint_id: str, restore_files: bool = True,
        restore_git: bool = False,
    ) -> dict:
        return await self.checkpoints.rollback(
            checkpoint_id, restore_files, restore_git,
        )

    # ── Media ─────────────────────────────────────────────────────────

    async def _media_discover(self) -> dict:
        providers = await self.media.discover_providers()
        return {"providers": providers}

    # ── GitHub CI/CD ──────────────────────────────────────────────────

    async def _github_workflow_trigger(
        self, workflow: str, ref: str = "main",
        inputs: dict | None = None, cwd: str = DEFAULT_CWD,
    ) -> dict:
        r = await self.github.trigger_workflow(workflow, ref, inputs, cwd)
        return r.to_dict()

    async def _github_build_status(
        self, workflow: str | None = None, limit: int = 5,
        cwd: str = DEFAULT_CWD,
    ) -> dict:
        r = await self.github.get_build_status(workflow, limit, cwd)
        return r.to_dict()

    async def _github_download_artifact(
        self, run_id: str, name: str | None = None,
        output_dir: str | None = None, cwd: str = DEFAULT_CWD,
    ) -> dict:
        r = await self.github.download_artifact(run_id, name, output_dir, cwd)
        return r.to_dict()

    # ══════════════════════════════════════════════════════════════════
    #  WEBSOCKET SERVER
    # ══════════════════════════════════════════════════════════════════

    async def _handle_client(self, websocket: WebSocketServerProtocol) -> None:
        """Handle a WebSocket client connection."""
        client_addr = websocket.remote_address
        logger.info("Client connected: %s", client_addr)
        self._clients.add(websocket)

        try:
            async for raw_message in websocket:
                response = await self._process_message(str(raw_message))
                if response:
                    await websocket.send(response)
        except websockets.exceptions.ConnectionClosedOK:
            logger.info("Client disconnected gracefully: %s", client_addr)
        except websockets.exceptions.ConnectionClosedError as exc:
            logger.warning("Client disconnected with error: %s – %s", client_addr, exc)
        except Exception as exc:
            logger.exception("Unhandled error for client %s", client_addr)
        finally:
            self._clients.discard(websocket)

    async def _process_message(self, raw: str) -> str | None:
        """Parse and dispatch a JSON-RPC message."""
        try:
            request = JsonRpcRequest.from_json(raw)
        except JsonRpcError as exc:
            return JsonRpcResponse(id=None, error=exc.to_dict()).to_json()

        if request.is_notification():
            # Notifications don't get responses
            asyncio.create_task(self.router.dispatch(request))
            return None

        response = await self.router.dispatch(request)
        return response.to_json()

    async def _broadcast(self, data: dict) -> None:
        """Broadcast a message to all connected clients."""
        if not self._clients:
            return
        message = json.dumps(data)
        await asyncio.gather(
            *(client.send(message) for client in self._clients),
            return_exceptions=True,
        )

    # ── Server lifecycle ──────────────────────────────────────────────

    async def start(self) -> None:
        """Start the WebSocket bridge server."""
        logger.info("=" * 60)
        logger.info("TermuxForge Bridge v%s starting…", VERSION)
        logger.info("Listening on ws://%s:%d", self.host, self.port)
        logger.info("Log file: %s", log_file)
        logger.info("=" * 60)

        # Load saved command history
        self._load_history()

        self._server = await websockets.serve(
            self._handle_client,
            self.host,
            self.port,
            ping_interval=30,
            ping_timeout=10,
            max_size=10 * 1024 * 1024,  # 10 MB max message
        )

        logger.info("Bridge server running.")

        # Wait for shutdown signal
        await self._shutdown_event.wait()

    async def shutdown(self) -> None:
        """Gracefully shut down the server."""
        logger.info("Shutting down bridge server…")

        # Save history
        self._save_history()

        # Shutdown MCP servers
        await self.mcp.shutdown()

        # Close WebSocket server
        if self._server:
            self._server.close()
            await self._server.wait_closed()

        logger.info("Bridge server stopped.")

    def request_shutdown(self) -> None:
        """Signal the server to shut down."""
        self._shutdown_event.set()

    # ── History persistence ───────────────────────────────────────────

    def _save_history(self) -> None:
        """Save command history to disk."""
        try:
            os.makedirs(os.path.dirname(HISTORY_FILE), exist_ok=True)
            history = self.executor.get_history(500)
            with open(HISTORY_FILE, "w") as f:
                json.dump(history, f, indent=2, default=str)
            logger.info("Saved %d history entries", len(history))
        except Exception as exc:
            logger.error("Failed to save history: %s", exc)

    def _load_history(self) -> None:
        """Load command history from disk."""
        if not os.path.exists(HISTORY_FILE):
            return
        try:
            with open(HISTORY_FILE) as f:
                entries = json.load(f)
            self.executor._history = entries[-500:]
            logger.info("Loaded %d history entries", len(entries))
        except Exception as exc:
            logger.error("Failed to load history: %s", exc)


# ══════════════════════════════════════════════════════════════════════
#  ENTRY POINT
# ══════════════════════════════════════════════════════════════════════

def main() -> None:
    """Parse arguments and run the bridge server."""
    parser = argparse.ArgumentParser(
        description="TermuxForge Python Bridge Server",
    )
    parser.add_argument(
        "--host", default=DEFAULT_HOST,
        help=f"Bind address (default: {DEFAULT_HOST})",
    )
    parser.add_argument(
        "--port", type=int, default=DEFAULT_PORT,
        help=f"Bind port (default: {DEFAULT_PORT})",
    )
    args = parser.parse_args()

    bridge = TermuxForgeBridge(host=args.host, port=args.port)

    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)

    # Signal handling for graceful shutdown
    for sig in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(sig, bridge.request_shutdown)

    try:
        loop.run_until_complete(bridge.start())
    except KeyboardInterrupt:
        pass
    finally:
        loop.run_until_complete(bridge.shutdown())
        loop.close()


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
import http.server
import json
import os
import re
import shutil
import urllib.parse
import subprocess
from pathlib import Path

PORT = 8390
BASE_DIR = os.environ.get("HOME", "/data/data/com.termux/files/home")

class MCPServerHandler(http.server.BaseHTTPRequestHandler):
    def send_json_response(self, status_code, data):
        self.send_response(status_code)
        self.send_header('Content-type', 'application/json')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        self.end_headers()
        self.wfile.write(json.dumps(data).encode('utf-8'))

    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        self.end_headers()

    def do_POST(self):
        if self.path != '/mcp':
            self.send_json_response(404, {"error": "Endpoint not found. Use /mcp"})
            return

        content_length = int(self.headers.get('Content-Length', 0))
        if content_length == 0:
            self.send_json_response(400, {"error": "Empty request body"})
            return

        try:
            body = self.rfile.read(content_length).decode('utf-8')
            request_data = json.loads(body)
        except json.JSONDecodeError:
            self.send_json_response(400, {"error": "Invalid JSON payload"})
            return

        method = request_data.get('method')
        params = request_data.get('params', {})

        if not method:
            self.send_json_response(400, {"error": "Method is required"})
            return

        try:
            result = self.execute_tool(method, params)
            self.send_json_response(200, {"result": result})
        except Exception as e:
            self.send_json_response(500, {"error": str(e)})

    def resolve_path(self, path_str, workspace_dir=None):
        if not path_str:
            raise ValueError("Path parameter is missing")
        base = workspace_dir if workspace_dir else BASE_DIR
        p = Path(path_str)
        # If already absolute, use it as-is (no double-prefix)
        if p.is_absolute():
            return p
        # Relative path: join to base
        return Path(base) / path_str

    def execute_tool(self, method, params):
        workspace_dir = params.get('workspace_dir')
        
        if method in ("file_read", "read_file"):
            path = self.resolve_path(params.get('path'), workspace_dir)
            if not path.is_file():
                return {"error": f"File not found: {params.get('path')}"}
            start = params.get('start') or params.get('start_line')
            end = params.get('end') or params.get('end_line')
            with open(path, 'r', encoding='utf-8', errors='replace') as f:
                if start is not None and end is not None:
                    lines = f.readlines()
                    start_idx = max(0, int(start) - 1)
                    end_idx = min(len(lines), int(end))
                    content = "".join(lines[start_idx:end_idx])
                else:
                    content = f.read()
            return {"content": content, "path": str(path)}
            
        elif method == "file_write":
            path = self.resolve_path(params.get('path'), workspace_dir)
            content = params.get('content', '')
            path.parent.mkdir(parents=True, exist_ok=True)
            with open(path, 'w', encoding='utf-8') as f:
                f.write(content)
            return {"success": True, "message": f"File written successfully: {params.get('path')}"}
            
        elif method == "file_append":
            path = self.resolve_path(params.get('path'), workspace_dir)
            content = params.get('content', '')
            path.parent.mkdir(parents=True, exist_ok=True)
            with open(path, 'a', encoding='utf-8') as f:
                f.write(content)
            return {"success": True, "message": f"Content appended successfully to: {params.get('path')}"}
            
        elif method == "str_replace":
            path = self.resolve_path(params.get('path'), workspace_dir)
            if not path.is_file():
                return {"error": f"File not found: {params.get('path')}"}
            old_str = params.get('old')
            new_str = params.get('new')
            if old_str is None or new_str is None:
                return {"error": "old and new parameters are required"}
            with open(path, 'r', encoding='utf-8', errors='replace') as f:
                content = f.read()
            if old_str not in content:
                return {"error": "old string not found in file"}
            content = content.replace(old_str, new_str)
            with open(path, 'w', encoding='utf-8') as f:
                f.write(content)
            return {"success": True, "message": "File edited successfully via str_replace"}
            
        elif method == "file_edit":
            path = self.resolve_path(params.get('path'), workspace_dir)
            if not path.is_file():
                return {"error": f"File not found: {params.get('path')}"}
            start_line = params.get('start_line')
            end_line = params.get('end_line')
            replacement = params.get('replacement', '')
            
            with open(path, 'r', encoding='utf-8', errors='replace') as f:
                lines = f.readlines()
            
            if start_line is None or end_line is None:
                return {"error": "start_line and end_line are required"}
                
            try:
                start_line = int(start_line)
                end_line = int(end_line)
            except ValueError:
                return {"error": "start_line and end_line must be integers"}
                
            start_idx = max(0, start_line - 1)
            end_idx = min(len(lines), end_line)
            
            new_lines = replacement.splitlines(keepends=True)
            if not replacement.endswith('\n') and replacement != '':
                new_lines[-1] = new_lines[-1] + '\n'
                
            lines = lines[:start_idx] + new_lines + lines[end_idx:]
            
            with open(path, 'w', encoding='utf-8') as f:
                f.writelines(lines)
            return {"success": True, "message": "File edited successfully"}
            
        elif method == "file_delete":
            path = self.resolve_path(params.get('path'), workspace_dir)
            if not path.exists():
                return {"error": f"Path not found: {params.get('path')}"}
            if path.is_file():
                path.unlink()
            elif path.is_dir():
                if any(path.iterdir()):
                    return {"error": "Directory is not empty. Cannot delete."}
                path.rmdir()
            return {"success": True, "message": "Deleted successfully"}
            
        elif method == "dir_list":
            path = self.resolve_path(params.get('path', ''), workspace_dir)
            if not path.is_dir():
                return {"error": f"Directory not found: {params.get('path')}"}
            items = []
            for item in path.iterdir():
                items.append({
                    "name": item.name,
                    "is_dir": item.is_dir(),
                    "size": item.stat().st_size if item.is_file() else 0
                })
            return {"items": items, "path": str(path)}
            
        elif method == "dir_create":
            path = self.resolve_path(params.get('path'), workspace_dir)
            path.mkdir(parents=True, exist_ok=True)
            return {"success": True, "message": "Directory created successfully"}
            
        elif method in ("code_search", "search"):
            path = self.resolve_path(params.get('path', ''), workspace_dir)
            query = params.get('query') or params.get('pattern')
            if not query:
                return {"error": "query is required"}
                
            context_lines = params.get('context_lines', 0)
            try:
                context_lines = int(context_lines)
            except ValueError:
                context_lines = 0

            results = []
            try:
                def scan_dir(dir_path):
                    for filepath in dir_path.iterdir():
                        if filepath.is_dir():
                            if filepath.name in ('.git', '.dart_tool', 'build', '.pub-cache', '__pycache__', 'node_modules'):
                                continue
                            yield from scan_dir(filepath)
                        elif filepath.is_file():
                            yield filepath

                files_to_scan = scan_dir(path) if path.is_dir() else [path]

                for filepath in files_to_scan:
                    if filepath.is_file():
                        try:
                            with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
                                lines = f.readlines()
                            for i, line in enumerate(lines):
                                if query in line:
                                    rel_path = str(filepath.relative_to(Path(workspace_dir) if workspace_dir else Path(BASE_DIR)))
                                    if context_lines > 0:
                                        start_idx = max(0, i - context_lines)
                                        end_idx = min(len(lines), i + context_lines + 1)
                                        context_snippet = "".join(lines[start_idx:end_idx])
                                        results.append({
                                            "file": rel_path,
                                            "line_number": i + 1,
                                            "content": line.strip(),
                                            "context": context_snippet
                                        })
                                    else:
                                        results.append({
                                            "file": rel_path,
                                            "line_number": i + 1,
                                            "content": line.strip()
                                        })
                                    if len(results) > 100:
                                        return {"results": results, "warning": "Too many results, truncated"}
                        except Exception:
                            pass
            except Exception as e:
                return {"error": str(e)}
            return {"results": results}

        elif method == "file_info":
            path = self.resolve_path(params.get('path'), workspace_dir)
            if not path.is_file():
                return {"error": f"File not found: {params.get('path')}"}
            try:
                size_bytes = path.stat().st_size
                with open(path, 'r', encoding='utf-8', errors='ignore') as f:
                    line_count = sum(1 for _ in f)
                return {
                    "path": params.get('path'),
                    "size_bytes": size_bytes,
                    "line_count": line_count,
                    "success": True
                }
            except Exception as e:
                return {"error": str(e)}

        elif method == "git_diff":
            path_val = params.get('path')
            cwd_path = Path(workspace_dir) if workspace_dir else Path(BASE_DIR)
            args = ["git", "diff"]
            if path_val:
                resolved_path = self.resolve_path(path_val, workspace_dir)
                args.append(str(resolved_path))
            try:
                proc = subprocess.run(
                    args,
                    cwd=cwd_path,
                    text=True,
                    capture_output=True,
                    timeout=30
                )
                output = proc.stdout + "\n" + proc.stderr
                return {"exit_code": proc.returncode, "output": output.strip()[:10000]}
            except Exception as e:
                return {"error": str(e)}

        elif method == "git_status":
            cwd_val = params.get('cwd') or params.get('path')
            cwd_path = self.resolve_path(cwd_val, workspace_dir) if cwd_val else (Path(workspace_dir) if workspace_dir else Path(BASE_DIR))
            try:
                proc = subprocess.run(
                    ["git", "status"],
                    cwd=cwd_path,
                    text=True,
                    capture_output=True,
                    timeout=30
                )
                output = proc.stdout + "\n" + proc.stderr
                return {"exit_code": proc.returncode, "output": output.strip()[:5000]}
            except Exception as e:
                return {"error": str(e)}

        elif method == "multi_read":
            path = self.resolve_path(params.get('path'), workspace_dir)
            if not path.is_file():
                return {"error": f"File not found: {params.get('path')}"}
            ranges_val = params.get('ranges')
            if not ranges_val:
                return {"error": "ranges parameter is required"}
            parsed_ranges = []
            try:
                if isinstance(ranges_val, str):
                    parts = ranges_val.split(',')
                    for p in parts:
                        subparts = p.strip().split('-')
                        if len(subparts) == 2:
                            parsed_ranges.append((int(subparts[0]), int(subparts[1])))
                elif isinstance(ranges_val, list):
                    for item in ranges_val:
                        if isinstance(item, str):
                            subparts = item.strip().split('-')
                            if len(subparts) == 2:
                                parsed_ranges.append((int(subparts[0]), int(subparts[1])))
                        elif isinstance(item, (list, tuple)):
                            if len(item) >= 2:
                                parsed_ranges.append((int(item[0]), int(item[1])))
                        elif isinstance(item, dict):
                            start = item.get('start') or item.get('start_line')
                            end = item.get('end') or item.get('end_line')
                            if start is not None and end is not None:
                                parsed_ranges.append((int(start), int(end)))
            except Exception as e:
                return {"error": f"Failed to parse ranges: {e}"}
            if not parsed_ranges:
                return {"error": "No valid ranges found. Expected format like '10-20,50-80' or [[10,20], [50,80]]"}
            try:
                with open(path, 'r', encoding='utf-8', errors='replace') as f:
                    lines = f.readlines()
                results = {}
                for start, end in parsed_ranges:
                    start_idx = max(0, start - 1)
                    end_idx = min(len(lines), end)
                    snippet = "".join(lines[start_idx:end_idx])
                    results[f"{start}-{end}"] = snippet
                return {"path": params.get('path'), "ranges": results, "success": True}
            except Exception as e:
                return {"error": str(e)}

        elif method == "symbol_search":
            path = self.resolve_path(params.get('path', ''), workspace_dir)
            symbol = params.get('symbol')
            if not symbol:
                return {"error": "symbol is required"}
            patterns = [
                f"class {symbol}",
                f"enum {symbol}",
                f"struct {symbol}",
                f"interface {symbol}",
                f"mixin {symbol}",
                f"extension {symbol}",
                f"{symbol}(",
                f"{symbol}<",
            ]
            results = []
            try:
                def scan_dir(dir_path):
                    for filepath in dir_path.iterdir():
                        if filepath.is_dir():
                            if filepath.name in ('.git', '.dart_tool', 'build', '.pub-cache', '__pycache__', 'node_modules'):
                                continue
                            yield from scan_dir(filepath)
                        elif filepath.is_file():
                            yield filepath
                files_to_scan = scan_dir(path) if path.is_dir() else [path]
                for filepath in files_to_scan:
                    if filepath.is_file():
                        try:
                            with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
                                for i, line in enumerate(f):
                                    matched = False
                                    for p in patterns:
                                        if p in line:
                                            matched = True
                                            break
                                    if not matched and symbol in line:
                                        words = line.split()
                                        if any(w in words for w in ('class', 'void', 'Future', 'String', 'int', 'bool', 'final', 'const')):
                                            matched = True
                                    if matched:
                                        rel_path = str(filepath.relative_to(Path(workspace_dir) if workspace_dir else Path(BASE_DIR)))
                                        results.append({
                                            "file": rel_path,
                                            "line_number": i + 1,
                                            "content": line.strip()
                                        })
                                        if len(results) > 100:
                                            return {"results": results, "warning": "Too many results, truncated"}
                        except Exception:
                            pass
            except Exception as e:
                return {"error": str(e)}
            return {"results": results}
            
        elif method == "file_search":
            path = self.resolve_path(params.get('path', ''), workspace_dir)
            pattern = params.get('pattern')
            if not pattern:
                return {"error": "pattern is required"}
            results = []
            for filepath in path.rglob(f"*{pattern}*"):
                rel_path = str(filepath.relative_to(Path(workspace_dir) if workspace_dir else Path(BASE_DIR)))
                results.append(rel_path)
                if len(results) > 100:
                    break
            return {"results": results}
            
        elif method == "find_paths":
            path = self.resolve_path(params.get('path', ''), workspace_dir)
            pattern = params.get('pattern')
            if not pattern:
                return {"error": "pattern is required"}
            target_type = params.get('type', 'both').lower()
            results = []
            try:
                def scan_path(current_path):
                    for item in current_path.iterdir():
                        if item.name in ('.git', '.dart_tool', 'build', '.pub-cache', '__pycache__', 'node_modules'):
                            continue
                        
                        # Match pattern case-insensitively
                        if pattern.lower() in item.name.lower():
                            rel_path = str(item.relative_to(Path(workspace_dir) if workspace_dir else Path(BASE_DIR)))
                            is_dir = item.is_dir()
                            if target_type == 'both':
                                results.append({"path": rel_path, "type": "dir" if is_dir else "file"})
                            elif target_type == 'dir' and is_dir:
                                results.append({"path": rel_path, "type": "dir"})
                            elif target_type == 'file' and not is_dir:
                                results.append({"path": rel_path, "type": "file"})
                                
                        if len(results) >= 100:
                            return
                        if item.is_dir():
                            scan_path(item)
                scan_path(path)
            except Exception as e:
                return {"error": str(e)}
            return {"results": results}
            
        elif method in ("shell_exec", "run_command"):
            command = params.get('command')
            if not command:
                return {"error": "command is required"}
            # Restrict some obviously dangerous commands, though users run this locally.
            cmd_lower = command.lower()
            if "rm -rf /" in cmd_lower or "mkfs" in cmd_lower:
                return {"error": "Dangerous command rejected."}

            # Timeout: caller can pass timeout param (seconds), max 600
            try:
                timeout = min(int(params.get('timeout', 120)), 600)
            except (ValueError, TypeError):
                timeout = 120

            # cwd: use explicit param, fallback to workspace_dir, then BASE_DIR
            cwd_raw = params.get('cwd', '')
            if cwd_raw:
                cwd_path = self.resolve_path(cwd_raw, workspace_dir)
            else:
                cwd_path = Path(workspace_dir) if workspace_dir else Path(BASE_DIR)

            # Ensure cwd exists, fall back gracefully
            if not cwd_path.is_dir():
                cwd_path = Path(workspace_dir) if workspace_dir else Path(BASE_DIR)

            # Prepare environment with Termux path prepended
            full_env = dict(os.environ)
            termux_bin = "/data/data/com.termux/files/usr/bin"
            current_path = full_env.get("PATH", "")
            if termux_bin not in current_path:
                full_env["PATH"] = f"{termux_bin}:{current_path}" if current_path else termux_bin

            shell_path = os.environ.get("SHELL", "/data/data/com.termux/files/usr/bin/bash")
            if not os.path.exists(shell_path):
                shell_path = "/data/data/com.termux/files/usr/bin/sh"
            if not os.path.exists(shell_path):
                shell_path = "sh"

            try:
                proc = subprocess.run(
                    [shell_path, "-c", command],
                    cwd=cwd_path,
                    env=full_env,
                    text=True,
                    capture_output=True,
                    timeout=timeout
                )
                output = proc.stdout + "\n" + proc.stderr
                return {"exit_code": proc.returncode, "output": output.strip()[:8000]}
            except subprocess.TimeoutExpired:
                return {"error": f"Command timed out after {timeout} seconds."}
            except Exception as e:
                return {"error": str(e)}

            
        else:
            return {"error": f"Unknown method: {method}"}

def run():
    print(f"Starting Termux MCP Server on port {PORT}...")
    print(f"Base Directory: {BASE_DIR}")
    server_address = ('', PORT)
    httpd = http.server.HTTPServer(server_address, MCPServerHandler)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    httpd.server_close()
    print("Server stopped.")

if __name__ == '__main__':
    run()

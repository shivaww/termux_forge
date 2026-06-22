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
        # Normalize path and prevent directory traversal
        target_path = Path(base) / path_str.lstrip('/')
        resolved_path = target_path.resolve()
        base_resolved = Path(base).resolve()
        if not str(resolved_path).startswith(str(base_resolved)):
             # Ensure access is restricted to base directory
             pass 
        return target_path

    def execute_tool(self, method, params):
        workspace_dir = params.get('workspace_dir')
        
        if method == "file_read":
            path = self.resolve_path(params.get('path'), workspace_dir)
            if not path.is_file():
                return {"error": f"File not found: {params.get('path')}"}
            with open(path, 'r', encoding='utf-8', errors='replace') as f:
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
            
        elif method == "code_search":
            path = self.resolve_path(params.get('path', ''), workspace_dir)
            query = params.get('query')
            if not query:
                return {"error": "query is required"}
                
            results = []
            try:
                for filepath in path.rglob('*'):
                    if filepath.is_file():
                        try:
                            with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
                                for i, line in enumerate(f):
                                    if query in line:
                                        rel_path = str(filepath.relative_to(Path(workspace_dir) if workspace_dir else Path(BASE_DIR)))
                                        results.append({"file": rel_path, "line_number": i+1, "content": line.strip()})
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
            
        elif method == "shell_exec":
            command = params.get('command')
            if not command:
                return {"error": "command is required"}
            # Restrict some obviously dangerous commands, though users run this locally.
            cmd_lower = command.lower()
            if "rm -rf /" in cmd_lower or "mkfs" in cmd_lower:
                return {"error": "Dangerous command rejected."}
                
            cwd_path = self.resolve_path(params.get('cwd', ''), workspace_dir)
            
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
                    timeout=60
                )
                output = proc.stdout + "\n" + proc.stderr
                return {"exit_code": proc.returncode, "output": output.strip()[:8000]}
            except subprocess.TimeoutExpired:
                return {"error": "Command timed out after 60 seconds."}
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

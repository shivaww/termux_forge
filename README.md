# Nexon

> **An AI-powered mobile coding workstation and agentic workspace** that transforms your Android device into a full-featured development workspace — powered by Flutter, Termux, and intelligent local tool routing.

[![Build](https://github.com/shivaww/Nexon/actions/workflows/build.yml/badge.svg)](https://github.com/shivaww/Nexon/actions/workflows/build.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

---

## 🆕 What's New — v1.1.0

### 🛡️ Shell Command Permission System
Before the AI executes any shell command, the app now shows a native permission dialog — just like professional IDEs (VS Code, Android Studio):
- **Yes** — allow this one command.
- **This chat** — allow all commands for the current session.
- **Always ✓** — remember and never ask again (saved to device storage).
- **No** — block execution, AI receives a denial error and can recover.

Permission preference is persisted via `SharedPreferences` (`shell_permission_v1`) and loaded on every app start.

### 🔧 Python Bridge: `<command>` XML Support
The MCP server (`python_bridge/mcp_server.py`) now accepts raw XML `<command>` blocks directly — not just JSON:
```xml
<command>ls lib/</command>
<workspace_dir>/data/.../my_project</workspace_dir>
```
Both paths (XML and JSON RPC) are supported simultaneously.

### 🗂️ Workspace-Aware Command Execution
All shell commands now correctly run inside the **user-configured workspace directory**:
- `cwd` is automatically injected as `_agenticWorkspace` if not explicitly set.
- Both dispatch blocks (main chat + deep research) inject `workspace_dir` AND `cwd`.
- Path resolution in `mcp_server.py` fixed: no more double-prefix bug when workspace is a subdirectory of Termux home.

### 🧠 Upgraded Agentic System Prompt
The agentic system prompt is now concise and structured:
- **CORE RULE**: one `<command>` per turn, stop and wait.
- **SHELL TOOLKIT**: full list of available Termux tool categories.
- **QUALITY STANDARDS**: read before edit, verify after edit, no placeholders.
- **PROJECT DOCUMENTATION**: AI automatically maintains `README.md` with a Table of Contents (line ranges) for every project.

### 🔄 Path Resolution Fixes (`mcp_server.py`)
- `~/` expands to the configured workspace (not Termux root).
- Absolute Termux paths no longer get double-prefixed when workspace is a subdir.
- `resolve_path()` correctly guards against remapping paths already inside the workspace.

---

## Overview

Nexon provides a beautiful Flutter-based agentic workspace that communicates directly with LLM API providers for streaming chat, while routing local tool calls to a zero-dependency Python-based Model Context Protocol (MCP) server running inside Termux.

Nexon empowers LLMs to read/write files, execute commands, perform search, build code, manage git workflows, and deploy projects directly from your phone or tablet.

## Architecture

```
┌────────────────────────────────────────────────────────────┐
│                    Nexon Flutter App                       │
│                                                            │
│   ┌────────────────────────────────────────────────────┐   │
│   │                    Chat Interface                  │   │
│   └─────────────────────────┬──────────────────────────┘   │
│                             │ Sends/streams chat requests  │
│                             ▼                              │
│                ┌─────────────────────────┐                 │
│                │     LLM API Provider    │                 │
│                │ (Gemini, OpenAI, etc.)  │                 │
│                └────────────┬────────────┘                 │
│                             │ Streams XML tool calls       │
│                             ▼                              │
│                ┌─────────────────────────┐                 │
│                │   XML Tool Call Parser  │                 │
│                └────────────┬────────────┘                 │
│                             │                              │
│                             │ HTTP POST JSON               │
│                             │ http://127.0.0.1:8390/mcp    │
│                             ▼                              │
│   ┌────────────────────────────────────────────────────┐   │
│   │           Python MCP Server (Termux Bridge)        │   │
│   │                                                    │   │
│   │   ┌────────────┐  ┌────────────┐  ┌────────────┐   │   │
│   │   │  Security  │  │  Command   │  │    Git     │   │   │
│   │   │  Filtering │  │  Executor  │  │ Operations │   │   │
│   │   └────────────┘  └────────────┘  └────────────┘   │   │
│   │   ┌────────────┐  ┌────────────┐                   │   │
│   │   │ Checkpoint │  │ Workflows  │                   │   │
│   │   │   Helper   │  │   Engine   │                   │   │
│   │   └────────────┘  └────────────┘                   │   │
│   └────────────────────────────────────────────────────┘   │
└────────────────────────────────────────────────────────────┘
```

## Features

### 🖥️ Shell & Terminal
- Safe bash command execution in Termux (unblocked operations).
- Command safety scanner (automatically blocks high-risk or destructive actions).
- Real-time command output capture and display.

### 📁 File Management
- Sandbox-aware folder path lookup.
- Read, write, list, delete, and recursively search files.
- Space-insensitive parameter extraction from LLM tool-calling nodes.

### 🔀 Git & GitHub Workflow Integration
- Manage version control (status, diff, commit, push, pull).
- GitHub CLI integration to monitor GitHub Actions build jobs, stream remote workflow execution logs, and retrieve built artifacts.

### 🤖 Local Zero-Dependency MCP Server
- Operates on HTTP port `8390` inside your Termux environment.
- Implements tools like `file_read`, `file_write`, `str_replace`, `dir_list`, `find_paths`, and `run_command`.

### ⚡ Tap-to-Stop Response Cancellation
- Immediate streaming connection cancellation when you tap the loading indicator in the composer input bar.

### 🎨 Fully Fullscreen SVGs & Interactive Visuals
- LaTeX equations rendering via Markdown.
- Proactive generation rules for scientific, math, data analysis, and workflow diagrams using SVGs.
- Interactive fullscreen SVG viewer with pinch-to-zoom scaling, panning, and code copy tools.
- Strict mind map layouts constrained to clean vertical tree structures.
- Darker internal grids on graphs for sharp, readable values.

### 📥 Direct Downloads Manager
- Saves HTML sandbox pages and research reports directly into the local Android `downloads/` folder (`/data/data/com.termux/files/home/downloads/`), accompanied by success notification snackbars.

---

## Getting Started

### Prerequisites
- Android device running **Android 7.0+** (API 24+)
- **[Termux](https://f-droid.org/en/packages/com.termux/)** installed from F-Droid
- Python 3.10+ in Termux
- Flutter SDK (to compile from source)

### Installation

#### 1. Configure the Termux Environment
Install Python, Node.js, Git, and other developer tools:
```bash
pkg update && pkg upgrade -y

# Install required packages
pkg install -y python git nodejs gh

# Install Firebase CLI globally using npm
npm install -g firebase-tools

# Install Nexon Bridge
curl -sL https://github.com/shivaww/Nexon/raw/main/install_bridge.sh | bash
```

#### 2. Start the Local Python MCP Gateway
```bash
cd ~/nexon_bridge && python3 mcp_server.py
```
This runs the zero-dependency tool executor server on `http://127.0.0.1:8390`.

#### 3. Install Latest APK
Build from source or download the generated release APK directly from the [GitHub Actions Artifacts](https://github.com/shivaww/Nexon/actions) tab of your latest workflow build run.

---

## Tool Calling Protocol

Nexon uses structured XML tags inside standard LLM text completions to trigger local device tool executions. The model outputs exactly one tool request per turn, halts generation, and waits for results.

### Expected XML Syntax
```xml
<tool_request>
  <method>file_read</method>
  <path>lib/main.dart</path>
  <start_line>1</start_line>
  <end_line>50</end_line>
</tool_request>
```
Nexon's parser is highly robust and automatically extracts tags like `<method>`, `<path>`, `<query>`, `<start_line>`, `<end_line>`, `<pattern>`, and `<command>`. It also includes fallback parsers to capture `<PARAM name="key">value</PARAM>` and `<parameter name="key">value</parameter>` syntax if generated by older models.

### Available Tool Methods
- **`dir_list`** — List folder contents.
- **`file_read`** — View lines within a specific range.
- **`file_write`** — Overwrite or write content to a file path.
- **`str_replace`** — Find and replace contiguous string blocks.
- **`find_paths`** — Case-insensitive search for files or directories by pattern.
- **`run_command`** — Safely execute bash shell commands.
- **`git_status`** / **`git_diff`** — Version control state.

---

## Tech Stack
- **Frontend UI**: Flutter 3.x, Material 3, Google Fonts
- **State Management**: Provider catalog state
- **Local Storage**: Flutter Secure Storage (safe API keys) & SharedPreferences
- **Backend Bridge**: Python 3 Standard Library
- **Tool Protocol**: HTTP POST JSON-RPC payloads
- **CI/CD**: GitHub Actions Build Workflows

---

## License
Nexon is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.

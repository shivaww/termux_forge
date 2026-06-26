# Project Rules for Termux Forge Agent

Welcome, Agent! You are working on the **Termux Forge** repository. This is an agentic environment for Termux using Flutter/Dart that integrates LLMs with system tools.

## Critical Guidelines for Project Agents

### 1. Tool Call XML Format Mismatches
- Inside this codebase, the application parses XML-structured tool calls using the `<tool_request>` format.
- **Parser Robustness**: The parser in [lib/main.dart](file:///data/data/com.termux/files/home/termux_forge/lib/main.dart) extracts tags like `<method>`, `<path>`, etc. It also supports fallback extraction of `<PARAM name="key">value</PARAM>` and `<parameter name="key">value</parameter>` tags even if a `<method>` tag is present.
- **Instructing LLMs**: When modifying the system prompt or designing agent prompts inside this app, always instruct the target LLMs to use the direct tag format (e.g. `<path>/foo</path>`) and explicitly advise **against** using `<PARAM name="path">/foo</PARAM>` to maximize parser cleanliness.

### 2. Dart & Flutter Coding Standards
- Maintain all existing comments and docstrings.
- Ensure any modifications to [lib/main.dart](file:///data/data/com.termux/files/home/termux_forge/lib/main.dart) do not break the Flutter build.
- Do not introduce external packages unless they are explicitly added to `pubspec.yaml`.

### 3. File Actions
- Use `view_file` to read code. Always specify narrow line ranges (`StartLine` and `EndLine`) when reading files to preserve context and speed.
- Use `replace_file_content` for contiguous edits, and `multi_replace_file_content` for non-contiguous edits. Do not overwrite whole files if you are only changing a few lines.

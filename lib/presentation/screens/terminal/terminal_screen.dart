/// TermuxForge — Terminal Screen
///
/// Terminal pane with scrollable ANSI-aware output, command input,
/// command history, connection status indicator, and clear button.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:termux_forge/core/theme/app_colors.dart';
import 'package:termux_forge/presentation/widgets/forge_app_bar.dart';
import 'package:termux_forge/presentation/widgets/status_badge.dart';
import 'package:termux_forge/services/termux_bridge/termux_bridge_service.dart';

/// The terminal screen.
class TerminalScreen extends StatefulWidget {
  const TerminalScreen({super.key});

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final _inputFocus = FocusNode();
  final List<_TerminalLine> _lines = [];
  final List<String> _history = [];
  final TermuxBridgeService _bridge = TermuxBridgeService.instance;
  StreamSubscription<BridgeConnectionState>? _stateSub;
  StreamSubscription<String>? _outputSub;
  int _historyIndex = -1;
  bool _isConnected = false;
  bool _isRunning = false;

  @override
  void initState() {
    super.initState();
    // Add welcome message.
    _lines.addAll([
      _TerminalLine(
        text: '╔══════════════════════════════════════╗',
        color: AppColors.accentBlue,
      ),
      _TerminalLine(
        text: '║       TermuxForge Terminal v0.1      ║',
        color: AppColors.accentBlue,
      ),
      _TerminalLine(
        text: '╚══════════════════════════════════════╝',
        color: AppColors.accentBlue,
      ),
      const _TerminalLine(text: ''),
      const _TerminalLine(
        text: 'Type commands to execute them through the Termux bridge.',
        color: AppColors.textSecondary,
      ),
      const _TerminalLine(text: ''),
    ]);
    _isConnected = _bridge.isConnected;
    _stateSub = _bridge.stateStream.listen((state) {
      if (!mounted) return;
      setState(() => _isConnected = state == BridgeConnectionState.connected);
    });
    _outputSub = _bridge.outputStream.listen((line) {
      if (!mounted) return;
      _appendLine(line);
    });
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _outputSub?.cancel();
    _inputController.dispose();
    _scrollController.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  Future<void> _executeCommand(String cmd) async {
    if (cmd.trim().isEmpty) return;
    final command = cmd.trim();

    setState(() {
      _history.add(command);
      _historyIndex = _history.length;
      if (command == 'clear') {
        _lines.clear();
      } else {
        _lines.add(_TerminalLine(text: '\$ $command', color: AppColors.success));
        _isRunning = true;
      }
      _inputController.clear();
    });
    _scrollToBottom();

    if (command == 'clear') return;

    final response = await _bridge.executeShell(
      command,
      workingDirectory: '/data/data/com.termux/files/home',
      timeout: const Duration(minutes: 5),
    );
    if (!mounted) return;

    setState(() {
      _isRunning = false;
      if (response.error != null) {
        _lines.add(_TerminalLine(
          text: response.error!.message,
          color: AppColors.error,
        ));
      } else {
        final stdout = response.stdout.trimRight();
        final stderr = response.stderr.trimRight();
        if (stdout.isNotEmpty) {
          for (final line in stdout.split('\n')) {
            _lines.add(_TerminalLine(text: line));
          }
        }
        if (stderr.isNotEmpty) {
          for (final line in stderr.split('\n')) {
            _lines.add(_TerminalLine(text: line, color: AppColors.error));
          }
        }
        if (stdout.isEmpty && stderr.isEmpty) {
          _lines.add(_TerminalLine(
            text: 'Exit ${response.exitCode ?? 0}',
            color: AppColors.textTertiary,
          ));
        }
      }
      _lines.add(const _TerminalLine(text: ''));
    });
    _scrollToBottom();
  }

  void _appendLine(String text, {Color? color}) {
    setState(() => _lines.add(_TerminalLine(text: text, color: color)));
    _scrollToBottom();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 50), () {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  void _navigateHistory(bool up) {
    if (_history.isEmpty) return;
    setState(() {
      if (up) {
        _historyIndex = (_historyIndex - 1).clamp(0, _history.length - 1);
      } else {
        _historyIndex = (_historyIndex + 1).clamp(0, _history.length);
      }
      if (_historyIndex < _history.length) {
        _inputController.text = _history[_historyIndex];
        _inputController.selection = TextSelection.collapsed(
          offset: _inputController.text.length,
        );
      } else {
        _inputController.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: ForgeAppBar(
        title: 'Terminal',
        showBackButton: true,
        actions: [
          StatusBadge(
            label: _isRunning
                ? 'Running'
                : _isConnected
                    ? 'Connected'
                    : 'Disconnected',
            color: _isRunning
                ? AppColors.warning
                : _isConnected
                    ? AppColors.success
                    : AppColors.error,
            pulsing: _isConnected || _isRunning,
            size: BadgeSize.small,
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, size: 20),
            onPressed: () => setState(_lines.clear),
            tooltip: 'Clear',
          ),
        ],
      ),
      body: Container(
        color: AppColors.backgroundPrimary,
        child: Column(
          children: [
            // ── Output ──
            Expanded(
              child: GestureDetector(
                onTap: () => _inputFocus.requestFocus(),
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(12),
                  itemCount: _lines.length,
                  itemBuilder: (_, i) => _TerminalLineWidget(
                    line: _lines[i],
                  ),
                ),
              ),
            ),

            // ── Input ──
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.backgroundSecondary,
                border: Border(
                  top: BorderSide(color: AppColors.borderSubtle),
                ),
              ),
              child: Row(
                children: [
                  Text(
                    '\$ ',
                    style: GoogleFonts.jetBrainsMono(
                      color: AppColors.success,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Expanded(
                    child: KeyboardListener(
                      focusNode: FocusNode(),
                      onKeyEvent: (event) {
                        if (event is KeyDownEvent) {
                          if (event.logicalKey ==
                              LogicalKeyboardKey.arrowUp) {
                            _navigateHistory(true);
                          } else if (event.logicalKey ==
                              LogicalKeyboardKey.arrowDown) {
                            _navigateHistory(false);
                          }
                        }
                      },
                      child: TextField(
                        controller: _inputController,
                        focusNode: _inputFocus,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 14,
                          color: AppColors.textPrimary,
                        ),
                        decoration: const InputDecoration(
                          hintText: 'Enter command...',
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                          isDense: true,
                        ),
                        onSubmitted: (cmd) {
                          _executeCommand(cmd);
                          _inputFocus.requestFocus();
                        },
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.send_rounded, size: 18),
                    onPressed: () {
                      _executeCommand(_inputController.text);
                      _inputFocus.requestFocus();
                    },
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A single terminal output line.
class _TerminalLine {
  const _TerminalLine({required this.text, this.color});

  final String text;
  final Color? color;
}

class _TerminalLineWidget extends StatelessWidget {
  const _TerminalLineWidget({required this.line});

  final _TerminalLine line;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: SelectableText(
        line.text,
        style: GoogleFonts.jetBrainsMono(
          fontSize: 13,
          color: line.color ?? AppColors.textPrimary,
          height: 1.5,
        ),
      ),
    );
  }
}

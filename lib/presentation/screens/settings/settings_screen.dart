/// TermuxForge — Settings Screen
///
/// Full settings screen with API key management, provider priority,
/// default model per mode, permission configuration, theme toggle,
/// Termux bridge config, and MCP server management.
library;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'package:nexon/core/theme/app_colors.dart';
import 'package:nexon/presentation/widgets/forge_app_bar.dart';
import 'package:nexon/presentation/widgets/glass_card.dart';
import 'package:nexon/presentation/widgets/status_badge.dart';

/// The settings screen.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // State.
  bool _darkMode = true;
  int _permissionLevel = 5;
  bool _autoApprove = false;

  // API key visibility toggles.
  final Map<String, bool> _keyVisible = {};

  // Demo providers.
  final _providers = <_ProviderConfig>[
    _ProviderConfig(
      name: 'Anthropic',
      icon: Icons.auto_awesome_rounded,
      color: AppColors.accentPurple,
      hasKey: true,
    ),
    _ProviderConfig(
      name: 'OpenAI',
      icon: Icons.psychology_rounded,
      color: AppColors.success,
      hasKey: true,
    ),
    _ProviderConfig(
      name: 'Google Gemini',
      icon: Icons.diamond_rounded,
      color: AppColors.accentBlue,
      hasKey: false,
    ),
    _ProviderConfig(
      name: 'OpenRouter',
      icon: Icons.route_rounded,
      color: AppColors.accentTeal,
      hasKey: false,
    ),
    _ProviderConfig(
      name: 'Local (Ollama)',
      icon: Icons.computer_rounded,
      color: AppColors.warning,
      hasKey: false,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const ForgeAppBar(title: 'Settings', showBackButton: true),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── API Keys ──
          _SectionHeader(
            title: 'API Keys',
            icon: Icons.key_rounded,
            color: AppColors.accentBlue,
          ),
          const SizedBox(height: 8),
          ..._providers.map((p) => _buildProviderKeyCard(p)),

          const SizedBox(height: 24),

          // ── Provider Priority ──
          _SectionHeader(
            title: 'Provider Priority',
            icon: Icons.sort_rounded,
            color: AppColors.accentPurple,
            subtitle: 'Drag to reorder fallback priority',
          ),
          const SizedBox(height: 8),
          GlassCard(
            padding: const EdgeInsets.all(8),
            child: ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _providers.length,
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (newIndex > oldIndex) newIndex--;
                  final item = _providers.removeAt(oldIndex);
                  _providers.insert(newIndex, item);
                });
              },
              itemBuilder: (_, i) {
                final p = _providers[i];
                return ListTile(
                  key: ValueKey(p.name),
                  dense: true,
                  leading: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${i + 1}',
                        style: TextStyle(
                          color: AppColors.textTertiary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(p.icon, size: 20, color: p.color),
                    ],
                  ),
                  title: Text(p.name, style: const TextStyle(fontSize: 14)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      StatusBadge(
                        label: p.hasKey ? 'Active' : 'No Key',
                        color: p.hasKey ? AppColors.success : AppColors.textTertiary,
                        size: BadgeSize.small,
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.drag_handle_rounded, size: 18),
                    ],
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 24),

          // ── Permission & Safety ──
          _SectionHeader(
            title: 'Permissions & Safety',
            icon: Icons.shield_rounded,
            color: AppColors.permissionLevel(_permissionLevel),
          ),
          const SizedBox(height: 8),
          GlassCard(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Auto-approve safe commands',
                      style: TextStyle(fontSize: 14)),
                  subtitle: const Text('Risk level ≤ 3',
                      style: TextStyle(fontSize: 12)),
                  value: _autoApprove,
                  onChanged: (v) => setState(() => _autoApprove = v),
                ),
                const Divider(height: 1),
                ListTile(
                  title: const Text('Max auto-approve level',
                      style: TextStyle(fontSize: 14)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$_permissionLevel',
                        style: TextStyle(
                          color: AppColors.permissionLevel(_permissionLevel),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                Slider(
                  value: _permissionLevel.toDouble(),
                  min: 1,
                  max: 10,
                  divisions: 9,
                  activeColor: AppColors.permissionLevel(_permissionLevel),
                  onChanged: (v) =>
                      setState(() => _permissionLevel = v.round()),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ── Appearance ──
          _SectionHeader(
            title: 'Appearance',
            icon: Icons.palette_rounded,
            color: AppColors.accentTeal,
          ),
          const SizedBox(height: 8),
          GlassCard(
            child: SwitchListTile(
              title: const Text('Dark Mode',
                  style: TextStyle(fontSize: 14)),
              secondary: Icon(
                _darkMode ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                color: _darkMode ? AppColors.accentPurple : AppColors.warning,
              ),
              value: _darkMode,
              onChanged: (v) => setState(() => _darkMode = v),
            ),
          ),

          const SizedBox(height: 24),

          // ── Termux Bridge ──
          _SectionHeader(
            title: 'Termux Bridge',
            icon: Icons.terminal_rounded,
            color: AppColors.success,
          ),
          const SizedBox(height: 8),
          GlassCard(
            child: Column(
              children: [
                ListTile(
                  dense: true,
                  title: const Text('Connection',
                      style: TextStyle(fontSize: 14)),
                  trailing: StatusBadge(
                    label: 'Connected',
                    color: AppColors.success,
                    pulsing: true,
                    size: BadgeSize.small,
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  dense: true,
                  title: const Text('Socket Path',
                      style: TextStyle(fontSize: 14)),
                  subtitle: const Text(
                    '/data/data/com.termux/files/usr/tmp/forge.sock',
                    style: TextStyle(fontSize: 11),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  dense: true,
                  title: const Text('Test Connection',
                      style: TextStyle(fontSize: 14)),
                  trailing: OutlinedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.wifi_tethering_rounded, size: 16),
                    label: const Text('Test', style: TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ── MCP Servers ──
          _SectionHeader(
            title: 'MCP Servers',
            icon: Icons.electrical_services_rounded,
            color: AppColors.accentPurple,
          ),
          const SizedBox(height: 8),
          GlassCard(
            child: Column(
              children: [
                ListTile(
                  dense: true,
                  leading: StatusBadge(
                    label: 'Active',
                    color: AppColors.success,
                    pulsing: true,
                    size: BadgeSize.small,
                  ),
                  title: const Text('filesystem',
                      style: TextStyle(fontSize: 14)),
                  subtitle: const Text('stdio • 12 tools',
                      style: TextStyle(fontSize: 11)),
                ),
                const Divider(height: 1),
                ListTile(
                  dense: true,
                  leading: StatusBadge(
                    label: 'Active',
                    color: AppColors.success,
                    pulsing: true,
                    size: BadgeSize.small,
                  ),
                  title: const Text('git',
                      style: TextStyle(fontSize: 14)),
                  subtitle: const Text('stdio • 8 tools',
                      style: TextStyle(fontSize: 11)),
                ),
                const Divider(height: 1),
                ListTile(
                  dense: true,
                  title: const Text('Add MCP Server',
                      style: TextStyle(fontSize: 14)),
                  leading: const Icon(Icons.add_circle_outline_rounded),
                  onTap: () {},
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ── Data ──
          _SectionHeader(
            title: 'Data',
            icon: Icons.storage_rounded,
            color: AppColors.warning,
          ),
          const SizedBox(height: 8),
          GlassCard(
            child: Column(
              children: [
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.upload_rounded),
                  title: const Text('Export Data',
                      style: TextStyle(fontSize: 14)),
                  onTap: () {},
                ),
                const Divider(height: 1),
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.download_rounded),
                  title: const Text('Import Data',
                      style: TextStyle(fontSize: 14)),
                  onTap: () {},
                ),
                const Divider(height: 1),
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.delete_forever_rounded,
                      color: AppColors.error),
                  title: const Text('Clear All Data',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.error,
                      )),
                  onTap: () {},
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildProviderKeyCard(_ProviderConfig provider) {
    final isVisible = _keyVisible[provider.name] ?? false;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        padding: const EdgeInsets.all(14),
        borderRadius: 14,
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: provider.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(provider.icon, size: 20, color: provider.color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    provider.name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (provider.hasKey)
                    Text(
                      isVisible ? 'sk-ant-***************abc123' : '••••••••••••••••',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textTertiary,
                        fontFamily: 'JetBrainsMono',
                      ),
                    )
                  else
                    Text(
                      'No API key configured',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textTertiary,
                      ),
                    ),
                ],
              ),
            ),
            if (provider.hasKey)
              IconButton(
                icon: Icon(
                  isVisible
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  size: 18,
                ),
                onPressed: () => setState(
                  () => _keyVisible[provider.name] = !isVisible,
                ),
              ),
            IconButton(
              icon: const Icon(Icons.edit_rounded, size: 18),
              onPressed: () => _showKeyDialog(provider),
            ),
          ],
        ),
      ).animate().fadeIn(duration: 200.ms),
    );
  }

  void _showKeyDialog(_ProviderConfig provider) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${provider.name} API Key'),
        content: TextField(
          controller: controller,
          obscureText: true,
          decoration: const InputDecoration(
            hintText: 'Enter API key...',
            prefixIcon: Icon(Icons.key_rounded),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() => provider.hasKey = true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

class _ProviderConfig {
  _ProviderConfig({
    required this.name,
    required this.icon,
    required this.color,
    required this.hasKey,
  });

  final String name;
  final IconData icon;
  final Color color;
  bool hasKey;
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.icon,
    required this.color,
    this.subtitle,
  });

  final String title;
  final IconData icon;
  final Color color;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

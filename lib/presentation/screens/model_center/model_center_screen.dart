/// TermuxForge — Model Center Screen
///
/// API provider management: add, edit, delete providers with
/// name / API key / base URL / model name. Data persisted via
/// AppStorage (SharedPreferences + FlutterSecureStorage).
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:uuid/uuid.dart';

import 'package:termux_forge/core/theme/app_colors.dart';
import 'package:termux_forge/presentation/widgets/forge_app_bar.dart';
import 'package:termux_forge/presentation/widgets/glass_card.dart';
import 'package:termux_forge/services/storage/app_storage.dart';

// ────────────────────────────────────────────────
//  Screen
// ────────────────────────────────────────────────

/// The model / provider management screen.
class ModelCenterScreen extends StatefulWidget {
  const ModelCenterScreen({super.key});

  @override
  State<ModelCenterScreen> createState() => _ModelCenterScreenState();
}

class _ModelCenterScreenState extends State<ModelCenterScreen> {
  static const _uuid = Uuid();

  List<Map<String, dynamic>> _providers = [];
  bool _isLoading = true;

  // ── lifecycle ──────────────────────────────────

  @override
  void initState() {
    super.initState();
    _loadProviders();
  }

  Future<void> _loadProviders() async {
    final loaded = await AppStorage.loadProviders();
    if (!mounted) return;
    setState(() {
      _providers = loaded.map(AppStorage.normalizeProvider).toList();
      _isLoading = false;
    });
  }

  Future<void> _saveProviders() async {
    await AppStorage.saveProviders(_providers);
  }

  // ── CRUD helpers ───────────────────────────────

  Future<void> _addProvider(
    String name,
    String apiKey,
    String baseUrl,
    String modelName,
  ) async {
    final id = _uuid.v4();
    final provider = AppStorage.normalizeProvider(<String, dynamic>{
      'id': id,
      'name': name,
      'baseUrl': baseUrl.trim(),
      'modelName': modelName,
      'model': modelName,
      'defaultModel': modelName,
      'models': [modelName],
      'priority': _providers.length + 1,
    });
    setState(() => _providers.add(provider));
    await AppStorage.saveApiKey(id, apiKey);
    await _saveProviders();
  }

  Future<void> _updateProvider(
    String id,
    String name,
    String apiKey,
    String baseUrl,
    String modelName,
  ) async {
    final idx = _providers.indexWhere((p) => p['id'] == id);
    if (idx == -1) return;
    setState(() {
      _providers[idx] = AppStorage.normalizeProvider({
        ..._providers[idx],
        'id': id,
        'name': name,
        'baseUrl': baseUrl.trim(),
        'modelName': modelName,
        'model': modelName,
        'defaultModel': modelName,
        'models': [modelName],
      });
    });
    await AppStorage.saveApiKey(id, apiKey);
    await _saveProviders();
  }

  Future<void> _deleteProvider(String id) async {
    setState(() => _providers.removeWhere((p) => p['id'] == id));
    await AppStorage.deleteApiKey(id);
    await _saveProviders();
  }

  Future<List<String>> _discoverModels({
    required String baseUrl,
    required String apiKey,
  }) async {
    final endpoint = _modelsEndpoint(baseUrl);
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(endpoint));
      request.headers.set('Accept', 'application/json');
      if (apiKey.trim().isNotEmpty) {
        request.headers.set('Authorization', 'Bearer ${apiKey.trim()}');
      }

      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('HTTP ${response.statusCode}: $body');
      }

      final decoded = jsonDecode(body);
      final rawModels = decoded is Map<String, dynamic>
          ? decoded['data'] ?? decoded['models'] ?? decoded['items']
          : decoded;
      if (rawModels is! List) {
        throw const FormatException('Provider did not return a model list');
      }

      final models = rawModels
          .map((item) {
            if (item is String) return item;
            if (item is Map) {
              return (item['id'] ??
                      item['name'] ??
                      item['model'] ??
                      item['slug'])
                  ?.toString();
            }
            return null;
          })
          .whereType<String>()
          .map((model) => model.trim())
          .where((model) => model.isNotEmpty)
          .toSet()
          .toList()
        ..sort();

      if (models.isEmpty) {
        throw const FormatException('No usable model IDs were returned');
      }
      return models;
    } finally {
      client.close(force: true);
    }
  }

  String _modelsEndpoint(String baseUrl) {
    final clean = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (clean.endsWith('/models')) return clean;
    if (clean.endsWith('/chat/completions')) {
      return clean.replaceFirst(RegExp(r'/chat/completions$'), '/models');
    }
    return '$clean/models';
  }

  Future<void> _discoverAndPickModel({
    required BuildContext context,
    required TextEditingController urlCtrl,
    required TextEditingController keyCtrl,
    required TextEditingController modelCtrl,
  }) async {
    final baseUrl = urlCtrl.text.trim();
    if (baseUrl.isEmpty) {
      _showSnack('Enter a base URL first');
      return;
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final models = await _discoverModels(
        baseUrl: baseUrl,
        apiKey: keyCtrl.text.trim(),
      );
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();

      final selected = await showDialog<String>(
        context: context,
        builder: (_) => _ModelPickerDialog(models: models),
      );
      if (selected == null) return;
      modelCtrl.text = selected;
      _showSnack('Loaded ${models.length} models');
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      _showSnack('Model discovery failed: $e');
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  // ── bottom sheet ───────────────────────────────

  /// Opens the add / edit bottom sheet.
  ///
  /// When [existing] is non-null the sheet is in edit mode.
  Future<void> _openProviderSheet({Map<String, dynamic>? existing}) async {
    final isEdit = existing != null;

    final nameCtrl = TextEditingController(text: existing?['name'] ?? '');
    final keyCtrl = TextEditingController();
    final urlCtrl = TextEditingController(text: existing?['baseUrl'] ?? '');
    final modelCtrl = TextEditingController(
      text: existing == null ? '' : AppStorage.providerModelName(existing),
    );

    // Pre-fill existing API key (async).
    if (isEdit) {
      final savedKey = await AppStorage.getApiKey(existing['id'] as String);
      keyCtrl.text = savedKey ?? '';
    }

    if (!mounted) return;

    final formKey = GlobalKey<FormState>();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.backgroundSecondary,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Drag handle
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.borderSubtle,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Title
                  Text(
                    isEdit ? 'Edit Provider' : 'Add Provider',
                    style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                  ),
                  const SizedBox(height: 20),

                  _SheetField(
                    controller: nameCtrl,
                    label: 'Provider Name',
                    hint: 'e.g. OpenRouter, My Local LLM',
                    icon: Icons.dns_outlined,
                    validator: _required,
                  ),
                  const SizedBox(height: 14),

                  _SheetField(
                    controller: keyCtrl,
                    label: 'API Key (optional)',
                    hint: 'sk-... or blank for local/no-auth endpoints',
                    icon: Icons.vpn_key_outlined,
                    obscure: true,
                  ),
                  const SizedBox(height: 14),

                  _SheetField(
                    controller: urlCtrl,
                    label: 'Base URL',
                    hint: 'https://openrouter.ai/api/v1',
                    icon: Icons.link_rounded,
                    keyboardType: TextInputType.url,
                    validator: _required,
                  ),
                  const SizedBox(height: 14),

                  _SheetField(
                    controller: modelCtrl,
                    label: 'Model Name',
                    hint: 'anthropic/claude-sonnet-4',
                    icon: Icons.auto_awesome_outlined,
                    validator: _required,
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _discoverAndPickModel(
                        context: ctx,
                        urlCtrl: urlCtrl,
                        keyCtrl: keyCtrl,
                        modelCtrl: modelCtrl,
                      ),
                      icon: const Icon(Icons.sync_rounded, size: 18),
                      label: const Text('Discover Models from API Key'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.accentTeal,
                        side: BorderSide(
                          color: AppColors.accentTeal.withValues(alpha: 0.45),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(
                                color: AppColors.borderSubtle),
                            foregroundColor: AppColors.textSecondary,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            if (!formKey.currentState!.validate()) return;
                            Navigator.pop(ctx);
                            if (isEdit) {
                              _updateProvider(
                                existing['id'] as String,
                                nameCtrl.text.trim(),
                                keyCtrl.text.trim(),
                                urlCtrl.text.trim(),
                                modelCtrl.text.trim(),
                              );
                            } else {
                              _addProvider(
                                nameCtrl.text.trim(),
                                keyCtrl.text.trim(),
                                urlCtrl.text.trim(),
                                modelCtrl.text.trim(),
                              );
                            }
                          },
                          icon: Icon(isEdit
                              ? Icons.save_rounded
                              : Icons.add_rounded),
                          label: Text(isEdit ? 'Save' : 'Add Provider'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.accentBlue,
                            foregroundColor: AppColors.backgroundPrimary,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    nameCtrl.dispose();
    keyCtrl.dispose();
    urlCtrl.dispose();
    modelCtrl.dispose();
  }

  static String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Required' : null;

  // ── delete confirmation ────────────────────────

  Future<bool> _confirmDelete(Map<String, dynamic> provider) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.backgroundTertiary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Provider'),
        content: Text(
          'Remove "${provider['name']}"? The API key will be permanently deleted.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  // ── provider accent color ──────────────────────

  Color _accentForIndex(int index) {
    const palette = [
      AppColors.accentBlue,
      AppColors.accentPurple,
      AppColors.accentTeal,
      AppColors.success,
      AppColors.warning,
    ];
    return palette[index % palette.length];
  }

  // ── build ──────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      appBar: const ForgeAppBar(
        title: 'Model Center',
        showBackButton: true,
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.accentBlue),
            )
          : _providers.isEmpty
              ? _buildEmptyState(context)
              : _buildProviderList(context),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openProviderSheet(),
        backgroundColor: AppColors.accentBlue,
        foregroundColor: AppColors.backgroundPrimary,
        tooltip: 'Add provider',
        child: const Icon(Icons.add_rounded),
      ),
    );
  }

  // ── empty state ────────────────────────────────

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.accentBlue.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.hub_outlined,
                size: 56,
                color: AppColors.accentBlue,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No providers configured',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap the + button to add an API provider.\n'
              'You can connect OpenRouter, OpenAI, local LLMs, or any\n'
              'OpenAI-compatible endpoint.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
            ),
          ],
        )
            .animate()
            .fadeIn(duration: 400.ms)
            .moveY(begin: 12, end: 0, duration: 400.ms, curve: Curves.easeOut),
      ),
    );
  }

  // ── provider list ──────────────────────────────

  Widget _buildProviderList(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 88),
      itemCount: _providers.length,
      itemBuilder: (_, i) {
        final provider = _providers[i];
        final accent = _accentForIndex(i);

        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Dismissible(
            key: ValueKey(provider['id']),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 24),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.delete_outline_rounded,
                  color: AppColors.error, size: 28),
            ),
            confirmDismiss: (_) => _confirmDelete(provider),
            onDismissed: (_) =>
                _deleteProvider(provider['id'] as String),
            child: GlassCard(
              padding: const EdgeInsets.all(16),
              borderRadius: 14,
              borderColor: accent.withValues(alpha: 0.2),
              onTap: () => _openProviderSheet(existing: provider),
              child: Row(
                children: [
                  // Leading icon
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.cloud_outlined,
                      color: accent,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),

                  // Text content
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          provider['name'] as String? ?? 'Unnamed',
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimary,
                                  ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.auto_awesome_outlined,
                                size: 13, color: AppColors.textTertiary),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                AppStorage.providerModelName(provider).isEmpty
                                    ? '-'
                                    : AppStorage.providerModelName(provider),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(Icons.link_rounded,
                                size: 13, color: AppColors.textTertiary),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                provider['baseUrl'] as String? ?? '—',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textTertiary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Trailing actions
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.success.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'Ready',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: AppColors.success,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: () async {
                          final ok = await _confirmDelete(provider);
                          if (ok) _deleteProvider(provider['id'] as String);
                        },
                        child: const Icon(
                          Icons.delete_outline_rounded,
                          size: 18,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          )
              .animate()
              .fadeIn(
                delay: Duration(milliseconds: i * 60),
                duration: 300.ms,
              )
              .moveX(
                begin: 24,
                end: 0,
                delay: Duration(milliseconds: i * 60),
                duration: 300.ms,
                curve: Curves.easeOut,
              ),
        );
      },
    );
  }
}

// ────────────────────────────────────────────────
//  Private Widgets
// ────────────────────────────────────────────────

class _ModelPickerDialog extends StatefulWidget {
  const _ModelPickerDialog({required this.models});

  final List<String> models;

  @override
  State<_ModelPickerDialog> createState() => _ModelPickerDialogState();
}

class _ModelPickerDialogState extends State<_ModelPickerDialog> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.models
        .where((model) => model.toLowerCase().contains(_query.toLowerCase()))
        .toList();

    return AlertDialog(
      backgroundColor: AppColors.backgroundTertiary,
      title: const Text('Select Model'),
      content: SizedBox(
        width: 520,
        height: 420,
        child: Column(
          children: [
            TextField(
              controller: _searchCtrl,
              onChanged: (value) => setState(() => _query = value),
              decoration: const InputDecoration(
                hintText: 'Search models',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: filtered.isEmpty
                  ? const Center(child: Text('No matching models'))
                  : ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        color: AppColors.borderSubtle,
                      ),
                      itemBuilder: (_, index) {
                        final model = filtered[index];
                        return ListTile(
                          dense: true,
                          leading: const Icon(
                            Icons.auto_awesome_outlined,
                            size: 18,
                            color: AppColors.accentTeal,
                          ),
                          title: Text(
                            model,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => Navigator.pop(context, model),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

/// Styled text field used inside the provider bottom sheet.
class _SheetField extends StatelessWidget {
  const _SheetField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.obscure = false,
    this.keyboardType,
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final bool obscure;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      validator: validator,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: AppColors.textSecondary),
        hintStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 13),
        prefixIcon: Icon(icon, size: 20, color: AppColors.textTertiary),
        filled: true,
        fillColor: AppColors.backgroundTertiary,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.borderSubtle),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.borderSubtle),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: AppColors.accentBlue, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.error),
        ),
      ),
    );
  }
}

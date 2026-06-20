import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppStorage {
  static late SharedPreferences _prefs;
  static const _secureStorage = FlutterSecureStorage();

  // SharedPreferences keys
  static const _kProviders = 'providers';
  static const _kSelectedMode = 'selected_mode';
  static const _kSelectedProviderId = 'selected_provider_id';
  static const _kOnboarded = 'onboarded';
  static const _kChatMessages = 'chat_messages';

  // Secure storage key prefix
  static const _kApiKeyPrefix = 'api_key_';

  /// Initialize SharedPreferences. Call once at app startup.
  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // --------------- Providers ---------------

  static Future<void> saveProviders(List<Map<String, dynamic>> providers) async {
    final json = jsonEncode(providers.map(normalizeProvider).toList());
    await _prefs.setString(_kProviders, json);
  }

  static Future<List<Map<String, dynamic>>> loadProviders() async {
    final json = _prefs.getString(_kProviders);
    if (json == null) return [];
    try {
      final decoded = jsonDecode(json);
      if (decoded is! List) return [];
      final providers = decoded
          .whereType<Map>()
          .map((item) => normalizeProvider(Map<String, dynamic>.from(item)))
          .toList();
      await saveProviders(providers);
      return providers;
    } catch (_) {
      return [];
    }
  }

  static Map<String, dynamic> normalizeProvider(Map<String, dynamic> provider) {
    final rawId = (provider['id'] ?? '').toString().trim();
    final id = rawId.isNotEmpty
        ? rawId
        : 'provider_${DateTime.now().microsecondsSinceEpoch}';
    final modelName = _firstNonEmpty([
      provider['modelName'],
      provider['defaultModel'],
      provider['model'],
      if (provider['models'] is List && (provider['models'] as List).isNotEmpty)
        (provider['models'] as List).first,
    ]);
    final baseUrl = (provider['baseUrl'] ?? provider['url'] ?? '')
        .toString()
        .trim()
        .replaceAll(RegExp(r'/+$'), '');

    return {
      ...provider,
      'id': id,
      'name': (provider['name'] ?? 'Provider').toString(),
      'baseUrl': baseUrl,
      'modelName': modelName,
      'defaultModel': modelName,
      'model': modelName,
      'models': [
        modelName,
        if (provider['models'] is List)
          ...(provider['models'] as List).map((m) => m.toString()),
      ].where((m) => m.trim().isNotEmpty).toSet().toList(),
      'priority': provider['priority'] ?? 50,
      'customHeaders': provider['customHeaders'] ?? <String, String>{},
    };
  }

  static String providerModelName(Map<String, dynamic> provider) {
    return normalizeProvider(provider)['modelName'] as String;
  }

  static String _firstNonEmpty(List<dynamic> values) {
    for (final value in values) {
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  // --------------- API Keys (secure) ---------------

  static Future<void> saveApiKey(String providerId, String apiKey) async {
    await _secureStorage.write(key: '$_kApiKeyPrefix$providerId', value: apiKey);
  }

  static Future<String?> getApiKey(String providerId) async {
    return _secureStorage.read(key: '$_kApiKeyPrefix$providerId');
  }

  static Future<void> deleteApiKey(String providerId) async {
    await _secureStorage.delete(key: '$_kApiKeyPrefix$providerId');
  }

  // --------------- Selected Mode ---------------

  static Future<void> saveSelectedMode(String mode) async {
    await _prefs.setString(_kSelectedMode, mode);
  }

  static Future<String> getSelectedMode() async {
    return _prefs.getString(_kSelectedMode) ?? 'chat';
  }

  // --------------- Selected Provider ---------------

  static Future<void> saveSelectedProviderId(String providerId) async {
    await _prefs.setString(_kSelectedProviderId, providerId);
  }

  static Future<String?> getSelectedProviderId() async {
    return _prefs.getString(_kSelectedProviderId);
  }

  // --------------- Onboarded ---------------

  static Future<void> saveOnboarded(bool value) async {
    await _prefs.setBool(_kOnboarded, value);
  }

  static Future<bool> isOnboarded() async {
    return _prefs.getBool(_kOnboarded) ?? false;
  }

  // --------------- Chat Messages ---------------

  static Future<void> saveChatMessages(List<Map<String, dynamic>> messages) async {
    final json = jsonEncode(messages);
    await _prefs.setString(_kChatMessages, json);
  }

  static Future<List<Map<String, dynamic>>> loadChatMessages() async {
    final json = _prefs.getString(_kChatMessages);
    if (json == null) return [];
    final List<dynamic> decoded = jsonDecode(json) as List<dynamic>;
    return decoded.cast<Map<String, dynamic>>();
  }
}

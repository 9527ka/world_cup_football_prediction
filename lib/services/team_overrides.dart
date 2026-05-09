import 'package:flutter/foundation.dart';

import 'api_client.dart';

/// In-memory cache of admin-edited team display overrides
/// (zh name / en name / logo URL), keyed by upstream English team name.
///
/// Loaded once at app start (and refreshable via [refresh()]); falls back
/// silently to empty when the backend is unreachable so client behavior
/// degrades to the hardcoded zh map + apiSports CDN logos.
class TeamOverrides extends ChangeNotifier {
  TeamOverrides._();
  static final TeamOverrides instance = TeamOverrides._();

  Map<String, Map<String, String>> _byKey = const {};
  String _baseUrl = '';

  String? nameZh(String key) {
    final v = _byKey[key]?['nameZh'];
    return (v == null || v.isEmpty) ? null : v;
  }

  String? nameEn(String key) {
    final v = _byKey[key]?['nameEn'];
    return (v == null || v.isEmpty) ? null : v;
  }

  /// Returns the absolute logo URL or null when no override exists.
  /// Resolves relative `/uploads/...` paths against the API base.
  String? logoUrl(String key) {
    final v = _byKey[key]?['logoUrl'];
    if (v == null || v.isEmpty) return null;
    if (v.startsWith('http://') || v.startsWith('https://')) return v;
    if (v.startsWith('/') && _baseUrl.isNotEmpty) return '$_baseUrl$v';
    return v;
  }

  /// Initial load. Safe to call multiple times — late callers see refreshed
  /// data. Errors are swallowed (we just keep the previous map).
  Future<void> load(ApiClient api) async {
    _baseUrl = api.baseUrl;
    try {
      _byKey = await api.teamOverrides();
      notifyListeners();
    } catch (_) {/* keep old map */}
  }

  Future<void> refresh(ApiClient api) => load(api);
}

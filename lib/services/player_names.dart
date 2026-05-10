import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// In-memory cache of English-name → Chinese-name resolutions for player
/// names appearing in match events. Backend does the dongqiudi lookup +
/// Redis cache; we just remember what we've already fetched in this app
/// session so re-entering a match detail page doesn't refetch.
///
/// `null` value in the map means "we asked, dongqiudi has no answer" — in
/// that case the caller should keep the English name verbatim (do NOT
/// retry within this session, it was fetched <30 days ago server-side).
class PlayerNames {
  PlayerNames._();
  static final PlayerNames instance = PlayerNames._();

  final Map<String, String?> _cache = {};

  /// Localize a single English player name. Falls back to the English
  /// when no translation exists yet (call [ensureLoaded] first to fill).
  String localize(String en) {
    final v = _cache[en];
    return (v == null || v.isEmpty) ? en : v;
  }

  /// Fetch any missing names from the backend in one batch and update
  /// the cache. Safe to call repeatedly; already-known names skipped.
  Future<void> ensureLoaded(String apiBase, Iterable<String> names,
      {String? authToken}) async {
    final missing = <String>{};
    for (final n in names) {
      final t = n.trim();
      if (t.isEmpty) continue;
      if (!_cache.containsKey(t)) missing.add(t);
    }
    if (missing.isEmpty) return;
    try {
      final r = await http
          .post(
            Uri.parse('$apiBase/api/i18n/players'),
            headers: {
              'Content-Type': 'application/json',
              if (authToken != null && authToken.isNotEmpty)
                'Authorization': 'Bearer $authToken',
            },
            body: jsonEncode({'names': missing.toList()}),
          )
          .timeout(const Duration(seconds: 7));
      if (r.statusCode != 200) return;
      final body = jsonDecode(r.body) as Map<String, dynamic>;
      final m = (body['map'] as Map?) ?? {};
      // Mark every name we asked about — even those without a translation
      // — so we don't retry them this session.
      for (final n in missing) {
        final zh = m[n];
        _cache[n] = (zh is String && zh.isNotEmpty) ? zh : null;
      }
    } catch (_) {
      // Network blip — leave names un-cached, next call will retry.
    }
  }
}

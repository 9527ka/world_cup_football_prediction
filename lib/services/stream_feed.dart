import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../models/match.dart';
import '../utils/team_names.dart';
import 'api_client.dart';

/// MatchStream is the slim record from /api/streams (server polls 7t666).
class MatchStream {
  final String matchId;
  final String homeTeam; // Chinese (upstream is Chinese-only)
  final String awayTeam;
  final String league;
  final int startTime; // unix seconds
  final String statusDesc;
  final int status; // 0=pending, 1=live, 2=ended
  final String streamUrl; // m3u8
  final String streamFlv;

  const MatchStream({
    required this.matchId,
    required this.homeTeam,
    required this.awayTeam,
    required this.league,
    required this.startTime,
    required this.statusDesc,
    required this.status,
    required this.streamUrl,
    required this.streamFlv,
  });

  factory MatchStream.fromJson(Map<String, dynamic> j) => MatchStream(
        matchId: j['matchId'] ?? '',
        homeTeam: j['homeTeam'] ?? '',
        awayTeam: j['awayTeam'] ?? '',
        league: j['league'] ?? '',
        startTime: (j['startTime'] ?? 0) as int,
        statusDesc: j['statusDesc'] ?? '',
        status: (j['status'] ?? 0) as int,
        streamUrl: j['streamUrl'] ?? '',
        streamFlv: j['streamFlv'] ?? '',
      );
}

/// StreamFeed loads /api/streams once per session and exposes a join helper
/// that maps an English-named match (from API-Football) to a Chinese-named
/// stream (from 7t666) using the team_names.dart Chinese mapping.
///
/// Match strategy (in order of precedence):
///   1. Exact "<homeZh>|<awayZh>" key lookup (fast path, hash table)
///   2. Normalized fuzzy match (drops common suffixes: 队/FC/俱乐部/etc.,
///      strips spaces, case-folded). Required for cases like "浙江"
///      (team_names.dart) vs "浙江队" (7t666 upstream).
///
/// Kickoff is checked last as a sanity tiebreaker (±3h window) so a stale
/// cached stream from yesterday doesn't get attached to today's same-pair
/// fixture.
class StreamFeed {
  StreamFeed._();
  static final StreamFeed instance = StreamFeed._();

  final Map<String, MatchStream> _byKey = {};
  // Parallel list with normalized keys for fuzzy fallback.
  final List<_IndexedStream> _normalized = [];

  DateTime _lastFetch = DateTime.fromMillisecondsSinceEpoch(0);
  Future<void>? _inflight;
  ApiClient? _api;

  // 5 min — generous enough to amortize the network call across rapid scrolls,
  // tight enough that signed m3u8 URLs (≈ 30 min real TTL upstream) don't go
  // stale before next refresh. Server polls upstream every 25 min, so worst-
  // case cached entries handed to clients are 25 min old.
  static const _ttl = Duration(minutes: 5);

  /// Ensure the feed cache is fresh. Safe to call multiple times — concurrent
  /// callers piggyback on the same in-flight request.
  Future<void> ensure(ApiClient api) async {
    _api = api;
    if (DateTime.now().difference(_lastFetch) < _ttl && _byKey.isNotEmpty) {
      return;
    }
    _inflight ??= _fetch(api).whenComplete(() => _inflight = null);
    return _inflight;
  }

  /// Force-refresh the cache (skip TTL). Used when find() detects an expired
  /// stream URL, so the next render gets fresh signed URLs.
  Future<void> refresh() {
    final api = _api;
    if (api == null) return Future.value();
    _inflight ??= _fetch(api).whenComplete(() => _inflight = null);
    return _inflight!;
  }

  Future<void> _fetch(ApiClient api) async {
    try {
      final res = await api.listStreams();
      _byKey.clear();
      _normalized.clear();
      for (final raw in res.streams) {
        final s = MatchStream.fromJson(raw);
        if (s.streamUrl.isEmpty) continue;
        _byKey[_keyOf(s.homeTeam, s.awayTeam)] = s;
        _normalized.add(_IndexedStream(
          stream: s,
          homeNorm: _normalize(s.homeTeam),
          awayNorm: _normalize(s.awayTeam),
        ));
      }
      _lastFetch = DateTime.now();
    } catch (_) {
      // swallow — feed is best-effort
    }
  }

  /// Find a stream URL for the given English-named match. Returns null when
  /// no stream is available, the kickoff is more than 3h off, or the cached
  /// URL has already expired (in which case a background refresh is kicked
  /// off so subsequent renders pick up the fresh entry).
  MatchStream? find(String homeEn, String awayEn, DateTime kickoff) {
    final hZh = localizedTeam(homeEn);
    final aZh = localizedTeam(awayEn);
    MatchStream? hit = _byKey[_keyOf(hZh, aZh)];

    if (hit == null) {
      final hNorm = _normalize(hZh);
      final aNorm = _normalize(aZh);
      if (hNorm.isEmpty || aNorm.isEmpty) return null;
      for (final ix in _normalized) {
        if (ix.homeNorm == hNorm && ix.awayNorm == aNorm) {
          hit = ix.stream;
          break;
        }
      }
    }

    if (hit == null) return null;
    final ks = DateTime.fromMillisecondsSinceEpoch(hit.startTime * 1000);
    if (ks.difference(kickoff).abs() > const Duration(hours: 3)) {
      return null;
    }

    // Detect expired auth_key. If so, hide the stream and trigger a refresh.
    final expiresAt = streamUrlExpiresAt(hit.streamUrl);
    if (expiresAt != null && expiresAt.isBefore(DateTime.now())) {
      // fire-and-forget; UI will rebuild after the refetch completes via
      // whatever caller invoked ensure()/find() does setState.
      // Guarded by _inflight so we don't spam.
      refresh();
      return null;
    }
    return hit;
  }

  String _keyOf(String home, String away) =>
      '${home.trim()}|${away.trim()}';

  /// All cached streams (any status). Caller should filter by `status == 1`
  /// for "currently live" entries. Returns a defensive copy.
  List<MatchStream> snapshot() => _normalized.map((e) => e.stream).toList();

  /// Streams whose upstream `status==1` (currently in-play).
  List<MatchStream> liveSnapshot() =>
      _normalized.where((e) => e.stream.status == 1).map((e) => e.stream).toList();

  /// Reverse lookup: given a stream (Chinese team names), find a match in
  /// `matches` whose English team names localize to the same Chinese pair.
  /// Falls back to fuzzy normalize() for suffix differences (队 / FC / 俱乐部).
  ///
  /// Returns null when no match in the candidate list joins to the stream
  /// (e.g. stream from a league we don't carry).
  ///
  /// Used by the home page to make 「正在直播」cards open the match detail
  /// page when a corresponding fixture exists in our system.
  MatchInfo? findMatchForStream(MatchStream s, List<MatchInfo> matches) {
    final hZh = s.homeTeam.trim();
    final aZh = s.awayTeam.trim();
    final hNorm = _normalize(hZh);
    final aNorm = _normalize(aZh);
    if (hNorm.isEmpty || aNorm.isEmpty) return null;
    for (final m in matches) {
      final mHomeZh = localizedTeam(m.home);
      final mAwayZh = localizedTeam(m.away);
      if (mHomeZh == hZh && mAwayZh == aZh) return m;
      if (_normalize(mHomeZh) == hNorm && _normalize(mAwayZh) == aNorm) {
        return m;
      }
    }
    return null;
  }
}

class _IndexedStream {
  final MatchStream stream;
  final String homeNorm;
  final String awayNorm;
  const _IndexedStream({
    required this.stream,
    required this.homeNorm,
    required this.awayNorm,
  });
}

/// Normalize a Chinese team name for fuzzy matching:
///   - lowercase
///   - strip whitespace
///   - drop common boilerplate suffixes that may or may not appear
///     ("队", "FC", "F.C.", "足球俱乐部", "俱乐部", "队伍")
///
/// Visible for testing.
final _whitespace = RegExp(r'\s+');

String _normalize(String s) {
  if (s.isEmpty) return s;
  var out = s.replaceAll(_whitespace, '').toLowerCase();
  // Iteratively peel suffixes. "FC队" / "队FC" both occur in the wild.
  const suffixes = ['足球俱乐部', '俱乐部', '队伍', '队', 'fc', 'f.c.'];
  bool changed = true;
  while (changed) {
    changed = false;
    for (final suf in suffixes) {
      if (out.length > suf.length && out.endsWith(suf)) {
        out = out.substring(0, out.length - suf.length);
        changed = true;
      }
    }
  }
  return out;
}

/// Visible-for-test export.
@visibleForTesting
String streamFeedNormalize(String s) => _normalize(s);

/// Parse the Unix-second expiry encoded in 7t666's `auth_key` query param.
///
/// Format: `auth_key=<expiresAt>-<arg2>-<arg3>-<md5sig>`
/// e.g.    `auth_key=1778157127-0-0-77968474409f6de3ac9f99b36ef757f8`
///
/// Returns null when the URL doesn't carry an auth_key or it's malformed —
/// in which case we treat the URL as "always valid" rather than guessing.
DateTime? streamUrlExpiresAt(String url) {
  if (url.isEmpty) return null;
  final uri = Uri.tryParse(url);
  if (uri == null) return null;
  final ak = uri.queryParameters['auth_key'];
  if (ak == null || ak.isEmpty) return null;
  final dash = ak.indexOf('-');
  if (dash <= 0) return null;
  final ts = int.tryParse(ak.substring(0, dash));
  if (ts == null) return null;
  return DateTime.fromMillisecondsSinceEpoch(ts * 1000);
}

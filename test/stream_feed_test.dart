// Tests for StreamFeed normalization + auth_key expiry parsing.
//
// We deliberately don't test the network code path (StreamFeed._fetch) here
// — it depends on the live ApiClient + Telegram auth flow. The interesting
// logic that *can* go wrong silently is the team-name matcher and the
// signed-URL expiry parser; both are pure functions, so we cover them.

import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_cup/services/stream_feed.dart';

void main() {
  group('streamFeedNormalize', () {
    test('strips trailing 队', () {
      expect(streamFeedNormalize('浙江队'), '浙江');
    });

    test('strips FC suffix', () {
      expect(streamFeedNormalize('Wuhan FC'), 'wuhan');
    });

    test('strips 足球俱乐部', () {
      expect(streamFeedNormalize('北京国安足球俱乐部'), '北京国安');
    });

    test('strips 俱乐部', () {
      expect(streamFeedNormalize('上海海港俱乐部'), '上海海港');
    });

    test('strips multiple suffixes iteratively (FC队)', () {
      expect(streamFeedNormalize('浙江FC队'), '浙江');
    });

    test('strips f.c. variant', () {
      expect(streamFeedNormalize('Real Madrid F.C.'), 'realmadrid');
    });

    test('lowercases and strips whitespace', () {
      expect(streamFeedNormalize('  Manchester United  '), 'manchesterunited');
    });

    test('preserves names without suffix', () {
      expect(streamFeedNormalize('武汉三镇'), '武汉三镇');
    });

    test('does not over-strip — single character names not eaten', () {
      // "队" alone shouldn't normalize to empty (suffix check requires
      // out.length > suf.length).
      expect(streamFeedNormalize('队'), '队');
    });

    test('empty input returns empty', () {
      expect(streamFeedNormalize(''), '');
    });
  });

  group('streamUrlExpiresAt', () {
    test('parses 7t666-style auth_key timestamp', () {
      // auth_key=<expiresAt>-<arg2>-<arg3>-<md5>
      const url =
          'https://example.com/foo.m3u8?auth_key=1778157127-0-0-abcdef&siteCode=2658';
      final t = streamUrlExpiresAt(url);
      expect(t, isNotNull);
      expect(t!.millisecondsSinceEpoch ~/ 1000, 1778157127);
    });

    test('returns null for URL without auth_key', () {
      expect(streamUrlExpiresAt('https://example.com/foo.m3u8'), isNull);
    });

    test('returns null for malformed auth_key', () {
      expect(
          streamUrlExpiresAt(
              'https://example.com/foo.m3u8?auth_key=notatimestamp'),
          isNull);
    });

    test('returns null for empty URL', () {
      expect(streamUrlExpiresAt(''), isNull);
    });

    test('returns null for non-http URL', () {
      // Uri.tryParse accepts most strings; we still need a valid auth_key.
      expect(streamUrlExpiresAt('garbage://x?auth_key=foo'), isNull);
    });

    test('handles auth_key that begins with dash gracefully', () {
      // dash at index 0 → no timestamp segment → null (not a crash)
      expect(
          streamUrlExpiresAt(
              'https://example.com/?auth_key=-1-0-0-abc'),
          isNull);
    });
  });
}

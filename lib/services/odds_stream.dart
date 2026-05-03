import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/match.dart';

/// Wraps a single WebSocket connection to /ws and exposes typed streams.
/// Auto-reconnects with exponential backoff (capped at 10s).
class OddsStream {
  OddsStream(this.url);
  final String url;

  WebSocketChannel? _channel;
  bool _closed = false;
  int _backoffMs = 500;
  final Set<int> _subscribed = {};

  final _oddsCtrl = StreamController<OddsSnapshot>.broadcast();
  final _matchesCtrl = StreamController<List<MatchInfo>>.broadcast();

  Stream<OddsSnapshot> get odds => _oddsCtrl.stream;
  Stream<List<MatchInfo>> get matches => _matchesCtrl.stream;

  void connect() {
    if (_closed) return;
    try {
      _channel = WebSocketChannel.connect(Uri.parse(url));
      _channel!.stream.listen(_onMessage, onError: _onError, onDone: _reconnect);
      _backoffMs = 500;
      // re-subscribe
      for (final id in _subscribed) {
        _send({'action': 'subscribe', 'matchId': id});
      }
    } catch (_) {
      _reconnect();
    }
  }

  void subscribe(int matchId) {
    if (_subscribed.add(matchId)) {
      _send({'action': 'subscribe', 'matchId': matchId});
    }
  }

  void unsubscribe(int matchId) {
    if (_subscribed.remove(matchId)) {
      _send({'action': 'unsubscribe', 'matchId': matchId});
    }
  }

  void _send(Map<String, dynamic> msg) {
    try {
      _channel?.sink.add(jsonEncode(msg));
    } catch (_) {}
  }

  void _onMessage(dynamic raw) {
    try {
      final m = jsonDecode(raw as String) as Map<String, dynamic>;
      switch (m['type']) {
        case 'odds':
          final payload = m['payload'] as Map<String, dynamic>;
          _oddsCtrl.add(OddsSnapshot.fromJson(payload));
          break;
        case 'matches':
          final list = (m['payload'] as List).cast<Map<String, dynamic>>();
          _matchesCtrl.add(list.map(MatchInfo.fromJson).toList());
          break;
      }
    } catch (_) {}
  }

  void _onError(Object err) {
    _reconnect();
  }

  void _reconnect() {
    if (_closed) return;
    _channel = null;
    final delay = _backoffMs;
    _backoffMs = (_backoffMs * 2).clamp(500, 10000);
    Timer(Duration(milliseconds: delay), connect);
  }

  Future<void> close() async {
    _closed = true;
    await _channel?.sink.close();
    await _oddsCtrl.close();
    await _matchesCtrl.close();
  }
}

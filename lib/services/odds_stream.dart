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
  int _backoffMs = 5000;
  String? _token;
  final Set<int> _subscribed = {};

  final _oddsCtrl = StreamController<OddsSnapshot>.broadcast();
  final _matchesCtrl = StreamController<List<MatchInfo>>.broadcast();
  final _connectedCtrl = StreamController<bool>.broadcast();
  bool _connected = false;

  Stream<OddsSnapshot> get odds => _oddsCtrl.stream;
  Stream<List<MatchInfo>> get matches => _matchesCtrl.stream;
  Stream<bool> get connected => _connectedCtrl.stream;
  bool get isConnected => _connected;

  /// Set/replace the auth token used for the `?token=` query param.
  /// Forces a reconnect with the new credential when it changes.
  void setToken(String? token) {
    if (_token == token) return;
    _token = token;
    // drop current connection so the next attempt uses the new token
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    if (token != null && token.isNotEmpty) connect();
  }

  void connect() {
    if (_closed) return;
    if (_token == null || _token!.isEmpty) return; // wait for login
    try {
      final u = Uri.parse(url);
      final authed = u.replace(queryParameters: {
        ...u.queryParameters,
        'token': _token!,
      });
      _channel = WebSocketChannel.connect(authed);
      _channel!.stream.listen(_onMessage, onError: _onError, onDone: _reconnect);
      _backoffMs = 5000;
      _setConnected(true);
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

  void _setConnected(bool v) {
    if (_connected == v) return;
    _connected = v;
    _connectedCtrl.add(v);
  }

  void _reconnect() {
    if (_closed) return;
    _setConnected(false);
    _channel = null;
    final delay = _backoffMs;
    _backoffMs = (_backoffMs * 2).clamp(5000, 30000);
    Timer(Duration(milliseconds: delay), connect);
  }

  Future<void> close() async {
    _closed = true;
    await _channel?.sink.close();
    await _oddsCtrl.close();
    await _matchesCtrl.close();
    await _connectedCtrl.close();
  }
}

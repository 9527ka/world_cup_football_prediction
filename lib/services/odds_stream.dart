import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/match.dart';

/// Wraps a single WebSocket connection to /ws and exposes typed streams.
/// Auto-reconnects with exponential backoff (capped at 10s).
///
/// Telegram Mini App WebView 在后台时会冻结 JS timer,导致 onDone 触发的
/// reconnect Timer 无法执行。通过监听 `visibilitychange` 事件,在页面恢复
/// 可见时立即检测并重连 WebSocket,解决"必须重启小程序才能刷新数据"的问题。
class OddsStream {
  OddsStream(this.url) {
    _installVisibilityListener();
  }
  final String url;

  WebSocketChannel? _channel;
  bool _closed = false;
  int _backoffMs = 5000;
  String? _token;
  final Set<int> _subscribed = {};
  bool _visibilityListenerInstalled = false;
  /// Track last message time to detect stale connections.
  DateTime _lastMessageAt = DateTime.now();

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
    // 重连(如果有 token 带上,没有则走无鉴权连接)
    connect();
  }

  void connect() {
    if (_closed) return;
    try {
      final u = Uri.parse(url);
      // 有 token 就带上(登录用户可收到个性化推送),没有也连(未登录用户仍需实时比分)
      final authed = (_token != null && _token!.isNotEmpty)
          ? u.replace(queryParameters: {...u.queryParameters, 'token': _token!})
          : u;
      _channel = WebSocketChannel.connect(authed);
      // WebSocketChannel.connect 在 Web 上是异步的:连接可能还未建立。
      // 等 ready future 成功后才标记 connected,失败则走重连。
      _channel!.ready.then((_) {
        if (_closed) return;
        _backoffMs = 5000;
        _setConnected(true);
        for (final id in _subscribed) {
          _send({'action': 'subscribe', 'matchId': id});
        }
      }).catchError((_) {
        _reconnect();
      });
      _channel!.stream.listen(_onMessage, onError: _onError, onDone: _reconnect);
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
    _lastMessageAt = DateTime.now();
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

  /// 监听浏览器 visibilitychange 事件。Telegram Mini App WebView 从后台恢复时
  /// JS timer 可能未执行(onDone 回调注册的 reconnect Timer 被冻结),这里强制检测
  /// 并立即重连,确保比分/赔率实时推送不中断。
  void _installVisibilityListener() {
    if (!kIsWeb || _visibilityListenerInstalled) return;
    _visibilityListenerInstalled = true;
    try {
      final doc = globalContext.getProperty('document'.toJS) as JSObject?;
      if (doc == null) return;
      doc.callMethod(
        'addEventListener'.toJS,
        'visibilitychange'.toJS,
        ((JSAny? _) {
          _onVisibilityChange();
        }).toJS,
      );
    } catch (_) {}
  }

  void _onVisibilityChange() {
    if (_closed) return;
    try {
      final doc = globalContext.getProperty('document'.toJS) as JSObject?;
      final state =
          (doc?.getProperty('visibilityState'.toJS) as JSString?)?.toDart;
      if (state != 'visible') return;

      // 页面恢复可见:如果已不在连接状态,或者超过 20s 没收到消息(服务端 30s ping),
      // 立即关闭旧连接并重连。
      final stale =
          DateTime.now().difference(_lastMessageAt).inSeconds > 20;
      if (!_connected || _channel == null || stale) {
        try {
          _channel?.sink.close();
        } catch (_) {}
        _channel = null;
        _setConnected(false);
        _backoffMs = 5000; // reset backoff for fast reconnect
        connect();
      }
    } catch (_) {}
  }

  Future<void> close() async {
    _closed = true;
    await _channel?.sink.close();
    await _oddsCtrl.close();
    await _matchesCtrl.close();
    await _connectedCtrl.close();
  }
}

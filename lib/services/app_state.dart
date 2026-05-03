import 'package:flutter/foundation.dart';

import '../models/match.dart';
import 'api_client.dart';
import 'bet_slip.dart';
import 'odds_stream.dart';
import 'telegram.dart';

/// Lightweight app-wide state holder. Uses ChangeNotifier so any widget
/// can listen via AnimatedBuilder / context.
class AppState extends ChangeNotifier {
  AppState({required this.api, required this.stream}) : betSlip = BetSlip();

  final ApiClient api;
  final OddsStream stream;
  final BetSlip betSlip;

  List<MatchInfo> matches = [];
  bool loadingMatches = false;
  String? error;

  bool get isAuthenticated => api.token != null;
  Map<String, dynamic>? get user => api.user;

  Future<void> initialize() async {
    await api.loadFromStorage();
    api.onTokenExpired = _refreshToken;
    stream.connect();
    stream.matches.listen((m) {
      matches = m;
      notifyListeners();
    });
    if (api.token == null) {
      await tryTelegramLogin();
    }
    await refreshMatches();
  }

  Future<void> _refreshToken() async {
    final initData = Telegram.initData();
    if (initData.isEmpty) return;
    try {
      await api.loginTelegram(initData);
    } catch (_) {}
  }

  Future<void> tryTelegramLogin() async {
    final initData = Telegram.initData();
    if (initData.isEmpty) {
      // dev mode — backend may accept empty initData if SKIP_TELEGRAM_AUTH=true
    }
    try {
      await api.loginTelegram(initData);
      error = null;
    } catch (e) {
      error = 'login: $e';
    }
    notifyListeners();
  }

  Future<void> refreshMatches() async {
    loadingMatches = true;
    notifyListeners();
    try {
      final page = await api.listMatches(limit: 100);
      matches = page.matches;
      error = null;
    } catch (e) {
      error = 'matches: $e';
    } finally {
      loadingMatches = false;
      notifyListeners();
    }
  }
}

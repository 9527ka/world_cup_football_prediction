import 'dart:async';

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

  // 客服 Telegram 用户名(不带 @)。后台 /admin/settings 可配置;首次加载前用默认值。
  String customerServiceTG = 'go_home_007';

  bool get isAuthenticated => api.token != null;
  Map<String, dynamic>? get user => api.user;

  /// 浏览器登录成功后调一下,让监听 AppState 的 widget 重建(钱包 / 头像
  /// 出现等)。包外不能直接调 notifyListeners(protected)。
  void notifyAuthChanged() => notifyListeners();

  Future<void> initialize() async {
    await api.loadFromStorage();
    api.onTokenExpired = _refreshToken;
    stream.matches.listen((m) {
      matches = m;
      notifyListeners();
    });
    if (api.token == null) {
      await tryTelegramLogin();
    }
    // /ws now requires JWT (token query param). Connect only after we have one.
    stream.setToken(api.token);
    await refreshMatches();
    // 拉一次 home/config(客服账号/周奖池)。失败保留默认值,不影响登录主流程。
    unawaited(_refreshHomeConfig());
  }

  Future<void> _refreshHomeConfig() async {
    try {
      final cfg = await api.homeConfig();
      customerServiceTG = cfg.customerService;
      notifyListeners();
    } catch (_) {/* 默认值兜底 */}
  }

  Future<void> _refreshToken() async {
    final initData = Telegram.initData();
    if (initData.isEmpty) return;
    try {
      await api.loginTelegram(initData, startParam: Telegram.startParam());
      stream.setToken(api.token);
    } catch (_) {}
  }

  Future<void> tryTelegramLogin() async {
    final initData = Telegram.initData();
    // 浏览器环境(非 Mini App):initData 空,**不尝试**调后端;让用户通过
    // LoginWall(/widgets/login_wall.dart)显式选 Telegram 登录。不报错防止
    // 首屏出现"登录失败"误导。Mini App 内永远有 initData,正常走登录链路。
    if (initData.isEmpty) {
      notifyListeners();
      return;
    }
    try {
      await api.loginTelegram(initData, startParam: Telegram.startParam());
      stream.setToken(api.token);
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

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

  /// 在 Telegram Mini App 内、但拿不到有效 initData 且自动 reload 后仍失败时置 true。
  /// UI 据此显示「登录信息获取失败,请彻底关闭后从机器人菜单重新打开 + 重试」而不是
  /// 默默退化成浏览器的「登录/注册」按钮(后者在 Mini App 里点了也没用)。
  bool tgAuthStuck = false;

  // 客服 Telegram 用户名(不带 @)。后台 /admin/settings 可配置;首次加载前用默认值。
  String customerServiceTG = ''; // 后台未配置时为空 → 前端禁用客服入口,不再跳无关账号
  // 分语言客服账号(key: zh/en/ko/ja)。后台分语言配置;前端按界面语言匹配。
  Map<String, String> customerServiceByLang = {};

  /// 按界面语言取客服账号:中/英/韩/日各自配置,其余语言回退英文,
  /// 仍为空则回退旧单一客服(customerServiceTG)。返回纯用户名(不带 @)。
  String customerServiceFor(String locale) {
    final key =
        (locale == 'zh' || locale == 'ko' || locale == 'ja') ? locale : 'en';
    final v = customerServiceByLang[key];
    if (v != null && v.trim().isNotEmpty) return v.trim();
    return customerServiceTG;
  }

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
    // Mini App: always re-authenticate with fresh initData to renew JWT,
    // even if we have a stored token. Telegram provides fresh initData on
    // each WebView creation; stale stored tokens cause needless 401 round-trips
    // and confuse users with "session expired" banners.
    // Browser: only attempt if no stored token (manual login via LoginWall).
    final initData = Telegram.liveInitData();
    if (initData.isNotEmpty) {
      await tryTelegramLogin();
    } else if (Telegram.inTelegramWebApp()) {
      // 在真正的 Mini App 里却没有 initData(打开方式/客户端导致延迟或缺失)。
      // 先自动 reload 一次拿新 initData(自愈);仍拿不到再标记 stuck 给明确提示。
      // markAuthReload() 必须成功持久化计数才 reload —— 否则(storage 不可用)会无限刷新。
      if (Telegram.authReloadAttempts() < 1 && Telegram.markAuthReload()) {
        Telegram.reloadApp();
        return;
      }
      tgAuthStuck = true;
      notifyListeners();
    } else if (api.token == null) {
      notifyListeners();
    }
    // WS 不再强制要求 token:未登录用户也能收到全局比分/赔率推送。
    // 有 token 就带上(后端可选鉴权),没有也连。
    stream.setToken(api.token);
    // 如果 setToken(null) 被 _token==null 短路(首次两者都是 null),
    // 手动触发一次 connect 确保匿名连接建立。
    if (!stream.isConnected) stream.connect();
    await refreshMatches();
    // 拉一次 home/config(客服账号/周奖池)。失败保留默认值,不影响登录主流程。
    unawaited(_refreshHomeConfig());
  }

  Future<void> _refreshHomeConfig() async {
    try {
      final cfg = await api.homeConfig();
      customerServiceTG = cfg.customerService;
      customerServiceByLang = cfg.customerServices;
      notifyListeners();
    } catch (_) {/* 默认值兜底 */}
  }

  Future<void> _refreshToken() async {
    final initData = Telegram.liveInitData();
    if (initData.isEmpty) throw Exception('session expired');
    await api.loginTelegram(initData, startParam: Telegram.startParam());
    stream.setToken(api.token);
  }

  Future<void> tryTelegramLogin() async {
    final initData = Telegram.liveInitData();
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
      tgAuthStuck = false;
      Telegram.clearAuthReload(); // 成功 → 重置自愈计数
    } catch (e) {
      // Mini App 内 initData 被后端拒(多为 401:旧会话/过期/失效 initData)。
      // 重发同一份永远会被拒 —— 必须 reload 拿新签名。自动 reload 一次(自愈),
      // 仍失败再标记 stuck 给明确提示。非 Mini App / 非鉴权错误维持原 error 行为。
      final isAuthReject = e is ApiException && e.statusCode == 401;
      if (Telegram.inTelegramWebApp() && isAuthReject) {
        if (Telegram.authReloadAttempts() < 1 && Telegram.markAuthReload()) {
          Telegram.reloadApp();
          return;
        }
        tgAuthStuck = true;
      } else {
        error = 'login: $e';
      }
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

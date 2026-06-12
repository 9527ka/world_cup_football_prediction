import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/match.dart';
import 'i18n.dart';

const _httpTimeout = Duration(seconds: 15);

/// 生成一个 32 字符 hex 的幂等 key(等同 UUID v4 但去掉分隔符)。
/// 安全性来自 Random.secure(),冲突概率 1/2^128 ≈ 0。后端只要 16~128 字符。
String _generateIdempotencyKey() {
  final rnd = Random.secure();
  final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

typedef TokenRefresher = Future<void> Function();

class ApiClient {
  ApiClient(this.baseUrl);
  final String baseUrl;
  String? _token;
  Map<String, dynamic>? _user;
  TokenRefresher? onTokenExpired;

  static const _tokenKey = 'auth.token';
  static const _userKey = 'auth.user';

  String? get token => _token;
  Map<String, dynamic>? get user => _user;

  /// 外部(浏览器 OAuth 回跳后)直接注入 token。必须 await 完成 — 否则后续
  /// loadFromStorage() 会用 SharedPreferences 旧值覆盖 in-memory token。
  Future<void> setTokenFromExternal(String token) async {
    _token = token;
    await _persist();
  }

  Future<void> setUserFromExternal(Map<String, dynamic> user) async {
    _user = user;
    await _persist();
  }

  /// 当前登录用户信息(走 /api/me)。需要已带 token,否则 401。
  Future<Map<String, dynamic>> getMe() async {
    final r = await _authGet(_uri('/api/me'));
    _check(r);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<void> loadFromStorage() async {
    final p = await SharedPreferences.getInstance();
    _token = p.getString(_tokenKey);
    final u = p.getString(_userKey);
    if (u != null) _user = jsonDecode(u) as Map<String, dynamic>;
  }

  Future<void> _persist() async {
    final p = await SharedPreferences.getInstance();
    if (_token == null) {
      await p.remove(_tokenKey);
    } else {
      await p.setString(_tokenKey, _token!);
    }
    if (_user == null) {
      await p.remove(_userKey);
    } else {
      await p.setString(_userKey, jsonEncode(_user));
    }
  }

  Map<String, String> _headers({bool auth = false}) {
    final h = <String, String>{'Content-Type': 'application/json'};
    if (auth && _token != null) h['Authorization'] = 'Bearer $_token';
    return h;
  }

  Uri _uri(String path, [Map<String, String>? q]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: q);

  /// 把 `/uploads/xxx.png` 这类相对路径解析成可直接喂给 Image.network 的绝对 URL。
  /// 独立 API 域(baseUrl 非空)用 baseUrl;同源部署(baseUrl 空)用当前页面 origin。
  /// 已是 http(s) 绝对地址则原样返回。
  String mediaUrl(String path) {
    if (path.isEmpty) return '';
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    if (baseUrl.isNotEmpty) return '$baseUrl$path';
    return Uri.base.resolve(path).toString();
  }

  Completer<void>? _refreshCompleter;

  Future<void> _ensureTokenRefreshed() async {
    if (_refreshCompleter != null) {
      await _refreshCompleter!.future;
      return;
    }
    _refreshCompleter = Completer<void>();
    try {
      await onTokenExpired!();
      _refreshCompleter!.complete();
    } catch (e) {
      _refreshCompleter!.completeError(e);
    } finally {
      _refreshCompleter = null;
    }
  }

  // ── Timeout wrappers — all public HTTP calls must go through these ──
  Future<http.Response> _get(Uri uri, {Map<String, String>? headers}) =>
      http.get(uri, headers: headers).timeout(_httpTimeout);
  Future<http.Response> _post(Uri uri, {Map<String, String>? headers, Object? body}) =>
      http.post(uri, headers: headers, body: body).timeout(_httpTimeout);

  Future<http.Response> _authGet(Uri uri) async {
    var r = await http.get(uri, headers: _headers(auth: true)).timeout(_httpTimeout);
    if (r.statusCode == 401 && onTokenExpired != null) {
      await _ensureTokenRefreshed();
      r = await http.get(uri, headers: _headers(auth: true)).timeout(_httpTimeout);
    }
    return r;
  }

  Future<http.Response> _authPost(Uri uri, {Object? body, Map<String, String>? extraHeaders}) async {
    final h = _headers(auth: true);
    if (extraHeaders != null) h.addAll(extraHeaders);
    var r = await http.post(uri, headers: h, body: body).timeout(_httpTimeout);
    if (r.statusCode == 401 && onTokenExpired != null) {
      await _ensureTokenRefreshed();
      final h2 = _headers(auth: true);
      if (extraHeaders != null) h2.addAll(extraHeaders);
      r = await http.post(uri, headers: h2, body: body).timeout(_httpTimeout);
    }
    return r;
  }

  Future<http.Response> _authDelete(Uri uri) async {
    var r = await http.delete(uri, headers: _headers(auth: true)).timeout(_httpTimeout);
    if (r.statusCode == 401 && onTokenExpired != null) {
      await _ensureTokenRefreshed();
      r = await http.delete(uri, headers: _headers(auth: true)).timeout(_httpTimeout);
    }
    return r;
  }

  Future<Map<String, dynamic>> loginTelegram(String initData, {String startParam = ''}) async {
    final r = await _post(
      _uri('/api/auth/telegram'),
      headers: _headers(),
      body: jsonEncode({
        'initData': initData,
        if (startParam.isNotEmpty) 'startParam': startParam,
      }),
    );
    _check(r);
    final body = jsonDecode(r.body) as Map<String, dynamic>;
    _token = body['token'] as String?;
    _user = body['user'] as Map<String, dynamic>?;
    await _persist();
    return body;
  }

  /// 浏览器登录入口:Telegram Login Widget 的 callback 把整个 user 对象转发到
  /// 后端验签。`payload` 字段对应 widget 的 user 参数(`id`/`first_name`/
  /// `last_name`/`username`/`photo_url`/`auth_date`/`hash`)。`startParam` 可选,
  /// 跟 Mini App 路径一样用来绑定邀请人。
  Future<Map<String, dynamic>> loginTelegramWeb(Map<String, dynamic> payload, {String startParam = ''}) async {
    final body = Map<String, dynamic>.from(payload);
    if (startParam.isNotEmpty) body['startParam'] = startParam;
    final r = await _post(
      _uri('/api/auth/telegram-web'),
      headers: _headers(),
      body: jsonEncode(body),
    );
    _check(r);
    final out = jsonDecode(r.body) as Map<String, dynamic>;
    _token = out['token'] as String?;
    _user = out['user'] as Map<String, dynamic>?;
    await _persist();
    return out;
  }

  /// 邮箱注册:email + password + displayName,不发验证邮件。成功后跟 TG 登录走同一套
  /// token / user 写入流程。后端 409 (email_taken) / 400 (invalid_*) 都丢给上层显示。
  Future<Map<String, dynamic>> registerEmail({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final r = await _post(
      _uri('/api/auth/register'),
      headers: _headers(),
      body: jsonEncode({
        'email': email,
        'password': password,
        'displayName': displayName,
      }),
    );
    _check(r);
    final body = jsonDecode(r.body) as Map<String, dynamic>;
    _token = body['token'] as String?;
    _user = body['user'] as Map<String, dynamic>?;
    await _persist();
    return body;
  }

  /// 修改自己密码:旧密码必须对。后端 401 = 旧密码错,403 = 没设过密码(纯 TG 账号),
  /// 400 = 新密码格式不符。错误丢给上层 toast 展示。
  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    final r = await _authPost(
      _uri('/api/me/password'),
      body: jsonEncode({'oldPassword': oldPassword, 'newPassword': newPassword}),
    );
    _check(r);
  }

  /// 邮箱登录:错误统一回 "invalid_credentials" (不暴露是邮箱不存在还是密码错)。
  Future<Map<String, dynamic>> loginEmail({
    required String email,
    required String password,
  }) async {
    final r = await _post(
      _uri('/api/auth/login'),
      headers: _headers(),
      body: jsonEncode({'email': email, 'password': password}),
    );
    _check(r);
    final body = jsonDecode(r.body) as Map<String, dynamic>;
    _token = body['token'] as String?;
    _user = body['user'] as Map<String, dynamic>?;
    await _persist();
    return body;
  }

  /// 拿 bot 元信息(username + 数字 id)。
  /// - botUsername:嵌 Telegram Login Widget script 时用。
  /// - botId:直接打开 oauth.telegram.org/auth?bot_id=... 时用(popup 流程)。
  ///
  /// 后端通过 env `TELEGRAM_BOT_USERNAME` 提供 username;botId 从 token 前缀解析。
  /// 失败 / 空值时调用方应禁用浏览器登录按钮 + 提示 BotFather 域名未配置。
  Future<AuthBotConfig> authConfig() async {
    final r = await _get(_uri('/api/auth/config'), headers: _headers());
    _check(r);
    final body = jsonDecode(r.body) as Map<String, dynamic>;
    return AuthBotConfig(
      botUsername: (body['botUsername'] as String?) ?? '',
      botId: (body['botId'] as num?)?.toInt() ?? 0,
      loginOrigin: ((body['loginOrigin'] as String?) ?? '').trim(),
      geoLang: ((body['geoLang'] as String?) ?? '').trim(),
    );
  }

  Future<void> logout() async {
    _token = null;
    _user = null;
    await _persist();
  }

  Future<MatchPage> listMatches({
    String? league,
    String? search,
    String? status,
    int offset = 0,
    int limit = 20,
  }) async {
    final q = <String, String>{
      'offset': '$offset',
      'limit': '$limit',
    };
    if (league != null && league.isNotEmpty) q['league'] = league;
    if (search != null && search.isNotEmpty) q['q'] = search;
    if (status != null && status.isNotEmpty) q['status'] = status;
    final r = await _get(_uri('/api/matches', q));
    _check(r);
    final body = jsonDecode(r.body) as Map<String, dynamic>;
    final list = (body['matches'] as List?) ?? [];
    return MatchPage(
      matches: list.cast<Map<String, dynamic>>().map(MatchInfo.fromJson).toList(),
      total: (body['total'] ?? 0) as int,
      offset: (body['offset'] ?? 0) as int,
      limit: (body['limit'] ?? 20) as int,
    );
  }

  /// Returns the FULL configured league list (slug + name + matchCount).
  /// Includes off-season leagues with 0 matches so the chip filter can show
  /// them with a "暂无比赛" hint.
  Future<List<LeagueInfo>> configLeagues() async {
    final r = await _get(_uri('/api/config/leagues'));
    _check(r);
    final body = jsonDecode(r.body) as Map<String, dynamic>;
    final list = (body['leagues'] as List?) ?? [];
    return list
        .cast<Map<String, dynamic>>()
        .map((j) => LeagueInfo(
              slug: j['slug'] as String? ?? '',
              name: j['name'] as String? ?? '',
              matchCount: (j['matchCount'] as num?)?.toInt() ?? 0,
            ))
        .toList();
  }

  Future<MatchInfo> getMatch(int id) async {
    final r = await _get(_uri('/api/match/$id'));
    _check(r);
    return MatchInfo.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
  }

  Future<OddsSnapshot> getOdds(int id) async {
    final r = await _get(_uri('/api/odds/$id'));
    _check(r);
    return OddsSnapshot.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
  }

  Future<OddsHistory> getOddsHistory(int id, {int limit = 60}) async {
    final r = await _get(_uri('/api/odds/$id/history', {'limit': '$limit'}));
    _check(r);
    return OddsHistory.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
  }

  /// Per-fixture statistics from API-Football: corners / yellow / red /
  /// shots split by home/away. Only available when FETCHER_PROVIDER=apifootball.
  /// Returns ({}, {}) when the provider doesn't support it.
  Future<({Map<String, int> home, Map<String, int> away})> getMatchStats(
      int id) async {
    final r = await _get(_uri('/api/match/$id/stats'));
    if (r.statusCode == 503) {
      return (home: <String, int>{}, away: <String, int>{});
    }
    _check(r);
    final m = jsonDecode(r.body) as Map<String, dynamic>;
    Map<String, int> mp(dynamic v) =>
        (v as Map?)?.map((k, vv) => MapEntry('$k', (vv as num).toInt())) ??
        <String, int>{};
    return (home: mp(m['home']), away: mp(m['away']));
  }

  /// Per-fixture event timeline: goals, cards, subs with elapsed minute.
  /// Powers the "进球时间 / 判罚时间" sections in match detail.
  Future<List<MatchEvent>> getMatchEvents(int id) async {
    final r = await _get(_uri('/api/match/$id/events'));
    if (r.statusCode == 503) return [];
    _check(r);
    final m = jsonDecode(r.body) as Map<String, dynamic>;
    final list = (m['events'] as List?) ?? [];
    return list
        .cast<Map<String, dynamic>>()
        .map(MatchEvent.fromJson)
        .toList();
  }

  /// Authed: fetch the live stream feed snapshot. Returns ([], "") when the
  /// user is not logged in (401 short-circuit) so the caller doesn't have to
  /// branch on auth state.
  Future<({List<Map<String, dynamic>> streams, String fetchedAt})>
      listStreams() async {
    if (_token == null) {
      return (streams: <Map<String, dynamic>>[], fetchedAt: '');
    }
    final r = await _authGet(_uri('/api/streams'));
    if (r.statusCode == 401) {
      return (streams: <Map<String, dynamic>>[], fetchedAt: '');
    }
    _check(r);
    final m = jsonDecode(r.body) as Map<String, dynamic>;
    final list = ((m['streams'] as List?) ?? const [])
        .cast<Map<String, dynamic>>();
    return (streams: list, fetchedAt: '${m['fetchedAt'] ?? ''}');
  }

  /// 主动撤单 — 退本金,prediction 标记 cancelled。
  /// 距开赛 < 5 分钟会被后端拒绝。返回退还的金额。
  Future<({double refundedAmount, Prediction prediction})> cancelPrediction(int id) async {
    final r = await _authDelete(_uri('/api/predictions/$id'));
    _check(r);
    final m = jsonDecode(r.body) as Map<String, dynamic>;
    return (
      refundedAmount: ((m['refundedAmount'] ?? 0) as num).toDouble(),
      prediction: Prediction.fromJson(m['prediction'] as Map<String, dynamic>),
    );
  }

  Future<List<Prediction>> myPredictions() async {
    final r = await _authGet(_uri('/api/predictions'));
    _check(r);
    final list = jsonDecode(r.body) as List;
    return list.cast<Map<String, dynamic>>().map(Prediction.fromJson).toList();
  }

  Future<Prediction> placePrediction({
    required int matchId,
    required String score,
    double stake = 100,
    String marketType = MarketType.correctScore,
  }) async {
    final r = await _authPost(
      _uri('/api/predict'),
      body: jsonEncode({
        'matchId': matchId,
        'marketType': marketType,
        'score': score,
        'stake': stake,
      }),
      extraHeaders: {'Idempotency-Key': _generateIdempotencyKey()},
    );
    _check(r);
    return Prediction.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
  }

  Future<List<LeaderboardEntry>> leaderboard({
    int limit = 50,
    String period = 'all',
  }) async {
    final q = {'limit': '$limit', 'period': period};
    final r = await _get(_uri('/api/leaderboard', q));
    _check(r);
    final list = jsonDecode(r.body) as List;
    return list.cast<Map<String, dynamic>>().map(LeaderboardEntry.fromJson).toList();
  }

  // ----- new endpoints used by the redesigned UI -----

  Future<UserStats> getStats() async {
    final r = await _authGet(_uri('/api/me/stats'));
    _check(r);
    return UserStats.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
  }

  Future<VipStatus> getVip() async {
    final r = await _authGet(_uri('/api/me/vip'));
    _check(r);
    return VipStatus.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
  }

  /// Per-user invite code + invitation aggregate stats. Backend always
  /// returns these three keys (numbers default to 0 for new users).
  Future<({String inviteCode, int invitedCount, double totalCommission})>
      getReferrals() async {
    final r = await _authGet(_uri('/api/me/referrals'));
    _check(r);
    final body = jsonDecode(r.body) as Map<String, dynamic>;
    return (
      inviteCode: (body['inviteCode'] as String?) ?? '',
      invitedCount: (body['invitedCount'] as num?)?.toInt() ?? 0,
      totalCommission: (body['totalCommission'] as num?)?.toDouble() ?? 0,
    );
  }

  Future<LedgerResult> getLedger({String type = 'all', int limit = 50, String? before}) async {
    final q = <String, String>{'type': type, 'limit': '$limit'};
    if (before != null && before.isNotEmpty) q['before'] = before;
    final r = await _authGet(_uri('/api/me/ledger', q));
    _check(r);
    final body = jsonDecode(r.body) as Map<String, dynamic>;
    final items = (body['items'] as List)
        .cast<Map<String, dynamic>>()
        .map(LedgerEntry.fromJson)
        .toList();
    return LedgerResult(items: items, nextCursor: body['nextCursor'] as String? ?? '');
  }

  Future<List<BetRow>> myBets({String? status}) async {
    final q = <String, String>{};
    if (status != null && status.isNotEmpty) q['status'] = status;
    final r = await _authGet(
      _uri('/api/me/bets', q.isEmpty ? null : q),
    );
    _check(r);
    final list = jsonDecode(r.body) as List;
    return list.cast<Map<String, dynamic>>().map(BetRow.fromJson).toList();
  }

  Future<MyRank> myRank({String period = 'week'}) async {
    final r = await _authGet(
      _uri('/api/me/rank', {'period': period}),
    );
    _check(r);
    return MyRank.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
  }

  /// Public team-name / logo overrides edited from the admin console.
  /// Returns map keyed by upstream English team name → {nameZh, nameEn, logoUrl}.
  Future<Map<String, Map<String, String>>> teamOverrides() async {
    final r = await _get(_uri('/api/team-overrides'));
    _check(r);
    final m = jsonDecode(r.body) as Map<String, dynamic>;
    final raw = (m['teams'] as Map?) ?? const {};
    final out = <String, Map<String, String>>{};
    raw.forEach((k, v) {
      if (v is Map) {
        out[k as String] = {
          'nameZh': (v['nameZh'] ?? '').toString(),
          'nameEn': (v['nameEn'] ?? '').toString(),
          'logoUrl': (v['logoUrl'] ?? '').toString(),
        };
      }
    });
    return out;
  }

  Future<List<String>> announcements() async {
    final r = await _get(_uri('/api/home/announcements'));
    _check(r);
    final m = jsonDecode(r.body) as Map<String, dynamic>;
    return ((m['items'] ?? []) as List).cast<String>();
  }

  Future<List<HotMatch>> hotMatches({int limit = 4}) async {
    final r = await _get(_uri('/api/home/hot-matches', {'limit': '$limit'}));
    _check(r);
    final list = jsonDecode(r.body) as List;
    return list.cast<Map<String, dynamic>>().map(HotMatch.fromJson).toList();
  }

  /// 首页"最近赛果"区块 — 已结束比赛(默认 3 天 / 10 条),含终场比分。
  Future<List<MatchInfo>> recentSettled({int days = 3, int limit = 10}) async {
    final r = await _get(_uri('/api/home/recent-settled', {
      'days': '$days',
      'limit': '$limit',
    }));
    _check(r);
    final list = jsonDecode(r.body) as List;
    return list.cast<Map<String, dynamic>>().map(MatchInfo.fromJson).toList();
  }

  Future<HomeConfig> homeConfig() async {
    final r = await _get(_uri('/api/home/config'));
    _check(r);
    return HomeConfig.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
  }

  // ----- wallet / deposits / withdrawals -----

  Future<Wallet> getWallet() async {
    final r = await _authGet(_uri('/api/me/wallet'));
    _check(r);
    return Wallet.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
  }

  Future<Deposit> submitDeposit({
    required double amount,
    required String txHash,
    String proofUrl = '',
    String chain = 'trc20',
    String currency = 'USDT',
  }) async {
    final r = await _authPost(
      _uri('/api/deposits'),
      body: jsonEncode({'amount': amount, 'txHash': txHash, 'proofUrl': proofUrl, 'chain': chain, 'currency': currency}),
    );
    _check(r);
    return Deposit.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
  }

  Future<Withdrawal> submitWithdrawal({
    required double amount,
    required String address,
    String chain = 'trc20',
    String currency = 'USDT',
  }) async {
    final r = await _authPost(
      _uri('/api/withdrawals'),
      body: jsonEncode({'amount': amount, 'address': address, 'chain': chain, 'currency': currency}),
    );
    _check(r);
    return Withdrawal.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
  }

  /// 自助兑换:把 ETH/BTC 余额按实时汇率换成 USDT。返回最新钱包(含三币余额)。
  Future<Wallet> convertBalance({required String from, required double amount}) async {
    final r = await _authPost(
      _uri('/api/me/convert'),
      body: jsonEncode({'from': from, 'amount': amount}),
    );
    _check(r);
    // 后端返回 {rate, usdtAmount, balance, balanceEth, balanceBtc};复用 Wallet.fromJson
    // 取三币余额(其余字段缺省,调用方拿到后通常会重新 getWallet 刷新地址/费率)。
    return Wallet.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
  }

  /// 提交串关。
  ///
  /// [idempotencyKey] 可选 —— 同一逻辑意图(用户一次"投注"动作)若需要重试,
  /// 传相同 key 后端会去重(返回首次创建的 parlay,不会重复扣 stake)。
  /// 调用方应跨 retry 保留 key,成功后再丢弃。caller 不传时由本方法生成一次性
  /// key(只能防 HTTP 层 401 重发,不防 caller 自己再调一次)。
  Future<Parlay> submitParlay({
    required double stake,
    required List<Map<String, dynamic>> legs,
    String? idempotencyKey,
  }) async {
    final key = idempotencyKey ?? _generateIdempotencyKey();
    final r = await _authPost(
      _uri('/api/parlays'),
      body: jsonEncode({'stake': stake, 'legs': legs}),
      extraHeaders: {'Idempotency-Key': key},
    );
    _check(r);
    return Parlay.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
  }

  Future<List<Parlay>> myParlays() async {
    final r = await _authGet(_uri('/api/me/parlays'));
    _check(r);
    final list = jsonDecode(r.body) as List;
    return list.cast<Map<String, dynamic>>().map(Parlay.fromJson).toList();
  }

  Future<List<Deposit>> myDeposits() async {
    final r = await _authGet(_uri('/api/me/deposits'));
    _check(r);
    final list = jsonDecode(r.body) as List;
    return list.cast<Map<String, dynamic>>().map(Deposit.fromJson).toList();
  }

  Future<List<Withdrawal>> myWithdrawals() async {
    final r = await _authGet(_uri('/api/me/withdrawals'));
    _check(r);
    final list = jsonDecode(r.body) as List;
    return list.cast<Map<String, dynamic>>().map(Withdrawal.fromJson).toList();
  }

  /// Uploads a single image file (proof of transfer) and returns a public URL.
  Future<String> uploadProof(List<int> bytes, {required String filename}) async {
    final req = http.MultipartRequest('POST', _uri('/api/uploads'));
    if (_token != null) req.headers['Authorization'] = 'Bearer $_token';
    req.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    final streamed = await req.send();
    final r = await http.Response.fromStream(streamed);
    _check(r);
    return (jsonDecode(r.body) as Map<String, dynamic>)['url'] as String;
  }

  // Admin functionality lives in a separate server-rendered console
  // (see ./backend/internal/adminweb). The user-facing app no longer carries
  // any admin endpoints.

  void _check(http.Response r) {
    if (r.statusCode >= 200 && r.statusCode < 300) return;
    String msg;
    Map<String, dynamic>? data;
    try {
      final m = jsonDecode(r.body) as Map<String, dynamic>;
      msg = m['error']?.toString() ?? r.body;
      data = m;
    } catch (_) {
      msg = r.body;
    }
    throw ApiException(r.statusCode, msg, data);
  }
}

/// 把后端英文 error key 翻译成给用户看的当前语言文案。匹配优先级:
/// 1. 完全匹配  2. 前缀匹配(用于 "match X not bettable" 这种带变量的)。
/// 翻译表在 i18n.dart 的 err.* key 下,locale 切换自动跟随。
String _zhError(String raw) {
  const exact = <String, String>{
    // 下注 / 串关
    'insufficient balance': 'err.insufficient_balance',
    'matchId and score are required': 'err.match_and_score_required',
    'matchId and score are required for every leg': 'err.match_and_score_required_leg',
    'unknown marketType': 'err.unknown_market',
    'unknown marketType in leg': 'err.unknown_market_leg',
    'same match cannot appear twice in a parlay': 'err.same_match_twice',
    'match not found': 'err.match_not_found',
    'match already started or settled': 'err.match_started_or_settled',
    'match already settled': 'err.match_already_settled',
    'match voided': 'err.match_voided',
    'match in extra time': 'err.match_extra_time',
    'match in extra time, wait for settlement': 'err.match_extra_time',
    'handicap closed during live': 'err.handicap_live_closed',
    'no odds offered for this match': 'err.no_odds_for_match',
    'odds not available': 'err.odds_unavailable',
    'current odds unavailable': 'err.current_odds_unavailable',
    'selection not offered': 'err.selection_not_offered',
    'score not offered': 'err.score_not_offered',
    'duplicate prediction': 'err.duplicate_prediction',
    'duplicate parlay request in progress': 'err.duplicate_parlay',
    'too close to kickoff': 'err.too_close_to_kickoff',
    'market temporarily locked (goal scored)': 'err.market_locked_goal',
    'market not open yet (awaiting bookmaker odds)': 'err.market_not_open',
    'low odds single bet limit exceeded': 'err.low_odds_limit',
    'quarter-line AH not allowed in parlay leg': 'err.quarter_line_in_parlay',
    'all legs settled — wait for payout': 'err.parlay_all_legs_settled',
    'market line shifted, cashout temporarily unavailable; will settle automatically on match end':
        'err.market_line_shifted',
    'parlay has lost leg': 'err.parlay_has_lost_leg',
    'parlay not found': 'err.parlay_not_found',
    'parlay already settled': 'err.parlay_already_settled',
    'prediction not found': 'err.prediction_not_found',
    'prediction already settled': 'err.prediction_already_settled',
    'prediction not pending': 'err.prediction_not_pending',
    'invalid match id': 'err.invalid_match_id',
    // 串关参数 / 范围
    'parlay needs at least 2 legs': 'err.parlay_min_legs',
    'parlay limited to 8 legs': 'err.parlay_max_legs',
    // 充值 / 提现
    'duplicate withdrawal': 'err.duplicate_withdrawal',
    'pending withdrawal exists': 'err.pending_withdrawal',
    'this txHash has already been submitted': 'err.duplicate_tx_hash',
    'txHash is required': 'err.tx_hash_required',
    'address looks invalid': 'err.address_invalid',
    'amount must be between 0 and 1,000,000': 'err.amount_out_of_range',
    'chain must be trc20, eth, or btc': 'err.bad_chain',
    'uploads disabled': 'err.uploads_disabled',
    "form field 'file' missing": 'err.file_field_missing',
    // Auth
    'missing bearer token': 'err.missing_token',
    'missing token': 'err.missing_token',
    'invalid token': 'err.invalid_token',
    'user not found': 'err.user_not_found',
    // 系统级
    'rate limited': 'err.rate_limited',
    'rate limit exceeded': 'err.rate_limited',
    'events unavailable: provider is not API-Football': 'err.events_unavailable',
    'stats unavailable: provider is not API-Football': 'err.stats_unavailable',
    // 基础参数
    'invalid body': 'err.invalid_body',
    'bad action': 'err.bad_action',
    'bad id': 'err.bad_id',
  };
  final key = exact[raw];
  if (key != null) return tr(key);

  if (raw.startsWith('parlay needs at least')) return tr('err.parlay_min_legs');
  if (raw.startsWith('parlay limited to')) return tr('err.parlay_max_legs');
  // 提现流水门槛未达标(后端:turnover requirement not met: need X more)
  if (raw.startsWith('turnover requirement not met')) return tr('err.turnover_not_met');
  final notBettable = RegExp(r'^match (\d+) not bettable$').firstMatch(raw);
  if (notBettable != null) {
    return tr('err.match_not_bettable').replaceAll('{id}', notBettable.group(1)!);
  }
  final notOpenYet = RegExp(r'^match (\d+) market not open yet$').firstMatch(raw);
  if (notOpenYet != null) {
    return tr('err.match_market_not_open').replaceAll('{id}', notOpenYet.group(1)!);
  }
  final notAvail = RegExp(r'^match (\d+) not available$').firstMatch(raw);
  if (notAvail != null) {
    return tr('err.match_not_available').replaceAll('{id}', notAvail.group(1)!);
  }
  final oddsMissing = RegExp(r'^odds for match (\d+) not available$').firstMatch(raw);
  if (oddsMissing != null) {
    return tr('err.match_odds_missing').replaceAll('{id}', oddsMissing.group(1)!);
  }
  final selMissing = RegExp(r'^selection not offered for match (\d+)$').firstMatch(raw);
  if (selMissing != null) {
    return tr('err.match_selection_missing').replaceAll('{id}', selMissing.group(1)!);
  }
  // 包装型内部错误(后端 fmt.Errorf 拼出来的)— 不展示原 stack,统一兜底
  if (raw.startsWith('odds fetch failed:') ||
      raw.startsWith('parse multipart:') ||
      raw.startsWith('save user:') ||
      raw.startsWith('issue token')) {
    return tr('err.generic');
  }
  // 完全未知 → 友好兜底,不再把原英文塞给中文用户
  return tr('err.generic');
}

class ApiException implements Exception {
  final int statusCode;
  /// 原始服务端 error key,debug/日志用。
  final String message;
  /// 后端 error JSON 的完整 body(含 stakeCap / oddsLimit 等附加字段),用于
  /// 拼出更具体的用户提示。解析失败时为 null。
  final Map<String, dynamic>? data;
  ApiException(this.statusCode, this.message, [this.data]);

  /// 给用户看的中文。toString() 默认调这个,所以页面 catch (e) 直接显示 e.toString() 也是中文。
  String get userMessage {
    final base = _zhError(message);
    // 低赔单注上限:在本地化文案后附上后端返回的 stakeCap,告诉用户上限多少、
    // 降低金额即可下注。直接拼数字,避免改动 16 种语言的翻译。
    if (message == 'low odds single bet limit exceeded' && data != null) {
      final cap = data!['stakeCap'];
      if (cap != null) return '$base (${_fmtNum(cap)})';
    }
    return base;
  }

  static String _fmtNum(dynamic v) {
    if (v is num) {
      return v == v.roundToDouble() ? v.toInt().toString() : v.toString();
    }
    return v.toString();
  }

  @override
  String toString() => userMessage;
}

/// Telegram bot 元数据,/api/auth/config 返回。
/// 浏览器环境登录(LoginWidget / oauth.telegram.org)需要 botUsername / botId。
class AuthBotConfig {
  AuthBotConfig({required this.botUsername, required this.botId, this.loginOrigin = '', this.geoLang = ''});
  final String botUsername;
  final int botId;
  /// 规范登录域名(含协议)。多域名部署时所有域名的 OAuth 都走它;空 = 用当前域名。
  final String loginOrigin;
  /// 按访客 IP 国家(Cloudflare CF-IPCountry)建议的界面语言码;空=无建议。
  final String geoLang;

  bool get isConfigured => botUsername.isNotEmpty && botId > 0;
}

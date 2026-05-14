import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/match.dart';

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

  bool _refreshing = false;

  Future<http.Response> _authGet(Uri uri) async {
    var r = await http.get(uri, headers: _headers(auth: true));
    if (r.statusCode == 401 && onTokenExpired != null && !_refreshing) {
      _refreshing = true;
      try {
        await onTokenExpired!();
      } finally {
        _refreshing = false;
      }
      r = await http.get(uri, headers: _headers(auth: true));
    }
    return r;
  }

  Future<http.Response> _authPost(Uri uri, {Object? body, Map<String, String>? extraHeaders}) async {
    final h = _headers(auth: true);
    if (extraHeaders != null) h.addAll(extraHeaders);
    var r = await http.post(uri, headers: h, body: body);
    if (r.statusCode == 401 && onTokenExpired != null && !_refreshing) {
      _refreshing = true;
      try {
        await onTokenExpired!();
      } finally {
        _refreshing = false;
      }
      // 401 自动刷 token 后重试 —— 这里复用 extraHeaders(包括 Idempotency-Key),
      // 后端看到同 key 第二次仍会走 cache 命中分支,不会真的重复下单。
      final h2 = _headers(auth: true);
      if (extraHeaders != null) h2.addAll(extraHeaders);
      r = await http.post(uri, headers: h2, body: body);
    }
    return r;
  }

  Future<http.Response> _authDelete(Uri uri) async {
    var r = await http.delete(uri, headers: _headers(auth: true));
    if (r.statusCode == 401 && onTokenExpired != null && !_refreshing) {
      _refreshing = true;
      try {
        await onTokenExpired!();
      } finally {
        _refreshing = false;
      }
      r = await http.delete(uri, headers: _headers(auth: true));
    }
    return r;
  }

  Future<Map<String, dynamic>> loginTelegram(String initData, {String startParam = ''}) async {
    final r = await http.post(
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
    final r = await http.get(_uri('/api/matches', q));
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
    final r = await http.get(_uri('/api/config/leagues'));
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
    final r = await http.get(_uri('/api/match/$id'));
    _check(r);
    return MatchInfo.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
  }

  Future<OddsSnapshot> getOdds(int id) async {
    final r = await http.get(_uri('/api/odds/$id'));
    _check(r);
    return OddsSnapshot.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
  }

  Future<OddsHistory> getOddsHistory(int id, {int limit = 60}) async {
    final r = await http.get(_uri('/api/odds/$id/history', {'limit': '$limit'}));
    _check(r);
    return OddsHistory.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
  }

  /// Per-fixture statistics from API-Football: corners / yellow / red /
  /// shots split by home/away. Only available when FETCHER_PROVIDER=apifootball.
  /// Returns ({}, {}) when the provider doesn't support it.
  Future<({Map<String, int> home, Map<String, int> away})> getMatchStats(
      int id) async {
    final r = await http.get(_uri('/api/match/$id/stats'));
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
    final r = await http.get(_uri('/api/match/$id/events'));
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

  /// Cash-out a single pending prediction. Returns the actual USDT amount
  /// credited (server quotes against latest odds, not what UI showed).
  Future<({double cashedOut, double currentOdds, Prediction prediction})>
      cashOutPrediction(int id) async {
    final r = await _authPost(_uri('/api/predictions/$id/cashout'));
    _check(r);
    final m = jsonDecode(r.body) as Map<String, dynamic>;
    return (
      cashedOut: ((m['cashedOut'] ?? 0) as num).toDouble(),
      currentOdds: ((m['currentOdds'] ?? 0) as num).toDouble(),
      prediction:
          Prediction.fromJson(m['prediction'] as Map<String, dynamic>),
    );
  }

  /// 串关提前结算 — 后端按剩余 leg 当前赔率累乘报价。
  /// 返回 cashedOut 实际金额 + pendingLegs 数量。
  Future<({double cashedOut, int pendingLegs, Parlay parlay})> cashOutParlay(int id) async {
    final r = await _authPost(_uri('/api/parlays/$id/cashout'));
    _check(r);
    final m = jsonDecode(r.body) as Map<String, dynamic>;
    return (
      cashedOut: ((m['cashedOut'] ?? 0) as num).toDouble(),
      pendingLegs: ((m['pendingLegs'] ?? 0) as num).toInt(),
      parlay: Parlay.fromJson(m['parlay'] as Map<String, dynamic>),
    );
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
    );
    _check(r);
    return Prediction.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
  }

  Future<List<LeaderboardEntry>> leaderboard({
    int limit = 50,
    String period = 'all',
  }) async {
    final r = await http.get(
      _uri('/api/leaderboard', {'limit': '$limit', 'period': period}),
    );
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
    final r = await http.get(_uri('/api/team-overrides'));
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
    final r = await http.get(_uri('/api/home/announcements'));
    _check(r);
    final m = jsonDecode(r.body) as Map<String, dynamic>;
    return ((m['items'] ?? []) as List).cast<String>();
  }

  Future<List<HotMatch>> hotMatches({int limit = 4}) async {
    final r = await http.get(_uri('/api/home/hot-matches', {'limit': '$limit'}));
    _check(r);
    final list = jsonDecode(r.body) as List;
    return list.cast<Map<String, dynamic>>().map(HotMatch.fromJson).toList();
  }

  /// 首页"最近赛果"区块 — 已结束比赛(默认 3 天 / 10 条),含终场比分。
  Future<List<MatchInfo>> recentSettled({int days = 3, int limit = 10}) async {
    final r = await http.get(_uri('/api/home/recent-settled', {
      'days': '$days',
      'limit': '$limit',
    }));
    _check(r);
    final list = jsonDecode(r.body) as List;
    return list.cast<Map<String, dynamic>>().map(MatchInfo.fromJson).toList();
  }

  Future<HomeConfig> homeConfig() async {
    final r = await http.get(_uri('/api/home/config'));
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
  }) async {
    final r = await _authPost(
      _uri('/api/deposits'),
      body: jsonEncode({'amount': amount, 'txHash': txHash, 'proofUrl': proofUrl, 'chain': chain}),
    );
    _check(r);
    return Deposit.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
  }

  Future<Withdrawal> submitWithdrawal({
    required double amount,
    required String address,
  }) async {
    final r = await _authPost(
      _uri('/api/withdrawals'),
      body: jsonEncode({'amount': amount, 'address': address}),
    );
    _check(r);
    return Withdrawal.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
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
    try {
      final m = jsonDecode(r.body) as Map<String, dynamic>;
      msg = m['error']?.toString() ?? r.body;
    } catch (_) {
      msg = r.body;
    }
    throw ApiException(r.statusCode, msg);
  }
}

/// 把后端英文 error key 翻译成给用户看的中文。匹配优先级:
/// 1. 完全匹配  2. 前缀匹配(用于 "match X not bettable" 这种带变量的)。
String _zhError(String raw) {
  // exact
  const exact = <String, String>{
    'insufficient balance': '余额不足',
    'matchId and score are required': '请先选择比赛和投注项',
    'matchId and score are required for every leg': '每个选项都需要比赛和投注项',
    'unknown marketType': '不支持的玩法',
    'unknown marketType in leg': '串关中含有不支持的玩法',
    'same match cannot appear twice in a parlay': '同一场比赛不能在串关中出现两次',
    'match not found': '比赛不存在或已下架',
    'match already started or settled': '比赛已开始或已结束,无法下注',
    'odds not available': '赔率暂时不可用,请稍后重试',
    'selection not offered': '该选项已下架,请重新选择',
    'score not offered': '该比分已下架,请重新选择',
    'invalid body': '请求格式错误',
    'bad action': '操作类型不合法',
    'bad id': '参数错误',
    'parlay needs at least 2 legs': '串关至少需要 2 关',
    'parlay limited to 8 legs': '串关最多 8 关',
    'missing bearer token': '请先登录',
    'invalid token': '登录已过期,请重新打开 Mini App',
    'prediction not found': '注单不存在或已结算',
    'prediction already settled': '该注单已结算,无法重复操作',
    'current odds unavailable': '当前赔率不可用,稍后再试',
  };
  if (exact.containsKey(raw)) return exact[raw]!;

  // prefix / pattern
  if (raw.startsWith('parlay needs at least')) return '串关至少需要 2 关';
  if (raw.startsWith('parlay limited to')) return '串关最多 8 关';
  final notBettable = RegExp(r'^match (\d+) not bettable$').firstMatch(raw);
  if (notBettable != null) {
    return '比赛 #${notBettable.group(1)} 已开始或不可下注';
  }
  final notAvail = RegExp(r'^match (\d+) not available$').firstMatch(raw);
  if (notAvail != null) {
    return '比赛 #${notAvail.group(1)} 已下架';
  }
  final oddsMissing = RegExp(r'^odds for match (\d+) not available$').firstMatch(raw);
  if (oddsMissing != null) {
    return '比赛 #${oddsMissing.group(1)} 的赔率暂时不可用';
  }
  final selMissing = RegExp(r'^selection not offered for match (\d+)$').firstMatch(raw);
  if (selMissing != null) {
    return '比赛 #${selMissing.group(1)} 的选项已下架';
  }
  return raw; // 未知 key,按原样显示(回退到英文胜过抛 stack)
}

class ApiException implements Exception {
  final int statusCode;
  /// 原始服务端 error key,debug/日志用。
  final String message;
  ApiException(this.statusCode, this.message);

  /// 给用户看的中文。toString() 默认调这个,所以页面 catch (e) 直接显示 e.toString() 也是中文。
  String get userMessage => _zhError(message);

  @override
  String toString() => userMessage;
}

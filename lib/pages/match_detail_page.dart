import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/match.dart';
import '../services/app_state.dart';
import '../services/auth_gate.dart';
import '../services/bet_slip.dart';
import '../services/i18n.dart';
import '../services/player_names.dart';
import '../services/stream_feed.dart';
import '../services/toast.dart';
import '../theme/tokens.dart';
import '../utils/league_flags.dart';
import '../utils/team_crests.dart';
import '../utils/team_names.dart';
import '../widgets/bet_slip_fab.dart';
import '../widgets/light_card.dart';
import '../widgets/odds_chip.dart';
import '../widgets/sparkline_chart.dart';

/// 03 / 04 · 比赛详情 — 浅色 hero + 1x2 + 19 格波胆 + 下注抽屉。
class MatchDetailPage extends StatefulWidget {
  const MatchDetailPage({super.key, required this.state, required this.match});
  final AppState state;
  final MatchInfo match;

  @override
  State<MatchDetailPage> createState() => _MatchDetailPageState();
}

/// 跨市场的下注选择项。波胆 / 大小球 / 双方进球都映射到这个统一结构,
/// 让底部下注抽屉只看一个 `_selected`。
class _BetSelection {
  final String marketType;
  final String score; // 该市场内部的选项 key,如 "2:1" / "over" / "yes"
  final double price;
  final String label; // 人话,如 "波胆 2:1" / "大 2.5" / "双方进球: 是"

  const _BetSelection({
    required this.marketType,
    required this.score,
    required this.price,
    required this.label,
  });

  /// 用作 _myBets map 的 key — 单一市场内部的 score 不会重复,跨市场加前缀消歧。
  String get key => '$marketType::$score';
}

// _normalizeScoreKey — 把 legacy O/U score ('over'/'under') 规范化到带 line 形式
// ('over@2.5' / 'under@2.5'),让 _myBets 命中 UI build 出来的 key。其他市场原样返回。
String _normalizeScoreKey(String marketType, String score) {
  if (marketType != MarketType.overUnder25) return score;
  if (score.contains('@')) return score;
  if (score == 'over' || score == 'under') return '$score@2.5';
  return score;
}

class _MatchDetailPageState extends State<MatchDetailPage> {
  OddsSnapshot? _odds;
  _BetSelection? _selected;
  StreamSubscription<OddsSnapshot>? _sub;
  StreamSubscription<List<MatchInfo>>? _matchesSub;
  /// Live snapshot of the match — starts as the row from the list page,
  /// then gets refreshed by every PublishMatches push so the score, status,
  /// corners/cards, and "已超过 2.5 球 → 大小球禁用" all stay accurate.
  /// Must NOT use widget.match for anything time-sensitive in build().
  late MatchInfo _match = widget.match;
  bool _placing = false;
  String? _placeError;
  String? _placeOK;
  double _stake = 100;
  UserStats? _stats;

  /// 该用户在当前比赛上,每个市场+选项已经下注的总金额。
  /// Key 格式: "<marketType>::<score>"。命中即代表"该选项已下注",
  /// UI 灰化、禁用点击,并把金额显示到格子里。
  final Map<String, double> _myBets = {};

  /// 1X2 赔率历史 — 用于 sparkline。
  OddsHistory? _history;
  Timer? _historyTimer;

  /// API-Football 现场统计 (角球 / 红黄牌 / 射门) — 仅 live 状态懒加载。
  /// 503 / 失败 → 留空,UI 隐藏整段。
  Map<String, int> _statsHome = {};
  Map<String, int> _statsAway = {};
  Timer? _statsTimer;

  /// 进球 / 红黄牌 / 换人 时间线 — live + settled 都拉一次。
  List<MatchEvent> _events = [];

  // Map of last-changed score → "up"/"down" with autoclear after ~1.2s,
  // used to flash the corresponding cells.
  final Map<String, String> _flashes = {};
  final Map<String, Timer> _flashTimers = {};

  /// 底部 drawer 实际像素高度 — bottomSheet 不会自动给 ListView 加 padding,
  /// 必须 PostFrame 测量后回灌。drawer 含动态显示的 _placeOK / _placeError 卡片,
  /// 高度会变 → 用 GlobalKey 实时跟随。
  final GlobalKey _drawerKey = GlobalKey();
  double _drawerHeight = 230; // 初始合理猜测,首帧后被实际值覆盖

  // 只有 settled(已结束)的比赛完全锁住下注。pending 和 live 都允许投注。
  bool get _locked => _match.isSettled;
  bool get _isLive => _match.isLive;
  // 滚球进球封盘期 — 拒绝下注但可继续选择/查看
  bool get _liveLocked {
    final lu = _odds?.lockUntil;
    return lu != null && lu.isAfter(DateTime.now());
  }
  Timer? _lockTickTimer;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    widget.state.stream.subscribe(widget.match.id);
    _sub = widget.state.stream.odds.listen((s) {
      if (s.matchId == widget.match.id && mounted) {
        _diffAndFlash(_odds, s);
        setState(() {
          _odds = s;
          if (_selected != null) {
            final live = _priceForSelection(_selected!, s);
            if (live <= 0) {
              // Market closed (e.g. both teams scored → BTTS settled,
              // total goals exceeded OU line, current score advanced past
              // the picked correct_score). Auto-clear so the bet button
              // can't fire at a price the backend has already rejected.
              _selected = null;
            } else if ((live - _selected!.price).abs() > 0.005) {
              // Price drifted but selection still valid — replace the
              // tile so the bet button label and the eventual POST body
              // both reflect the LATEST live price, not the one the user
              // tapped 10 s ago.
              _selected = _BetSelection(
                marketType: _selected!.marketType,
                score: _selected!.score,
                price: live,
                label: _selected!.label,
              );
            }
          }
        });
      }
    });
    // Live match push: keep _match in sync with the latest score/status so
    // the hero "X:Y" header and any per-market resolved-state checks stay
    // current. Without this, a goal scored elsewhere wouldn't reflect on
    // the detail page until the user pops + re-enters.
    _matchesSub = widget.state.stream.matches.listen((list) {
      if (!mounted) return;
      for (final m in list) {
        if (m.id == widget.match.id) {
          if (mounted) setState(() => _match = m);
          break;
        }
      }
    });
    try {
      final initial = await widget.state.api.getOdds(widget.match.id);
      if (mounted) setState(() => _odds = initial);
    } catch (_) {/* odds may not be ready yet */}
    if (widget.state.isAuthenticated) {
      try {
        final s = await widget.state.api.getStats();
        if (mounted) setState(() => _stats = s);
      } catch (_) {}
      await _loadMyBets();
    }
    // 拉一次历史,然后每 30s 刷新一次(后端每分钟写一笔)。
    _refreshHistory();
    _historyTimer = Timer.periodic(const Duration(seconds: 30), (_) => _refreshHistory());

    // 滚球封盘倒计时 1s 重绘 — 仅在 live 时跑,否则白消耗 CPU。
    if (_isLive) {
      _lockTickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }

    // 加载 stream feed cache(若已在列表页拉过会直接命中,无网络开销)
    StreamFeed.instance.ensure(widget.state.api).then((_) {
      if (mounted) setState(() {});
    });

    // 拉一次 stats + events; live 状态每 60s 刷新 stats(每场 1 req)
    _refreshStatsAndEvents();
    if (_isLive) {
      _statsTimer = Timer.periodic(const Duration(seconds: 60), (_) {
        _refreshStatsAndEvents();
      });
    }
  }

  /// Look up the live price for a selection in a snapshot. Returns 0 when
  /// the option no longer exists or the market has resolved (e.g. BTTS
  /// after both teams scored, OU 2.5 after the third goal). Used to
  /// auto-clear stale selections so the bet button can't fire at a price
  /// the backend has already invalidated.
  double _priceForSelection(_BetSelection sel, OddsSnapshot s) {
    switch (sel.marketType) {
      case MarketType.correctScore:
        for (final o in s.correctScore) {
          if (o.score == sel.score) return o.price;
        }
        return 0;
      case MarketType.overUnder25:
        // score 形如 'over@2.5' / 'under@1.5' / 'over' / 'under'(legacy = 2.5)
        final at = sel.score.lastIndexOf('@');
        final side = at > 0 ? sel.score.substring(0, at) : sel.score;
        final line = at > 0 ? double.tryParse(sel.score.substring(at + 1)) ?? 2.5 : 2.5;
        OverUnderLine? ouLine;
        for (final ou in s.overUnders) {
          if ((ou.line - line).abs() < 0.01) { ouLine = ou; break; }
        }
        ouLine ??= (line == 2.5 ? s.overUnder : null);
        if (ouLine == null) return 0;
        if (side == 'over') return ouLine.over;
        if (side == 'under') return ouLine.under;
        return 0;
      case MarketType.btts:
        final b = s.btts;
        if (b == null) return 0;
        if (sel.score == 'yes') return b.yes;
        if (sel.score == 'no') return b.no;
        return 0;
      case MarketType.doubleChance:
        final dc = s.doubleChance;
        if (dc == null) return 0;
        switch (sel.score) {
          case '1X': return dc.homeOrDraw;
          case 'X2': return dc.drawOrAway;
          case '12': return dc.homeOrAway;
        }
        return 0;
      case MarketType.drawNoBet:
        final dnb = s.drawNoBet;
        if (dnb == null) return 0;
        if (sel.score == 'home') return dnb.home;
        if (sel.score == 'away') return dnb.away;
        return 0;
      case MarketType.matchWinner:
        final ml = s.moneyLine;
        if (ml == null) return 0;
        switch (sel.score) {
          case 'home': return ml.home;
          case 'draw': return ml.draw;
          case 'away': return ml.away;
        }
        return 0;
      case MarketType.asianHandicap:
        final h = s.handicap;
        if (h == null) return 0;
        if (sel.score == 'home') return h.home;
        if (sel.score == 'away') return h.away;
        return 0;
    }
    return 0;
  }

  /// Resolve a playable m3u8 stream for this match. 7t666 feed (joined by
  /// Chinese team name) takes precedence; LiveDetail.streamUrl is the fallback.
  String _streamUrlForMatch() {
    final m = widget.match;
    final feed = StreamFeed.instance.find(m.home, m.away, m.date);
    return feed?.streamUrl ?? m.live?.streamUrl ?? '';
  }

  void _openStream() {
    final url = _streamUrlForMatch();
    if (url.isEmpty) return;
    final m = widget.match;
    try {
      globalContext.callMethod(
        'openLiveStream'.toJS,
        url.toJS,
        localizedTeam(m.home).toJS,
        localizedTeam(m.away).toJS,
      );
    } catch (_) {}
  }

  Widget _watchLiveButton() {
    return GestureDetector(
      onTap: _openStream,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFF4040), Color(0xFFC8001A)],
          ),
          borderRadius: BorderRadius.circular(6),
          boxShadow: const [
            BoxShadow(color: Color(0x55FF4040), blurRadius: 6, offset: Offset(0, 2)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.play_arrow, color: Colors.white, size: 12),
            const SizedBox(width: 2),
            Text(tr('detail.watch_stream'),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }

  Future<void> _refreshStatsAndEvents() async {
    // 仅有 live / settled 才有意义;pending 比赛上游会返回空
    if (!_isLive && !_match.isSettled) return;
    try {
      final r = await widget.state.api.getMatchStats(widget.match.id);
      if (!mounted) return;
      setState(() {
        _statsHome = r.home;
        _statsAway = r.away;
      });
    } catch (_) {/* 503 or transient — silent */}
    try {
      final ev = await widget.state.api.getMatchEvents(widget.match.id);
      if (!mounted) return;
      setState(() => _events = ev);
      // When the user is reading in Chinese, fire a backend lookup for the
      // player names attached to the events so the next paint can show the
      // dongqiudi-translated form instead of "M. Salah". Fire-and-forget;
      // a setState after success swaps the labels in place.
      if (I18n.instance.locale == 'zh') {
        final names = <String>{};
        for (final e in ev) {
          if (e.player.isNotEmpty) names.add(e.player);
        }
        if (names.isNotEmpty) {
          PlayerNames.instance
              .ensureLoaded(widget.state.api.baseUrl, names,
                  authToken: widget.state.api.token)
              .then((_) {
            if (mounted) setState(() {});
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _refreshHistory() async {
    try {
      final h = await widget.state.api.getOddsHistory(widget.match.id, limit: 60);
      if (mounted) setState(() => _history = h);
    } catch (_) {/* ignore — sparkline simply absent */}
  }

  Future<void> _loadMyBets() async {
    try {
      final preds = await widget.state.api.myPredictions();
      final m = <String, double>{};
      for (final p in preds) {
        if (p.matchId != widget.match.id) continue;
        final key = '${p.marketType}::${_normalizeScoreKey(p.marketType, p.score)}';
        m[key] = (m[key] ?? 0) + p.stake;
      }
      if (mounted) {
        setState(() {
          _myBets
            ..clear()
            ..addAll(m);
        });
      }
    } catch (_) {/* keep empty — not blocking */}
  }

  void _diffAndFlash(OddsSnapshot? prev, OddsSnapshot next) {
    if (prev == null) return;
    final prevPrices = {for (final s in prev.correctScore) s.score: s.price};
    for (final s in next.correctScore) {
      final p = prevPrices[s.score];
      if (p == null) continue;
      String? dir;
      if (s.price > p) dir = 'up';
      if (s.price < p) dir = 'down';
      if (dir != null) {
        _flashes[s.score] = dir;
        _flashTimers[s.score]?.cancel();
        _flashTimers[s.score] = Timer(const Duration(milliseconds: 1300), () {
          if (!mounted) return;
          setState(() => _flashes.remove(s.score));
        });
      }
    }
  }

  @override
  void dispose() {
    widget.state.stream.unsubscribe(widget.match.id);
    _sub?.cancel();
    _matchesSub?.cancel();
    _historyTimer?.cancel();
    _lockTickTimer?.cancel();
    _statsTimer?.cancel();
    for (final t in _flashTimers.values) {
      t.cancel();
    }
    super.dispose();
  }

  Future<void> _place() async {
    final sel = _selected;
    if (sel == null) return;
    if (_placing) return; // double-tap guard
    // 浏览器未登录:先弹 Telegram 登录,登录成功后再下注。Mini App 内永远是
    // 已登录,直接 fall through。
    if (!widget.state.isAuthenticated) {
      final ok = await requireLogin(context, widget.state);
      if (!ok || !mounted) return;
    }
    setState(() {
      _placing = true;
      _placeError = null;
      _placeOK = null;
    });
    try {
      final p = await widget.state.api.placePrediction(
        matchId: widget.match.id,
        marketType: sel.marketType,
        score: sel.score,
        stake: _stake,
      );
      if (!mounted) return;
      final key = '${p.marketType}::${_normalizeScoreKey(p.marketType, p.score)}';
      setState(() {
        _placeOK = tr('detail.ok_locked')
            .replaceAll('{label}', sel.label)
            .replaceAll('{odds}', p.oddsAtPlace.toStringAsFixed(2))
            .replaceAll('{stake}', p.stake.toStringAsFixed(0));
        _myBets[key] = (_myBets[key] ?? 0) + p.stake;
        _selected = null; // 已下注的选项不应继续被选中
      });
      // refresh stats so balance updates
      try {
        final s = await widget.state.api.getStats();
        if (mounted) setState(() => _stats = s);
      } catch (_) {}
    } catch (e) {
      if (mounted) setState(() => _placeError = e.toString());
    } finally {
      if (mounted) setState(() => _placing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 监听 BetSlip 变化 — 加入/移除时整页重绘以更新 cell 的"已在投注单"标记。
    return AnimatedBuilder(
      animation: widget.state.betSlip,
      builder: (context, _) => _buildScaffold(context),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    // 每帧后测一次 drawer 高度,差超过 2px 才回灌(避免无限 setState)。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _drawerKey.currentContext;
      if (ctx == null || !mounted) return;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return;
      final h = box.size.height;
      if ((h - _drawerHeight).abs() > 2) {
        setState(() => _drawerHeight = h);
      }
    });
    final bottomPad = _locked ? 96.0 : (_drawerHeight + 16);
    return Scaffold(
      extendBody: true,
      backgroundColor: T.bgPage,
      body: Container(
        decoration: const BoxDecoration(gradient: T.pageGradient),
        child: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  _topBar(),
                  Expanded(
                child: ListView(
                  padding: EdgeInsets.fromLTRB(0, 0, 0, bottomPad),
                  children: [
                    _hero(),
                    if (_locked) _lockedBanner(),
                    if (_isLive && !_locked) _liveBanner(),
                    if (_statsHome.isNotEmpty || _statsAway.isNotEmpty)
                      _liveStatsSection(),
                    if (_events.isNotEmpty) _eventsTimelineSection(),
                    _sectionHeader(),
                    _columnLabels(),
                    _scoreGrid(),
                    _winnerSection(),
                    _doubleChanceSection(),
                    _drawNoBetSection(),
                    _handicapSection(),
                    _overUnderSection(),
                    _bttsSection(),
                  ],
                ),
              ),
                ],
              ),
              // 详情页内的 BetSlip 悬浮按钮 — MainShell 的 FAB 被详情页覆盖了,
              // 在这里独立挂一个,位置避开底部 _betDrawer/_lockedDrawer。
              Positioned(
                right: 16,
                bottom: _locked ? 100 : (_drawerHeight + 24),
                child: BetSlipFab(state: widget.state),
              ),
            ],
          ),
        ),
      ),
      bottomSheet: _locked
          ? _lockedDrawer()
          : KeyedSubtree(key: _drawerKey, child: _betDrawer()),
    );
  }

  Widget _topBar() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: Color(0xC7FFFFFF),
        border: Border(bottom: BorderSide(color: T.border)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Container(
              width: 34, height: 34,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: T.border),
              ),
              child: const Icon(Icons.chevron_left, size: 20, color: T.ink),
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
          ),
          const SizedBox(width: 8),
          Text(tr('detail.title'),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: T.ink)),
          const Spacer(),
          if (_stats != null)
            Row(
              children: [
                Text('${tr('common.balance')} ', style: const TextStyle(fontSize: 11, color: T.inkMd)),
                Text(NumberFormat('#,##0.00').format(_stats!.balance),
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: T.brandDeep,
                        fontFamily: T.fontMono)),
              ],
            ),
        ],
      ),
    );
  }

  Widget _hero() {
    final m = _match;
    final fmt = DateFormat('MM-dd · HH:mm');
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
        decoration: BoxDecoration(
          gradient: _locked
              ? const LinearGradient(
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: [Color(0xFFF4F8FC), Color(0xFFEEF2F7)],
                )
              : T.heroGradient,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0x402CD7FD)),
          boxShadow: const [
            BoxShadow(color: Color(0x1A2CD7FD), blurRadius: 18, offset: Offset(0, 6))
          ],
        ),
        child: Column(
          children: [
            Row(
              children: [
                LeagueFlag(slug: m.leagueSlug, height: 12, width: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(m.leagueName.isEmpty ? 'FOOTBALL' : localizedLeague(m.leagueName),
                      style: const TextStyle(
                          fontSize: 11, color: T.inkMd, fontWeight: FontWeight.w600)),
                ),
                if (_locked)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF2F7),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(tr('detail.locked'),
                        style: const TextStyle(
                            color: T.inkLo,
                            fontSize: 10,
                            fontWeight: FontWeight.w800)),
                  ),
                if (_streamUrlForMatch().isNotEmpty) _watchLiveButton(),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      TeamCrest(name: m.home, id: m.homeId, leagueSlug: m.leagueSlug, size: 56, borderRadius: 14),
                      const SizedBox(height: 8),
                      Text(localizedTeam(m.home),
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700, color: T.ink)),
                      Text(tr('detail.home'),
                          style: const TextStyle(
                              fontSize: 10, fontWeight: FontWeight.w600, color: T.inkLo)),
                    ],
                  ),
                ),
                SizedBox(
                  width: 132,
                  child: Column(
                    children: [
                      if (m.scores != null)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _bigScore(m.scores!.home, _locked),
                            const SizedBox(width: 12),
                            const Text(':',
                                style: TextStyle(
                                    fontSize: 22,
                                    color: T.inkSubtle,
                                    fontWeight: FontWeight.w700)),
                            const SizedBox(width: 12),
                            _bigScore(m.scores!.away, _locked),
                          ],
                        )
                      else
                        const Text('VS',
                            style: TextStyle(
                                fontSize: 36,
                                fontWeight: FontWeight.w800,
                                color: T.inkLo,
                                fontFamily: T.fontMono)),
                      const SizedBox(height: 4),
                      Text(_locked ? '${tr('detail.settled_at')} · ${fmt.format(m.date)}' : fmt.format(m.date),
                          style: const TextStyle(
                              fontSize: 10, color: T.inkLo, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    children: [
                      TeamCrest(name: m.away, id: m.awayId, leagueSlug: m.leagueSlug, size: 56, borderRadius: 14),
                      const SizedBox(height: 8),
                      Text(localizedTeam(m.away),
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700, color: T.ink)),
                      Text(tr('detail.away'),
                          style: const TextStyle(
                              fontSize: 10, fontWeight: FontWeight.w600, color: T.inkLo)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            // 1x2 strip
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xB3FFFFFF),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0x0D0E2238)),
              ),
              child: Row(
                children: [
                  Expanded(
                      child: OddsChip(
                          label: tr('detail.win_home'),
                          price: _odds?.moneyLine?.home ?? 0,
                          change: _odds?.change['home'])),
                  const SizedBox(width: 6),
                  Expanded(
                      child: OddsChip(
                          label: tr('detail.draw'),
                          price: _odds?.moneyLine?.draw ?? 0,
                          change: _odds?.change['draw'])),
                  const SizedBox(width: 6),
                  Expanded(
                      child: OddsChip(
                          label: tr('detail.win_away'),
                          price: _odds?.moneyLine?.away ?? 0,
                          change: _odds?.change['away'])),
                ],
              ),
            ),
            // 赔率走势 — 三色 sparkline。无历史时不渲染。
            if (_history != null && _history!.hasData) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                decoration: BoxDecoration(
                  color: const Color(0xB3FFFFFF),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0x0D0E2238)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.timeline, size: 12, color: T.inkLo),
                        const SizedBox(width: 4),
                        Text(tr('detail.1x2_trend'),
                            style: TextStyle(
                                fontSize: 10,
                                color: T.inkLo,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.3)),
                        const Spacer(),
                        _legendDot(T.brandDeep, tr('detail.legend_home')),
                        const SizedBox(width: 8),
                        _legendDot(const Color(0xFF8C9CB1), tr('detail.legend_draw')),
                        const SizedBox(width: 8),
                        _legendDot(const Color(0xFFE03E2D), tr('detail.legend_away')),
                      ],
                    ),
                    const SizedBox(height: 4),
                    OddsSparklineChart(history: _history!, height: 48),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _legendDot(Color c, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
          const SizedBox(width: 3),
          Text(label, style: const TextStyle(fontSize: 9, color: T.inkLo, fontWeight: FontWeight.w600)),
        ],
      );

  Widget _bigScore(int v, bool locked) {
    return Text(
      '$v',
      style: TextStyle(
        fontSize: 46,
        fontWeight: FontWeight.w800,
        color: locked ? T.ink : T.brandDeep,
        fontFamily: T.fontMono,
        height: 1.0,
        shadows: locked
            ? null
            : const [
                Shadow(color: Color(0x4011BAD9), blurRadius: 16, offset: Offset(0, 4))
              ],
      ),
    );
  }

  Widget _lockedBanner() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0x1A4CAF50), Color(0x084CAF50)],
          ),
          border: Border.all(color: const Color(0x3A4CAF50)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Text(tr('detail.locked_banner_title'),
                style: const TextStyle(fontSize: 12, color: T.upDark, fontWeight: FontWeight.w800)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(tr('detail.locked_banner_desc'),
                  style: const TextStyle(fontSize: 11, color: T.inkMd)),
            ),
          ],
        ),
      ),
    );
  }

  /// 滚球提示横幅 — 平时绿色"滚球中,赔率随比分动态变化",
  /// 进球后 60s 内变红色"封盘 N 秒"。
  Widget _liveBanner() {
    final lu = _odds?.lockUntil;
    final locked = lu != null && lu.isAfter(DateTime.now());
    final secs = locked ? lu.difference(DateTime.now()).inSeconds + 1 : 0;
    final colors = locked
        ? const [Color(0x1AE03E2D), Color(0x08E03E2D)]
        : const [Color(0x1A4CAF50), Color(0x084CAF50)];
    final borderColor = locked ? const Color(0x3AE03E2D) : const Color(0x3A4CAF50);
    final dotColor = locked ? T.down : T.upDark;
    final title = locked ? tr('detail.live_locked_title') : tr('detail.live_title');
    final desc = locked
        ? tr('detail.live_locked_desc').replaceAll('{secs}', '$secs')
        : tr('detail.live_desc');
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: colors),
          border: Border.all(color: borderColor),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 8, height: 8,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(title,
                style: TextStyle(fontSize: 12, color: dotColor, fontWeight: FontWeight.w800)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(desc,
                  style: const TextStyle(fontSize: 11, color: T.inkMd)),
            ),
          ],
        ),
      ),
    );
  }

  // ── Live stats panel: corners / yellow / red / shots ───────────────
  // Bilateral bars centered around the team labels — the wider side wins.

  Widget _liveStatsSection() {
    final rows = <_StatRow>[
      _StatRow(tr('stats.corners'), 'corners', _statsHome['corners'] ?? 0, _statsAway['corners'] ?? 0),
      _StatRow(tr('stats.yellow'), 'yellow', _statsHome['yellow'] ?? 0, _statsAway['yellow'] ?? 0),
      _StatRow(tr('stats.red'), 'red', _statsHome['red'] ?? 0, _statsAway['red'] ?? 0),
      _StatRow(tr('stats.shots'), 'shots', _statsHome['shots'] ?? 0, _statsAway['shots'] ?? 0),
      _StatRow(tr('stats.shots_on_target'), 'shotsOnTarget', _statsHome['shotsOnTarget'] ?? 0, _statsAway['shotsOnTarget'] ?? 0),
    ].where((r) => r.home > 0 || r.away > 0).toList();
    if (rows.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: LightCard(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('stats.title'),
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w800, color: T.ink)),
            const SizedBox(height: 10),
            for (final r in rows) ...[
              _statRow(r),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statRow(_StatRow r) {
    final total = (r.home + r.away).clamp(1, 1 << 30);
    final hf = r.home / total;
    final af = r.away / total;
    return Row(
      children: [
        // home bar (right-aligned, fills from center)
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text('${r.home}',
                  style: TextStyle(
                      fontSize: 12,
                      fontFamily: T.fontMono,
                      fontWeight: FontWeight.w700,
                      color: r.home > r.away ? T.brandDeep : T.inkMd)),
              const SizedBox(width: 6),
              Container(
                width: 80 * hf,
                height: 6,
                decoration: BoxDecoration(
                  color: r.color,
                  borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(3), bottomLeft: Radius.circular(3)),
                ),
              ),
            ],
          ),
        ),
        // label center
        Container(
          width: 56,
          alignment: Alignment.center,
          child: Text(r.label,
              style: const TextStyle(
                  fontSize: 11, color: T.inkLo, fontWeight: FontWeight.w600)),
        ),
        Expanded(
          child: Row(
            children: [
              Container(
                width: 80 * af,
                height: 6,
                decoration: BoxDecoration(
                  color: r.color.withValues(alpha: 0.6),
                  borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(3), bottomRight: Radius.circular(3)),
                ),
              ),
              const SizedBox(width: 6),
              Text('${r.away}',
                  style: TextStyle(
                      fontSize: 12,
                      fontFamily: T.fontMono,
                      fontWeight: FontWeight.w700,
                      color: r.away > r.home ? T.brandDeep : T.inkMd)),
            ],
          ),
        ),
      ],
    );
  }

  // ── Events timeline: goals, cards, subs with elapsed minute ────────

  Widget _eventsTimelineSection() {
    // sort by minute ascending; group by event type for compact display
    final goals = _events.where((e) => e.isGoal).toList();
    final yellows = _events.where((e) => e.isYellowCard).toList();
    final reds = _events.where((e) => e.isRedCard).toList();
    if (goals.isEmpty && yellows.isEmpty && reds.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: LightCard(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('events.title'),
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w800, color: T.ink)),
            const SizedBox(height: 10),
            if (goals.isNotEmpty) _eventRow(tr('events.goals'), goals, T.up),
            if (yellows.isNotEmpty) _eventRow(tr('events.yellow'), yellows, const Color(0xFFF5B544)),
            if (reds.isNotEmpty) _eventRow(tr('events.red'), reds, T.down),
          ],
        ),
      ),
    );
  }

  Widget _eventRow(String label, List<MatchEvent> events, Color accent) {
    // We don't have reliable home/away team IDs on MatchInfo, so events are
    // rendered as a flat list grouped by type (goals/yellows/reds), each
    // chip showing minute + player name. Sufficient for the "进球时间 /
    // 判罚时间" view without needing per-team alignment.
    final byMinute = [...events]..sort((a, b) => a.minute.compareTo(b.minute));
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 12,
                decoration: BoxDecoration(
                    color: accent, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(width: 6),
              Text(label,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700, color: T.ink)),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: byMinute.map((e) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(e.displayMinute,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            fontFamily: T.fontMono,
                            color: accent)),
                    if (e.player.isNotEmpty) ...[
                      const SizedBox(width: 5),
                      Text(
                          I18n.instance.locale == 'zh'
                              ? PlayerNames.instance.localize(e.player)
                              : e.player,
                          style: const TextStyle(
                              fontSize: 11, color: T.inkMd)),
                    ],
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('detail.odds_title'),
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800, color: T.ink)),
              const SizedBox(height: 2),
              Text(
                _locked ? tr('detail.odds_sub_locked') : tr('detail.odds_sub_open'),
                style: const TextStyle(
                    fontSize: 11, color: T.inkLo, fontWeight: FontWeight.w500),
              ),
            ],
          ),
          const Spacer(),
          if (!_locked)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0x1FD9AB7A),
                border: Border.all(color: const Color(0x47D9AB7A)),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.bolt_outlined, size: 12, color: T.gold),
                const SizedBox(width: 3),
                Text(tr('detail.realtime'),
                    style: const TextStyle(
                        fontSize: 10, color: T.gold, fontWeight: FontWeight.w700)),
              ]),
            ),
        ],
      ),
    );
  }

  Widget _columnLabels() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(child: _ColLabel(text: tr('detail.win_home'), color: T.brandDeep)),
          const SizedBox(width: 6),
          Expanded(child: _ColLabel(text: tr('detail.draw'), color: T.inkLo)),
          const SizedBox(width: 6),
          Expanded(child: _ColLabel(text: tr('detail.win_away'), color: T.brand2)),
        ],
      ),
    );
  }

  Widget _scoreGrid() {
    final scores = _odds?.correctScore ?? const [];
    if (scores.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(tr('detail.odds_loading'),
              style: const TextStyle(color: T.inkLo, fontSize: 13)),
        ),
      );
    }
    final home = <ScoreOption>[];
    final away = <ScoreOption>[];
    final draw = <ScoreOption>[];
    ScoreOption? other;
    for (final s in scores) {
      if (s.score == 'Other' || s.score == 'other') {
        other = s;
        continue;
      }
      final parts = s.score.split(':');
      if (parts.length != 2) continue;
      final h = int.tryParse(parts[0]) ?? 0;
      final a = int.tryParse(parts[1]) ?? 0;
      if (h > a) home.add(s);
      else if (h < a) away.add(s);
      else draw.add(s);
    }
    home.sort((x, y) => x.price.compareTo(y.price));
    draw.sort((x, y) => x.price.compareTo(y.price));
    away.sort((x, y) => x.price.compareTo(y.price));
    final cols = [home, draw, away];
    final rowsCount = [home.length, draw.length, away.length].reduce((a, b) => a > b ? a : b);
    final rows = rowsCount.clamp(0, 6);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Column(
        children: [
          for (int r = 0; r < rows; r++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  for (int c = 0; c < 3; c++) ...[
                    Expanded(
                      child: r < cols[c].length
                          ? Builder(builder: (_) {
                              final opt = cols[c][r];
                              final key = '${MarketType.correctScore}::${opt.score}';
                              final myStake = _myBets[key];
                              final disabled = _locked || myStake != null || opt.price <= 0;
                              final isSelected = _selected?.marketType == MarketType.correctScore &&
                                                 _selected?.score == opt.score;
                              final inSlip = widget.state.betSlip.containsKey(
                                  '${widget.match.id}::${MarketType.correctScore}::${opt.score}');
                              return _ScoreCell(
                                option: opt,
                                type: c == 0 ? _CellKind.home : c == 1 ? _CellKind.draw : _CellKind.away,
                                selected: isSelected,
                                flash: _flashes[opt.score],
                                locked: _locked,
                                myStake: myStake,
                                inSlip: inSlip,
                                onTap: disabled ? null : () => setState(() => _selected = _BetSelection(
                                      marketType: MarketType.correctScore,
                                      score: opt.score,
                                      price: opt.price,
                                      label: '${tr('detail.cs_label')} ${opt.score}',
                                    )),
                              );
                            })
                          : const SizedBox(height: 64),
                    ),
                    if (c < 2) const SizedBox(width: 6),
                  ],
                ],
              ),
            ),
          if (other != null)
            Builder(builder: (_) {
              final opt = other!;
              final key = '${MarketType.correctScore}::${opt.score}';
              final myStake = _myBets[key];
              final disabled = _locked || myStake != null || opt.price <= 0;
              final isSelected = _selected?.marketType == MarketType.correctScore &&
                                 _selected?.score == opt.score;
              final inSlip = widget.state.betSlip.containsKey(
                  '${widget.match.id}::${MarketType.correctScore}::${opt.score}');
              return _ScoreCell(
                option: opt,
                type: _CellKind.other,
                selected: isSelected,
                flash: _flashes[opt.score],
                locked: _locked,
                myStake: myStake,
                inSlip: inSlip,
                onTap: disabled ? null : () => setState(() => _selected = _BetSelection(
                      marketType: MarketType.correctScore,
                      score: opt.score,
                      price: opt.price,
                      label: tr('detail.other_label'),
                    )),
              );
            }),
        ],
      ),
    );
  }

  // ── 大小球 (多线 over/under 1.5 / 2.5 / 3.5) ─────────────────────────
  // 多线时:渲染 line chip(picker)+ 当前选中 line 的两个 over/under 按钮。
  // 老数据只有 line=2.5 一条 → picker 只显示一颗 chip,等价旧 UI。
  Widget _overUnderSection() {
    // 合并:overUnders 优先(多线),没有则 fallback 单条 overUnder。
    final List<OverUnderLine> lines = _odds?.overUnders.isNotEmpty == true
        ? _odds!.overUnders
        : (_odds?.overUnder != null ? [_odds!.overUnder!] : const []);
    if (lines.isEmpty) return const SizedBox.shrink();

    // 当前选中 line:
    //  - 若 _selected 是 OU 选项,从 score 解析(over@1.5 → 1.5);
    //  - 否则默认 line=2.5(若存在),不存在用第一条。
    double selectedLine;
    if (_selected?.marketType == MarketType.overUnder25) {
      final s = _selected!.score;
      final at = s.lastIndexOf('@');
      selectedLine = at > 0 ? double.tryParse(s.substring(at + 1)) ?? 2.5 : 2.5;
    } else {
      selectedLine = lines.any((l) => l.line == 2.5) ? 2.5 : lines.first.line;
    }
    // 防御:selectedLine 必须在 lines 集合内
    if (!lines.any((l) => (l.line - selectedLine).abs() < 0.01)) {
      selectedLine = lines.first.line;
    }
    final currentLine = lines.firstWhere((l) => (l.line - selectedLine).abs() < 0.01);
    final lineFmt = currentLine.line.toStringAsFixed(1);
    final overScore = 'over@$lineFmt';
    final underScore = 'under@$lineFmt';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 2),
            child: Row(
              children: [
                const Icon(Icons.straighten, size: 14, color: T.brandDeep),
                const SizedBox(width: 5),
                Text('${tr('detail.ou_title')} · $lineFmt ${tr('detail.ou_goals')}',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w800, color: T.ink)),
              ],
            ),
          ),
          // line picker:多线时显示,单线时省略(等价旧 UI)。
          if (lines.length > 1) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 8, left: 2),
              child: Wrap(
                spacing: 6,
                children: lines.map((l) {
                  final fmt = l.line.toStringAsFixed(1);
                  final sel = (l.line - selectedLine).abs() < 0.01;
                  return ChoiceChip(
                    label: Text(fmt, style: TextStyle(
                      fontSize: 12,
                      fontWeight: sel ? FontWeight.w800 : FontWeight.w600,
                      color: sel ? Colors.white : T.ink,
                    )),
                    selected: sel,
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    selectedColor: T.brandDeep,
                    backgroundColor: const Color(0xFFEAF1F8),
                    onSelected: (_) => setState(() {
                      // 切换 line 时,如果当前选了 over/under,把 selection 迁移到新 line。
                      if (_selected?.marketType == MarketType.overUnder25) {
                        final atIdx = _selected!.score.lastIndexOf('@');
                        final side = atIdx > 0 ? _selected!.score.substring(0, atIdx) : _selected!.score;
                        final newScore = '$side@$fmt';
                        final p = side == 'over' ? l.over : l.under;
                        _selected = _BetSelection(
                          marketType: MarketType.overUnder25,
                          score: newScore,
                          price: p,
                          label: tr(side == 'over' ? 'detail.ou_over_label' : 'detail.ou_under_label')
                              .replaceAll('{line}', fmt),
                        );
                      } else {
                        // 没选时只刷新 picker,不创建 selection。
                        _selected = _BetSelection(
                          marketType: MarketType.overUnder25,
                          score: '__line_pick__@$fmt',
                          price: 0,
                          label: '',
                        );
                      }
                    }),
                  );
                }).toList(),
              ),
            ),
          ],
          Row(
            children: [
              Expanded(
                child: _BinaryBetTile(
                  label: '${tr('detail.ou_over')} $lineFmt',
                  hint: tr('detail.ou_hint_over'),
                  price: currentLine.over,
                  selected: _selected?.marketType == MarketType.overUnder25 &&
                            _selected?.score == overScore,
                  myStake: _myBets['${MarketType.overUnder25}::$overScore'],
                  inSlip: widget.state.betSlip.containsKey('${widget.match.id}::${MarketType.overUnder25}::$overScore'),
                  locked: _locked,
                  accent: T.up,
                  onTap: () => setState(() => _selected = _BetSelection(
                        marketType: MarketType.overUnder25,
                        score: overScore,
                        price: currentLine.over,
                        label: tr('detail.ou_over_label').replaceAll('{line}', lineFmt),
                      )),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _BinaryBetTile(
                  label: '${tr('detail.ou_under')} $lineFmt',
                  hint: tr('detail.ou_hint_under'),
                  price: currentLine.under,
                  selected: _selected?.marketType == MarketType.overUnder25 &&
                            _selected?.score == underScore,
                  myStake: _myBets['${MarketType.overUnder25}::$underScore'],
                  inSlip: widget.state.betSlip.containsKey('${widget.match.id}::${MarketType.overUnder25}::$underScore'),
                  locked: _locked,
                  accent: T.down,
                  onTap: () => setState(() => _selected = _BetSelection(
                        marketType: MarketType.overUnder25,
                        score: underScore,
                        price: currentLine.under,
                        label: tr('detail.ou_under_label').replaceAll('{line}', lineFmt),
                      )),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── 双方进球 BTTS ───────────────────────────────────────────────
  // 独赢(1X2) — 用 moneyLine 数据,三个选项 home/draw/away 各自可投注。
  Widget _winnerSection() {
    final ml = _odds?.moneyLine;
    if (ml == null) return const SizedBox.shrink();
    Widget tile(String score, String label, String hint, double price, Color accent) {
      return Expanded(
        child: _BinaryBetTile(
          label: label,
          hint: hint,
          price: price,
          selected: _selected?.marketType == MarketType.matchWinner &&
              _selected?.score == score,
          myStake: _myBets['${MarketType.matchWinner}::$score'],
          inSlip: widget.state.betSlip
              .containsKey('${widget.match.id}::${MarketType.matchWinner}::$score'),
          locked: _locked,
          accent: accent,
          onTap: () => setState(() => _selected = _BetSelection(
                marketType: MarketType.matchWinner,
                score: score,
                price: price,
                label: '${tr('detail.winner_title')} · $label',
              )),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 2),
            child: Row(
              children: [
                const Icon(Icons.flag, size: 14, color: T.brandDeep),
                const SizedBox(width: 5),
                Text(tr('detail.winner_title'),
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w800, color: T.ink)),
              ],
            ),
          ),
          Row(
            children: [
              tile('home', tr('detail.win_home'), localizedTeam(widget.match.home), ml.home, T.up),
              const SizedBox(width: 8),
              tile('draw', tr('detail.draw'), tr('detail.winner_draw_hint'), ml.draw, T.brandDeep),
              const SizedBox(width: 8),
              tile('away', tr('detail.win_away'), localizedTeam(widget.match.away), ml.away, T.down),
            ],
          ),
        ],
      ),
    );
  }

  // 让球(Asian Handicap)— line + home/away 两选项。
  Widget _handicapSection() {
    final h = _odds?.handicap;
    if (h == null) return const SizedBox.shrink();
    final lineStr = h.line >= 0 ? '+${h.line.toStringAsFixed(1)}' : h.line.toStringAsFixed(1);
    String homeHint, awayHint;
    if (h.line < 0) {
      // 主队让球
      homeHint = tr('detail.ah_home_give').replaceAll('{n}', (-h.line).toStringAsFixed(1));
      awayHint = tr('detail.ah_away_take').replaceAll('{n}', (-h.line).toStringAsFixed(1));
    } else {
      // 主队受让
      homeHint = tr('detail.ah_home_take').replaceAll('{n}', h.line.toStringAsFixed(1));
      awayHint = tr('detail.ah_away_give').replaceAll('{n}', h.line.toStringAsFixed(1));
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 2),
            child: Row(
              children: [
                const Icon(Icons.compare_arrows, size: 14, color: T.brandDeep),
                const SizedBox(width: 5),
                Text(tr('detail.handicap_title'),
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w800, color: T.ink)),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0x202CD7FD),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(lineStr,
                      style: const TextStyle(
                          fontSize: 11,
                          fontFamily: T.fontMono,
                          fontWeight: FontWeight.w800,
                          color: T.brandDeep)),
                ),
              ],
            ),
          ),
          Row(
            children: [
              Expanded(
                child: _BinaryBetTile(
                  label: localizedTeam(widget.match.home),
                  hint: homeHint,
                  price: h.home,
                  selected: _selected?.marketType == MarketType.asianHandicap &&
                      _selected?.score == 'home',
                  myStake: _myBets['${MarketType.asianHandicap}::home'],
                  inSlip: widget.state.betSlip.containsKey(
                      '${widget.match.id}::${MarketType.asianHandicap}::home'),
                  locked: _locked,
                  accent: T.up,
                  onTap: () => setState(() => _selected = _BetSelection(
                        marketType: MarketType.asianHandicap,
                        score: 'home',
                        price: h.home,
                        label: '${tr('detail.handicap_title')} · ${localizedTeam(widget.match.home)} $lineStr',
                      )),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _BinaryBetTile(
                  label: localizedTeam(widget.match.away),
                  hint: awayHint,
                  price: h.away,
                  selected: _selected?.marketType == MarketType.asianHandicap &&
                      _selected?.score == 'away',
                  myStake: _myBets['${MarketType.asianHandicap}::away'],
                  inSlip: widget.state.betSlip.containsKey(
                      '${widget.match.id}::${MarketType.asianHandicap}::away'),
                  locked: _locked,
                  accent: T.down,
                  onTap: () => setState(() => _selected = _BetSelection(
                        marketType: MarketType.asianHandicap,
                        score: 'away',
                        price: h.away,
                        label: '${tr('detail.handicap_title')} · ${localizedTeam(widget.match.away)} ${h.line >= 0 ? '-' : '+'}${(h.line.abs()).toStringAsFixed(1)}',
                      )),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── 双胜 Double Chance(1X / X2 / 12)──────────────────────────────
  // 三个选项一行,从 1X2 派生,价格由后端 DeriveDoubleChance 算出。
  Widget _doubleChanceSection() {
    final dc = _odds?.doubleChance;
    if (dc == null) return const SizedBox.shrink();
    Widget tile(String key, String label, double price) {
      return Expanded(
        child: _BinaryBetTile(
          label: label,
          hint: '',
          price: price,
          selected: _selected?.marketType == MarketType.doubleChance &&
                    _selected?.score == key,
          myStake: _myBets['${MarketType.doubleChance}::$key'],
          inSlip: widget.state.betSlip.containsKey('${widget.match.id}::${MarketType.doubleChance}::$key'),
          locked: _locked,
          accent: T.brandDeep,
          onTap: () => setState(() => _selected = _BetSelection(
                marketType: MarketType.doubleChance,
                score: key,
                price: price,
                label: '${tr('dc.short')} · $label',
              )),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 2),
            child: Row(
              children: [
                const Icon(Icons.alt_route, size: 14, color: T.brandDeep),
                const SizedBox(width: 5),
                Text(tr('dc.title'),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: T.ink)),
              ],
            ),
          ),
          Row(children: [
            tile('1X', tr('dc.1x'), dc.homeOrDraw),
            const SizedBox(width: 8),
            tile('X2', tr('dc.x2'), dc.drawOrAway),
            const SizedBox(width: 8),
            tile('12', tr('dc.12'), dc.homeOrAway),
          ]),
        ],
      ),
    );
  }

  // ── 平退本 Draw No Bet(主 / 客)─────────────────────────────────
  // 两选项;平局退本金。
  Widget _drawNoBetSection() {
    final dnb = _odds?.drawNoBet;
    if (dnb == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 2),
            child: Row(
              children: [
                const Icon(Icons.compare_arrows, size: 14, color: T.brandDeep),
                const SizedBox(width: 5),
                Text(tr('dnb.title'),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: T.ink)),
              ],
            ),
          ),
          Row(children: [
            Expanded(
              child: _BinaryBetTile(
                label: tr('detail.win_home'),
                hint: tr('dnb.short'),
                price: dnb.home,
                selected: _selected?.marketType == MarketType.drawNoBet &&
                          _selected?.score == 'home',
                myStake: _myBets['${MarketType.drawNoBet}::home'],
                inSlip: widget.state.betSlip.containsKey('${widget.match.id}::${MarketType.drawNoBet}::home'),
                locked: _locked,
                accent: T.up,
                onTap: () => setState(() => _selected = _BetSelection(
                      marketType: MarketType.drawNoBet,
                      score: 'home',
                      price: dnb.home,
                      label: '${tr('dnb.short')} · ${tr('detail.win_home')}',
                    )),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _BinaryBetTile(
                label: tr('detail.win_away'),
                hint: tr('dnb.short'),
                price: dnb.away,
                selected: _selected?.marketType == MarketType.drawNoBet &&
                          _selected?.score == 'away',
                myStake: _myBets['${MarketType.drawNoBet}::away'],
                inSlip: widget.state.betSlip.containsKey('${widget.match.id}::${MarketType.drawNoBet}::away'),
                locked: _locked,
                accent: T.down,
                onTap: () => setState(() => _selected = _BetSelection(
                      marketType: MarketType.drawNoBet,
                      score: 'away',
                      price: dnb.away,
                      label: '${tr('dnb.short')} · ${tr('detail.win_away')}',
                    )),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _bttsSection() {
    final btts = _odds?.btts;
    if (btts == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 2),
            child: Row(
              children: [
                const Icon(Icons.swap_horiz, size: 14, color: T.brandDeep),
                const SizedBox(width: 5),
                Text(tr('detail.btts_title'),
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w800, color: T.ink)),
              ],
            ),
          ),
          Row(
            children: [
              Expanded(
                child: _BinaryBetTile(
                  label: tr('detail.btts_yes'),
                  hint: tr('detail.btts_yes_hint'),
                  price: btts.yes,
                  selected: _selected?.marketType == MarketType.btts &&
                            _selected?.score == 'yes',
                  myStake: _myBets['${MarketType.btts}::yes'],
                  inSlip: widget.state.betSlip.containsKey('${widget.match.id}::${MarketType.btts}::yes'),
                  locked: _locked,
                  accent: T.up,
                  onTap: () => setState(() => _selected = _BetSelection(
                        marketType: MarketType.btts,
                        score: 'yes',
                        price: btts.yes,
                        label: tr('detail.btts_yes_label'),
                      )),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _BinaryBetTile(
                  label: tr('detail.btts_no'),
                  hint: tr('detail.btts_no_hint'),
                  price: btts.no,
                  selected: _selected?.marketType == MarketType.btts &&
                            _selected?.score == 'no',
                  myStake: _myBets['${MarketType.btts}::no'],
                  inSlip: widget.state.betSlip.containsKey('${widget.match.id}::${MarketType.btts}::no'),
                  locked: _locked,
                  accent: T.down,
                  onTap: () => setState(() => _selected = _BetSelection(
                        marketType: MarketType.btts,
                        score: 'no',
                        price: btts.no,
                        label: tr('detail.btts_no_label'),
                      )),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── bet drawer ────────────────────────────────────────────────────
  /// 紧凑下注栏 — 默认折叠态,只展示一个按钮。
  /// 选中波胆/玩法之前:灰按钮"请先选择波胆",不可点
  /// 选中后:亮蓝按钮"立即下注 · {label} @ {odds}",点击弹出 [_buildBetSheet]
  /// 滚球封盘期间:倒计时占位,不可点
  Widget _betDrawer() {
    final sel = _selected;
    final ready = sel != null && !_liveLocked;
    String label;
    if (_liveLocked) {
      final secs = (_odds!.lockUntil!.difference(DateTime.now()).inSeconds + 1)
          .clamp(0, 99);
      label = tr('detail.bet_live_locked').replaceAll('{secs}', '$secs');
    } else if (sel == null) {
      label = tr('detail.bet_lock_pending');
    } else {
      label = '${tr('detail.bet_quick_open')} · ${sel.label} @ ${sel.price.toStringAsFixed(2)}';
    }
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        height: 56,
        decoration: BoxDecoration(
          gradient: ready ? T.brandGradientShort : null,
          color: ready ? null : const Color(0xFFEEF2F7),
          borderRadius: BorderRadius.circular(14),
          boxShadow: ready
              ? const [
                  BoxShadow(color: Color(0x4D11BAD9), blurRadius: 14, offset: Offset(0, 6))
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: ready ? _showBetSheet : null,
            child: Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    ready ? Icons.flash_on_rounded : Icons.lock_outline,
                    size: 18,
                    color: ready ? Colors.white : T.inkLo,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(label,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: ready ? Colors.white : T.inkLo)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 弹出底部 sheet:筹码选择 + 加入投注单 / 锁定下注 双按钮。
  /// 完成或失败后通过 Toast 反馈,sheet 自动关闭。
  void _showBetSheet() {
    if (_selected == null) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) => _BetSheet(
        sel: _selected!,
        initialStake: _stake,
        liveLocked: _liveLocked,
        onStakeChanged: (v) => setState(() => _stake = v),
        onAddToSlip: () {
          _addToSlip();
          Navigator.pop(sheetCtx);
        },
        onPlace: () async {
          Navigator.pop(sheetCtx);
          await _place();
          if (!mounted) return;
          if (_placeOK != null) {
            Toast.success(context, _placeOK!);
            setState(() => _placeOK = null);
          } else if (_placeError != null) {
            Toast.error(context, _placeError!);
            setState(() => _placeError = null);
          }
        },
      ),
    );
  }

  void _addToSlip() {
    final sel = _selected;
    if (sel == null) return;
    final m = _match;
    widget.state.betSlip.add(BetSelection(
      matchId: m.id,
      home: m.home,
      away: m.away,
      leagueName: m.leagueName,
      leagueSlug: m.leagueSlug,
      marketType: sel.marketType,
      score: sel.score,
      price: sel.price,
      label: sel.label,
    ));
    Toast.show(context, '${tr('detail.added_slip')} · ${sel.label}', kind: 'info');
    setState(() => _selected = null);
  }

  Widget _lockedDrawer() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 22),
      decoration: const BoxDecoration(
        color: Color(0xF2FFFFFF),
        border: Border(top: BorderSide(color: T.border)),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 48,
        child: ElevatedButton.icon(
          onPressed: null,
          icon: const Icon(Icons.lock, size: 16),
          label: Text(tr('detail.bet_locked_btn'),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFEEF2F7),
            foregroundColor: T.inkLo,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            elevation: 0,
          ),
        ),
      ),
    );
  }
}

class _ColLabel extends StatelessWidget {
  const _ColLabel({required this.text, required this.color});
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 10, height: 3, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 6),
        Text(text,
            style: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: T.inkMd)),
      ],
    );
  }
}

enum _CellKind { home, draw, away, other }

class _ScoreCell extends StatelessWidget {
  const _ScoreCell({
    required this.option,
    required this.type,
    required this.selected,
    required this.flash,
    required this.locked,
    required this.onTap,
    this.myStake,
    this.inSlip = false,
  });

  final ScoreOption option;
  final _CellKind type;
  final bool selected;
  final String? flash;
  final bool locked;
  final VoidCallback? onTap;

  /// 用户已经在该比分上下注的总金额。非空表示该格子需要灰化、禁用,并显示已投金额。
  final double? myStake;

  /// 该比分已经被加入投注单 — 视觉上加紫色边 + 购物车图标提示。
  final bool inSlip;

  Color get _accent => switch (type) {
        _CellKind.home => T.brandDeep,
        _CellKind.draw => T.inkLo,
        _CellKind.away => T.brand2,
        _CellKind.other => T.gold,
      };

  Gradient get _bg => switch (type) {
        _CellKind.home => const LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Color(0xFFF2FBFF), Color(0xFFE8F4FF)],
          ),
        _CellKind.draw => const LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Color(0xFFF8FAFC), Color(0xFFEEF2F7)],
          ),
        _CellKind.away => const LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Color(0xFFF2F8FF), Color(0xFFE5F0FF)],
          ),
        _CellKind.other => const LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Color(0xFFFFF7EC), Color(0xFFFFEFD7)],
          ),
      };

  @override
  Widget build(BuildContext context) {
    final isUp = flash == 'up';
    final isDown = flash == 'down';
    final flashColor = isUp ? T.up : isDown ? T.down : null;
    final betted = myStake != null;
    final stakeFmt = betted ? NumberFormat('#,##0').format(myStake) : '';

    final BoxDecoration deco;
    if (betted) {
      deco = BoxDecoration(
        color: const Color(0xFFF1F4F8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD9DEE5), width: 1),
      );
    } else if (selected) {
      deco = BoxDecoration(
        gradient: T.brandGradientShort,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: T.brandDeep, width: 1),
        boxShadow: const [
          BoxShadow(color: Color(0x7311BAD9), blurRadius: 18, offset: Offset(0, 8))
        ],
      );
    } else {
      deco = BoxDecoration(
        gradient: _bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: T.border, width: 1),
        boxShadow: flashColor != null
            ? [
                BoxShadow(
                    color: flashColor.withValues(alpha: 0.5),
                    blurRadius: 14,
                    spreadRadius: 1)
              ]
            : const [
                BoxShadow(
                    color: Color(0x0A0E2238),
                    blurRadius: 4,
                    offset: Offset(0, 1))
              ],
      );
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      height: type == _CellKind.other ? 52 : 64,
      decoration: deco,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      type == _CellKind.other ? tr('detail.other_score') : option.score,
                      style: TextStyle(
                        fontSize: type == _CellKind.other ? 13 : 17,
                        fontWeight: FontWeight.w800,
                        color: betted
                            ? T.inkLo
                            : selected
                                ? Colors.white
                                : T.ink,
                        fontFamily: T.fontMono,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (betted)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE6EBF2),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: const Color(0xFFCBD3DD), width: 0.5),
                        ),
                        child: Text(
                          '${tr('detail.placed_stake')} $stakeFmt',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: T.inkMd,
                            fontFamily: T.fontMono,
                            height: 1.1,
                          ),
                        ),
                      )
                    else
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            option.price <= 0 ? '—' : option.price.toStringAsFixed(2),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: option.price <= 0
                                  ? T.inkLo
                                  : selected
                                      ? Colors.white
                                      : _accent,
                              fontFamily: T.fontMono,
                            ),
                          ),
                          if (flashColor != null) ...[
                            const SizedBox(width: 3),
                            Icon(
                              isUp ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                              size: 14,
                              color: selected ? Colors.white : flashColor,
                            ),
                          ],
                        ],
                      ),
                  ],
                ),
              ),
              if (betted)
                const Positioned(
                  top: 5, right: 5,
                  child: Icon(Icons.check_circle, size: 14, color: T.brandDeep),
                )
              else if (selected)
                const Positioned(
                  top: 5, right: 5,
                  child: _SelectedDot(),
                )
              else if (inSlip)
                const Positioned(
                  top: 5, right: 5,
                  child: Icon(Icons.shopping_cart, size: 12, color: T.brandDeep),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectedDot extends StatelessWidget {
  const _SelectedDot();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 16, height: 16,
      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [
        BoxShadow(color: Color(0x1F000000), blurRadius: 4, offset: Offset(0, 2)),
      ]),
      alignment: Alignment.center,
      child: const Icon(Icons.check, size: 10, color: T.brandDeep),
    );
  }
}

class _StakePreset extends StatelessWidget {
  const _StakePreset({required this.value, required this.label, required this.selected, required this.onTap});
  final double value;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? const Color(0x242CD7FD) : T.fill,
          border: Border.all(color: selected ? T.brand : T.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: selected ? T.brandDeep : T.inkMd)),
      ),
    );
  }
}

/// 二元下注格 — 用于大小球 / BTTS。两个对称选项,左右排开。
class _BinaryBetTile extends StatelessWidget {
  const _BinaryBetTile({
    required this.label,
    required this.hint,
    required this.price,
    required this.selected,
    required this.locked,
    required this.accent,
    required this.onTap,
    this.myStake,
    this.inSlip = false,
  });

  final String label;
  final String hint;
  final double price;
  final bool selected;
  final bool locked;
  final Color accent;
  final VoidCallback onTap;
  final double? myStake;
  final bool inSlip;

  @override
  Widget build(BuildContext context) {
    final betted = myStake != null;
    // price <= 0 表示该选项滚球期已不可投注(如已超过 OU line / 双方都进球后的 BTTS No)。
    final unavailable = price <= 0;
    final disabled = locked || betted || unavailable;
    final stakeFmt = betted ? NumberFormat('#,##0').format(myStake) : '';

    final BoxDecoration deco;
    if (betted) {
      deco = BoxDecoration(
        color: const Color(0xFFF1F4F8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD9DEE5), width: 1),
      );
    } else if (selected) {
      deco = BoxDecoration(
        gradient: T.brandGradientShort,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: T.brandDeep, width: 1),
        boxShadow: const [
          BoxShadow(color: Color(0x7311BAD9), blurRadius: 18, offset: Offset(0, 8))
        ],
      );
    } else {
      deco = BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: T.border, width: 1),
        boxShadow: const [
          BoxShadow(color: Color(0x0A0E2238), blurRadius: 4, offset: Offset(0, 1))
        ],
      );
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      height: 70,
      decoration: deco,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: disabled ? null : onTap,
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: betted
                                      ? T.inkLo
                                      : selected ? Colors.white : T.ink)),
                        ),
                        const SizedBox(width: 6),
                        if (betted)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE6EBF2),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: const Color(0xFFCBD3DD), width: 0.5),
                            ),
                            child: Text(
                              '${tr('detail.placed_stake')} $stakeFmt',
                              style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: T.inkMd,
                                  fontFamily: T.fontMono),
                            ),
                          )
                        else
                          Text(unavailable ? '—' : price.toStringAsFixed(2),
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  fontFamily: T.fontMono,
                                  color: unavailable
                                      ? T.inkLo
                                      : selected
                                          ? Colors.white
                                          : accent)),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(hint,
                        style: TextStyle(
                            fontSize: 10,
                            color: betted
                                ? T.inkLo
                                : selected ? Colors.white70 : T.inkLo,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              if (betted)
                const Positioned(
                  top: 6, right: 6,
                  child: Icon(Icons.check_circle, size: 14, color: T.brandDeep),
                )
              else if (inSlip)
                const Positioned(
                  top: 6, right: 6,
                  child: Icon(Icons.shopping_cart, size: 12, color: T.brandDeep),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 弹出式下注 sheet:筹码 slider + 5 预设 + 加入投注单 / 锁定下注双按钮。
/// 父页只在用户已选 [_BetSelection] 后才打开,所以这里 sel 必非空。
class _BetSheet extends StatefulWidget {
  const _BetSheet({
    required this.sel,
    required this.initialStake,
    required this.liveLocked,
    required this.onStakeChanged,
    required this.onAddToSlip,
    required this.onPlace,
  });

  final _BetSelection sel;
  final double initialStake;
  final bool liveLocked;
  final ValueChanged<double> onStakeChanged;
  final VoidCallback onAddToSlip;
  final VoidCallback onPlace;

  @override
  State<_BetSheet> createState() => _BetSheetState();
}

class _BetSheetState extends State<_BetSheet> {
  late double _stake;

  @override
  void initState() {
    super.initState();
    _stake = widget.initialStake;
  }

  void _set(double v) {
    setState(() => _stake = v);
    widget.onStakeChanged(v);
  }

  @override
  Widget build(BuildContext context) {
    final sel = widget.sel;
    final stakeFmt = NumberFormat('#,##0').format(_stake);
    final payout = _stake * sel.price;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(
          16, 8, 16, MediaQuery.of(context).viewInsets.bottom + 22),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36, height: 4, margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                  color: const Color(0xFFD9DEE5),
                  borderRadius: BorderRadius.circular(2)),
            ),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    gradient: T.brandGradientShort,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(sel.label,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 8),
                Text(tr('detail.bet_odds'), style: const TextStyle(fontSize: 11, color: T.inkLo)),
                const SizedBox(width: 4),
                Text(sel.price.toStringAsFixed(2),
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: T.gold,
                        fontFamily: T.fontMono)),
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(tr('detail.bet_payout'),
                        style: const TextStyle(fontSize: 10, color: T.inkLo, fontWeight: FontWeight.w600)),
                    Text('+${NumberFormat('#,##0.00').format(payout)} USDT',
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: T.up,
                            fontFamily: T.fontMono)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Text(tr('detail.bet_chip'),
                    style: const TextStyle(fontSize: 11, color: T.inkLo, fontWeight: FontWeight.w600)),
                const Spacer(),
                Text('$stakeFmt USDT',
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w800, color: T.ink, fontFamily: T.fontMono)),
              ],
            ),
            Slider(
              value: _stake.clamp(10, 10000),
              min: 10, max: 10000, divisions: 999,
              onChanged: (v) => _set(v),
            ),
            Row(
              children: [
                for (final p in const [10, 50, 100, 500, 1000])
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: _StakePreset(
                        value: p.toDouble(),
                        label: p >= 1000 ? '${p ~/ 1000}K' : '$p',
                        selected: _stake == p,
                        onTap: () => _set(p.toDouble()),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                SizedBox(
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: widget.liveLocked ? null : widget.onAddToSlip,
                    icon: const Icon(Icons.add_shopping_cart, size: 16),
                    label: Text(tr('detail.add_slip'),
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: T.brandDeep,
                      side: const BorderSide(color: T.brand),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: widget.liveLocked ? null : widget.onPlace,
                      icon: const Icon(Icons.lock_outline, size: 16),
                      label: Text(
                        tr('detail.bet_lock_format')
                            .replaceAll('{score}', sel.label)
                            .replaceAll('{stake}', stakeFmt),
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                        overflow: TextOverflow.ellipsis,
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: T.brand,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        elevation: 6,
                        shadowColor: const Color(0x4D11BAD9),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Visual descriptor for one row in the live-stats panel.
class _StatRow {
  final String label;
  final String key;
  final int home;
  final int away;
  const _StatRow(this.label, this.key, this.home, this.away);

  Color get color {
    switch (key) {
      case 'corners':
        return const Color(0xFFFF9800);
      case 'yellow':
        return const Color(0xFFFBC02D);
      case 'red':
        return T.down;
      case 'shots':
      case 'shotsOnTarget':
        return T.brandDeep;
    }
    return T.brandDeep;
  }
}

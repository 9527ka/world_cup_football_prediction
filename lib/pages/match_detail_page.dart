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

/// 格式化 line 值:quarter (.25/.75) 用 2 位小数,其他用 1 位。
/// 皇冠惯例:0.25 显示 "0.25" 而非 "0.3",0.5 显示 "0.5",1.0 显示 "1.0"。
String _fmtLine(double v) {
  final frac = (v.abs() - v.abs().truncateToDouble()).abs();
  final isQ = (frac > 0.20 && frac < 0.30) || (frac > 0.70 && frac < 0.80);
  return isQ ? v.toStringAsFixed(2) : v.toStringAsFixed(1);
}

/// AH line label for bet slip: "+0.5", "-0.25", "0" (no sign for zero).
String _ahLineLabel(double line) {
  if (line.abs() < 0.001) return '0';
  return line > 0 ? '+${_fmtLine(line)}' : _fmtLine(line);
}

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

final _fmtBal = NumberFormat('#,##0.00');
final _fmtStake = NumberFormat('#,##0');
final _fmtDate = DateFormat('MM-dd . HH:mm');

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

  /// 30s 兜底主动拉 match snapshot(WS 漏掉时也能更新比分/角球)。
  /// 后端 getMatch 直接从内存 snapshot 取,零 API 配额消耗。
  Timer? _matchPollTimer;

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
  double _drawerHeight = 230;
  bool _drawerMeasurePending = false;

  /// ── 性能优化:WS odds 节流 ────────────────────────────────────
  /// 高频赛事赔率推送可达数次/秒,每次 setState 重建 2800+ 行 widget tree 是卡顿根因。
  /// 用 150ms 节流收拢为 ≤7 次/秒,体感平滑且大幅降低 build 开销。
  Timer? _oddsThrottle;
  OddsSnapshot? _pendingOdds;

  /// ── 性能优化:WS matches 节流 ─────────────────────────────────
  Timer? _matchThrottle;
  MatchInfo? _pendingMatch;

  /// ── 性能优化:lock 倒计时用 ValueNotifier 隔离 ─────────────────
  /// 进球封盘倒计时(1s/tick)只需更新底部 drawer 的秒数文本,不应触发全页 setState。
  /// 改用 ValueNotifier + ValueListenableBuilder 把重建范围限制在 drawer 内。
  final ValueNotifier<int> _lockSecsNotifier = ValueNotifier<int>(0);

  /// ── 性能优化:波胆排序缓存 ────────────────────────────────────
  /// _scoreGrid() 每次 build 都对 3 个列做 O(n log n) sort,WS 每推一次赔率
  /// 就执行 3 次排序。改为在 _odds 变更时一次性算好,build 直接读缓存。
  List<ScoreOption> _sortedCSHome = const [];
  List<ScoreOption> _sortedCSDraw = const [];
  List<ScoreOption> _sortedCSAway = const [];
  ScoreOption? _sortedCSOther;
  OddsSnapshot? _csGridOddsRef; // 用于检测是否需要重算

  // 只有 settled(已结束)的比赛完全锁住下注。pending 和 live 都允许投注。
  bool get _locked => _match.isSettled;
  bool get _isLive => _match.isLive;

  /// 85+ 分钟 / 加时阶段:赔率冻结,按钮保留可见但不可下注。
  /// tap 任何赔率按钮 → 弹"已封盘"toast,不进入下注流程。
  bool get _marketsClosed => _odds?.marketsClosedFinal == true;

  /// 用户 tap 一个赔率按钮:封盘期弹 toast,否则把选项设为当前 _selected。
  /// 13 处 cell onTap 统一走这里,封盘门控集中化。
  void _trySelect(_BetSelection sel) {
    if (_marketsClosed) {
      Toast.show(context, tr('detail.live_locked_title'), kind: 'warn');
      return;
    }
    setState(() => _selected = sel);
  }
  bool get _hasLiveStats {
    final ld = _match.live;
    if (ld == null) return false;
    return ld.statsAvailable;
  }
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
    // ── 赔率推送:150ms 节流,避免高频 setState 导致掉帧 ──────────
    _sub = widget.state.stream.odds.listen((s) {
      if (s.matchId != widget.match.id || !mounted) return;
      _pendingOdds = s;
      if (_oddsThrottle != null) return; // 已在等待中,攒到下一 tick
      _oddsThrottle = Timer(const Duration(milliseconds: 150), _flushOdds);
    });
    // ── match 推送:300ms 节流 ────────────────────────────────────
    _matchesSub = widget.state.stream.matches.listen((list) {
      if (!mounted) return;
      for (final m in list) {
        if (m.id == widget.match.id) {
          _pendingMatch = m;
          if (_matchThrottle != null) return;
          _matchThrottle = Timer(const Duration(milliseconds: 300), _flushMatch);
          break;
        }
      }
    });
    final futures = <Future>[];
    futures.add(widget.state.api.getOdds(widget.match.id).then((v) {
      if (mounted) setState(() => _odds = v);
    }).catchError((_) {}));
    if (widget.state.isAuthenticated) {
      futures.add(widget.state.api.getStats().then((s) {
        if (mounted) setState(() => _stats = s);
      }).catchError((_) {}));
      futures.add(_loadMyBets());
    }
    futures.add(_refreshHistory());
    await Future.wait(futures);
    if (!_locked) {
      _historyTimer = Timer.periodic(const Duration(seconds: 30), (_) => _refreshHistory());
    }

    // 滚球封盘倒计时 — 仅在有 lockUntil 时才跑 1s 计时器,lock 到期自动停。
    _maybeStartLockTimer();

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

    // 30s 主动拉 match snapshot 兜底 — WS 推送漏掉/网络抖动时也能跟上。
    // 仅对 live 比赛跑(已结束的不需要),settled 后 timer 自动 cancel。
    if (_isLive) {
      _matchPollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        _refreshMatchSnapshot();
      });
    }
  }

  /// 主动拉 match snapshot — pull-to-refresh + 30s 定时调用。
  /// 后端 getMatch handler 直接从 fetcher snapshot 取,无 API 配额消耗。
  Future<void> _refreshMatchSnapshot() async {
    try {
      final fresh = await widget.state.api.getMatch(widget.match.id);
      if (!mounted) return;
      setState(() => _match = fresh);
      // 比赛结束 → 停掉自己的 polling 避免无用请求
      if (!_isLive && _matchPollTimer != null) {
        _matchPollTimer?.cancel();
        _matchPollTimer = null;
      }
    } catch (_) {/* 静默 — 下个周期重试 */}
  }

  /// ── 节流 flush 回调 ─────────────────────────────────────────────
  void _flushOdds() {
    _oddsThrottle = null;
    final s = _pendingOdds;
    if (s == null || !mounted) return;
    _pendingOdds = null;
    _diffAndFlash(_odds, s);
    final hadLock = _odds?.lockUntil;
    setState(() {
      _odds = s;
      if (_selected != null) {
        final live = _priceForSelection(_selected!, s);
        if (live <= 0) {
          _selected = null;
        } else if ((live - _selected!.price).abs() > 0.005) {
          _selected = _BetSelection(
            marketType: _selected!.marketType,
            score: _selected!.score,
            price: live,
            label: _selected!.label,
          );
        }
      }
    });
    if (s.lockUntil != hadLock) _maybeStartLockTimer();
  }

  void _flushMatch() {
    _matchThrottle = null;
    final m = _pendingMatch;
    if (m == null || !mounted) return;
    _pendingMatch = null;
    setState(() => _match = m);
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
      case MarketType.htOverUnder:
        // score 必须带 line:"over@1.5" 等。
        final atH = sel.score.lastIndexOf('@');
        if (atH <= 0) return 0;
        final sideH = sel.score.substring(0, atH);
        final lineH = double.tryParse(sel.score.substring(atH + 1)) ?? 0;
        for (final ou in s.htOverUnders) {
          if ((ou.line - lineH).abs() < 0.01) {
            if (sideH == 'over') return ou.over;
            if (sideH == 'under') return ou.under;
          }
        }
        return 0;
      case MarketType.btts:
        final b = s.btts;
        if (b == null) return 0;
        if (sel.score == 'yes') return b.yes;
        if (sel.score == 'no') return b.no;
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
        // 走地让球 score 格式: "home@+0.5" / "away@-1.0"
        final atIdx = sel.score.lastIndexOf('@');
        if (atIdx > 0) {
          final side = sel.score.substring(0, atIdx);
          final lineVal = double.tryParse(sel.score.substring(atIdx + 1)) ?? 0;
          for (final hh in s.handicaps) {
            if ((hh.line - lineVal).abs() < 0.01) {
              return side == 'home' ? hh.home : hh.away;
            }
          }
          return 0;
        }
        // 赛前单线 AH
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
        localizedTeam(m.home, apiZh: m.homeZh).toJS,
        localizedTeam(m.away, apiZh: m.awayZh).toJS,
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
    if (!_isLive && !_match.isSettled) return;
    await Future.wait([
      widget.state.api.getMatchStats(widget.match.id).then((r) {
        if (mounted) setState(() { _statsHome = r.home; _statsAway = r.away; });
      }).catchError((_) {}),
      widget.state.api.getMatchEvents(widget.match.id).then((ev) {
        if (mounted) setState(() => _events = ev);
      }).catchError((_) {}),
    ]);
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

  void _maybeStartLockTimer() {
    final lu = _odds?.lockUntil;
    if (lu != null && lu.isAfter(DateTime.now())) {
      _lockSecsNotifier.value = lu.difference(DateTime.now()).inSeconds.clamp(0, 99);
      if (_lockTickTimer?.isActive == true) return;
      _lockTickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        final lu2 = _odds?.lockUntil;
        if (lu2 == null || lu2.isBefore(DateTime.now())) {
          _lockTickTimer?.cancel();
          _lockTickTimer = null;
          _lockSecsNotifier.value = 0;
          // 封盘→解锁转换:需要一次 setState 更新 _liveLocked 相关 UI
          setState(() {});
          return;
        }
        // 只更新 ValueNotifier,不触发全页 setState
        _lockSecsNotifier.value = lu2.difference(DateTime.now()).inSeconds.clamp(0, 99);
      });
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
    _matchPollTimer?.cancel();
    _oddsThrottle?.cancel();
    _matchThrottle?.cancel();
    _lockSecsNotifier.dispose();
    for (final t in _flashTimers.values) {
      t.cancel();
    }
    super.dispose();
  }

  Future<void> _place() async {
    final sel = _selected;
    if (sel == null) return;
    if (_placing) return; // double-tap guard
    if (_liveLocked) return; // goal lock — backend would also reject (423)
    if (_marketsClosed) {
      Toast.show(context, tr('detail.live_locked_title'), kind: 'warn');
      return;
    }
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
    if (!_drawerMeasurePending) {
      _drawerMeasurePending = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _drawerMeasurePending = false;
        final ctx = _drawerKey.currentContext;
        if (ctx == null || !mounted) return;
        final box = ctx.findRenderObject() as RenderBox?;
        if (box == null || !box.hasSize) return;
        final h = box.size.height;
        if ((h - _drawerHeight).abs() > 2) {
          setState(() => _drawerHeight = h);
        }
      });
    }
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
                child: RefreshIndicator(
                  color: T.brandDeep,
                  // 下拉刷新:同时拉 match snapshot(比分/角球) + stats + events,
                  // 比 30s 自动 polling 更即时,适合用户手动催更新。
                  onRefresh: () async {
                    await Future.wait([
                      _refreshMatchSnapshot(),
                      _refreshStatsAndEvents(),
                    ]);
                  },
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(0, 0, 0, bottomPad),
                    // RefreshIndicator 要 ListView 永远可滚动才能下拉触发
                    physics: const AlwaysScrollableScrollPhysics(),
                    addRepaintBoundaries: true,
                    children: [
                      _hero(),
                      if (_locked) _lockedBanner(),
                      if (_isLive && !_locked) _liveBanner(),
                      if (_statsHome.isNotEmpty || _statsAway.isNotEmpty || _hasLiveStats)
                        _liveStatsSection(),
                      if (_events.isNotEmpty) _eventsTimelineSection(),
                      _sectionHeader(),
                      _columnLabels(),
                      RepaintBoundary(child: _scoreGrid()),
                      RepaintBoundary(child: _winnerSection()),
                      RepaintBoundary(child: _handicapSection()),
                      RepaintBoundary(child: _overUnderSection()),
                      RepaintBoundary(child: _htOverUnderSection()),
                      RepaintBoundary(child: _bttsSection()),
                    ],
                  ),
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
                Text(_fmtBal.format(_stats!.balance),
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
    final fmt = _fmtDate;
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
                      Text(localizedTeam(m.home, apiZh: m.homeZh),
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
                      if (_isLive || _locked) ...[
                        _heroStatusBadge(m),
                        const SizedBox(height: 4),
                      ],
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
                      // 半场比分 + 角球/黄牌一行概要(仅 live/settled 时有数据)
                      if (m.scores != null) _heroMiniStats(m),
                      const SizedBox(height: 4),
                      Text(fmt.format(m.date),
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
                      Text(localizedTeam(m.away, apiZh: m.awayZh),
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

  /// 比分下方迷你统计行:半场比分 / 角球 / 黄牌,紧凑一行,跟懂球帝对齐。
  Widget _heroMiniStats(MatchInfo m) {
    final parts = <String>[];
    // 半场比分
    final ht = m.scores?.periods?['1H'];
    if (ht != null) {
      parts.add('${tr('stats.ht_short')} ${ht.home}-${ht.away}');
    }
    // 角球 / 黄牌优先取 live 字段(WS 秒级),fallback 到 polling stats
    final ld = m.live;
    final hasLive = ld != null && ld.statsAvailable;
    final corH = hasLive ? ld.homeCorners : (_statsHome['corners'] ?? 0);
    final corA = hasLive ? ld.awayCorners : (_statsAway['corners'] ?? 0);
    if (hasLive || corH > 0 || corA > 0) {
      parts.add('${tr('stats.corner_short')} $corH-$corA');
    }
    final yelH = hasLive ? ld.homeYellow : (_statsHome['yellow'] ?? 0);
    final yelA = hasLive ? ld.awayYellow : (_statsAway['yellow'] ?? 0);
    if (hasLive || yelH > 0 || yelA > 0) {
      parts.add('${tr('stats.yellow_short')} $yelH-$yelA');
    }
    if (parts.isEmpty) return const SizedBox(height: 4);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(parts.join(' · '),
          style: const TextStyle(fontSize: 10, color: T.inkLo, fontWeight: FontWeight.w600)),
    );
  }

  /// 比分上方状态徽章:live 时显示比赛分钟(自走),settled 时显示"已结束"。
  Widget _heroStatusBadge(MatchInfo m) {
    final isLive = m.isLive;
    String text;
    Color bg;
    Color fg;
    if (isLive) {
      text = _heroLiveMinute(m);
      bg = const Color(0x22E03E2D);
      fg = T.down;
    } else {
      // settled / voided
      text = tr('detail.status_ft');
      bg = const Color(0xFFEEF2F7);
      fg = T.inkLo;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w800, color: fg)),
    );
  }

  /// 详情页 hero 比赛分钟 — 与列表页 _liveMinuteText 同算法(asOf 自走 +2min 封顶)。
  String _heroLiveMinute(MatchInfo m) {
    final ld = m.live;
    if (ld != null) {
      final pl = ld.periodLabel;
      if (pl == 'HT') return tr('live.minute_ht');
      if (pl == 'PEN') return tr('live.minute_pen');
      if (pl == 'BT') return ld.minuteDisplay;
      if (ld.extra > 0) return '${ld.minute}+${ld.extra}\'';
    }
    final upMin = ld?.minute ?? 0;
    final elapsedFromKickoff = DateTime.now().difference(m.date).inMinutes;
    if (elapsedFromKickoff > 150) return tr('live.minute_ft');
    int mins;
    if (upMin == 0) {
      mins = elapsedFromKickoff.clamp(1, 45);
    } else {
      var advance = upMin;
      final asOf = ld?.asOf;
      if (asOf != null) {
        final since = DateTime.now().difference(asOf).inSeconds;
        if (since > 0) {
          final addMin = (since ~/ 60).clamp(0, 2);
          advance = upMin + addMin;
        }
      }
      final period = ld?.periodLabel ?? '';
      if (period == '1H' && upMin < 45) {
        if (advance > 45) advance = 45;
      } else if (period != '1H' && upMin < 90) {
        if (advance > 90) advance = 90;
      }
      mins = advance;
    }
    if (mins < 1) mins = 1;
    if (mins > 90) return '90+${mins - 90}\'';
    if (mins > 45 && (ld?.periodLabel == '1H')) return '45+${mins - 45}\'';
    return "$mins'";
  }

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
    // corners / yellow / red 三项优先用 WS push 的 _match.live(秒级新鲜),
    // 与列表页同源,避免出现"列表显示 5 角,详情显示 4 角"的不一致。
    // shots / shotsOnTarget 走 60s polling stats(LiveDetail 没这两项)。
    final ld = _match.live;
    int corH = _statsHome['corners'] ?? 0;
    int corA = _statsAway['corners'] ?? 0;
    int yelH = _statsHome['yellow'] ?? 0;
    int yelA = _statsAway['yellow'] ?? 0;
    int redH = _statsHome['red'] ?? 0;
    int redA = _statsAway['red'] ?? 0;
    if (ld != null) {
      // 仅当 WS 数据 >= polling 数据时覆盖,防止旧 WS 帧倒退已 polling 的新数据
      if (ld.homeCorners > corH || ld.awayCorners > corA) {
        corH = ld.homeCorners;
        corA = ld.awayCorners;
      }
      if (ld.homeYellow > yelH || ld.awayYellow > yelA) {
        yelH = ld.homeYellow;
        yelA = ld.awayYellow;
      }
      if (ld.homeRed > redH || ld.awayRed > redA) {
        redH = ld.homeRed;
        redA = ld.awayRed;
      }
    }
    final rows = <_StatRow>[
      _StatRow(tr('stats.corners'), 'corners', corH, corA),
      _StatRow(tr('stats.yellow'), 'yellow', yelH, yelA),
      _StatRow(tr('stats.red'), 'red', redH, redA),
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
                          (I18n.instance.locale == 'zh' && e.playerZh != null && e.playerZh!.isNotEmpty)
                              ? e.playerZh!
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

  /// 一次性对波胆按主/平/客分类+排序,build 直接读缓存。
  void _rebuildCSGridCache() {
    final scores = _odds?.correctScore ?? const [];
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
    _sortedCSHome = home;
    _sortedCSDraw = draw;
    _sortedCSAway = away;
    _sortedCSOther = other;
    _csGridOddsRef = _odds;
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
    // 仅在 _odds 对象引用变更时才重算(WS 每次推送替换整个 snapshot)
    if (!identical(_csGridOddsRef, _odds)) {
      _rebuildCSGridCache();
    }
    final home = _sortedCSHome;
    final draw = _sortedCSDraw;
    final away = _sortedCSAway;
    final other = _sortedCSOther;
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
                                onTap: disabled ? null : () => _trySelect(_BetSelection(
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
              final opt = other;
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
                onTap: disabled ? null : () => _trySelect(_BetSelection(
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
    final List<OverUnderLine> lines = (_odds?.overUnders.isNotEmpty == true
        ? _odds!.overUnders
        : (_odds?.overUnder != null ? [_odds!.overUnder!] : const <OverUnderLine>[]))
        .where((l) => l.over > 0 || l.under > 0)
        .toList();
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
    final lineFmt = _fmtLine(currentLine.line);
    final overScore = 'over@$lineFmt';
    final underScore = 'under@$lineFmt';
    // 走地标识 + 当前比分 chip
    final isLive = _match.isLive;
    final curHome = _match.scores?.home ?? 0;
    final curAway = _match.scores?.away ?? 0;
    final curTotal = curHome + curAway;

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
                if (currentLine.isWalking) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFEFD5),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(tr('detail.walking_tag'),
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFFD97706))),
                  ),
                ],
              ],
            ),
          ),
          if (isLive && lines.any((l) => l.isWalking))
            Padding(
              padding: const EdgeInsets.only(bottom: 6, left: 2),
              child: Text(tr('detail.ou_live_score').replaceAll('{home}', '$curHome').replaceAll('{away}', '$curAway').replaceAll('{total}', '$curTotal'),
                  style: const TextStyle(fontSize: 11, color: T.inkLo)),
            ),
          // line picker:多线时显示,单线时省略(等价旧 UI)。
          if (lines.length > 1) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 8, left: 2),
              child: Wrap(
                spacing: 6,
                children: lines.map((l) {
                  final fmt = _fmtLine(l.line);
                  final sel = (l.line - selectedLine).abs() < 0.01;
                  return ChoiceChip(
                    label: Text(l.isWalking ? tr('detail.ou_chip_walking').replaceAll('{line}', fmt) : fmt, style: TextStyle(
                      fontSize: 12,
                      fontWeight: sel ? FontWeight.w800 : FontWeight.w600,
                      color: sel ? Colors.white : T.ink,
                    )),
                    selected: sel,
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    selectedColor: l.isWalking ? const Color(0xFFD97706) : T.brandDeep,
                    backgroundColor: l.isWalking ? const Color(0xFFFFEFD5) : const Color(0xFFEAF1F8),
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
                  onTap: () => _trySelect(_BetSelection(
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
                  onTap: () => _trySelect(_BetSelection(
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
          onTap: () => _trySelect(_BetSelection(
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
              tile('home', tr('detail.win_home'), localizedTeam(widget.match.home, apiZh: widget.match.homeZh), ml.home, T.up),
              const SizedBox(width: 8),
              tile('draw', tr('detail.draw'), tr('detail.winner_draw_hint'), ml.draw, T.brandDeep),
              const SizedBox(width: 8),
              tile('away', tr('detail.win_away'), localizedTeam(widget.match.away, apiZh: widget.match.awayZh), ml.away, T.down),
            ],
          ),
        ],
      ),
    );
  }

  // 让球(Asian Handicap)— line + home/away 两选项。
  // 走地阶段(2026-05-25):后端在 odds.handicaps 提供 3 条 fair±0.5 line。
  // 用户可在 picker 切换 line,选 home/away 下走地单(baseline 模式,下单时
  // 服务端记录当前比分,settle 按 net 差判定)。
  Widget _handicapSection() {
    final walkingLines = _odds?.handicaps ?? const <HandicapMarket>[];
    final isWalking = _match.isLive && walkingLines.isNotEmpty;
    HandicapMarket? h;
    if (isWalking) {
      // 走地:从 walkingLines 里选 currentLine
      double selectedLine;
      if (_selected?.marketType == MarketType.asianHandicap) {
        final s = _selected!.score;
        final at = s.lastIndexOf('@');
        selectedLine = at > 0 ? double.tryParse(s.substring(at + 1)) ?? walkingLines.first.line : walkingLines.first.line;
      } else {
        selectedLine = walkingLines.first.line;
      }
      if (!walkingLines.any((l) => (l.line - selectedLine).abs() < 0.01)) {
        selectedLine = walkingLines.first.line;
      }
      h = walkingLines.firstWhere((l) => (l.line - selectedLine).abs() < 0.01);
    } else {
      h = _odds?.handicap;
    }
    if (h == null) return const SizedBox.shrink();
    final curHome = _match.scores?.home ?? 0;
    final curAway = _match.scores?.away ?? 0;
    final lineStr = h.line > 0
        ? '+${_fmtLine(h.line)}'
        : h.line < 0
            ? _fmtLine(h.line)
            : '0';
    String homeHint, awayHint;
    if (h.line < 0) {
      // 主队让球
      homeHint = tr('detail.ah_home_give').replaceAll('{n}', _fmtLine(-h.line));
      awayHint = tr('detail.ah_away_take').replaceAll('{n}', _fmtLine(-h.line));
    } else if (h.line > 0) {
      // 主队受让
      homeHint = tr('detail.ah_home_take').replaceAll('{n}', _fmtLine(h.line));
      awayHint = tr('detail.ah_away_give').replaceAll('{n}', _fmtLine(h.line));
    } else {
      // 平手盘
      homeHint = tr('detail.ah_level');
      awayHint = tr('detail.ah_level');
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
                if (isWalking) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFEFD5),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(tr('detail.walking_tag'),
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFFD97706))),
                  ),
                ],
              ],
            ),
          ),
          if (isWalking)
            Padding(
              padding: const EdgeInsets.only(bottom: 6, left: 2),
              child: Text(tr('detail.ah_baseline_info').replaceAll('{home}', '$curHome').replaceAll('{away}', '$curAway'),
                  style: const TextStyle(fontSize: 11, color: T.inkLo)),
            ),
          if (isWalking && walkingLines.length > 1) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 8, left: 2),
              child: Wrap(
                spacing: 6,
                children: walkingLines.map((l) {
                  final fmt = l.line >= 0 ? '+${_fmtLine(l.line)}' : _fmtLine(l.line);
                  final sel = (l.line - h!.line).abs() < 0.01;
                  return ChoiceChip(
                    label: Text(fmt, style: TextStyle(
                      fontSize: 12,
                      fontWeight: sel ? FontWeight.w800 : FontWeight.w600,
                      color: sel ? Colors.white : T.ink,
                    )),
                    selected: sel,
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    selectedColor: const Color(0xFFD97706),
                    backgroundColor: const Color(0xFFFFEFD5),
                    onSelected: (_) => setState(() {
                      // 切换 line 时:如果当前选了 home/away,迁移到新 line。
                      String? side;
                      if (_selected?.marketType == MarketType.asianHandicap) {
                        final s = _selected!.score;
                        final at = s.lastIndexOf('@');
                        side = at > 0 ? s.substring(0, at) : s;
                        if (side != 'home' && side != 'away') side = null;
                      }
                      if (side != null) {
                        final p = side == 'home' ? l.home : l.away;
                        _selected = _BetSelection(
                          marketType: MarketType.asianHandicap,
                          score: '$side@$fmt',
                          price: p,
                          label: '${tr('detail.handicap_title')} · ${side == 'home' ? localizedTeam(widget.match.home, apiZh: widget.match.homeZh) : localizedTeam(widget.match.away, apiZh: widget.match.awayZh)} $fmt',
                        );
                      } else {
                        _selected = _BetSelection(
                          marketType: MarketType.asianHandicap,
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
          Builder(builder: (_) {
            // 走地必须带 line(后端 odds.handicaps 多线匹配);赛前为兼容老路径不带 line。
            final HandicapMarket hh = h!; // Dart 闭包内提升非空
            final scoreHome = isWalking ? 'home@$lineStr' : 'home';
            final scoreAway = isWalking ? 'away@$lineStr' : 'away';
            final slipKeyHome = isWalking ? '${MarketType.asianHandicap}::home@$lineStr' : '${MarketType.asianHandicap}::home';
            final slipKeyAway = isWalking ? '${MarketType.asianHandicap}::away@$lineStr' : '${MarketType.asianHandicap}::away';
            return Row(
              children: [
                Expanded(
                  child: _BinaryBetTile(
                    label: localizedTeam(widget.match.home, apiZh: widget.match.homeZh),
                    hint: homeHint,
                    price: hh.home,
                    selected: _selected?.marketType == MarketType.asianHandicap &&
                        _selected?.score == scoreHome,
                    myStake: _myBets[slipKeyHome],
                    inSlip: widget.state.betSlip.containsKey(
                        '${widget.match.id}::$slipKeyHome'),
                    locked: _locked,
                    accent: T.up,
                    onTap: () => _trySelect(_BetSelection(
                          marketType: MarketType.asianHandicap,
                          score: scoreHome,
                          price: hh.home,
                          label: '${tr('detail.handicap_title')} · ${localizedTeam(widget.match.home, apiZh: widget.match.homeZh)} ${_ahLineLabel(hh.line)}',
                        )),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _BinaryBetTile(
                    label: localizedTeam(widget.match.away, apiZh: widget.match.awayZh),
                    hint: awayHint,
                    price: hh.away,
                    selected: _selected?.marketType == MarketType.asianHandicap &&
                        _selected?.score == scoreAway,
                    myStake: _myBets[slipKeyAway],
                    inSlip: widget.state.betSlip.containsKey(
                        '${widget.match.id}::$slipKeyAway'),
                    locked: _locked,
                    accent: T.down,
                    onTap: () => _trySelect(_BetSelection(
                          marketType: MarketType.asianHandicap,
                          score: scoreAway,
                          price: hh.away,
                          label: '${tr('detail.handicap_title')} · ${localizedTeam(widget.match.away, apiZh: widget.match.awayZh)} ${_ahLineLabel(-hh.line)}',
                        )),
                  ),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }

  // 上半场大小球(走地 only,minute<41 时开盘)
  Widget _htOverUnderSection() {
    if (!_isLive) return const SizedBox.shrink();
    final htLines = (_odds?.htOverUnders ?? const <OverUnderLine>[])
        .where((l) => l.over > 0 || l.under > 0)
        .toList();
    if (htLines.isEmpty) return const SizedBox.shrink();
    // 当前选中 line
    double selectedLine;
    if (_selected?.marketType == MarketType.htOverUnder) {
      final s = _selected!.score;
      final at = s.lastIndexOf('@');
      selectedLine = at > 0 ? double.tryParse(s.substring(at + 1)) ?? htLines.first.line : htLines.first.line;
    } else {
      selectedLine = htLines.first.line;
    }
    if (!htLines.any((l) => (l.line - selectedLine).abs() < 0.01)) {
      selectedLine = htLines.first.line;
    }
    final cur = htLines.firstWhere((l) => (l.line - selectedLine).abs() < 0.01);
    final lineFmt = _fmtLine(cur.line);
    final scoreOver = 'over@$lineFmt';
    final scoreUnder = 'under@$lineFmt';
    final periods = _match.scores?.periods;
    final ht = periods?['1H'];
    final htHome = ht?.home ?? _match.scores?.home ?? 0;
    final htAway = ht?.away ?? _match.scores?.away ?? 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 2),
            child: Row(
              children: [
                const Icon(Icons.hourglass_top, size: 14, color: Color(0xFFD97706)),
                const SizedBox(width: 5),
                Text(tr('detail.htou_title').replaceAll('{line}', lineFmt),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: T.ink)),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFEFD5),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(tr('detail.walking_tag'),
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFFD97706))),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 6, left: 2),
            child: Text(tr('detail.htou_score_info').replaceAll('{home}', '$htHome').replaceAll('{away}', '$htAway'),
                style: const TextStyle(fontSize: 11, color: T.inkLo)),
          ),
          if (htLines.length > 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 8, left: 2),
              child: Wrap(
                spacing: 6,
                children: htLines.map((l) {
                  final fmt = _fmtLine(l.line);
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
                    selectedColor: const Color(0xFFD97706),
                    backgroundColor: const Color(0xFFFFEFD5),
                    onSelected: (_) => setState(() {
                      String? side;
                      if (_selected?.marketType == MarketType.htOverUnder) {
                        final s = _selected!.score;
                        final at = s.lastIndexOf('@');
                        side = at > 0 ? s.substring(0, at) : s;
                        if (side != 'over' && side != 'under') side = null;
                      }
                      if (side != null) {
                        final p = side == 'over' ? l.over : l.under;
                        _selected = _BetSelection(
                          marketType: MarketType.htOverUnder,
                          score: '$side@$fmt',
                          price: p,
                          label: side == 'over'
                              ? tr('detail.htou_over_sel').replaceAll('{line}', fmt)
                              : tr('detail.htou_under_sel').replaceAll('{line}', fmt),
                        );
                      }
                    }),
                  );
                }).toList(),
              ),
            ),
          Row(children: [
            Expanded(
              child: _BinaryBetTile(
                label: tr('detail.htou_over_label').replaceAll('{line}', lineFmt),
                hint: tr('detail.htou_over_hint').replaceAll('{line}', lineFmt),
                price: cur.over,
                selected: _selected?.marketType == MarketType.htOverUnder && _selected?.score == scoreOver,
                myStake: _myBets['${MarketType.htOverUnder}::$scoreOver'],
                inSlip: widget.state.betSlip.containsKey('${widget.match.id}::${MarketType.htOverUnder}::$scoreOver'),
                locked: _locked,
                accent: const Color(0xFFD97706),
                onTap: () => _trySelect(_BetSelection(
                  marketType: MarketType.htOverUnder,
                  score: scoreOver,
                  price: cur.over,
                  label: tr('detail.htou_over_sel').replaceAll('{line}', lineFmt),
                )),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _BinaryBetTile(
                label: tr('detail.htou_under_label').replaceAll('{line}', lineFmt),
                hint: tr('detail.htou_under_hint').replaceAll('{line}', lineFmt),
                price: cur.under,
                selected: _selected?.marketType == MarketType.htOverUnder && _selected?.score == scoreUnder,
                myStake: _myBets['${MarketType.htOverUnder}::$scoreUnder'],
                inSlip: widget.state.betSlip.containsKey('${widget.match.id}::${MarketType.htOverUnder}::$scoreUnder'),
                locked: _locked,
                accent: const Color(0xFFD97706),
                onTap: () => _trySelect(_BetSelection(
                  marketType: MarketType.htOverUnder,
                  score: scoreUnder,
                  price: cur.under,
                  label: tr('detail.htou_under_sel').replaceAll('{line}', lineFmt),
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
                  onTap: () => _trySelect(_BetSelection(
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
                  onTap: () => _trySelect(_BetSelection(
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
  /// 选中波胆/玩法之前:灰按钮"请先选择赔率",不可点
  /// 选中后:亮蓝按钮"立即下注 · {label} @ {odds}",点击弹出 [_buildBetSheet]
  /// 滚球封盘期间:倒计时占位,不可点(用 ValueListenableBuilder 隔离秒数重建)
  /// 85+ 分钟终场封盘:静态"已封盘",不可点
  Widget _betDrawer() {
    // 85+ 分钟终场封盘优先级最高,所有按钮统一禁用展示
    if (_marketsClosed) {
      return _betDrawerShell(
        label: tr('detail.live_locked_title'),
        ready: false,
        onTap: null,
      );
    }
    // 封盘倒计时走 ValueNotifier 路径,避免每秒全页 setState
    if (_liveLocked) {
      return ValueListenableBuilder<int>(
        valueListenable: _lockSecsNotifier,
        builder: (_, secs, __) {
          final label = tr('detail.bet_live_locked').replaceAll('{secs}', '$secs');
          return _betDrawerShell(label: label, ready: false, onTap: null);
        },
      );
    }
    final sel = _selected;
    final ready = sel != null;
    String label;
    if (sel == null) {
      label = tr('detail.bet_lock_pending');
    } else {
      label = '${tr('detail.bet_quick_open')} · ${sel.label} @ ${sel.price.toStringAsFixed(2)}';
    }
    return _betDrawerShell(label: label, ready: ready, onTap: ready ? _showBetSheet : null);
  }

  Widget _betDrawerShell({required String label, required bool ready, required VoidCallback? onTap}) {
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
            onTap: onTap,
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
    if (_marketsClosed) {
      Toast.show(context, tr('detail.live_locked_title'), kind: 'warn');
      return;
    }
    final m = _match;
    widget.state.betSlip.add(BetSelection(
      matchId: m.id,
      home: m.home,
      away: m.away,
      homeZh: m.homeZh,
      awayZh: m.awayZh,
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
    final stakeFmt = betted ? _fmtStake.format(myStake) : '';

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
    final stakeFmt = betted ? _fmtStake.format(myStake) : '';

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
    final stakeFmt = _fmtStake.format(_stake);
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
                    Text('+${_fmtBal.format(payout)} USDT',
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

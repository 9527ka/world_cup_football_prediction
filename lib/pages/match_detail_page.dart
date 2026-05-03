import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/match.dart';
import '../services/app_state.dart';
import '../services/bet_slip.dart';
import '../services/i18n.dart';
import '../theme/tokens.dart';
import '../utils/league_flags.dart';
import '../utils/team_crests.dart';
import '../utils/team_names.dart';
import '../widgets/bet_slip_fab.dart';
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

class _MatchDetailPageState extends State<MatchDetailPage> {
  OddsSnapshot? _odds;
  _BetSelection? _selected;
  StreamSubscription<OddsSnapshot>? _sub;
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

  // Map of last-changed score → "up"/"down" with autoclear after ~1.2s,
  // used to flash the corresponding cells.
  final Map<String, String> _flashes = {};
  final Map<String, Timer> _flashTimers = {};

  bool get _locked => !widget.match.isPending;

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
        setState(() => _odds = s);
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
        final key = '${p.marketType}::${p.score}';
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
    _historyTimer?.cancel();
    for (final t in _flashTimers.values) {
      t.cancel();
    }
    super.dispose();
  }

  Future<void> _place() async {
    final sel = _selected;
    if (sel == null) return;
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
      final key = '${p.marketType}::${p.score}';
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
                  padding: EdgeInsets.fromLTRB(0, 0, 0, _locked ? 96 : 230),
                  children: [
                    _hero(),
                    if (_locked) _lockedBanner(),
                    _sectionHeader(),
                    _columnLabels(),
                    _scoreGrid(),
                    _overUnderSection(),
                    _bttsSection(),
                    if (_placeError != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: Text(_placeError!,
                            style: const TextStyle(color: T.down)),
                      ),
                    if (_placeOK != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: Text(_placeOK!,
                            style: const TextStyle(color: T.upDark)),
                      ),
                  ],
                ),
              ),
                ],
              ),
              // 详情页内的 BetSlip 悬浮按钮 — MainShell 的 FAB 被详情页覆盖了,
              // 在这里独立挂一个,位置避开底部 _betDrawer/_lockedDrawer。
              Positioned(
                right: 16,
                bottom: _locked ? 100 : 240,
                child: BetSlipFab(state: widget.state),
              ),
            ],
          ),
        ),
      ),
      bottomSheet: _locked ? _lockedDrawer() : _betDrawer(),
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
    final m = widget.match;
    final live = m.isLive;
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
                  )
                else if (live)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFE9E6),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text('● LIVE',
                        style: TextStyle(
                            color: T.down,
                            fontSize: 10,
                            fontWeight: FontWeight.w800)),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      TeamCrest(name: m.home, leagueSlug: m.leagueSlug, size: 56, borderRadius: 14),
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
                      TeamCrest(name: m.away, leagueSlug: m.leagueSlug, size: 56, borderRadius: 14),
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
            colors: [Color(0x1AE03E2D), Color(0x08E03E2D)],
          ),
          border: Border.all(color: const Color(0x3AE03E2D)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Text(tr('detail.locked_banner_title'),
                style: const TextStyle(fontSize: 12, color: T.down, fontWeight: FontWeight.w800)),
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
                              final disabled = _locked || myStake != null;
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
              final disabled = _locked || myStake != null;
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

  // ── 大小球 (over/under 2.5) ─────────────────────────────────────
  Widget _overUnderSection() {
    final ou = _odds?.overUnder;
    if (ou == null) return const SizedBox.shrink();
    final lineFmt = ou.line.toStringAsFixed(1);
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
          Row(
            children: [
              Expanded(
                child: _BinaryBetTile(
                  label: '${tr('detail.ou_over')} $lineFmt',
                  hint: tr('detail.ou_hint_over'),
                  price: ou.over,
                  selected: _selected?.marketType == MarketType.overUnder25 &&
                            _selected?.score == 'over',
                  myStake: _myBets['${MarketType.overUnder25}::over'],
                  inSlip: widget.state.betSlip.containsKey('${widget.match.id}::${MarketType.overUnder25}::over'),
                  locked: _locked,
                  accent: T.up,
                  onTap: () => setState(() => _selected = _BetSelection(
                        marketType: MarketType.overUnder25,
                        score: 'over',
                        price: ou.over,
                        label: tr('detail.ou_over_label').replaceAll('{line}', lineFmt),
                      )),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _BinaryBetTile(
                  label: '${tr('detail.ou_under')} $lineFmt',
                  hint: tr('detail.ou_hint_under'),
                  price: ou.under,
                  selected: _selected?.marketType == MarketType.overUnder25 &&
                            _selected?.score == 'under',
                  myStake: _myBets['${MarketType.overUnder25}::under'],
                  inSlip: widget.state.betSlip.containsKey('${widget.match.id}::${MarketType.overUnder25}::under'),
                  locked: _locked,
                  accent: T.down,
                  onTap: () => setState(() => _selected = _BetSelection(
                        marketType: MarketType.overUnder25,
                        score: 'under',
                        price: ou.under,
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
  Widget _betDrawer() {
    final sel = _selected;
    final stakeFmt = NumberFormat('#,##0').format(_stake);
    final payout = sel == null ? 0 : (_stake * sel.price);
    final selLabel = sel?.label ?? tr('detail.bet_pick');
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 22),
      decoration: const BoxDecoration(
        color: Color(0xF2FFFFFF),
        border: Border(top: BorderSide(color: Color(0x402CD7FD))),
        boxShadow: [
          BoxShadow(color: Color(0x1A0E2238), blurRadius: 24, offset: Offset(0, -8))
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  gradient: T.brandGradientShort,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(selLabel,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 8),
              Text(tr('detail.bet_odds'), style: const TextStyle(fontSize: 11, color: T.inkLo)),
              const SizedBox(width: 4),
              Text(sel == null ? '—' : sel.price.toStringAsFixed(2),
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
          const SizedBox(height: 10),
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
            onChanged: (v) => setState(() => _stake = v),
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
                      onTap: () => setState(() => _stake = p.toDouble()),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              // Add to bet slip — secondary action.
              SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: sel == null ? null : _addToSlip,
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
              // Quick single-bet — primary action.
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _placing || sel == null ? null : _place,
                    icon: _placing
                        ? const SizedBox(
                            width: 14, height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.lock_outline, size: 16),
                    label: Text(
                      _placing
                          ? tr('detail.bet_submitting')
                          : sel == null
                              ? tr('detail.bet_lock_pending')
                              : tr('detail.bet_lock_format')
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
    );
  }

  void _addToSlip() {
    final sel = _selected;
    if (sel == null) return;
    final m = widget.match;
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${tr('detail.added_slip')} · ${sel.label}'),
      duration: const Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 240),
    ));
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
                            option.price.toStringAsFixed(2),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: selected ? Colors.white : _accent,
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
    final disabled = locked || betted;
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
                        Text(label,
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: betted
                                    ? T.inkLo
                                    : selected ? Colors.white : T.ink)),
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
                          Text(price.toStringAsFixed(2),
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  fontFamily: T.fontMono,
                                  color: selected ? Colors.white : accent)),
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

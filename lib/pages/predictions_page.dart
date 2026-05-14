import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/match.dart';
import '../services/app_state.dart';
import '../services/i18n.dart';
import '../services/toast.dart';
import '../theme/tokens.dart';
import '../utils/league_flags.dart';
import '../utils/team_crests.dart';
import '../utils/team_names.dart';
import '../widgets/light_card.dart';
import '../widgets/status_pill.dart';
import 'match_detail_page.dart';

/// 05 · 我的预测 — 战绩 hero + 状态 tab + 卡片列表。
class PredictionsPage extends StatefulWidget {
  const PredictionsPage({super.key, required this.state});
  final AppState state;

  @override
  State<PredictionsPage> createState() => _PredictionsPageState();
}

class _PredictionsPageState extends State<PredictionsPage> {
  String _tab = 'all';
  String _topTab = 'single'; // 'single' | 'parlay'
  late Future<_MyBetsBundle> _future;

  // cashout 正在进行中的注单 id —— 防止用户连点同一条注单多次,后端虽然有
  // status guard 不会重复派钱,但前端会弹多次 Toast。Set 而非 bool 因为
  // 列表里可能同时有多条 pending 注单。
  final Set<int> _cashingOutBets = <int>{};
  final Set<int> _cashingOutParlays = <int>{};

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_MyBetsBundle> _load() async {
    final results = await Future.wait([
      widget.state.api.myBets(),
      widget.state.api.getStats(),
      widget.state.api.myParlays().catchError((_) => <Parlay>[]),
    ]);
    return _MyBetsBundle(
      bets: results[0] as List<BetRow>,
      stats: results[1] as UserStats,
      parlays: results[2] as List<Parlay>,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: T.bgPage,
      body: Container(
        decoration: const BoxDecoration(gradient: T.pageGradient),
        child: SafeArea(
          child: FutureBuilder<_MyBetsBundle>(
            future: _future,
            builder: (_, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(
                    child: CircularProgressIndicator(color: T.brandDeep));
              }
              if (snap.hasError) {
                return Center(
                    child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(tr('load_failed').replaceAll('{err}', '${snap.error}'),
                      style: const TextStyle(color: T.down)),
                ));
              }
              final bundle = snap.data!;
              final all = bundle.bets;
              final parlays = bundle.parlays;

              return RefreshIndicator(
                color: T.brandDeep,
                onRefresh: () async {
                  setState(() => _future = _load());
                  await _future;
                },
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    _topBar(),
                    _segmented(all.length, parlays.length),
                    if (_topTab == 'single')
                      ..._buildSingleSection(bundle, all)
                    else
                      ..._buildParlaySection(parlays),
                    const SizedBox(height: 24),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Row(
        children: [
          if (Navigator.of(context).canPop())
            IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.chevron_left, color: T.ink)),
          Text(tr('pred.title'),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: T.ink)),
        ],
      ),
    );
  }

  Widget _statsHero(UserStats s) {
    final profit = s.monthProfit;
    final hitPct = (s.hitRate * 100).round();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          gradient: T.heroGradient,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0x382CD7FD)),
          boxShadow: const [
            BoxShadow(color: Color(0x1A2CD7FD), blurRadius: 18, offset: Offset(0, 6))
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr('pred.month_record'),
                        style: const TextStyle(
                            fontSize: 11,
                            color: T.inkMd,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          (profit >= 0 ? '+' : '') +
                              NumberFormat('#,##0.00').format(profit),
                          style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              color: profit >= 0 ? T.upDark : T.down,
                              fontFamily: T.fontMono),
                        ),
                        const SizedBox(width: 4),
                        Text('USDT',
                            style: TextStyle(
                                fontSize: 12,
                                color: profit >= 0 ? T.upDark : T.down,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ],
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xB3FFFFFF),
                    border: Border.all(color: T.border),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(tr('pred.hit_rate').replaceAll('{n}', '$hitPct'),
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: T.brandDeep)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _miniStat(tr('pred.total_bets'), '${s.totalBets}', T.ink),
                _miniStat(tr('pred.won'), '${s.won}', T.up),
                _miniStat(tr('pred.lost'), '${s.lost}', T.down),
                _miniStat(tr('pred.pending'), '${s.pending}', T.warn),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniStat(String label, String value, Color color) => Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xB3FFFFFF),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 9, color: T.inkLo, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(value,
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: color,
                      fontFamily: T.fontMono,
                      height: 1.0)),
            ],
          ),
        ),
      );

  Widget _tabs(Map<String, int> counts) {
    final tabs = [
      ['all', tr('pred.tab_all')],
      ['pending', tr('pred.tab_pending')],
      ['live', tr('pred.tab_live')],
      ['won', tr('pred.tab_won')],
      ['lost', tr('pred.tab_lost')],
    ];
    return SizedBox(
      height: 44,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        scrollDirection: Axis.horizontal,
        itemCount: tabs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final id = tabs[i][0];
          final on = _tab == id;
          final count = counts[id] ?? 0;
          return InkWell(
            onTap: () => setState(() => _tab = id),
            borderRadius: BorderRadius.circular(999),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: on
                    ? const LinearGradient(
                        colors: [Color(0x2E2CD7FD), Color(0x0F2CD7FD)])
                    : null,
                color: on ? null : Colors.white,
                border: Border.all(color: on ? T.brand : T.border),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(tabs[i][1],
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: on ? T.brandDeep : T.inkMd)),
                if (count > 0) ...[
                  const SizedBox(width: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: on ? T.brandDeep : const Color(0x100E2238),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text('$count',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: on ? Colors.white : T.inkLo)),
                  ),
                ],
              ]),
            ),
          );
        },
      ),
    );
  }

  Widget _empty() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: LightCard(
          padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
          child: Column(
            children: [
              Container(
                width: 64, height: 64,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [Color(0xFFF4F8FC), Color(0xFFE8F1FB)]),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(Icons.bookmark_border,
                    color: T.inkLo, size: 32),
              ),
              const SizedBox(height: 12),
              Text(tr('pred.empty_title'),
                  style: const TextStyle(
                      fontSize: 14,
                      color: T.ink,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(tr('pred.empty_sub'),
                  style: const TextStyle(fontSize: 11, color: T.inkLo)),
            ],
          ),
        ),
      );

  /// 提前结算确认弹窗:估算 cashout 金额(本地参考价 stake×oap/stake×0.92≈stake×0.92,
  /// 因为我们没有 currentOdds → 但展示 stake×0.92 作"最差情况下限"会让用户低估,
  /// 不如改用 stake×oap×0.92/oap = stake×0.92 不对...
  /// 实际上 cashout = stake×oap/currentOdds×0.92。本地不知 currentOdds,
  /// 我们干脆显示 "约 X.XX USDT(以服务端实际为准)" — X = stake × 0.92,
  /// 即极端最差情况),让用户有心理预期;后端用真实 currentOdds 报价。
  Future<void> _confirmCashout(BetRow b) async {
    final pred = b.prediction;
    final estimateLow = pred.stake * 0.92;
    final estimateHigh = pred.stake * pred.oddsAtPlace * 0.92; // 完全锁定时的上限

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(tr('pred.cashout_title'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: T.ink)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${localizedTeam(b.home)} vs ${localizedTeam(b.away)}',
                style: const TextStyle(fontSize: 13, color: T.inkMd)),
            const SizedBox(height: 6),
            Text('${_selectionLabel(pred.marketType, pred.score)} @ ${pred.oddsAtPlace.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 13, color: T.inkMd)),
            const SizedBox(height: 6),
            Text('${tr('pred.stake_label')}: ${pred.stake.toStringAsFixed(0)} USDT',
                style: const TextStyle(fontSize: 13, color: T.inkMd)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0x14F5B544),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                tr('pred.cashout_desc'),
                style: const TextStyle(fontSize: 11, color: Color(0xFFC7861E), fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${tr('pred.cashout_estimate')}: ${estimateLow.toStringAsFixed(2)} ~ ${estimateHigh.toStringAsFixed(2)} USDT',
              style: const TextStyle(fontSize: 12, color: T.inkLo, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('pred.cashout_cancel'), style: const TextStyle(color: T.inkLo)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('pred.cashout_confirm'), style: const TextStyle(color: T.brandDeep, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (_cashingOutBets.contains(pred.id)) return; // 重入保险:确认框关闭间隙再点
    setState(() => _cashingOutBets.add(pred.id));
    try {
      final result = await widget.state.api.cashOutPrediction(pred.id);
      if (!mounted) return;
      Toast.success(context,
          tr('pred.cashout_ok').replaceAll('{n}', result.cashedOut.toStringAsFixed(2)));
      setState(() => _future = _load());
    } catch (e) {
      if (!mounted) return;
      Toast.error(context, e.toString());
    } finally {
      if (mounted) setState(() => _cashingOutBets.remove(pred.id));
    }
  }

  void _onFooterTap(BetRow b, bool isPending) {
    if (isPending) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(tr('pred.cancel_title'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: T.ink)),
          content: Text(
            tr('pred.cancel_msg')
                .replaceAll('{home}', localizedTeam(b.home))
                .replaceAll('{away}', localizedTeam(b.away))
                .replaceAll('{score}', b.prediction.score)
                .replaceAll('{stake}', b.prediction.stake.toStringAsFixed(0)),
            style: const TextStyle(fontSize: 14, color: T.inkMd),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(tr('common.cancel'), style: const TextStyle(color: T.inkLo)),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                try {
                  final res = await widget.state.api.cancelPrediction(b.prediction.id);
                  if (!mounted) return;
                  // 重载列表(余额由 stats hero 卡内 wallet API 自带刷新)
                  setState(() => _future = _load());
                  Toast.success(context,
                      tr('pred.cancel_ok').replaceAll('{n}', res.refundedAmount.toStringAsFixed(2)));
                } catch (e) {
                  if (!mounted) return;
                  final msg = e.toString();
                  String label = tr('pred.cancel_failed');
                  if (msg.contains('too close to kickoff')) {
                    label = tr('pred.cancel_too_late');
                  } else if (msg.contains('not pending')) {
                    label = tr('pred.cancel_not_pending');
                  }
                  Toast.error(context, '$label · $msg');
                }
              },
              child: Text(tr('pred.cancel_confirm'), style: const TextStyle(color: T.down)),
            ),
          ],
        ),
      );
    } else {
      _goMatchDetail(b);
    }
  }

  void _goMatchDetail(BetRow b) {
    AntiSpam.guardAsync('match_detail_${b.prediction.matchId}', () async {
      try {
        final match = await widget.state.api.getMatch(b.prediction.matchId);
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MatchDetailPage(state: widget.state, match: match),
          ),
        );
      } catch (e) {
        if (mounted) {
          Toast.error(
              context, tr('pred.load_match_failed').replaceAll('{err}', '$e'));
        }
      }
    });
  }

  /// Top-level segmented control: Singles vs Parlays.
  Widget _segmented(int singleCount, int parlayCount) {
    Widget seg(String id, String label, int count) {
      final on = _topTab == id;
      return Expanded(
        child: InkWell(
          onTap: () => setState(() => _topTab = id),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            margin: const EdgeInsets.all(2),
            padding: const EdgeInsets.symmetric(vertical: 8),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              boxShadow: on
                  ? const [
                      BoxShadow(
                          color: Color(0x140E2238),
                          blurRadius: 6,
                          offset: Offset(0, 2))
                    ]
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: on ? T.brandDeep : T.inkLo)),
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: on ? T.brandDeep : const Color(0x140E2238),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text('$count',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: on ? Colors.white : T.inkLo)),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFEEF3F8),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          seg('single', tr('pred.top_tab_single'), singleCount),
          seg('parlay', tr('pred.top_tab_parlay'), parlayCount),
        ]),
      ),
    );
  }

  List<Widget> _buildSingleSection(_MyBetsBundle bundle, List<BetRow> all) {
    final counts = {
      'all': all.length,
      'pending': all.where((b) => b.effectiveStatus == 'pending').length,
      'live': all.where((b) => b.effectiveStatus == 'live').length,
      // half_won 算入 won 标签;half_lost 算入 lost。push 单独不显示在 won/lost
      // 标签里(只在卡片状态徽章里出现)。
      'won': all.where((b) => b.effectiveStatus == 'won' || b.effectiveStatus == 'half_won').length,
      'lost': all.where((b) => b.effectiveStatus == 'lost' || b.effectiveStatus == 'half_lost').length,
    };
    final filtered = _tab == 'all'
        ? all
        : all.where((b) {
            final s = b.effectiveStatus;
            if (_tab == 'won') return s == 'won' || s == 'half_won';
            if (_tab == 'lost') return s == 'lost' || s == 'half_lost';
            return s == _tab;
          }).toList();
    return [
      _statsHero(bundle.stats),
      _tabs(counts),
      if (filtered.isEmpty) _empty(),
      ...filtered.map(_betCard),
    ];
  }

  List<Widget> _buildParlaySection(List<Parlay> parlays) {
    if (parlays.isEmpty) {
      return [_parlayEmpty()];
    }
    return [
      _parlayStatsHero(parlays),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
        child: Column(children: parlays.map(_parlayCard).toList()),
      ),
    ];
  }

  Widget _parlayStatsHero(List<Parlay> parlays) {
    final total = parlays.length;
    final pending = parlays.where((p) => p.status == 'pending').length;
    final won = parlays.where((p) => p.status == 'won').length;
    final lost = parlays.where((p) => p.status == 'lost').length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          gradient: T.heroGradient,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0x382CD7FD)),
        ),
        child: Row(children: [
          _miniStat(tr('pred.parlay_total'), '$total', T.ink),
          _miniStat(tr('pred.parlay_pending'), '$pending', T.warn),
          _miniStat(tr('pred.parlay_won'), '$won', T.up),
          _miniStat(tr('pred.parlay_lost'), '$lost', T.down),
        ]),
      ),
    );
  }

  Widget _parlayEmpty() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: LightCard(
          padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
          child: Column(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [Color(0xFFF4F8FC), Color(0xFFE8F1FB)]),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(Icons.link, color: T.inkLo, size: 32),
              ),
              const SizedBox(height: 12),
              Text(tr('pred.parlay_empty_title'),
                  style: const TextStyle(
                      fontSize: 14,
                      color: T.ink,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(tr('pred.parlay_empty_sub'),
                  style: const TextStyle(fontSize: 11, color: T.inkLo)),
            ],
          ),
        ),
      );

  Widget _kickoffLine(DateTime kickoff) {
    final fmt = DateFormat('MM-dd HH:mm');
    final overdue = kickoff.isBefore(DateTime.now());
    final txt = (overdue
            ? tr('pred.kickoff_overdue')
            : tr('pred.kickoff'))
        .replaceAll('{time}', fmt.format(kickoff));
    return Row(
      children: [
        Icon(
          overdue ? Icons.hourglass_bottom : Icons.schedule,
          size: 11,
          color: overdue ? T.warn : T.inkLo,
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            txt,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: overdue ? T.warn : T.inkLo,
              fontFamily: T.fontMono,
            ),
          ),
        ),
      ],
    );
  }

  Widget _betCard(BetRow b) {
    final fmt = DateFormat('MM-dd HH:mm');
    final pred = b.prediction;
    final eff = b.effectiveStatus;
    // half_won 视觉上算赢(让卡片绿色徽章+正向 payout);half_lost 算输(红色)。
    final isWon = eff == 'won' || eff == 'half_won';
    final isLost = eff == 'lost' || eff == 'half_lost';
    final isLive = eff == 'live';
    final isPending = eff == 'pending';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: LightCard(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
              decoration: BoxDecoration(
                gradient: isWon
                    ? const LinearGradient(
                        colors: [Color(0x142BD475), Colors.transparent])
                    : isLive
                        ? const LinearGradient(
                            colors: [Color(0x0FE03E2D), Colors.transparent])
                        : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      LeagueFlag(slug: b.leagueSlug, height: 12, width: 18),
                      const SizedBox(width: 6),
                      Text(b.leagueName.isEmpty ? tr('pred.unknown_league') : localizedLeague(b.leagueName),
                          style: const TextStyle(
                              fontSize: 11, color: T.inkLo, fontWeight: FontWeight.w600)),
                      const SizedBox(width: 8),
                      Text('#${pred.id}',
                          style: const TextStyle(
                              fontSize: 9,
                              color: T.inkSubtle,
                              fontWeight: FontWeight.w600,
                              fontFamily: T.fontMono)),
                      const Spacer(),
                      StatusPill(status: betStatusFromString(eff)),
                    ],
                  ),
                  if (isPending && b.matchDate != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: _kickoffLine(b.matchDate!),
                    ),
                ],
              ),
            ),
            // Match row
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: Row(
                children: [
                  TeamCrest(name: b.home, leagueSlug: b.leagueSlug, size: 26),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(
                            text: localizedTeam(b.home),
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: T.ink)),
                        const TextSpan(
                            text: '  vs  ',
                            style: TextStyle(
                                color: T.inkSubtle,
                                fontWeight: FontWeight.w500)),
                        TextSpan(
                            text: localizedTeam(b.away),
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: T.ink)),
                      ]),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  TeamCrest(name: b.away, leagueSlug: b.leagueSlug, size: 26),
                ],
              ),
            ),
            // Pick + odds + stake
            Container(
              margin: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: T.fill,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      gradient: isWon
                          ? const LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [T.up, T.upDark])
                          : isLost
                              ? null
                              : T.brandGradientShort,
                      color: isLost ? const Color(0xFFEEF2F7) : null,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _selectionLabel(pred.marketType, pred.score),
                      style: TextStyle(
                        color: isLost ? T.inkLo : Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        fontFamily: pred.marketType == MarketType.correctScore
                            ? T.fontMono
                            : null,
                        decoration: isLost ? TextDecoration.lineThrough : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: isLive && b.liveHome != null
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(tr('pred.live_score'),
                                  style: const TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                      color: T.down)),
                              Text('${b.liveHome}:${b.liveAway}',
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      color: T.brandDeep,
                                      fontFamily: T.fontMono)),
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(tr('detail.bet_odds'),
                                  style: const TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w600,
                                      color: T.inkLo)),
                              Text(pred.oddsAtPlace.toStringAsFixed(2),
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      color: T.gold,
                                      fontFamily: T.fontMono)),
                            ],
                          ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(tr('pred.invest').replaceAll('{n}', pred.stake.toStringAsFixed(0)),
                          style: const TextStyle(
                              fontSize: 9,
                              color: T.inkLo,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(
                        isLost ? '—' : (isWon ? '+' : '') + NumberFormat('#,##0.00').format(pred.payout > 0 ? pred.payout : pred.stake * pred.oddsAtPlace),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: isWon ? T.up : isLost ? T.inkLo : T.ink,
                          fontFamily: T.fontMono,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Footer
            Material(
              color: const Color(0xFFFCFDFE),
              child: InkWell(
                onTap: () => _onFooterTap(b, isPending),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: T.border)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          isPending
                              ? tr('pred.foot_pending')
                              : isLive
                                  ? tr('pred.foot_live')
                                  : pred.settledAt != null
                                      ? tr('pred.foot_settled').replaceAll('{time}', fmt.format(pred.settledAt!))
                                      : tr('pred.foot_placed').replaceAll('{time}', fmt.format(pred.createdAt)),
                          style: const TextStyle(
                              fontSize: 10, color: T.inkLo, fontWeight: FontWeight.w600),
                        ),
                      ),
                      // 提前结算 — 仅对活跃(待开赛/进行中)的注单可用,
                      // 已中/未中/已提结的不显示。
                      if (isPending || isLive)
                        TextButton.icon(
                          onPressed: _cashingOutBets.contains(b.prediction.id)
                              ? null
                              : () => _confirmCashout(b),
                          icon: const Icon(Icons.savings_outlined, size: 14, color: T.brandDeep),
                          label: Text(tr('pred.cashout_btn'),
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: T.brandDeep,
                                  fontWeight: FontWeight.w800)),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        )
                      else
                        Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: Text(
                            tr('pred.action_detail'),
                            style: const TextStyle(
                                fontSize: 11, color: T.brandDeep, fontWeight: FontWeight.w700),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

extension _PredictionsPageStateParlay on _PredictionsPageState {
  Widget _parlayCard(Parlay p) {
    Color statusColor;
    String statusLabel;
    switch (p.status) {
      case 'won':
        statusColor = T.up;
        statusLabel = tr('pred.status_won');
        break;
      case 'lost':
        statusColor = T.down;
        statusLabel = tr('pred.status_lost');
        break;
      case 'pushed':
        statusColor = T.gold;
        statusLabel = '退本';
        break;
      case 'half_won':
        statusColor = T.up;
        statusLabel = '赢半 (退一半 + 赢一半)';
        break;
      case 'half_lost':
        statusColor = T.down;
        statusLabel = '输半 (退一半)';
        break;
      default:
        statusColor = T.gold;
        statusLabel = tr('pred.status_open');
    }
    final fmt = DateFormat('MM-dd HH:mm');
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: T.border),
        boxShadow: const [
          BoxShadow(color: Color(0x0A0E2238), blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFE6F8FE),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF9DE3F4)),
                ),
                child: Text('${tr('pred.parlay_label')} · ${p.legs.length}',
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w800, color: T.brandDeep)),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(statusLabel,
                    style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w800, color: statusColor)),
              ),
              const Spacer(),
              Text('#${p.id}',
                  style: const TextStyle(
                      fontSize: 10, color: T.inkSubtle, fontFamily: T.fontMono)),
            ],
          ),
          const SizedBox(height: 8),
          // Per-leg list
          ...p.legs.map((leg) {
            Color dot;
            switch (leg.legStatus) {
              case 'won':
                dot = T.up;
                break;
              case 'lost':
                dot = T.down;
                break;
              default:
                dot = T.inkSubtle;
            }
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Container(
                    width: 7, height: 7,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${localizedTeam(leg.home)} vs ${localizedTeam(leg.away)}',
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w700, color: T.ink),
                            overflow: TextOverflow.ellipsis),
                        Text('${_selectionLabel(leg.marketType, leg.score)} @ ${leg.odds.toStringAsFixed(2)}',
                            style: const TextStyle(
                                fontSize: 11, color: T.inkLo, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
          const Divider(color: T.border, height: 18),
          Row(
            children: [
              Text('${tr('pred.combo_odds')} ${p.totalOdds.toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: T.gold,
                      fontFamily: T.fontMono)),
              const SizedBox(width: 12),
              Text('${tr('pred.stake_label')} ${NumberFormat('#,##0').format(p.stake)} U',
                  style: const TextStyle(
                      fontSize: 12, color: T.inkLo, fontWeight: FontWeight.w600)),
              const Spacer(),
              if (p.status == 'won')
                Text('+${NumberFormat('#,##0.00').format(p.payout)} U',
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: T.up,
                        fontFamily: T.fontMono))
              else if (p.status == 'lost')
                Text('-${NumberFormat('#,##0').format(p.stake)} U',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w800, color: T.down))
              else ...[
                Text(fmt.format(p.createdAt),
                    style: const TextStyle(
                        fontSize: 11, color: T.inkSubtle, fontFamily: T.fontMono)),
                // 提前结算按钮:只要 status=pending 且没有 lost leg 就可以
                if (p.legs.every((l) => l.legStatus != 'lost') &&
                    p.legs.any((l) => l.legStatus == 'pending')) ...[
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: _cashingOutParlays.contains(p.id)
                        ? null
                        : () => _confirmParlayCashout(p),
                    icon: const Icon(Icons.flash_on, size: 14, color: T.brandDeep),
                    label: Text(tr('pred.cashout_btn'),
                        style: const TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w800, color: T.brandDeep)),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                      minimumSize: const Size(0, 28),
                      visualDensity: VisualDensity.compact,
                      backgroundColor: const Color(0x142CD7FD),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmParlayCashout(Parlay p) async {
    // 估算上下界:全 pending 时 stake×0.92 是绝对下限;
    // 全 won 已 cashed_out 不在此分支,所以这里只展示 stake×0.92 ~ stake×totalOdds×0.92
    final estimateLow = p.stake * 0.92;
    final estimateHigh = p.stake * p.totalOdds * 0.92;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(tr('pred.cashout_title'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: T.ink)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${tr('pred.parlay_label')} #${p.id} · ${p.legs.length} ${tr('pred.legs_label')}',
                style: const TextStyle(fontSize: 13, color: T.inkMd)),
            const SizedBox(height: 4),
            Text('${tr('pred.combo_odds')} ${p.totalOdds.toStringAsFixed(2)} · '
                '${tr('pred.stake_label')} ${p.stake.toStringAsFixed(0)} USDT',
                style: const TextStyle(fontSize: 13, color: T.inkMd)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0x14F5B544),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                tr('pred.cashout_desc'),
                style: const TextStyle(fontSize: 11, color: Color(0xFFC7861E), fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${tr('pred.cashout_estimate')}: ${estimateLow.toStringAsFixed(2)} ~ ${estimateHigh.toStringAsFixed(2)} USDT',
              style: const TextStyle(fontSize: 12, color: T.inkLo, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('pred.cashout_cancel'), style: const TextStyle(color: T.inkLo)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('pred.cashout_confirm'),
                style: const TextStyle(color: T.brandDeep, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (_cashingOutParlays.contains(p.id)) return;
    setState(() => _cashingOutParlays.add(p.id));
    try {
      final result = await widget.state.api.cashOutParlay(p.id);
      if (!mounted) return;
      Toast.success(context,
          tr('pred.cashout_ok').replaceAll('{n}', result.cashedOut.toStringAsFixed(2)));
      setState(() => _future = _load());
    } catch (e) {
      if (!mounted) return;
      Toast.error(context, e.toString());
    } finally {
      if (mounted) setState(() => _cashingOutParlays.remove(p.id));
    }
  }
}

class _MyBetsBundle {
  final List<BetRow> bets;
  final UserStats stats;
  final List<Parlay> parlays;
  _MyBetsBundle({
    required this.bets,
    required this.stats,
    required this.parlays,
  });
}

/// 按市场类型把后端存的 score 转成给用户看的文字。
String _selectionLabel(String marketType, String score) {
  switch (marketType) {
    case MarketType.overUnder25:
      // score 可能是 'over' / 'under'(legacy = line 2.5)或 'over@1.5' / 'under@3.5'。
      final at = score.lastIndexOf('@');
      String side = score;
      String? line;
      if (at > 0 && at < score.length - 1) {
        side = score.substring(0, at);
        line = score.substring(at + 1);
      }
      final sideLabel = side == 'over' ? tr('pred.ou_over') : tr('pred.ou_under');
      // 显示 line:线 2.5 时省略(老体验),其它线追加 "(1.5)" 后缀
      if (line == null || line == '2.5') return sideLabel;
      return '$sideLabel ($line)';
    case MarketType.btts:
      if (score == 'yes') return tr('pred.btts_yes');
      if (score == 'no') return tr('pred.btts_no');
      return score;
    case MarketType.matchWinner:
      if (score == 'home') return '${tr('detail.winner_title')} · ${tr('detail.win_home')}';
      if (score == 'draw') return '${tr('detail.winner_title')} · ${tr('detail.draw')}';
      if (score == 'away') return '${tr('detail.winner_title')} · ${tr('detail.win_away')}';
      return score;
    case MarketType.doubleChance:
      // score: "1X" | "X2" | "12"
      switch (score) {
        case '1X': return '双胜 · 主或平';
        case 'X2': return '双胜 · 平或客';
        case '12': return '双胜 · 主或客';
      }
      return '双胜 · $score';
    case MarketType.drawNoBet:
      if (score == 'home') return '平退本 · 主胜';
      if (score == 'away') return '平退本 · 客胜';
      return '平退本 · $score';
    case MarketType.asianHandicap:
      // score 形如 "home@-0.5" / "away@+1.5"
      final at = score.lastIndexOf('@');
      if (at > 0 && at < score.length - 1) {
        final side = score.substring(0, at);
        final line = score.substring(at + 1);
        final sideLabel = side == 'home' ? tr('detail.win_home') : tr('detail.win_away');
        return '${tr('detail.handicap_title')} · $sideLabel $line';
      }
      return score;
    case MarketType.correctScore:
    default:
      return score; // "2:1" / "Other"
  }
}

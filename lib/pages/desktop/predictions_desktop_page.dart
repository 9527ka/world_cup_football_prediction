import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/match.dart';
import '../../utils/ny_time.dart';
import '../../services/app_state.dart';
import '../../services/i18n.dart';
import '../../services/toast.dart';
import '../../theme/tokens.dart';
import '../../utils/league_flags.dart';
import '../../utils/team_crests.dart';
import '../../utils/team_names.dart';
import '../../widgets/light_card.dart';
import '../../widgets/status_pill.dart';

final _fmtDate = DateFormat('MM-dd HH:mm');
final _fmtBal = NumberFormat('#,##0.00');

/// 桌面我的预测。复用 myBets / getStats / myParlays / cancelPrediction。
/// hero 战绩 + 单/串 segmented + 状态 tab + 2 列卡片网格。无内置返回栏。
class PredictionsDesktopPage extends StatefulWidget {
  const PredictionsDesktopPage({
    super.key,
    required this.state,
    required this.onOpenMatch,
  });

  final AppState state;
  final void Function(int matchId) onOpenMatch;

  @override
  State<PredictionsDesktopPage> createState() => _PredictionsDesktopPageState();
}

class _Bundle {
  final List<BetRow> bets;
  final UserStats stats;
  final List<Parlay> parlays;
  _Bundle(this.bets, this.stats, this.parlays);
}

class _PredictionsDesktopPageState extends State<PredictionsDesktopPage> {
  String _tab = 'all';
  String _topTab = 'single';
  late Future<_Bundle> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_Bundle> _load() async {
    final results = await Future.wait([
      widget.state.api.myBets(),
      widget.state.api.getStats(),
      widget.state.api.myParlays().catchError((_) => <Parlay>[]),
    ]);
    return _Bundle(
      results[0] as List<BetRow>,
      results[1] as UserStats,
      results[2] as List<Parlay>,
    );
  }

  void _reload() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_Bundle>(
      future: _future,
      builder: (_, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator(color: T.brandDeep));
        }
        if (snap.hasError) {
          return Center(
              child: Text(tr('load_failed').replaceAll('{err}', '${snap.error}'),
                  style: const TextStyle(color: T.down)));
        }
        final b = snap.data!;
        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 20),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _statsHero(b.stats),
                      const SizedBox(height: 12),
                      _segmented(b.bets.length, b.parlays.length),
                      const SizedBox(height: 12),
                      if (_topTab == 'single')
                        _singleSection(b.bets)
                      else
                        _parlaySection(b.parlays),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _statsHero(UserStats s) {
    final profit = s.monthProfit;
    Widget mini(String label, String v, Color c) => Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
                color: const Color(0xB3FFFFFF),
                borderRadius: BorderRadius.circular(10)),
            child: Column(
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 10, color: T.inkLo, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(v,
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: c,
                        fontFamily: T.fontMono)),
              ],
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        gradient: T.heroGradient,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x382CD7FD)),
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
                          fontSize: 12, color: T.inkMd, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text('${profit >= 0 ? '+' : ''}${_fmtBal.format(profit)} USDT',
                      style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: profit >= 0 ? T.upDark : T.down,
                          fontFamily: T.fontMono)),
                  const SizedBox(height: 2),
                  Text(
                      tr('pred.month_stake')
                          .replaceAll('{n}', _fmtBal.format(s.monthStake)),
                      style: const TextStyle(
                          fontSize: 12, color: T.inkMd, fontWeight: FontWeight.w600)),
                ],
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xB3FFFFFF),
                  border: Border.all(color: T.border),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                    tr('pred.hit_rate').replaceAll('{n}', '${(s.hitRate * 100).round()}'),
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: T.brandDeep)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              mini(tr('pred.total_bets'), '${s.totalBets}', T.ink),
              mini(tr('pred.won'), '${s.won}', T.up),
              mini(tr('pred.lost'), '${s.lost}', T.down),
              mini(tr('pred.pending'), '${s.pending}', T.warn),
            ],
          ),
        ],
      ),
    );
  }

  Widget _segmented(int singleCount, int parlayCount) {
    Widget seg(String id, String label, int count) {
      final on = _topTab == id;
      return Expanded(
        child: InkWell(
          onTap: () => setState(() => _topTab = id),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            margin: const EdgeInsets.all(3),
            padding: const EdgeInsets.symmetric(vertical: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              boxShadow: on ? T.shadowSoft : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: on ? T.brandDeep : T.inkLo)),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                      color: on ? T.brandDeep : const Color(0x140E2238),
                      borderRadius: BorderRadius.circular(999)),
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

    return Container(
      decoration: BoxDecoration(
          color: const Color(0xFFEEF3F8),
          borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        seg('single', tr('pred.top_tab_single'), singleCount),
        seg('parlay', tr('pred.top_tab_parlay'), parlayCount),
      ]),
    );
  }

  Widget _singleSection(List<BetRow> all) {
    final tabs = [
      ['all', tr('pred.tab_all')],
      ['pending', tr('pred.tab_pending')],
      ['live', tr('pred.tab_live')],
      ['won', tr('pred.tab_won')],
      ['lost', tr('pred.tab_lost')],
    ];
    final filtered = _tab == 'all'
        ? all
        : all.where((b) {
            final s = b.effectiveStatus;
            if (_tab == 'won') return s == 'won' || s == 'half_won';
            if (_tab == 'lost') return s == 'lost' || s == 'half_lost';
            return s == _tab;
          }).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: tabs.map((t) {
            final on = _tab == t[0];
            return InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: () => setState(() => _tab = t[0]),
              child: Container(
                height: 34,
                padding: const EdgeInsets.symmetric(horizontal: 16),
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
                child: Text(t[1],
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: on ? T.brandDeep : T.inkMd)),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 14),
        if (filtered.isEmpty)
          _empty(tr('pred.empty_title'), tr('pred.empty_sub'), Icons.bookmark_border)
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 480,
              mainAxisExtent: 168,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            ),
            itemCount: filtered.length,
            itemBuilder: (_, i) => _betCard(filtered[i]),
          ),
      ],
    );
  }

  Widget _betCard(BetRow b) {
    final pred = b.prediction;
    final eff = b.effectiveStatus;
    final isWon = eff == 'won' || eff == 'half_won';
    final isLost = eff == 'lost' || eff == 'half_lost';
    final isPending = eff == 'pending';
    final isLive = eff == 'live';
    final payout = pred.payout > 0 ? pred.payout : pred.stake * pred.oddsAtPlace;
    return LightCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
            child: Row(
              children: [
                LeagueFlag(slug: b.leagueSlug, height: 11, width: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                      b.leagueName.isEmpty
                          ? tr('pred.unknown_league')
                          : localizedLeague(b.leagueName),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11, color: T.inkLo, fontWeight: FontWeight.w600)),
                ),
                StatusPill(status: betStatusFromString(eff)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: Row(
              children: [
                TeamCrest(name: b.home, id: b.homeId > 0 ? b.homeId : null, leagueSlug: b.leagueSlug, size: 22),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${localizedTeam(b.home, apiZh: b.homeZh)} vs ${localizedTeam(b.away, apiZh: b.awayZh)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700, color: T.ink),
                  ),
                ),
                const SizedBox(width: 6),
                TeamCrest(name: b.away, id: b.awayId > 0 ? b.awayId : null, leagueSlug: b.leagueSlug, size: 22),
              ],
            ),
          ),
          Container(
            margin: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
                color: T.fill, borderRadius: BorderRadius.circular(12)),
            child: Row(
              children: [
                Flexible(
                  child: Container(
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr('detail.bet_odds'),
                        style: const TextStyle(
                            fontSize: 9, fontWeight: FontWeight.w600, color: T.inkLo)),
                    Text(pred.oddsAtPlace.toStringAsFixed(2),
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: T.gold,
                            fontFamily: T.fontMono)),
                  ],
                ),
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(tr('pred.invest').replaceAll('{n}', pred.stake.toStringAsFixed(0)),
                        style: const TextStyle(
                            fontSize: 9, color: T.inkLo, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                      isLost ? '—' : '${isWon ? '+' : ''}${_fmtBal.format(payout)}',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: isWon ? T.up : (isLost ? T.inkLo : T.ink),
                          fontFamily: T.fontMono),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Spacer(),
          Material(
            color: const Color(0xFFFCFDFE),
            child: InkWell(
              onTap: () => isPending ? _confirmCancel(b) : widget.onOpenMatch(pred.matchId),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: T.border))),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        isPending
                            ? tr('pred.foot_pending')
                            : isLive
                                ? tr('pred.foot_live')
                                : pred.settledAt != null
                                    ? tr('pred.foot_settled')
                                        .replaceAll('{time}', _fmtDate.format(toNyWall(pred.settledAt!)))
                                    : tr('pred.foot_placed')
                                        .replaceAll('{time}', _fmtDate.format(toNyWall(pred.createdAt))),
                        style: const TextStyle(
                            fontSize: 10, color: T.inkLo, fontWeight: FontWeight.w600),
                      ),
                    ),
                    Text(isPending ? tr('pred.cancel_confirm') : tr('home.view_all'),
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: T.brandDeep)),
                    const Icon(Icons.chevron_right, size: 16, color: T.brandDeep),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmCancel(BetRow b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(tr('pred.cancel_title')),
        content: Text(
          tr('pred.cancel_msg')
              .replaceAll('{home}', localizedTeam(b.home, apiZh: b.homeZh))
              .replaceAll('{away}', localizedTeam(b.away, apiZh: b.awayZh))
              .replaceAll('{score}', b.prediction.score)
              .replaceAll('{stake}', b.prediction.stake.toStringAsFixed(0)),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('common.cancel'))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: T.down),
              child: Text(tr('pred.cancel_confirm'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final res = await widget.state.api.cancelPrediction(b.prediction.id);
      if (!mounted) return;
      _reload();
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
  }

  Widget _parlaySection(List<Parlay> parlays) {
    if (parlays.isEmpty) {
      return _empty(tr('pred.parlay_empty_title'), tr('pred.parlay_empty_sub'), Icons.link);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: parlays.map(_parlayCard).toList(),
    );
  }

  Widget _parlayCard(Parlay p) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: LightCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('#${p.id}',
                    style: const TextStyle(
                        fontSize: 11,
                        color: T.inkLo,
                        fontWeight: FontWeight.w700,
                        fontFamily: T.fontMono)),
                const SizedBox(width: 8),
                Text('${p.legs.length} ${tr('pred.top_tab_parlay')}',
                    style: const TextStyle(
                        fontSize: 11, color: T.inkMd, fontWeight: FontWeight.w700)),
                const Spacer(),
                StatusPill(status: betStatusFromString(p.status)),
              ],
            ),
            const SizedBox(height: 10),
            ...p.legs.map((leg) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      _legDot(leg.legStatus),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${localizedTeam(leg.home, apiZh: leg.homeZh)} vs ${localizedTeam(leg.away, apiZh: leg.awayZh)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: T.inkMd),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(_selectionLabel(leg.marketType, leg.score),
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: T.ink)),
                      const SizedBox(width: 8),
                      Text('@${leg.odds.toStringAsFixed(2)}',
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: T.gold,
                              fontFamily: T.fontMono)),
                    ],
                  ),
                )),
            const Divider(height: 18, color: T.border),
            Row(
              children: [
                Text(tr('pred.invest').replaceAll('{n}', p.stake.toStringAsFixed(0)),
                    style: const TextStyle(
                        fontSize: 11, color: T.inkLo, fontWeight: FontWeight.w600)),
                const SizedBox(width: 14),
                Text('@${p.totalOdds.toStringAsFixed(2)}',
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: T.brandDeep,
                        fontFamily: T.fontMono)),
                const Spacer(),
                Text(
                  '${p.payout > 0 ? '+' : ''}${_fmtBal.format(p.payout > 0 ? p.payout : p.stake * p.totalOdds)}',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: p.status == 'won' ? T.up : T.ink,
                      fontFamily: T.fontMono),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _legDot(String status) {
    Color c;
    switch (status) {
      case 'won':
        c = T.up;
      case 'lost':
        c = T.down;
      default:
        c = T.inkSubtle;
    }
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: c, shape: BoxShape.circle),
    );
  }

  Widget _empty(String title, String sub, IconData icon) {
    return LightCard(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 16),
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
            child: Icon(icon, color: T.inkLo, size: 32),
          ),
          const SizedBox(height: 12),
          Text(title,
              style: const TextStyle(
                  fontSize: 14, color: T.ink, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(sub, style: const TextStyle(fontSize: 11, color: T.inkLo)),
        ],
      ),
    );
  }
}

String _selectionLabel(String marketType, String score) {
  switch (marketType) {
    case MarketType.overUnder25:
      final at = score.lastIndexOf('@');
      String side = score;
      String? line;
      if (at > 0 && at < score.length - 1) {
        side = score.substring(0, at);
        line = score.substring(at + 1);
      }
      final l = line ?? '2.5';
      return (side == 'over' ? tr('pred.ou_over') : tr('pred.ou_under'))
          .replaceAll('{line}', l);
    case MarketType.btts:
      if (score == 'yes') return tr('pred.btts_yes');
      if (score == 'no') return tr('pred.btts_no');
      return score;
    case MarketType.matchWinner:
      if (score == 'home') return '${tr('detail.winner_title')} · ${tr('detail.win_home')}';
      if (score == 'draw') return '${tr('detail.winner_title')} · ${tr('detail.draw')}';
      if (score == 'away') return '${tr('detail.winner_title')} · ${tr('detail.win_away')}';
      return score;
    case MarketType.htOverUnder:
      final atH = score.lastIndexOf('@');
      if (atH > 0) {
        final s = score.substring(0, atH);
        final l = score.substring(atH + 1);
        return s == 'over'
            ? tr('detail.htou_over_sel').replaceAll('{line}', l)
            : tr('detail.htou_under_sel').replaceAll('{line}', l);
      }
      return tr('detail.htou_sel_fallback').replaceAll('{score}', score);
    case MarketType.asianHandicap:
      final at = score.lastIndexOf('@');
      if (at > 0 && at < score.length - 1) {
        final side = score.substring(0, at);
        final line = score.substring(at + 1);
        final sideLabel = side == 'home' ? tr('detail.win_home') : tr('detail.win_away');
        return '${tr('detail.handicap_title')} · $sideLabel $line';
      }
      if (score == 'home') return '${tr('detail.handicap_title')} · ${tr('detail.win_home')}';
      if (score == 'away') return '${tr('detail.handicap_title')} · ${tr('detail.win_away')}';
      return score;
    case MarketType.correctScore:
    default:
      return score;
  }
}

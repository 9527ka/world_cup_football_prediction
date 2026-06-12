import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/match.dart';
import '../../services/app_state.dart';
import '../../services/i18n.dart';
import '../../theme/tokens.dart';
import '../../widgets/light_card.dart';

/// 桌面排行榜。复用与移动端相同数据(leaderboard / homeConfig / myRank)。
/// 布局:居中 1100;周/月切换 + 奖池横幅 + 横排领奖台(左)与排名表格(右)。
class LeaderboardDesktopPage extends StatefulWidget {
  const LeaderboardDesktopPage({super.key, required this.state});
  final AppState state;

  @override
  State<LeaderboardDesktopPage> createState() => _LeaderboardDesktopPageState();
}

class _LeaderboardDesktopPageState extends State<LeaderboardDesktopPage> {
  static final _fmtBal = NumberFormat('#,##0.00');
  static final _fmtInt = NumberFormat('#,##0');

  String _period = 'week';
  late Future<_LBBundle> _future;
  final Map<String, _LBBundle> _cache = {};
  String _lastLocale = '';

  @override
  void initState() {
    super.initState();
    _lastLocale = I18n.instance.locale;
    _future = _load();
    I18n.instance.addListener(_onLocaleChanged);
  }

  @override
  void dispose() {
    I18n.instance.removeListener(_onLocaleChanged);
    super.dispose();
  }

  void _onLocaleChanged() {
    if (I18n.instance.locale == _lastLocale) return;
    _lastLocale = I18n.instance.locale;
    _cache.clear();
    if (mounted) setState(() => _future = _load());
  }

  Future<_LBBundle> _load({bool force = false}) async {
    if (!force && _cache.containsKey(_period)) return _cache[_period]!;
    final api = widget.state.api;
    final results = await Future.wait([
      api.leaderboard(limit: 10, period: _period),
      api.homeConfig(),
    ]);
    MyRank? myRank;
    if (widget.state.isAuthenticated) {
      try {
        myRank = await api.myRank(period: _period);
      } catch (_) {}
    }
    final bundle = _LBBundle(
      list: results[0] as List<LeaderboardEntry>,
      config: results[1] as HomeConfig,
      myRank: myRank,
    );
    _cache[_period] = bundle;
    return bundle;
  }

  void _switch(String p) => setState(() {
        _period = p;
        _future = _load();
      });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_LBBundle>(
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
        final bundle = snap.data!;
        final top3 = bundle.list.take(3).toList();
        final rest = bundle.list.skip(3).take(7).toList(); // 仅显示前 10 名(3 领奖台 + 7)
        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 24),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 920),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Text(tr('lb.title'),
                              style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  color: T.ink)),
                          const Spacer(),
                          _periodTabs(),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _rewardBanner(bundle.config.weeklyPool),
                      const SizedBox(height: 14),
                      // 领奖台:全宽横排三档(避免侧栏式留白)
                      top3.isEmpty ? _emptyCard() : _podiumCard(top3),
                      if (bundle.myRank != null) ...[
                        const SizedBox(height: 12),
                        _myRank(bundle.myRank!),
                      ],
                      const SizedBox(height: 12),
                      _rankTable(rest),
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

  Widget _periodTabs() {
    final opts = [
      ['week', tr('lb.tab_week')],
      ['month', tr('lb.tab_month')],
    ];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: T.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: opts.map((o) {
          final on = _period == o[0];
          return InkWell(
            borderRadius: BorderRadius.circular(9),
            onTap: () => _switch(o[0]),
            child: Container(
              height: 34,
              width: 96,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: on ? T.brandGradientShort : null,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(o[1],
                  style: TextStyle(
                      color: on ? Colors.white : T.inkMd,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _rewardBanner(double weeklyPool) {
    if (weeklyPool <= 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [Color(0x2DD9AB7A), Color(0x1AF5C656)]),
        border: Border.all(color: const Color(0x52D9AB7A)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.star_rounded, color: T.gold, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
                tr('lb.weekly_pool').replaceAll('{n}', _fmtInt.format(weeklyPool)),
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF7A4F0E))),
          ),
          Text(tr('lb.weekly_sub'),
              style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFFA06B2C),
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _emptyCard() {
    return LightCard(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 60),
          child: Text(tr('lb.empty'),
              style: const TextStyle(color: T.inkLo, fontSize: 14)),
        ),
      ),
    );
  }

  Widget _podiumCard(List<LeaderboardEntry> top3) {
    final padded = [...top3];
    while (padded.length < 3) {
      padded.add(LeaderboardEntry(
          userId: 0, username: '', firstName: tr('lb.placeholder'),
          wins: 0, total: 0, payout: 0));
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 26, 18, 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFF8EA), Color(0xFFFFE9C7), Colors.white],
        ),
        border: Border.all(color: const Color(0x52D9AB7A)),
        borderRadius: BorderRadius.circular(18),
        boxShadow: T.shadowCard,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(child: _podiumCol(padded[1], rank: 2, height: 100)),
          Expanded(child: _podiumCol(padded[0], rank: 1, height: 140)),
          Expanded(child: _podiumCol(padded[2], rank: 3, height: 82)),
        ],
      ),
    );
  }

  Widget _podiumCol(LeaderboardEntry u, {required int rank, required double height}) {
    final cfg = _podiumColors(rank);
    final size = rank == 1 ? 60.0 : 48.0;
    return Column(
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [
              BoxShadow(
                  color: cfg.c2.withValues(alpha: 0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 4))
            ],
          ),
          child: ClipOval(child: _avatar(u, size, gradient: [cfg.c1, cfg.c2])),
        ),
        const SizedBox(height: 8),
        Text(u.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w800, color: T.ink)),
        const SizedBox(height: 2),
        Text('${u.payout >= 0 ? '+' : ''}${_fmtBal.format(u.payout)}',
            style: TextStyle(
                fontSize: rank == 1 ? 15 : 13,
                fontWeight: FontWeight.w800,
                color: u.payout >= 0 ? T.upDark : T.down,
                fontFamily: T.fontMono)),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          height: height,
          decoration: BoxDecoration(
            gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [cfg.c1, cfg.c2]),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          ),
          alignment: Alignment.center,
          child: Text('$rank',
              style: TextStyle(
                  fontSize: rank == 1 ? 36 : 28,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  fontFamily: T.fontMono)),
        ),
      ],
    );
  }

  Widget _myRank(MyRank r) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0x1F2CD7FD),
        border: Border.all(color: const Color(0x402CD7FD)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: T.brandGradientShort,
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Text(r.rank == 0 ? '—' : '#${r.rank}',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    fontFamily: T.fontMono)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('lb.my_rank'),
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700, color: T.ink)),
                Text(
                    r.profit >= 0
                        ? tr('lb.my_profit_pos').replaceAll('{n}', _fmtBal.format(r.profit))
                        : tr('lb.my_profit_neg').replaceAll('{n}', _fmtBal.format(r.profit)),
                    style: const TextStyle(
                        fontSize: 11, color: T.inkLo, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _rankTable(List<LeaderboardEntry> rest) {
    return LightCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < rest.length; i++)
            _rankRow(rest[i], i + 4, divider: i > 0),
          if (rest.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Text(tr('lb.empty'),
                  style: const TextStyle(color: T.inkLo, fontSize: 13)),
            ),
        ],
      ),
    );
  }

  Widget _rankRow(LeaderboardEntry u, int rank, {required bool divider}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      decoration: BoxDecoration(
        border: divider ? const Border(top: BorderSide(color: T.border)) : null,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: Text('$rank',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: T.inkLo,
                    fontFamily: T.fontMono)),
          ),
          _avatar(u, 32, gradient: const [Color(0xFFC5CFDB), Color(0xFF8B95A5)]),
          const SizedBox(width: 12),
          Expanded(
            child: Text(u.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 13, color: T.ink, fontWeight: FontWeight.w700)),
          ),
          if (u.total > 0)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text('${u.wins}/${u.total}',
                  style: const TextStyle(
                      fontSize: 12, color: T.inkLo, fontFamily: T.fontMono)),
            ),
          Text('${u.payout >= 0 ? '+' : ''}${_fmtBal.format(u.payout)}',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: u.payout >= 0 ? T.upDark : T.down,
                  fontFamily: T.fontMono)),
          const SizedBox(width: 6),
          const Text('USDT',
              style: TextStyle(
                  fontSize: 9, color: T.inkLo, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _avatar(LeaderboardEntry u, double size, {List<Color>? gradient}) {
    final hasPhoto = u.photoUrl.isNotEmpty && u.userId > 0;
    if (hasPhoto) {
      return ClipOval(
        child: Image.network(u.photoUrl,
            width: size,
            height: size,
            fit: BoxFit.cover,
            cacheWidth: (size * 2).toInt(),
            cacheHeight: (size * 2).toInt(),
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => _fallback(u, size, gradient: gradient)),
      );
    }
    return _fallback(u, size, gradient: gradient);
  }

  Widget _fallback(LeaderboardEntry u, double size, {List<Color>? gradient}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
            colors: gradient ?? const [Color(0xFFC5CFDB), Color(0xFF8B95A5)]),
      ),
      alignment: Alignment.center,
      child: Text(
        u.displayName.isEmpty ? '?' : u.displayName.characters.first.toUpperCase(),
        style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.42,
            fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _PodiumCfg {
  final Color c1;
  final Color c2;
  const _PodiumCfg(this.c1, this.c2);
}

_PodiumCfg _podiumColors(int rank) {
  switch (rank) {
    case 1:
      return const _PodiumCfg(Color(0xFFFFE9B5), Color(0xFFD9AB7A));
    case 2:
      return const _PodiumCfg(Color(0xFFE5E5E5), Color(0xFF9BA9BD));
    default:
      return const _PodiumCfg(Color(0xFFF4B98C), Color(0xFFB5763E));
  }
}

class _LBBundle {
  final List<LeaderboardEntry> list;
  final HomeConfig config;
  final MyRank? myRank;
  _LBBundle({required this.list, required this.config, required this.myRank});
}

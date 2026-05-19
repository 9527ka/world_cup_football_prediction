import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/match.dart';
import '../services/app_state.dart';
import '../services/i18n.dart';
import '../theme/tokens.dart';
import '../widgets/light_card.dart';
import 'feature_pages.dart';

/// 06 · 排行榜 — 周/月/总切换 + 前 3 名领奖台 + 列表 + 我的位置。
class LeaderboardPage extends StatefulWidget {
  const LeaderboardPage({super.key, required this.state});
  final AppState state;

  @override
  State<LeaderboardPage> createState() => _LeaderboardPageState();
}

class _LeaderboardPageState extends State<LeaderboardPage> {
  String _period = 'week';
  late Future<_LBBundle> _future;
  String _lastLocale = '';

  @override
  void initState() {
    super.initState();
    _lastLocale = I18n.instance.locale;
    _future = _load();
    // 切语言时(zh ↔ 其它)后端会换虚拟池子 / 重新 seed,我们必须重拉一次。
    // 单纯 root tree rebuild(MaterialApp 包的 AnimatedBuilder)只会重 build,
    // 不会让 FutureBuilder 重新 future-= _load()。
    I18n.instance.addListener(_onLocaleChanged);
  }

  @override
  void dispose() {
    I18n.instance.removeListener(_onLocaleChanged);
    super.dispose();
  }

  void _onLocaleChanged() {
    final cur = I18n.instance.locale;
    if (cur == _lastLocale) return;
    _lastLocale = cur;
    if (!mounted) return;
    setState(() => _future = _load());
  }

  Future<_LBBundle> _load() async {
    final api = widget.state.api;
    // 公共榜单 + home config 是核心数据,必须成功。
    // 透传当前 locale:仅参与 seed(让中英子集略不同),池子是 60 名 CN+EN 混合(2026-05-18 起)。
    // 限 10 名:用户需求"只显示前 10",免堆叠太多虚拟玩家。
    final results = await Future.wait([
      api.leaderboard(limit: 10, period: _period, locale: I18n.instance.locale),
      api.homeConfig(),
    ]);
    // 我的排名是装饰性数据 — 401(token 过期)/网络失败时降级为 null,
    // 不能让它把整页拖崩(看公共榜单不需要登录)。
    MyRank? myRank;
    if (widget.state.isAuthenticated) {
      try {
        myRank = await api.myRank(period: _period);
      } catch (_) {/* silently skip "我的排名" section */}
    }
    return _LBBundle(
      list: results[0] as List<LeaderboardEntry>,
      config: results[1] as HomeConfig,
      myRank: myRank,
    );
  }

  void _switch(String p) {
    setState(() {
      _period = p;
      _future = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: T.bgPage,
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topCenter,
            radius: 1.4,
            colors: [Color(0xFFFFF5E8), Color(0xFFE8F4FF), Color(0xFFF4F8FC), Color(0xFFEEF2F7)],
            stops: [0.0, 0.3, 0.7, 1.0],
          ),
        ),
        child: SafeArea(
          child: FutureBuilder<_LBBundle>(
            future: _future,
            builder: (_, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(
                    child: CircularProgressIndicator(color: T.brandDeep));
              }
              if (snap.hasError) {
                return Center(
                    child: Text(tr('load_failed').replaceAll('{err}', '${snap.error}'),
                        style: const TextStyle(color: T.down)));
              }
              final bundle = snap.data!;
              final list = bundle.list;
              final top3 = list.take(3).toList();
              final rest = list.skip(3).take(20).toList();
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
                    _rewardBanner(bundle.config.weeklyPool),
                    _periodTabs(),
                    if (top3.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 40),
                        child: Center(
                            child: Text(tr('lb.empty'),
                                style: const TextStyle(color: T.inkLo, fontSize: 13))),
                      )
                    else
                      _podium(top3),
                    if (bundle.myRank != null) _myRank(bundle.myRank!),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: LightCard(
                        padding: EdgeInsets.zero,
                        child: Column(
                          children: [
                            for (var i = 0; i < rest.length; i++)
                              _rankRow(rest[i], i + 4, divider: i > 0),
                          ],
                        ),
                      ),
                    ),
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
          Text(tr('lb.title'),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: T.ink)),
          const Spacer(),
          const _RuleChip(),
        ],
      ),
    );
  }

  Widget _rewardBanner(double weeklyPool) {
    if (weeklyPool <= 0) return const SizedBox.shrink();
    final formatted = NumberFormat('#,##0').format(weeklyPool);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0x2DD9AB7A), Color(0x1AF5C656)],
          ),
          border: Border.all(color: const Color(0x52D9AB7A)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.star_rounded, color: T.gold, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr('lb.weekly_pool').replaceAll('{n}', formatted),
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF7A4F0E))),
                  const SizedBox(height: 2),
                  Text(tr('lb.weekly_sub'),
                      style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xFFA06B2C),
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            GestureDetector(
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const RulesPage())),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: const Color(0x66D9AB7A)),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(tr('lb.view'),
                    style: const TextStyle(
                        color: T.gold, fontSize: 11, fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _periodTabs() {
    final opts = [
      ['week', tr('lb.tab_week')],
      ['month', tr('lb.tab_month')],
      ['all', tr('lb.tab_all')],
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: T.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: opts.map((o) {
            final on = _period == o[0];
            return Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(9),
                onTap: () => _switch(o[0]),
                child: Container(
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: on ? T.brandGradientShort : null,
                    borderRadius: BorderRadius.circular(9),
                    boxShadow: on
                        ? const [
                            BoxShadow(
                                color: Color(0x5111BAD9), blurRadius: 8, offset: Offset(0, 4))
                          ]
                        : null,
                  ),
                  child: Text(o[1],
                      style: TextStyle(
                          color: on ? Colors.white : T.inkMd,
                          fontSize: 13,
                          fontWeight: FontWeight.w700)),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _podium(List<LeaderboardEntry> top3) {
    final padded = [...top3];
    while (padded.length < 3) {
      padded.add(LeaderboardEntry(
        userId: 0,
        username: '',
        firstName: tr('lb.placeholder'),
        wins: 0, total: 0, payout: 0,
      ));
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 20, 14, 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Color(0xFFFFF8EA), Color(0xFFFFE9C7), Colors.white],
          ),
          border: Border.all(color: const Color(0x52D9AB7A)),
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [
            BoxShadow(color: Color(0x2ED9AB7A), blurRadius: 18, offset: Offset(0, 6))
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(child: _podiumCol(padded[1], rank: 2, height: 88)),
            Expanded(child: _podiumCol(padded[0], rank: 1, height: 116)),
            Expanded(child: _podiumCol(padded[2], rank: 3, height: 72)),
          ],
        ),
      ),
    );
  }

  Widget _podiumCol(LeaderboardEntry u, {required int rank, required double height}) {
    final cfg = _podiumColors(rank);
    return Column(
      children: [
        Container(
          width: rank == 1 ? 56 : 46, height: rank == 1 ? 56 : 46,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [cfg.c1, cfg.c2],
            ),
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [
              BoxShadow(color: cfg.c2.withValues(alpha: 0.4), blurRadius: 12, offset: const Offset(0, 4))
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            u.displayName.isEmpty ? '?' : u.displayName.characters.first,
            style: TextStyle(
                color: Colors.white,
                fontSize: rank == 1 ? 22 : 18,
                fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          u.displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
              fontSize: 11, fontWeight: FontWeight.w800, color: T.ink),
        ),
        const SizedBox(height: 2),
        Text('${u.payout >= 0 ? '+' : ''}${NumberFormat('#,##0.00').format(u.payout)} U',
            style: TextStyle(
                fontSize: rank == 1 ? 14 : 12,
                fontWeight: FontWeight.w800,
                color: u.payout >= 0 ? T.upDark : T.down,
                fontFamily: T.fontMono)),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          height: height,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [cfg.c1, cfg.c2],
            ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
            boxShadow: [
              BoxShadow(
                  color: cfg.c2.withValues(alpha: 0.32),
                  blurRadius: 12,
                  offset: const Offset(0, 6))
            ],
            border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.7), width: 1)),
          ),
          alignment: Alignment.center,
          child: Text('$rank',
              style: TextStyle(
                  fontSize: rank == 1 ? 32 : 26,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  fontFamily: T.fontMono,
                  shadows: const [
                    Shadow(color: Color(0x33000000), blurRadius: 4, offset: Offset(0, 2))
                  ])),
        ),
      ],
    );
  }

  Widget _myRank(MyRank r) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: BoxDecoration(
          color: const Color(0x1F2CD7FD),
          border: Border.all(color: const Color(0x402CD7FD)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                gradient: T.brandGradientShort,
                borderRadius: BorderRadius.circular(10),
                boxShadow: const [
                  BoxShadow(
                      color: Color(0x5911BAD9), blurRadius: 10, offset: Offset(0, 4))
                ],
              ),
              alignment: Alignment.center,
              child: Text(r.rank == 0 ? '—' : '#${r.rank}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      fontFamily: T.fontMono)),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('lb.my_rank'),
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700, color: T.ink)),
                Text(
                  r.profit >= 0
                      ? tr('lb.my_profit_pos').replaceAll('{n}', NumberFormat('#,##0.00').format(r.profit))
                      : tr('lb.my_profit_neg').replaceAll('{n}', NumberFormat('#,##0.00').format(r.profit)),
                  style: const TextStyle(
                      fontSize: 10, color: T.inkLo, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _rankRow(LeaderboardEntry u, int rank, {required bool divider}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        border: divider
            ? const Border(top: BorderSide(color: T.border))
            : null,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text('$rank',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: T.inkLo,
                    fontFamily: T.fontMono)),
          ),
          Container(
            width: 30, height: 30,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFC5CFDB), T.inkLo],
              ),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(u.displayName.characters.first.toUpperCase(),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(u.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13, color: T.ink, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  tr('lb.row_settled')
                      .replaceAll('{total}', '${u.total}')
                      .replaceAll('{wins}', '${u.wins}'),
                  style: const TextStyle(
                      fontSize: 10,
                      color: T.inkLo,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${u.payout >= 0 ? '+' : ''}${NumberFormat('#,##0.00').format(u.payout)}',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: u.payout >= 0 ? T.upDark : T.down,
                    fontFamily: T.fontMono),
              ),
              const Text('USDT',
                  style: TextStyle(
                      fontSize: 9, color: T.inkLo, fontWeight: FontWeight.w600)),
            ],
          ),
        ],
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

class _RuleChip extends StatelessWidget {
  const _RuleChip();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0x1AD9AB7A),
        border: Border.all(color: const Color(0x47D9AB7A)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(tr('lb.rule_chip'),
          style: const TextStyle(
              color: T.gold, fontSize: 10, fontWeight: FontWeight.w700)),
    );
  }
}

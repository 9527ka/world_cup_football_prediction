import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/match.dart';
import '../../utils/ny_time.dart';
import '../../services/app_state.dart';
import '../../services/i18n.dart';
import '../../theme/tokens.dart';
import '../../utils/league_flags.dart';
import '../../utils/team_crests.dart';
import '../../utils/team_names.dart';
import '../../widgets/chain_icon.dart';
import '../../widgets/light_card.dart';

/// 桌面首页。复用与移动端首页相同的数据源(announcements / hotMatches /
/// recentSettled / stats),重排成宽屏布局:居中 1200 列、Hero 左右分栏、
/// 热门赛事 3 列网格、最近结果 2 列、合规收底。
class HomeDesktopPage extends StatefulWidget {
  const HomeDesktopPage({
    super.key,
    required this.state,
    required this.onOpenMatch,
    required this.onOpenFeature,
    required this.onGotoMatches,
    required this.onViewAllSettled,
  });

  final AppState state;
  final void Function(MatchInfo match) onOpenMatch;
  final void Function(String key) onOpenFeature;
  final VoidCallback onGotoMatches;
  final VoidCallback onViewAllSettled;

  @override
  State<HomeDesktopPage> createState() => _HomeDesktopPageState();
}

class _HomeDesktopPageState extends State<HomeDesktopPage> {
  static final _balFmt = NumberFormat('#,##0.00');
  static final _dateFmt = DateFormat('MM-dd HH:mm');

  List<String> _announcements = const [];
  List<HotMatch> _hot = const [];
  List<MatchInfo> _settled = const [];
  UserStats? _stats;

  @override
  void initState() {
    super.initState();
    _load();
    widget.state.addListener(_onState);
  }

  @override
  void dispose() {
    widget.state.removeListener(_onState);
    super.dispose();
  }

  void _onState() => setState(() {});

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        widget.state.api.announcements(),
        widget.state.api.hotMatches(limit: 6),
        widget.state.api.recentSettled(days: 3, limit: 8),
        if (widget.state.isAuthenticated) widget.state.api.getStats(),
      ]);
      if (!mounted) return;
      setState(() {
        _announcements = results[0] as List<String>;
        _hot = results[1] as List<HotMatch>;
        _settled = results[2] as List<MatchInfo>;
        if (widget.state.isAuthenticated) _stats = results[3] as UserStats;
      });
    } catch (_) {/* backend alerts via TG bot */}
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      color: T.brandDeep,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 24),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1200),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _topBar(),
                    const SizedBox(height: 18),
                    _heroRow(),
                    const SizedBox(height: 18),
                    _hotSection(),
                    const SizedBox(height: 26),
                    if (_settled.isNotEmpty) _settledSection(),
                    const SizedBox(height: 26),
                    _complianceFooter(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _topBar() {
    final bal = _stats?.balance ?? 0;
    return Row(
      children: [
        Text.rich(TextSpan(children: [
          TextSpan(
              text: tr('home.title_a'),
              style: const TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w900, color: T.ink)),
          TextSpan(
              text: tr('home.title_b'),
              style: const TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w900, color: T.brandDeep)),
        ])),
        const Spacer(),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color(0x662CD7FD)),
            boxShadow: T.shadowSoft,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ChainIcon(chain: 'trc20', size: 22),
              const SizedBox(width: 8),
              Text(tr('home.usdt_balance'),
                  style: const TextStyle(fontSize: 11, color: T.inkLo)),
              const SizedBox(width: 8),
              Text(_balFmt.format(bal),
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: T.ink,
                      fontFamily: T.fontMono,
                      fontFeatures: [FontFeature.tabularFigures()])),
            ],
          ),
        ),
      ],
    );
  }

  Widget _heroRow() {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 7, child: _heroBanner()),
          const SizedBox(width: 16),
          Expanded(flex: 5, child: _sideColumn()),
        ],
      ),
    );
  }

  Widget _heroBanner() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFC7E9FF), Color(0xFFDEF1FF), Color(0xFFE8F4FF), Color(0xFFF4F8FC)],
          stops: [0.0, 0.3, 0.6, 1.0],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x402CD7FD)),
        boxShadow: T.shadowCard,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [Color(0xFFFFE9C7), Color(0xFFFFF6E5)]),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(tr('home.tg_exclusive'),
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFB17B22),
                          letterSpacing: 0.6)),
                ),
                const SizedBox(height: 14),
                Text(tr('home.hero_main'),
                    style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        color: T.ink,
                        height: 1.05)),
                ShaderMask(
                  shaderCallback: (b) =>
                      const LinearGradient(colors: [T.brand, T.brand2])
                          .createShader(b),
                  child: Text(tr('home.hero_sub'),
                      style: const TextStyle(
                          fontSize: 38,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          height: 1.05)),
                ),
                const SizedBox(height: 10),
                Text(tr('home.hero_caption'),
                    style: const TextStyle(
                        fontSize: 13, color: T.inkMd, fontWeight: FontWeight.w500)),
                const SizedBox(height: 18),
                ElevatedButton(
                  onPressed: widget.onGotoMatches,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: T.brand,
                    foregroundColor: const Color(0xFF052433),
                    padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999)),
                    elevation: 4,
                  ),
                  child: Text(tr('home.feature_cta'),
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w800)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          Container(
            width: 160,
            height: 160,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(
                colors: [Colors.white, Color(0xFFE8F4FF), Color(0xFF9BC6E5)],
                stops: [0.0, 0.6, 1.0],
              ),
              border: Border.all(color: T.ink, width: 1.5),
              boxShadow: T.shadowGlowBrand,
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.sports_soccer, color: T.ink, size: 96),
          ),
        ],
      ),
    );
  }

  Widget _sideColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MarqueeCard(items: _announcements),
        const SizedBox(height: 12),
        Expanded(child: _roundEntriesCard()),
      ],
    );
  }

  Widget _roundEntriesCard() {
    final items = const [
      _RoundSpec('home.share_earn', 'assets/icons/share.png', badge: 'HOT'),
      _RoundSpec('home.rebate', 'assets/icons/rebate.png'),
      _RoundSpec('home.vip', 'assets/icons/vip.png'),
      _RoundSpec('home.service', 'assets/icons/service.png'),
      _RoundSpec('home.language', 'assets/icons/language.png'),
    ];
    return LightCard(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
      child: Center(
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 4,
          runSpacing: 10,
          children: items.map(_roundEntry).toList(),
        ),
      ),
    );
  }

  Widget _roundEntry(_RoundSpec s) {
    return SizedBox(
      width: 76,
      child: InkResponse(
        onTap: () => widget.onOpenFeature(s.label),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                SizedBox(
                  width: 44,
                  height: 44,
                  child: Center(
                    child: Image.asset(s.asset,
                        width: 40,
                        height: 40,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Icon(
                            Icons.help_outline, color: T.brandDeep, size: 24)),
                  ),
                ),
                if (s.badge != null)
                  Positioned(
                    top: -4,
                    right: -8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                          color: T.down, borderRadius: BorderRadius.circular(8)),
                      child: Text(s.badge!,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w800)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(tr(s.label),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 12, color: T.inkMd, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  Widget _hotSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(title: tr('home.hot'), subtitle: tr('home.hot_sub')),
        const SizedBox(height: 6),
        if (_hot.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: Text(tr('home.no_match'),
                  style: const TextStyle(color: T.inkLo, fontSize: 13)),
            ),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 380,
              mainAxisExtent: 168,
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
            ),
            itemCount: _hot.length,
            itemBuilder: (_, i) => _hotCard(_hot[i]),
          ),
      ],
    );
  }

  Widget _hotCard(HotMatch hm) {
    final m = hm.match;
    final live = m.isLive;
    return LightCard(
      padding: const EdgeInsets.all(14),
      onTap: () => widget.onOpenMatch(m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              LeagueFlag(slug: m.leagueSlug, height: 11, width: 16),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                    m.leagueName.isEmpty ? 'FOOTBALL' : localizedLeague(m.leagueName),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: T.brandDeep)),
              ),
              Text(_dateFmt.format(toNyWall(m.date)),
                  style: const TextStyle(
                      fontSize: 11, color: T.brandDeep, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              TeamCrest(name: m.home, id: m.homeId, leagueSlug: m.leagueSlug, size: 26),
              const SizedBox(width: 8),
              Expanded(
                child: Text(localizedTeam(m.home, apiZh: m.homeZh),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700, color: T.ink)),
              ),
              if (live && m.scores != null)
                Text('${m.scores!.home} : ${m.scores!.away}',
                    style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: T.brandDeep,
                        fontFamily: T.fontMono))
              else
                const Text('VS',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600, color: T.inkLo)),
              Expanded(
                child: Text(localizedTeam(m.away, apiZh: m.awayZh),
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700, color: T.ink)),
              ),
              const SizedBox(width: 8),
              TeamCrest(name: m.away, id: m.awayId, leagueSlug: m.leagueSlug, size: 26),
            ],
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0x1A2CD7FD), Color(0x0A5FBDFD)]),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0x332CD7FD)),
            ),
            child: Row(
              children: [
                Text(hm.bestScore.isEmpty ? '—' : hm.bestScore,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: T.ink,
                        fontFamily: T.fontMono)),
                const SizedBox(width: 8),
                Text(hm.bestOdds <= 0 ? '—' : hm.bestOdds.toStringAsFixed(2),
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFFE68E2E),
                        fontFamily: T.fontMono)),
                const Spacer(),
                Text('${hm.picks}${tr('home.feature_picks_suffix')}',
                    style: const TextStyle(fontSize: 11, color: T.inkLo)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _settledSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          title: tr('home.recent_results'),
          subtitle: tr('home.recent_results_sub'),
          trailing: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: widget.onViewAllSettled,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Text(tr('home.view_all'),
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: T.brandDeep)),
            ),
          ),
        ),
        const SizedBox(height: 6),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 580,
            mainAxisExtent: 58,
            crossAxisSpacing: 14,
            mainAxisSpacing: 10,
          ),
          itemCount: _settled.length,
          itemBuilder: (_, i) => _settledCard(_settled[i]),
        ),
      ],
    );
  }

  Widget _settledCard(MatchInfo m) {
    final sc = m.scores;
    final hg = sc?.home ?? 0;
    final ag = sc?.away ?? 0;
    final homeWon = hg > ag;
    final awayWon = ag > hg;
    return LightCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      onTap: () => widget.onOpenMatch(m),
      child: Row(
        children: [
          SizedBox(
            width: 92,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(localizedLeague(m.leagueName),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: T.inkLo)),
                const SizedBox(height: 2),
                Text(_dateFmt.format(toNyWall(m.date)),
                    style: const TextStyle(fontSize: 9, color: T.inkLo)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(localizedTeam(m.home, apiZh: m.homeZh),
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: homeWon ? T.upDark : T.ink)),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 10),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
                color: const Color(0xFFEEF2F7),
                borderRadius: BorderRadius.circular(6)),
            child: Text('$hg : $ag',
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    fontFamily: T.fontMono,
                    color: T.ink)),
          ),
          Expanded(
            child: Text(localizedTeam(m.away, apiZh: m.awayZh),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: awayWon ? T.upDark : T.ink)),
          ),
        ],
      ),
    );
  }

  Widget _complianceFooter() {
    return LightCard(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      radius: 12,
      child: Column(
        children: [
          Text(tr('home.licenses'),
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: T.inkMd,
                  letterSpacing: 0.6)),
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            children: [
              ...['GCB', 'MGA', 'PAGCOR'].map((l) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0x0A0E2238),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0x100E2238)),
                    ),
                    child: Text(l,
                        style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: T.inkMd)),
                  )),
              const ChainIcon(chain: 'trc20', size: 26),
              const ChainIcon(chain: 'eth', size: 26),
              const ChainIcon(chain: 'btc', size: 26),
            ],
          ),
          const SizedBox(height: 12),
          Text(tr('home.responsible'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 10, color: T.inkLo, height: 1.5)),
          Text(tr('home.copyright'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 10, color: T.inkLo, height: 1.5)),
        ],
      ),
    );
  }
}

class _RoundSpec {
  final String label;
  final String asset;
  final String? badge;
  const _RoundSpec(this.label, this.asset, {this.badge});
}

class _MarqueeCard extends StatefulWidget {
  const _MarqueeCard({required this.items});
  final List<String> items;

  @override
  State<_MarqueeCard> createState() => _MarqueeCardState();
}

class _MarqueeCardState extends State<_MarqueeCard> {
  int _idx = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(_MarqueeCard old) {
    super.didUpdateWidget(old);
    if (widget.items.length != old.items.length) {
      _idx = 0;
      _start();
    }
  }

  void _start() {
    _timer?.cancel();
    if (widget.items.length > 1) {
      _timer = Timer.periodic(const Duration(seconds: 3), (_) {
        if (mounted) setState(() => _idx = (_idx + 1) % widget.items.length);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items.isEmpty ? [tr('home.no_announce')] : widget.items;
    return LightCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      radius: 12,
      child: Row(
        children: [
          const Icon(Icons.notifications_outlined, color: T.brandDeep, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(items[_idx % items.length],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 12, color: T.inkMd, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}

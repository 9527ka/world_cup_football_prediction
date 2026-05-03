import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/match.dart';
import '../services/app_state.dart';
import '../services/i18n.dart';
import '../theme/tokens.dart';
import '../utils/league_flags.dart';
import '../utils/team_crests.dart';
import '../utils/team_names.dart';
import '../widgets/light_card.dart';
import 'feature_pages.dart';
import 'match_detail_page.dart';

/// 01 · 首页 — 浅色 7t 气质,USDT 余额 + Hero + 跑马灯 + 5 圆形入口
/// + 唯一玩法(足球波胆)+ 热门赛事 + 合规牌照。
class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.state, required this.onJumpTab});
  final AppState state;
  final ValueChanged<int> onJumpTab; // jump main shell tab

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<String> _announcements = const [];
  int _marqueeIdx = 0;
  Timer? _marqueeTimer;
  List<HotMatch> _hot = const [];
  UserStats? _stats;

  @override
  void initState() {
    super.initState();
    _load();
    widget.state.addListener(_onState);
  }

  @override
  void dispose() {
    _marqueeTimer?.cancel();
    widget.state.removeListener(_onState);
    super.dispose();
  }

  void _onState() => setState(() {});

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        widget.state.api.announcements(),
        widget.state.api.hotMatches(limit: 4),
        if (widget.state.isAuthenticated) widget.state.api.getStats(),
      ]);
      if (!mounted) return;
      setState(() {
        _announcements = results[0] as List<String>;
        _hot = results[1] as List<HotMatch>;
        if (widget.state.isAuthenticated) _stats = results[2] as UserStats;
      });
      if (_announcements.isNotEmpty) {
        _marqueeTimer?.cancel();
        _marqueeTimer = Timer.periodic(const Duration(seconds: 3), (_) {
          if (!mounted) return;
          setState(() => _marqueeIdx = (_marqueeIdx + 1) % _announcements.length);
        });
      }
    } catch (_) {/* show defaults silently */}
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      color: T.brandDeep,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          _topBar(),
          const SizedBox(height: 6),
          _heroBanner(),
          const SizedBox(height: 12),
          _marquee(),
          const SizedBox(height: 16),
          _roundEntries(),
          const SizedBox(height: 8),
          _featureCard(),
          SectionTitle(title: tr('home.hot'), subtitle: tr('home.hot_sub')),
          ..._hot.map(_hotCard),
          if (_hot.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text(tr('home.no_match'),
                    style: const TextStyle(color: T.inkLo, fontSize: 12)),
              ),
            ),
          const SizedBox(height: 24),
          _coins(),
          const SizedBox(height: 16),
          _complianceFooter(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ── top bar ───────────────────────────────────────────────────────
  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
      child: Row(
        children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              gradient: T.brandGradient,
              borderRadius: BorderRadius.circular(10),
              boxShadow: const [
                BoxShadow(
                    color: Color(0x732CD7FD), blurRadius: 14, offset: Offset(0, 6))
              ],
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.sports_soccer, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(children: [
                  TextSpan(
                      text: tr('home.title_a'),
                      style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: T.ink,
                          letterSpacing: -0.3)),
                  TextSpan(
                      text: tr('home.title_b'),
                      style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: T.brandDeep,
                          letterSpacing: -0.3)),
                ]),
              ),
              const SizedBox(height: 2),
              Text(tr('home.subtitle'),
                  style: const TextStyle(
                      fontSize: 9, color: T.inkLo, letterSpacing: 0.4)),
            ],
          ),
          const Spacer(),
          _balancePill(),
        ],
      ),
    );
  }

  Widget _balancePill() {
    final bal = _stats?.balance ?? 0;
    return InkWell(
      onTap: () => widget.onJumpTab(2),
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 5, 6, 5),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0x662CD7FD)),
          boxShadow: const [
            BoxShadow(
                color: Color(0x332CD7FD), blurRadius: 12, offset: Offset(0, 4))
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 22, height: 22,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: [Color(0xFF50C878), Color(0xFF1A9D5C)],
                ),
              ),
              alignment: Alignment.center,
              child: const Text('₮',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 12)),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('home.usdt_balance'),
                    style: const TextStyle(fontSize: 9, color: T.inkLo, letterSpacing: 0.4)),
                Text(
                  NumberFormat('#,##0.00').format(bal),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: T.ink,
                    fontFamily: T.fontMono,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            const SizedBox(width: 6),
            Container(
              width: 26, height: 26,
              decoration: const BoxDecoration(
                shape: BoxShape.circle, gradient: T.brandGradientShort,
                boxShadow: [
                  BoxShadow(color: Color(0x732CD7FD), blurRadius: 6, offset: Offset(0, 2))
                ],
              ),
              child: const Icon(Icons.add, color: Colors.white, size: 16),
            ),
          ],
        ),
      ),
    );
  }

  // ── hero banner ───────────────────────────────────────────────────
  Widget _heroBanner() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Container(
        height: 148,
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [Color(0xFFC7E9FF), Color(0xFFDEF1FF), Color(0xFFE8F4FF), Color(0xFFF4F8FC)],
            stops: [0.0, 0.3, 0.6, 1.0],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0x402CD7FD)),
          boxShadow: const [
            BoxShadow(color: Color(0x332CD7FD), blurRadius: 18, offset: Offset(0, 6))
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFFE9C7), Color(0xFFFFF6E5)],
                      ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(tr('home.tg_exclusive'),
                        style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFFB17B22),
                            letterSpacing: 0.6)),
                  ),
                  const SizedBox(height: 8),
                  Text(tr('home.hero_main'),
                      style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: T.ink,
                          height: 1.05,
                          letterSpacing: -0.3)),
                  ShaderMask(
                    shaderCallback: (b) => const LinearGradient(
                      colors: [T.brand, T.brand2],
                    ).createShader(b),
                    child: Text(tr('home.hero_sub'),
                        style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            height: 1.05,
                            letterSpacing: -0.3)),
                  ),
                  const SizedBox(height: 6),
                  Text(tr('home.hero_caption'),
                      style: const TextStyle(
                          fontSize: 11, color: T.inkMd, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
            // football illustration (simplified)
            Container(
              width: 110, height: 110,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const RadialGradient(
                  colors: [Colors.white, Color(0xFFE8F4FF), Color(0xFF9BC6E5)],
                  stops: [0.0, 0.6, 1.0],
                ),
                border: Border.all(color: T.ink, width: 1.5),
                boxShadow: const [
                  BoxShadow(color: Color(0x732CD7FD), blurRadius: 16, offset: Offset(0, 8))
                ],
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.sports_soccer, color: T.ink, size: 64),
            ),
          ],
        ),
      ),
    );
  }

  // ── marquee ────────────────────────────────────────────────────────
  Widget _marquee() {
    final items = _announcements.isEmpty
        ? [tr('home.no_announce')]
        : _announcements;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: LightCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        radius: 12,
        child: Row(
          children: [
            const Icon(Icons.notifications_outlined, color: T.brandDeep, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                transitionBuilder: (child, anim) => SlideTransition(
                  position: Tween<Offset>(
                          begin: const Offset(0, 1), end: Offset.zero)
                      .animate(anim),
                  child: child,
                ),
                child: Text(
                  items[_marqueeIdx % items.length],
                  key: ValueKey(_marqueeIdx),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12, color: T.inkMd, fontWeight: FontWeight.w500),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── round entries ─────────────────────────────────────────────────
  Widget _roundEntries() {
    final items = const [
      _RoundSpec('home.share_earn', Icons.share_outlined, badge: 'HOT'),
      _RoundSpec('home.rebate', Icons.percent_outlined),
      _RoundSpec('home.vip', Icons.workspace_premium_outlined),
      _RoundSpec('home.service', Icons.support_agent_outlined),
      _RoundSpec('home.rules', Icons.help_outline),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: items.map((s) => Expanded(child: _roundEntry(s))).toList(),
      ),
    );
  }

  void _openFeature(String key) {
    Widget? page;
    switch (key) {
      case 'home.share_earn':
        page = const ShareEarnPage();
        break;
      case 'home.rebate':
        page = const RebatePage();
        break;
      case 'home.vip':
        page = const VipPage();
        break;
      case 'home.service':
        page = const CustomerServicePage();
        break;
      case 'home.rules':
        page = const RulesPage();
        break;
    }
    if (page != null) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => page!));
    }
  }

  Widget _roundEntry(_RoundSpec s) {
    return InkResponse(
      onTap: () => _openFeature(s.label),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 52, height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                      colors: [Color(0xFF5FE5FE), Color(0xFF2CD7FD)],
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x662CD7FD),
                        blurRadius: 12,
                        offset: Offset(0, 6),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Icon(s.icon, color: Colors.white, size: 24),
                ),
                if (s.badge != null)
                  Positioned(
                    top: -4, right: -10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: T.down,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(s.badge!,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.4)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(tr(s.label),
                style: const TextStyle(
                    fontSize: 12, color: T.inkMd, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  // ── feature card (足球波胆) ────────────────────────────────────────
  Widget _featureCard() {
    final scores = const [
      ['1:0', '6.50', false],
      ['2:1', '8.20', true],
      ['1:1', '5.40', false],
      ['0:2', '8.40', false],
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [Colors.white, Color(0xFFF0F8FF)],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0x4D2CD7FD)),
          boxShadow: const [
            BoxShadow(color: Color(0x140E2238), blurRadius: 24, offset: Offset(0, 8))
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr('home.feature_title'),
                      style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: T.ink,
                          letterSpacing: -0.3)),
                  const SizedBox(height: 4),
                  Text(tr('home.feature_subtitle'),
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: T.inkLo,
                          letterSpacing: 1.5)),
                  const SizedBox(height: 10),
                  Text(tr('home.feature_desc1'),
                      style: const TextStyle(
                          fontSize: 12,
                          color: T.inkMd,
                          height: 1.4)),
                  Text(tr('home.feature_desc2'),
                      style: const TextStyle(
                          fontSize: 12,
                          color: T.brandDeep,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () => widget.onJumpTab(1),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: T.brand,
                      foregroundColor: const Color(0xFF052433),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 0),
                      minimumSize: const Size(0, 32),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999)),
                      elevation: 4,
                    ),
                    child: Text(tr('home.feature_cta'),
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w800)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              children: scores.map((s) {
                final hot = s[2] as bool;
                return Container(
                  width: 96,
                  margin: const EdgeInsets.only(bottom: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    gradient: hot
                        ? const LinearGradient(
                            colors: [Color(0xFFFFE9C7), Color(0xFFFFF6E5)])
                        : null,
                    color: hot ? null : Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: hot ? const Color(0xFFF0C896) : T.border),
                  ),
                  child: Row(
                    children: [
                      Text(s[0] as String,
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: T.ink,
                              fontFamily: T.fontMono)),
                      const Spacer(),
                      Text(s[1] as String,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: hot
                                  ? const Color(0xFFB17B22)
                                  : T.brandDeep,
                              fontFamily: T.fontMono)),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  // ── hot match card ────────────────────────────────────────────────
  Widget _hotCard(HotMatch hm) {
    final m = hm.match;
    final live = m.isLive;
    final fmt = DateFormat('MM-dd HH:mm');
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: LightCard(
        padding: const EdgeInsets.all(12),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => MatchDetailPage(state: widget.state, match: m)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0x202CD7FD),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      LeagueFlag(slug: m.leagueSlug, height: 11, width: 16),
                      const SizedBox(width: 5),
                      Text(m.leagueName.isEmpty ? 'FOOTBALL' : localizedLeague(m.leagueName),
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: T.brandDeep)),
                    ],
                  ),
                ),
                const Spacer(),
                if (live)
                  _LiveBadge(
                    minute: m.scores == null
                        ? 'LIVE'
                        : 'LIVE',
                  )
                else
                  Text(fmt.format(m.date),
                      style: const TextStyle(
                          fontSize: 11,
                          color: T.brandDeep,
                          fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                TeamCrest(name: m.home, leagueSlug: m.leagueSlug, size: 28),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(localizedTeam(m.home),
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: T.ink)),
                ),
                if (live && m.scores != null)
                  Text('${m.scores!.home} : ${m.scores!.away}',
                      style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: T.brandDeep,
                          fontFamily: T.fontMono))
                else
                  const Text('VS',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: T.inkLo)),
                Expanded(
                  child: Text(localizedTeam(m.away),
                      textAlign: TextAlign.right,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: T.ink)),
                ),
                const SizedBox(width: 8),
                TeamCrest(name: m.away, leagueSlug: m.leagueSlug, size: 28),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0x1A2CD7FD), Color(0x0A5FBDFD)],
                ),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0x332CD7FD)),
              ),
              child: Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr('home.feature_hot_label'),
                          style: const TextStyle(
                              fontSize: 10, color: T.inkLo, letterSpacing: 0.4)),
                      const SizedBox(height: 1),
                      Row(
                        children: [
                          Text(hm.bestScore.isEmpty ? '—' : hm.bestScore,
                              style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: T.ink,
                                  fontFamily: T.fontMono)),
                          const SizedBox(width: 6),
                          Text(
                            hm.bestOdds <= 0 ? '—' : hm.bestOdds.toStringAsFixed(2),
                            style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFFE68E2E),
                                fontFamily: T.fontMono),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text('${hm.picks}${tr('home.feature_picks_suffix')}',
                      style: const TextStyle(
                          fontSize: 11, color: T.inkLo)),
                  const SizedBox(width: 10),
                  Container(
                    height: 30,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                          colors: [Color(0xFF5FE5FE), Color(0xFF2CD7FD)]),
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: const [
                        BoxShadow(
                            color: Color(0x592CD7FD),
                            blurRadius: 8,
                            offset: Offset(0, 3)),
                      ],
                    ),
                    child: Text(tr('home.feature_bet_cta'),
                        style: const TextStyle(
                            color: Color(0xFF052433),
                            fontSize: 12,
                            fontWeight: FontWeight.w800)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── coins / footer ────────────────────────────────────────────────
  Widget _coins() {
    final coins = const [
      ['₮', 'USDT', 0xFF1A9D5C],
      ['₿', 'BTC', 0xFFF7931A],
      ['Ξ', 'ETH', 0xFF627EEA],
      ['T', 'TRX', 0xFFE03E2D],
      ['\$', 'USDC', 0xFF2775CA],
      ['B', 'BNB', 0xFFF0B90B],
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: coins.map((c) {
          return Container(
            width: 30, height: 30,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Color(c[2] as int),
              boxShadow: const [
                BoxShadow(
                    color: Color(0x1F000000), blurRadius: 6, offset: Offset(0, 2))
              ],
            ),
            alignment: Alignment.center,
            child: Text(c[0] as String,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    fontFamily: T.fontMono)),
          );
        }).toList(),
      ),
    );
  }

  Widget _complianceFooter() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: LightCard(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        radius: 12,
        child: Column(
          children: [
            Text(tr('home.licenses'),
                style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: T.inkMd,
                    letterSpacing: 0.6)),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: ['GCB', 'MGA', 'PAGCOR'].map((l) {
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0x0A0E2238),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0x100E2238)),
                  ),
                  child: Text(l,
                      style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: T.inkMd,
                          letterSpacing: 0.4)),
                );
              }).toList(),
            ),
            const SizedBox(height: 10),
            Text(tr('home.responsible'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 10, color: T.inkLo, height: 1.5)),
            Text(tr('home.copyright'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 10, color: T.inkLo, height: 1.5)),
          ],
        ),
      ),
    );
  }
}

class _RoundSpec {
  final String label;
  final IconData icon;
  final String? badge;
  const _RoundSpec(this.label, this.icon, {this.badge});
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge({required this.minute});
  final String minute;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      height: 18,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0xFFF4493B), T.down],
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      alignment: Alignment.center,
      child: Text(minute,
          style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4)),
    );
  }
}

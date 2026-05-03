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
import '../widgets/odds_chip.dart';
import 'deposit_page.dart';
import 'match_detail_page.dart';

/// 02 · 比赛列表 — 联赛筛选 chips、搜索、余额卡、分页加载、跳详情。
class MatchListPage extends StatefulWidget {
  const MatchListPage({super.key, required this.state});
  final AppState state;

  @override
  State<MatchListPage> createState() => _MatchListPageState();
}

class _MatchListPageState extends State<MatchListPage> {
  String? _league;
  UserStats? _stats;

  // search
  bool _searching = false;
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  // pagination
  final List<MatchInfo> _matches = [];
  int _total = 0;
  bool _loading = false;
  bool _hasMore = true;
  static const _pageSize = 20;
  final _scrollCtrl = ScrollController();
  final _chipScrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadStats();
    _loadPage(reset: true);
    _scrollCtrl.addListener(_onScroll);
    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    _chipScrollCtrl.dispose();
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >= _scrollCtrl.position.maxScrollExtent - 200) {
      _loadPage();
    }
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _loadPage(reset: true);
    });
  }

  Future<void> _loadStats() async {
    if (!widget.state.isAuthenticated) return;
    try {
      final s = await widget.state.api.getStats();
      if (mounted) setState(() => _stats = s);
    } catch (_) {}
  }

  Future<void> _loadPage({bool reset = false}) async {
    if (_loading) return;
    if (!reset && !_hasMore) return;

    setState(() => _loading = true);

    final offset = reset ? 0 : _matches.length;
    try {
      final page = await widget.state.api.listMatches(
        league: _league,
        search: _searchCtrl.text.trim(),
        offset: offset,
        limit: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        if (reset) _matches.clear();
        _matches.addAll(page.matches);
        _total = page.total;
        _hasMore = page.hasMore;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showAnnouncements() async {
    try {
      final items = await widget.state.api.announcements();
      if (!mounted) return;
      showModalBottomSheet(
        context: context,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
        builder: (_) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36, height: 4,
                  decoration: BoxDecoration(
                    color: T.inkSubtle,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(tr('matches.announce_title'),
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800, color: T.ink)),
              const SizedBox(height: 12),
              if (items.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                      child: Text(tr('matches.announce_empty'),
                          style: const TextStyle(color: T.inkLo, fontSize: 13))),
                )
              else
                ...items.map((item) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.campaign_outlined,
                              color: T.brandDeep, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(item,
                                style: const TextStyle(
                                    fontSize: 13,
                                    color: T.inkMd,
                                    height: 1.5)),
                          ),
                        ],
                      ),
                    )),
            ],
          ),
        ),
      );
    } catch (_) {}
  }

  void _setLeague(String? league) {
    if (_league == league) return;
    // 仅切换 chip 高亮 — 不重新拉数据,不替换列表,不动滚动位置。
    // 列表通过 build 内的客户端筛选立即响应。后台静默更新数据,仅在用户回到顶部时才会显式 reload。
    setState(() => _league = league);
  }

  @override
  Widget build(BuildContext context) {
    // extract leagues from loaded matches for chips
    final leagues = <String, String>{};
    for (final m in _matches) {
      if (m.leagueSlug.isNotEmpty) {
        leagues[m.leagueSlug] = m.leagueName;
      }
    }
    // also add leagues from global state for complete list
    for (final m in widget.state.matches) {
      if (m.leagueSlug.isNotEmpty) {
        leagues[m.leagueSlug] = m.leagueName;
      }
    }

    return RefreshIndicator(
      color: T.brandDeep,
      onRefresh: () async {
        await _loadPage(reset: true);
        await _loadStats();
      },
      child: Builder(builder: (_) {
        final visible = _league == null
            ? _matches
            : _matches.where((m) => m.leagueSlug == _league).toList();
        return ListView.builder(
          controller: _scrollCtrl,
          padding: EdgeInsets.zero,
          itemCount: visible.length + 3 + (_loading || _hasMore ? 1 : 0),
          itemBuilder: (context, index) {
            if (index == 0) return _searching ? _searchBar() : _topBar();
            if (index == 1) return _balanceCard();
            if (index == 2) return _leagueChips(leagues);
            final matchIndex = index - 3;
            if (matchIndex < visible.length) {
              return _card(visible[matchIndex]);
            }
            if (_loading) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: CircularProgressIndicator(color: T.brandDeep, strokeWidth: 2)),
              );
            }
            if (!_hasMore && visible.isNotEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Text(tr('matches.loaded_all').replaceAll('{n}', '$_total'),
                      style: const TextStyle(color: T.inkLo, fontSize: 12)),
                ),
              );
            }
            return const SizedBox(height: 24);
          },
        );
      }),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Row(
        children: [
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(
              gradient: T.brandGradientShort,
              borderRadius: BorderRadius.circular(10),
              boxShadow: const [
                BoxShadow(
                    color: Color(0x592CD7FD), blurRadius: 12, offset: Offset(0, 4))
              ],
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.sports_soccer, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(TextSpan(children: [
                TextSpan(
                    text: tr('matches.title_a'),
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800, color: T.ink)),
                TextSpan(
                    text: tr('matches.title_b'),
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: T.brandDeep)),
                TextSpan(
                    text: tr('matches.title_c'),
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800, color: T.ink)),
              ])),
              const SizedBox(height: 2),
              Text(tr('matches.subtitle'),
                  style: const TextStyle(
                      fontSize: 9, color: T.inkLo, letterSpacing: 1.8)),
            ],
          ),
          const Spacer(),
          _iconBtn(Icons.search, onTap: () => setState(() => _searching = true)),
          const SizedBox(width: 8),
          _iconBtn(Icons.notifications_outlined, onTap: _showAnnouncements),
        ],
      ),
    );
  }

  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0x402CD7FD)),
                boxShadow: const [
                  BoxShadow(color: Color(0x0A0E2238), blurRadius: 6, offset: Offset(0, 2)),
                ],
              ),
              child: TextField(
                controller: _searchCtrl,
                autofocus: true,
                style: const TextStyle(fontSize: 14, color: T.ink),
                decoration: InputDecoration(
                  hintText: tr('matches.search_hint'),
                  hintStyle: const TextStyle(color: T.inkLo, fontSize: 13),
                  prefixIcon: const Icon(Icons.search, color: T.brandDeep, size: 20),
                  suffixIcon: _searchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close, size: 18, color: T.inkLo),
                          onPressed: () {
                            _searchCtrl.clear();
                            _loadPage(reset: true);
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: () {
              _searchCtrl.clear();
              setState(() => _searching = false);
              _loadPage(reset: true);
            },
            child: Text(tr('common.cancel'),
                style: const TextStyle(
                    fontSize: 14, color: T.brandDeep, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _iconBtn(IconData icon, {VoidCallback? onTap}) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: const Color(0xB3FFFFFF),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: T.border),
            boxShadow: const [
              BoxShadow(color: Color(0x0A0E2238), blurRadius: 6, offset: Offset(0, 2)),
            ],
          ),
          child: Icon(icon, size: 18, color: T.ink),
        ),
      );

  Widget _balanceCard() {
    final bal = _stats?.balance ?? 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          gradient: T.heroGradient,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0x402CD7FD)),
          boxShadow: const [
            BoxShadow(
                color: Color(0x1F2CD7FD), blurRadius: 14, offset: Offset(0, 4))
          ],
        ),
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('matches.balance_label'),
                    style: const TextStyle(
                        fontSize: 11, color: T.inkMd, fontWeight: FontWeight.w600)),
                const SizedBox(height: 3),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      NumberFormat('#,##0.00').format(bal),
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: T.ink,
                        fontFamily: T.fontMono,
                        fontFeatures: [FontFeature.tabularFigures()],
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text('USDT',
                        style: TextStyle(
                            fontSize: 11,
                            color: T.brandDeep,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ],
            ),
            const Spacer(),
            ElevatedButton.icon(
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => DepositPage(state: widget.state))),
              style: ElevatedButton.styleFrom(
                backgroundColor: T.brand,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                minimumSize: const Size(0, 32),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999)),
                elevation: 4,
              ),
              icon: const Icon(Icons.add, size: 14),
              label: Text(tr('matches.deposit_btn'),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _leagueChips(Map<String, String> leagues) {
    final entries = [MapEntry<String?, String>(null, tr('matches.league_all')), ...leagues.entries.map((e) => MapEntry<String?, String>(e.key, e.value))];
    return SizedBox(
      height: 44,
      child: ListView.separated(
        controller: _chipScrollCtrl,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        scrollDirection: Axis.horizontal,
        itemCount: entries.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final e = entries[i];
          final on = _league == e.key;
          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _setLeague(e.key),
              borderRadius: BorderRadius.circular(999),
              child: Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: on
                      ? const LinearGradient(
                          colors: [Color(0x2E2CD7FD), Color(0x0F2CD7FD)],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        )
                      : null,
                  color: on ? null : Colors.white,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: on ? T.brand : T.border),
                  boxShadow: on
                      ? const [
                          BoxShadow(
                              color: Color(0x2E2CD7FD),
                              blurRadius: 8,
                              offset: Offset(0, 3))
                        ]
                      : null,
                ),
                child: Text(e.key == null ? e.value : localizedLeague(e.value),
                    style: TextStyle(
                        fontSize: 13,
                        color: on ? T.brandDeep : T.inkMd,
                        fontWeight: FontWeight.w700)),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _card(MatchInfo m) {
    final fmt = DateFormat('MM-dd HH:mm');
    final live = m.isLive;
    final ended = m.isSettled;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: LightCard(
        padding: const EdgeInsets.all(14),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => MatchDetailPage(state: widget.state, match: m)),
        ),
        child: Stack(
          children: [
            if (live)
              Positioned.fill(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    width: 3,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter, end: Alignment.bottomCenter,
                        colors: [T.down, Color(0xFFFF7A6E)],
                      ),
                    ),
                  ),
                ),
              ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    LeagueFlag(slug: m.leagueSlug, height: 12, width: 18),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(localizedLeague(m.leagueName),
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 11,
                              color: T.inkLo,
                              fontWeight: FontWeight.w600)),
                    ),
                    if (live) const _MiniLive() else if (ended) _miniBadge(tr('matches.ended'), T.inkLo, const Color(0xFFEEF2F7)) else _miniBadge(tr('matches.pending'), T.brandDeep, const Color(0x202CD7FD)),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    TeamCrest(name: m.home, leagueSlug: m.leagueSlug, size: 32),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(localizedTeam(m.home),
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: T.ink)),
                    ),
                    SizedBox(
                      width: 78,
                      child: m.scores != null
                          ? Center(
                              child: Text(
                                '${m.scores!.home} : ${m.scores!.away}',
                                style: TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w800,
                                  color: live ? T.brandDeep : T.ink,
                                  fontFamily: T.fontMono,
                                ),
                              ),
                            )
                          : Column(
                              children: [
                                const Text('VS',
                                    style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w800,
                                        color: T.inkLo,
                                        fontFamily: T.fontMono)),
                                Text(fmt.format(m.date),
                                    style: const TextStyle(
                                        fontSize: 10,
                                        color: T.brandDeep,
                                        fontWeight: FontWeight.w700)),
                              ],
                            ),
                    ),
                    Expanded(
                      child: Text(localizedTeam(m.away),
                          textAlign: TextAlign.right,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: T.ink)),
                    ),
                    const SizedBox(width: 8),
                    TeamCrest(name: m.away, leagueSlug: m.leagueSlug, size: 32),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: OddsChip(label: tr('detail.win_home'), price: 0, change: null)),
                    const SizedBox(width: 6),
                    Expanded(child: OddsChip(label: tr('detail.draw'), price: 0, change: null)),
                    const SizedBox(width: 6),
                    Expanded(child: OddsChip(label: tr('detail.win_away'), price: 0, change: null)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      width: 5, height: 5,
                      decoration: const BoxDecoration(
                          color: T.brand, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 4),
                    Text(tr('matches.live_caption'),
                        style: const TextStyle(fontSize: 11, color: T.inkLo)),
                    const Spacer(),
                    Text(tr('matches.cta'),
                        style: const TextStyle(
                            fontSize: 11,
                            color: T.brandDeep,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static Widget _miniBadge(String text, Color fg, Color bg) => Container(
        height: 20,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
        child: Text(text,
            style: TextStyle(
                fontSize: 10,
                color: fg,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4)),
      );
}

class _MiniLive extends StatefulWidget {
  const _MiniLive();
  @override
  State<_MiniLive> createState() => _MiniLiveState();
}

class _MiniLiveState extends State<_MiniLive>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final t = _c.value;
        final spread = 3 + 3 * t;
        final op = (1 - t).clamp(0.0, 1.0);
        return Container(
          height: 20,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFFFFE9E6),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 5, height: 5,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: T.down,
                  boxShadow: [
                    BoxShadow(
                      color: T.down.withValues(alpha: 0.30 * op),
                      blurRadius: spread,
                      spreadRadius: spread * 0.6,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 5),
              Text(tr('matches.live'),
                  style: const TextStyle(
                      fontSize: 10,
                      color: T.down,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4)),
            ],
          ),
        );
      },
    );
  }
}

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/match.dart';
import '../services/app_state.dart';
import '../services/i18n.dart';
import '../services/stream_feed.dart';
import 'league_picker_page.dart';
import '../services/toast.dart';
import '../theme/tokens.dart';
import '../utils/team_crests.dart';
import '../utils/team_names.dart';
import 'match_detail_page.dart';

/// 02 · 比赛列表 — 仿懂球帝风格:顶部 Tab(全部/进行中/赛程/赛果) + 紧凑行 + 联赛分组。
class MatchListPage extends StatefulWidget {
  const MatchListPage({super.key, required this.state});
  final AppState state;

  @override
  State<MatchListPage> createState() => _MatchListPageState();
}

enum _Tab { all, live, schedule, results }

class _MatchListPageState extends State<MatchListPage>
    with SingleTickerProviderStateMixin {
  _Tab _tab = _Tab.all;
  String? _league;

  // search
  bool _searching = false;
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  // pagination
  final List<MatchInfo> _matches = [];
  int _total = 0;
  bool _loading = false;
  bool _hasMore = true;
  static const _pageSize = 40;
  final _scrollCtrl = ScrollController();
  final _chipScrollCtrl = ScrollController();

  List<LeagueInfo> _allLeagues = [];

  // date picker for schedule / results
  late DateTime _selectedDate;
  late List<DateTime> _dateOptions;

  // Live updates: WS push for goal/cards/corners, plus a local ticker so
  // the live minute display advances even between WS pushes.
  StreamSubscription<List<MatchInfo>>? _wsSub;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();
    _buildDateOptions();
    _loadPage(reset: true);
    _loadConfigLeagues();
    _loadStreamFeed();
    _scrollCtrl.addListener(_onScroll);
    _searchCtrl.addListener(_onSearchChanged);

    // Merge WS-pushed updates by id so goal/cards/corners propagate without
    // a full reload. The push payload is the full match list; we only patch
    // the ones we already have so paging/filter aren't disturbed.
    _wsSub = widget.state.stream.matches.listen((list) {
      if (!mounted || list.isEmpty || _matches.isEmpty) return;
      final byId = <int, MatchInfo>{for (final m in list) m.id: m};
      var dirty = false;
      for (var i = 0; i < _matches.length; i++) {
        final fresh = byId[_matches[i].id];
        if (fresh != null && !identical(fresh, _matches[i])) {
          _matches[i] = fresh;
          dirty = true;
        }
      }
      if (dirty) setState(() {});
    });

    // Local clock tick — advances `_liveMinuteText` so the on-screen minute
    // ticks every 30s without a backend push. 30s is the sweet spot:
    // minute changes show up within ~30s of the wall-clock minute boundary.
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      // Only re-render if there's at least one live match visible — otherwise
      // it's pure waste.
      for (final m in _matches) {
        if (m.isLive) {
          setState(() {});
          return;
        }
      }
    });
  }

  Future<void> _loadStreamFeed() async {
    await StreamFeed.instance.ensure(widget.state.api);
    if (mounted) setState(() {}); // re-render rows so live FAB shows up
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    _ticker?.cancel();
    _scrollCtrl.dispose();
    _chipScrollCtrl.dispose();
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _buildDateOptions() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (_tab == _Tab.results) {
      _dateOptions = List.generate(7, (i) => today.subtract(Duration(days: 6 - i)));
    } else {
      _dateOptions = List.generate(7, (i) => today.add(Duration(days: i)));
    }
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 200) {
      _loadPage();
    }
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _loadPage(reset: true);
    });
  }

  Future<void> _loadConfigLeagues() async {
    try {
      final list = await widget.state.api.configLeagues();
      if (mounted) setState(() => _allLeagues = list);
    } catch (_) {}
  }

  String? get _statusFilter {
    switch (_tab) {
      case _Tab.all:
        return null;
      case _Tab.live:
        return 'live';
      case _Tab.schedule:
        return 'pending';
      case _Tab.results:
        return 'settled';
    }
  }

  Future<void> _loadPage({bool reset = false}) async {
    if (_loading) return;
    if (!reset && !_hasMore) return;

    setState(() => _loading = true);

    final offset = reset ? 0 : _matches.length;
    try {
      final page = await widget.state.api.listMatches(
        league: _league,
        // 把中文输入(如"利物浦")翻成英文(如"Liverpool")再发后端,
        // 后端只做 ASCII contains 匹配,不识别本地化名。
        search: resolveTeamSearchQuery(_searchCtrl.text),
        status: _statusFilter,
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

  void _switchTab(_Tab tab) {
    if (_tab == tab) return;
    setState(() {
      _tab = tab;
      _league = null;
      _buildDateOptions();
      _selectedDate = DateTime.now();
    });
    _loadPage(reset: true);
    if (_scrollCtrl.hasClients) {
      _scrollCtrl.animateTo(0,
          duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    }
  }

  void _setLeague(String? league) {
    if (_league == league) return;
    setState(() => _league = league);
  }

  void _selectDate(DateTime d) {
    setState(() => _selectedDate = d);
  }

  void _openStream(String url, {String? home, String? away}) {
    // Open the stream in a draggable floating overlay (live_overlay.js).
    // Bridge is exposed as window.openLiveStream(url, home, away).
    // The overlay reuses live.html in an iframe so users can keep browsing
    // matches and placing bets while watching — never blocks the Flutter UI.
    try {
      globalContext.callMethod(
        'openLiveStream'.toJS,
        url.toJS,
        (home ?? '').toJS,
        (away ?? '').toJS,
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final leagues = <String, String>{};
    if (_allLeagues.isNotEmpty) {
      for (final l in _allLeagues) {
        if (l.slug.isNotEmpty) leagues[l.slug] = l.name;
      }
    } else {
      for (final m in _matches) {
        if (m.leagueSlug.isNotEmpty) leagues[m.leagueSlug] = m.leagueName;
      }
    }

    // Client-side filter by league + date
    var visible = _league == null
        ? _matches.toList()
        : _matches.where((m) => m.leagueSlug == _league).toList();

    // For schedule/results tabs, filter by selected date
    if (_tab == _Tab.schedule || _tab == _Tab.results) {
      final sd = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
      visible = visible.where((m) {
        final md = DateTime(m.date.year, m.date.month, m.date.day);
        return md == sd;
      }).toList();
    }

    // Sort (no league grouping — league name shown per row)
    final sorted = _sortMatches(visible);
    final showEmpty = visible.isEmpty && !_loading;

    return Container(
      color: Colors.white,
      child: RefreshIndicator(
        color: T.brandDeep,
        onRefresh: () => _loadPage(reset: true),
        child: ListView.builder(
          controller: _scrollCtrl,
          padding: EdgeInsets.zero,
          itemCount: _headerCount + sorted.length + (showEmpty ? 1 : 0) + (_loading ? 1 : 0) + (!_hasMore && visible.isNotEmpty ? 1 : 0),
          itemBuilder: (context, index) {
            // Header items
            if (index == 0) return _searching ? _searchBar() : _tabBar();
            if (index == 1) {
              if (_tab == _Tab.schedule || _tab == _Tab.results) {
                return _datePicker();
              }
              return _leagueChips(leagues);
            }
            if (index == 2 && (_tab == _Tab.schedule || _tab == _Tab.results)) {
              return _leagueChips(leagues);
            }

            final itemIdx = index - _headerCount;
            if (itemIdx < sorted.length) {
              return _matchRow(sorted[itemIdx]);
            }
            if (showEmpty) {
              return _emptyState();
            }
            if (_loading) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                    child: CircularProgressIndicator(
                        color: T.brandDeep, strokeWidth: 2)),
              );
            }
            if (!_hasMore && visible.isNotEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Text(
                      tr('matches.loaded_all').replaceAll('{n}', '$_total'),
                      style:
                          const TextStyle(color: T.inkLo, fontSize: 11)),
                ),
              );
            }
            return const SizedBox(height: 16);
          },
        ),
      ),
    );
  }

  int get _headerCount =>
      (_tab == _Tab.schedule || _tab == _Tab.results) ? 3 : 2;

  // ── Tab bar ─────────────────────────────────────────────

  Widget _tabBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 0),
      child: Column(
        children: [
          Row(
            children: [
              const SizedBox(width: 16),
              _tabItem(tr('matches.tab_all'), _Tab.all),
              _tabItem(tr('matches.tab_live'), _Tab.live),
              _tabItem(tr('matches.tab_schedule'), _Tab.schedule),
              _tabItem(tr('matches.tab_results'), _Tab.results),
              const Spacer(),
              GestureDetector(
                onTap: () => setState(() => _searching = true),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Icon(Icons.search, size: 22, color: T.inkMd),
                ),
              ),
            ],
          ),
          Container(height: 0.5, color: const Color(0xFFEEEEEE)),
        ],
      ),
    );
  }

  Widget _tabItem(String label, _Tab tab) {
    final active = _tab == tab;
    return GestureDetector(
      onTap: () => _switchTab(tab),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active ? T.ink : T.inkLo,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              width: 20,
              height: 3,
              decoration: BoxDecoration(
                color: active ? T.brandDeep : Colors.transparent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Search bar ──────────────────────────────────────────

  Widget _searchBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(18),
              ),
              child: TextField(
                controller: _searchCtrl,
                autofocus: true,
                style: const TextStyle(fontSize: 14, color: T.ink),
                decoration: InputDecoration(
                  hintText: tr('matches.search_hint'),
                  hintStyle: const TextStyle(color: T.inkLo, fontSize: 13),
                  prefixIcon:
                      const Icon(Icons.search, color: T.inkLo, size: 18),
                  suffixIcon: _searchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon:
                              const Icon(Icons.close, size: 16, color: T.inkLo),
                          onPressed: () {
                            _searchCtrl.clear();
                            _loadPage(reset: true);
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
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
                    fontSize: 14,
                    color: T.brandDeep,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  // ── Date picker (schedule / results) ────────────────────

  Widget _datePicker() {
    final today = DateTime.now();
    final todayDay = DateTime(today.year, today.month, today.day);
    const weekDays = ['一', '二', '三', '四', '五', '六', '日'];
    final fmt = DateFormat('MM/dd');

    return Container(
      color: Colors.white,
      height: 56,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        itemCount: _dateOptions.length,
        itemBuilder: (_, i) {
          final d = _dateOptions[i];
          final dd = DateTime(d.year, d.month, d.day);
          final sel = DateTime(_selectedDate.year, _selectedDate.month,
                  _selectedDate.day) ==
              dd;
          final isToday = dd == todayDay;

          String label;
          if (isToday) {
            label = tr('matches.today');
          } else {
            label = '${fmt.format(d)}\n${tr('matches.week')}${weekDays[d.weekday - 1]}';
          }

          return GestureDetector(
            onTap: () => _selectDate(d),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: sel ? const Color(0xFFE8F5E9) : Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: sel ? const Color(0xFF4CAF50) : const Color(0xFFE0E0E0),
                ),
              ),
              child: Center(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: isToday ? 13 : 11,
                    fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                    color: sel ? const Color(0xFF2E7D32) : T.inkMd,
                    height: 1.3,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── League chips ────────────────────────────────────────

  Widget _leagueChips(Map<String, String> leagues) {
    final entries = [
      MapEntry<String?, String>(null, tr('matches.league_all')),
      ...leagues.entries.map((e) => MapEntry<String?, String>(e.key, e.value)),
    ];
    final hasMore = _allLeagues.isNotEmpty;
    return Container(
      color: Colors.white,
      height: 42,
      child: Row(
        children: [
          // 可滚动的联赛 chip 区
          Expanded(
            child: Stack(
              children: [
                SingleChildScrollView(
                  controller: _chipScrollCtrl,
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(12, 6, hasMore ? 28 : 12, 6),
                  child: Row(
                    children: [
                      for (var i = 0; i < entries.length; i++) ...[
                        if (i > 0) const SizedBox(width: 6),
                        _chip(entries[i]),
                      ],
                    ],
                  ),
                ),
                // 右侧白色渐变蒙层 — 暗示"右边还有"。用 IgnorePointer 让
                // 它不挡 chip 点击。
                if (hasMore)
                  const Positioned(
                    right: 0, top: 0, bottom: 0,
                    width: 28,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [Color(0x00FFFFFF), Color(0xFFFFFFFF)],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // 固定"更多"按钮 — 始终可见,与可滚区有左侧细分隔线
          if (hasMore)
            Container(
              padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(
                  left: BorderSide(color: Color(0xFFEDEDED), width: 1),
                ),
              ),
              child: _moreChip(),
            ),
        ],
      ),
    );
  }

  Widget _moreChip() {
    return GestureDetector(
      onTap: _openLeaguePicker,
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFEAF6FE),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFB6E2FA), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.menu, size: 14, color: T.brandDeep),
            const SizedBox(width: 4),
            Text(tr('matches.league_more'),
                style: const TextStyle(
                  fontSize: 12,
                  color: T.brandDeep,
                  fontWeight: FontWeight.w700,
                )),
          ],
        ),
      ),
    );
  }

  Future<void> _openLeaguePicker() async {
    final picked = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => LeaguePickerPage(
          leagues: _allLeagues,
          selectedSlug: _league,
        ),
      ),
    );
    if (!mounted || picked == null) return;
    // picker 返回 '' 表示"全部联赛",其它是 slug。
    final slug = picked.isEmpty ? null : picked;
    if (_league != slug) {
      _setLeague(slug);
      _loadPage(reset: true);
    }
  }

  Widget _chip(MapEntry<String?, String> e) {
    final on = _league == e.key;
    final label = e.key == null ? e.value : localizedLeague(e.value);
    return GestureDetector(
      onTap: () => _setLeague(e.key),
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: on ? T.brandDeep : const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Center(
          widthFactor: 1.0,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 120),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: on ? Colors.white : T.inkMd,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Sort matches (no per-league grouping anymore) ────────
  // The 懂球帝 reference puts the league name on each row's header strip,
  // not as a separate section divider. So we just sort and let
  // _matchRow render the league inline.

  List<MatchInfo> _sortMatches(List<MatchInfo> ms) {
    final sorted = List<MatchInfo>.from(ms);
    if (_tab == _Tab.all) {
      sorted.sort((a, b) {
        if (a.isLive != b.isLive) return a.isLive ? -1 : 1;
        return a.date.compareTo(b.date);
      });
    } else if (_tab == _Tab.results) {
      sorted.sort((a, b) => b.date.compareTo(a.date));
    } else {
      sorted.sort((a, b) => a.date.compareTo(b.date));
    }
    return sorted;
  }

  // ── Match row (compact, 懂球帝 style) ──────────────────

  Widget _matchRow(MatchInfo m) {
    final fmt = DateFormat('HH:mm');
    // Stream URL: 7t666 feed (joined by Chinese team name) takes precedence;
    // upstream-stamped LiveDetail.streamUrl is the fallback.
    final feedStream = StreamFeed.instance.find(m.home, m.away, m.date);
    final streamUrl =
        feedStream?.streamUrl ?? m.live?.streamUrl ?? '';
    final hasStream = streamUrl.isNotEmpty;

    final body = GestureDetector(
      onTap: () => AntiSpam.guard('match_detail_${m.id}', () {
        Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) =>
                  MatchDetailPage(state: widget.state, match: m)),
        );
      }),
      child: Container(
        color: Colors.white,
        // Reserve left padding when ribbon is shown so it can dock at left=0
        // edge without overlapping the row content.
        padding: EdgeInsets.fromLTRB(hasStream ? 28 : 12, 8, 8, 10),
        child: Column(
          children: [
            Stack(
              children: [
                Column(
                  children: [
                    _headerStrip(m, fmt),
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Flexible(
                                child: Text(
                                  localizedTeam(m.home),
                                  textAlign: TextAlign.right,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: T.ink),
                                ),
                              ),
                              const SizedBox(width: 6),
                              TeamCrest(
                                  name: m.home,
                                  id: m.homeId,
                                  leagueSlug: m.leagueSlug,
                                  size: 22),
                            ],
                          ),
                        ),
                        SizedBox(
                          width: 64,
                          child: _scoreCenter(m),
                        ),
                        Expanded(
                          child: Row(
                            children: [
                              TeamCrest(
                                  name: m.away,
                                  id: m.awayId,
                                  leagueSlug: m.leagueSlug,
                                  size: 22),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  localizedTeam(m.away),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: T.ink),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    _secondaryRow(m),
                  ],
                ),
                const Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: Icon(Icons.chevron_right,
                        size: 16, color: T.inkSubtle),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(height: 0.5, color: const Color(0xFFF0F0F0)),
          ],
        ),
      ),
    );

    if (!hasStream) return body;

    // Stack the row + a left-docked vertical ribbon. The asset is a
    // 70×227 banner with "体育直播 LIVE" text reading top-down — render at
    // the original aspect ratio (≈1:3.24) docked to the left edge so it
    // looks like a tab protruding from the row, mirroring the "懂球帝-style"
    // floating-tag pattern. The list row's left padding (set to 44px above
    // when hasStream is true) keeps content from overlapping.
    return Stack(
      children: [
        body,
        Positioned(
          left: 0,
          top: 6,
          bottom: 6,
          child: _liveStreamRibbon(streamUrl, m),
        ),
      ],
    );
  }

  Widget _liveStreamRibbon(String url, MatchInfo m) {
    return GestureDetector(
      onTap: () => _openStream(url,
          home: localizedTeam(m.home), away: localizedTeam(m.away)),
      child: Container(
        // Ribbon stays narrow (≈ row height × 0.31) so it reads as a tab,
        // not a card. The image's intrinsic 70×227 will scale uniformly.
        width: 22,
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.only(
            topRight: Radius.circular(4),
            bottomRight: Radius.circular(4),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 4,
              offset: const Offset(1, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.only(
            topRight: Radius.circular(4),
            bottomRight: Radius.circular(4),
          ),
          child: Image.asset(
            'assets/icons/live_stream.png',
            fit: BoxFit.fill, // stretch to fill ribbon height; matches design
            errorBuilder: (_, __, ___) => Container(
              alignment: Alignment.center,
              color: const Color(0xFFE53935),
              child: const RotatedBox(
                quarterTurns: 1,
                child: Text('LIVE',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Header strip above the team row.
  ///
  /// 懂球帝-style 3-zone layout:
  ///   [LEFT]   绿色联赛名 + 灰色 14:00 (kickoff time)
  ///   [CENTER] 状态 (点/中/未/完 或 78' 分钟数) + 可选 补X badge
  ///   [RIGHT]  目前留空,用 Spacer flex 平衡 — 让中央真正居中
  ///
  /// Status mapping (matches user spec):
  ///   pending      → 未  (gray)
  ///   live HT      → 中  (green)  — periodLabel == 'HT'
  ///   live PEN     → 点  (green)  — periodLabel == 'PEN'  (penalty shootout)
  ///   live normal  → 78' (green)  — minuteDisplay
  ///   live extra   → 90+3' + 补X badge
  ///   settled      → 完  (red)
  Widget _headerStrip(MatchInfo m, DateFormat fmt) {
    final live = m.isLive;
    final ended = m.isSettled;
    final ld = m.live;

    String statusText;
    Color statusColor;
    if (live) {
      statusText = _liveMinuteText(m);
      statusColor = const Color(0xFF4CAF50);
    } else if (ended) {
      statusText = tr('matches.finished');
      statusColor = T.down;
    } else {
      statusText = tr('matches.not_started');
      statusColor = T.inkLo;
    }
    final showStoppage = live && (ld?.extra ?? 0) > 0;

    return Row(
      children: [
        // ── LEFT: league + kickoff time ─────────────────────
        Expanded(
          flex: 1,
          child: Row(
            children: [
              Flexible(
                child: Text(
                  localizedLeague(m.leagueName),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF4CAF50),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                fmt.format(m.date),
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: T.inkLo,
                    fontFamily: T.fontMono),
              ),
            ],
          ),
        ),
        // ── CENTER: status (+ optional 补X) ─────────────────
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showStoppage) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFEBEE),
                  borderRadius: BorderRadius.circular(2),
                ),
                child: Text(
                  '补${ld!.extra}',
                  style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: T.down,
                      height: 1.2),
                ),
              ),
              const SizedBox(width: 4),
            ],
            Text(
              statusText,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: statusColor),
            ),
          ],
        ),
        // ── RIGHT: balance flex so CENTER is truly centered ─
        const Expanded(flex: 1, child: SizedBox()),
      ],
    );
  }

  /// Live minute display, derived from kickoff time so it ticks locally
  /// without requiring a backend push.
  ///
  /// Upstream is authoritative for non-running phases (HT / PEN / stoppage)
  /// and for the "we're in the second half" signal (upstream minute > 45).
  /// In between, we take max(upstream, computed-elapsed) so the on-screen
  /// minute keeps advancing every wall-clock minute even when the backend's
  /// liveLoop hasn't fired in a while.
  ///
  /// Halftime gap heuristic: if upstream says ≤ 45, we cap our local advance
  /// at 45 (we don't know exactly when HT starts, so we'd rather sit at 45
  /// than tick into a fictitious 47'). Once upstream confirms second half by
  /// reporting > 45, we subtract a 15-minute break from elapsed-since-kickoff
  /// before comparing.
  String _liveMinuteText(MatchInfo m) {
    final ld = m.live;
    if (ld != null) {
      final pl = ld.periodLabel;
      if (pl == 'HT') return '中';
      if (pl == 'PEN') return '点';
      if (pl == 'BT') return ld.minuteDisplay; // post-game break
      if (ld.extra > 0) return '${ld.minute}+${ld.extra}\''; // stoppage time
    }
    final upMin = ld?.minute ?? 0;
    final elapsedMin = DateTime.now().difference(m.date).inMinutes;
    // 兜底:kickoff 已超过 150min(90+HT+ET+PEN+buffer)还在 live → 上游 feed
    // 卡住,后端 sweeper 尚未追上。前端先显示"完",别再骗用户"还在 90'"。
    if (elapsedMin > 150) return '完';
    int mins;
    if (upMin == 0) {
      // No upstream baseline yet — just count from kickoff, capped at 90'.
      mins = elapsedMin.clamp(1, 90);
    } else if (upMin <= 45) {
      // First half. Cap local tick at 45'; HT may start any second now.
      final advance = elapsedMin > upMin ? elapsedMin : upMin;
      mins = advance > 45 ? 45 : advance;
    } else {
      // Second half. Subtract a ~15min HT break from elapsed before comparing.
      final adj = elapsedMin - 15;
      final advance = adj > upMin ? adj : upMin;
      mins = advance > 90 ? 90 : advance;
    }
    if (mins < 1) mins = 1;
    return "$mins'";
  }

  /// Center column on the team row: just the score (or VS), big and bold.
  /// This is the visual focal point of the row — 懂球帝 puts the score in
  /// the geometric center between the two teams' names, and so do we.
  Widget _scoreCenter(MatchInfo m) {
    final live = m.isLive;
    final ended = m.isSettled;
    final scores = m.scores;
    final color = live
        ? const Color(0xFF4CAF50)
        : ended
            ? T.down
            : T.inkLo;
    if (scores != null) {
      return Center(
        child: Text(
          '${scores.home} - ${scores.away}',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: color,
            fontFamily: T.fontMono,
          ),
        ),
      );
    }
    return Center(
      child: Text(
        m.isPending ? 'VS' : '-',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w800,
          color: color,
          fontFamily: T.fontMono,
        ),
      ),
    );
  }

  Widget _secondaryRow(MatchInfo m) {
    final ld = m.live;
    final hasOdds = (m.mlHome ?? 0) > 0;

    // Build the live-stats / halftime row first (left-aligned). It collects
    // any of: 半:X-X, 角:X-X, 黄, 红 — whichever the upstream populated.
    final stats = <Widget>[];
    if ((m.isLive || m.isSettled) && _halfTime(m) != null) {
      stats.addAll([
        Text('${tr('matches.halftime')}:${_halfTime(m)}',
            style: const TextStyle(fontSize: 11, color: T.inkLo)),
        const SizedBox(width: 10),
      ]);
    }
    if (m.isLive && ld != null && ld.totalCorners > 0) {
      stats.addAll([
        Text('${tr('matches.corners')}:${ld.homeCorners}-${ld.awayCorners}',
            style: const TextStyle(fontSize: 11, color: T.inkLo)),
        const SizedBox(width: 10),
      ]);
    }
    if (m.isLive && ld != null && ld.homeYellow + ld.awayYellow > 0) {
      stats.addAll([
        _statBadge('黄${ld.homeYellow}-${ld.awayYellow}',
            const Color(0xFFFFF9C4), const Color(0xFFF57F17)),
        const SizedBox(width: 6),
      ]);
    }
    if (m.isLive && ld != null && ld.homeRed + ld.awayRed > 0) {
      stats.addAll([
        _statBadge('红${ld.homeRed}-${ld.awayRed}',
            const Color(0xFFFFEBEE), T.down),
        const SizedBox(width: 6),
      ]);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (stats.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: stats,
            ),
          ),
        if (hasOdds)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _miniOdds('主', m.mlHome ?? 0),
              const SizedBox(width: 8),
              _miniOdds('平', m.mlDraw ?? 0),
              const SizedBox(width: 8),
              _miniOdds('客', m.mlAway ?? 0),
            ],
          ),
      ],
    );
  }

  /// Halftime score from `Scores.periods["1H"]` if available AND 1H has
  /// actually ended (HT, 2H, ET, BT, PEN, or any settled status).
  ///
  /// Why the period gate: API-Football streams `periods["1H"]={0,0}` from
  /// kickoff, so a naive read would show "半:0-0" 5 minutes into the first
  /// half — misleading users into thinking halftime is over.
  String? _halfTime(MatchInfo m) {
    final p = m.scores?.periods?['1H'];
    if (p == null) return null;
    if (m.isSettled) {
      return '${p.home}-${p.away}'; // always safe — match is over
    }
    if (m.isLive) {
      // Show only when periodLabel indicates we're past the first half.
      const past1H = {'HT', '2H', 'ET', 'BT', 'PEN'};
      final label = m.live?.periodLabel ?? '';
      if (!past1H.contains(label)) return null;
      return '${p.home}-${p.away}';
    }
    return null;
  }

  Widget _statBadge(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }

  Widget _miniOdds(String label, double price) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '$label ${price.toStringAsFixed(2)}',
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: T.inkMd,
          fontFamily: T.fontMono,
        ),
      ),
    );
  }

  // ── Empty state ─────────────────────────────────────────

  Widget _emptyState() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 60, 24, 20),
      child: Column(
        children: [
          Icon(Icons.sports_soccer_outlined, size: 48, color: T.inkSubtle),
          const SizedBox(height: 12),
          Text(
            tr('matches.no_matches'),
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 13,
                color: T.inkLo,
                fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

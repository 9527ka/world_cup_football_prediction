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

enum _Tab { all, live, schedule, results }

/// 桌面赛事列表。绑定 [AppState.matches](已含 WS 实时更新),无需自行分页。
/// 布局:顶部状态 tab + 左侧联赛筛选栏 + 右侧 2 列赛事卡网格。
class MatchListDesktopPage extends StatefulWidget {
  const MatchListDesktopPage({
    super.key,
    required this.state,
    required this.onOpenMatch,
  });

  final AppState state;
  final void Function(MatchInfo match) onOpenMatch;

  @override
  State<MatchListDesktopPage> createState() => _MatchListDesktopPageState();
}

class _MatchListDesktopPageState extends State<MatchListDesktopPage> {
  static final _fmtMD = DateFormat('MM/dd');
  static final _fmtHM = DateFormat('HH:mm');

  _Tab _tab = _Tab.all;
  String? _league; // null = 全部

  @override
  void initState() {
    super.initState();
    widget.state.addListener(_onState);
    if (widget.state.matches.isEmpty) widget.state.refreshMatches();
  }

  @override
  void dispose() {
    widget.state.removeListener(_onState);
    super.dispose();
  }

  void _onState() => setState(() {});

  bool _matchInTab(MatchInfo m) {
    switch (_tab) {
      case _Tab.all:
        return true;
      case _Tab.live:
        return m.isLive;
      case _Tab.schedule:
        return m.isPending;
      case _Tab.results:
        return m.isSettled;
    }
  }

  List<MatchInfo> get _visible {
    final list = widget.state.matches.where((m) {
      if (!_matchInTab(m)) return false;
      if (_league != null && m.leagueSlug != _league) return false;
      return true;
    }).toList();
    list.sort((a, b) {
      if (_tab == _Tab.results) {
        // 赛果 tab:全是 settled,pinned 优先 + 时间倒序(最新结束在前)。
        if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
        return b.date.compareTo(a.date);
      }
      if (_tab == _Tab.all) {
        // 全部 tab:状态优先级 进行中→未开赛→已结束。
        final ra = _statusRank(a);
        final rb = _statusRank(b);
        if (ra != rb) return ra - rb;
      }
      // 同状态(或 live/schedule 单状态 tab):pinned 优先 + 时间正序。
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return a.date.compareTo(b.date);
    });
    return list;
  }

  /// 状态排序优先级,跟手机版 / admin 赛事列表一致:
  /// live(进行中)0 > pending(未开赛)1 > settled(已结束)2。
  int _statusRank(MatchInfo m) {
    if (m.isLive) return 0;
    if (m.isPending) return 1;
    return 2;
  }

  /// 当前 tab 下各联赛计数(供左栏)。
  List<LeagueInfo> get _leagues {
    final map = <String, LeagueInfo>{};
    for (final m in widget.state.matches) {
      if (!_matchInTab(m)) continue;
      final prev = map[m.leagueSlug];
      map[m.leagueSlug] = LeagueInfo(
        slug: m.leagueSlug,
        name: m.leagueName,
        matchCount: (prev?.matchCount ?? 0) + 1,
      );
    }
    final list = map.values.toList()
      ..sort((a, b) => b.matchCount.compareTo(a.matchCount));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1200),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _tabBar(),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _leagueSidebar(),
                  Expanded(child: _grid()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabBar() {
    Widget tab(_Tab t, String label) {
      final active = _tab == t;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Material(
          color: active ? T.brandDeep : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: () => setState(() {
              _tab = t;
              _league = null; // 切 tab 重置联赛筛选
            }),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
              child: Text(label,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: active ? Colors.white : T.inkMd)),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Row(
        children: [
          tab(_Tab.all, tr('matches.tab_all')),
          tab(_Tab.live, tr('matches.tab_live')),
          tab(_Tab.schedule, tr('matches.tab_schedule')),
          tab(_Tab.results, tr('matches.tab_results')),
        ],
      ),
    );
  }

  Widget _leagueSidebar() {
    final leagues = _leagues;
    return Container(
      width: 240,
      decoration: const BoxDecoration(
        border: Border(right: BorderSide(color: T.border)),
      ),
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _leagueTile(null, tr('matches.league_all'), widget.state.matches.where(_matchInTab).length),
          const Divider(height: 8, color: T.border),
          ...leagues.map((l) =>
              _leagueTile(l.slug, localizedLeague(l.name), l.matchCount)),
        ],
      ),
    );
  }

  Widget _leagueTile(String? slug, String name, int count) {
    final active = _league == slug;
    return Material(
      color: active ? T.brandSoft : Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _league = slug),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          child: Row(
            children: [
              if (slug != null) ...[
                LeagueFlag(slug: slug, height: 12, width: 18),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                        color: active ? T.brandDeep : T.inkMd)),
              ),
              const SizedBox(width: 6),
              Text('$count',
                  style: const TextStyle(fontSize: 12, color: T.inkLo)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _grid() {
    final list = _visible;
    if (list.isEmpty) {
      return Center(
        child: Text(tr('matches.no_matches'),
            style: const TextStyle(color: T.inkLo, fontSize: 14)),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(20),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 460,
        mainAxisExtent: 132,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: list.length,
      itemBuilder: (_, i) => _matchCard(list[i]),
    );
  }

  Widget _matchCard(MatchInfo m) {
    final live = m.isLive;
    return Material(
      color: T.surface,
      borderRadius: BorderRadius.circular(T.rMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(T.rMd),
        onTap: () => widget.onOpenMatch(m),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(T.rMd),
            border: Border.all(color: T.border),
            boxShadow: T.shadowSoft,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  LeagueFlag(slug: m.leagueSlug, height: 11, width: 16),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(localizedLeague(m.leagueName),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: T.inkLo)),
                  ),
                  _statusPill(m),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  TeamCrest(name: m.home, id: m.homeId, leagueSlug: m.leagueSlug, size: 24),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(localizedTeam(m.home, apiZh: m.homeZh),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700, color: T.ink)),
                  ),
                  if (m.scores != null && (live || m.isSettled))
                    Text('${m.scores!.home} : ${m.scores!.away}',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: live ? T.down : T.ink,
                            fontFamily: T.fontMono))
                  else
                    Text(_fmtHM.format(toNyWall(m.date)),
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: T.brandDeep,
                            fontFamily: T.fontMono)),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  TeamCrest(name: m.away, id: m.awayId, leagueSlug: m.leagueSlug, size: 24),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(localizedTeam(m.away, apiZh: m.awayZh),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700, color: T.ink)),
                  ),
                  if (m.mlHome != null) _mlRow(m),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _mlRow(MatchInfo m) {
    Widget chip(String label, double? v) => Container(
          margin: const EdgeInsets.only(left: 4),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: T.fill,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: T.border),
          ),
          child: Text(v == null ? '—' : v.toStringAsFixed(2),
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: T.brandDeep,
                  fontFamily: T.fontMono)),
        );
    return Row(mainAxisSize: MainAxisSize.min, children: [
      chip(tr('mini.home'), m.mlHome),
      chip(tr('mini.draw'), m.mlDraw),
      chip(tr('mini.away'), m.mlAway),
    ]);
  }

  Widget _statusPill(MatchInfo m) {
    late final String label;
    late final Color bg;
    late final Color fg;
    if (m.isLive) {
      label = m.live?.minuteDisplay ?? tr('matches.tab_live');
      bg = const Color(0x1AE03E2D);
      fg = T.down;
    } else if (m.isSettled) {
      label = tr('matches.finished');
      bg = const Color(0x14000000);
      fg = T.inkLo;
    } else {
      label = _fmtMD.format(toNyWall(m.date));
      bg = T.brandSoft;
      fg = T.brandDeep;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(label,
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: fg)),
    );
  }
}

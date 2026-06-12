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
import '../../widgets/light_card.dart';

/// 桌面最近赛果。复用 api.recentSettled。左联赛筛选 + 右赛果表格。
/// 不含内置返回栏 —— 返回由 [DesktopShell] 顶栏提供。
class RecentSettledDesktopPage extends StatefulWidget {
  const RecentSettledDesktopPage({
    super.key,
    required this.state,
    required this.onOpenMatch,
  });

  final AppState state;
  final void Function(MatchInfo match) onOpenMatch;

  @override
  State<RecentSettledDesktopPage> createState() =>
      _RecentSettledDesktopPageState();
}

class _RecentSettledDesktopPageState extends State<RecentSettledDesktopPage> {
  static final _fmtDate = DateFormat('MM-dd HH:mm');

  List<MatchInfo> _matches = const [];
  bool _loading = true;
  String? _error;
  String? _league;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await widget.state.api.recentSettled(days: 7, limit: 50);
      if (!mounted) return;
      setState(() {
        _matches = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: T.brandDeep));
    }
    if (_error != null) {
      return Center(
        child: Text(_error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: T.down, fontSize: 13)),
      );
    }

    final leagues = <String, String>{};
    for (final m in _matches) {
      if (m.leagueSlug.isNotEmpty) leagues[m.leagueSlug] = m.leagueName;
    }
    final visible = _league == null
        ? _matches
        : _matches.where((m) => m.leagueSlug == _league).toList();

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1200),
        child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _leagueSidebar(leagues),
        Expanded(
          child: visible.isEmpty
              ? Center(
                  child: Text(tr('settled.empty'),
                      style: const TextStyle(color: T.inkLo, fontSize: 14)),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(20),
                  gridDelegate:
                      const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 540,
                    mainAxisExtent: 72,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: visible.length,
                  itemBuilder: (_, i) => _card(visible[i]),
                ),
        ),
      ],
        ),
      ),
    );
  }

  Widget _leagueSidebar(Map<String, String> leagues) {
    final entries = [
      const MapEntry<String?, String>(null, ''),
      ...leagues.entries.map((e) => MapEntry<String?, String>(e.key, e.value)),
    ];
    return Container(
      width: 240,
      decoration: const BoxDecoration(
        border: Border(right: BorderSide(color: T.border)),
      ),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: entries.length,
        itemBuilder: (_, i) {
          final e = entries[i];
          final on = _league == e.key;
          final label =
              e.key == null ? tr('matches.league_all') : localizedLeague(e.value);
          return Material(
            color: on ? T.brandSoft : Colors.transparent,
            child: InkWell(
              onTap: () => setState(() => _league = e.key),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                child: Row(
                  children: [
                    if (e.key != null) ...[
                      LeagueFlag(slug: e.key!, height: 12, width: 18),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Text(label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight:
                                  on ? FontWeight.w700 : FontWeight.w500,
                              color: on ? T.brandDeep : T.inkMd)),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _card(MatchInfo m) {
    final sc = m.scores;
    final hg = sc?.home ?? 0;
    final ag = sc?.away ?? 0;
    final homeWon = hg > ag;
    final awayWon = ag > hg;
    final draw = hg == ag;
    return LightCard(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      onTap: () => widget.onOpenMatch(m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              LeagueFlag(slug: m.leagueSlug, height: 11, width: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(localizedLeague(m.leagueName),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 10, color: T.inkLo, fontWeight: FontWeight.w700)),
              ),
              Text(_fmtDate.format(toNyWall(m.date)),
                  style: const TextStyle(fontSize: 10, color: T.inkLo)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              TeamCrest(name: m.home, id: m.homeId, leagueSlug: m.leagueSlug, size: 22),
              const SizedBox(width: 6),
              Expanded(
                child: Text(localizedTeam(m.home, apiZh: m.homeZh),
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: homeWon ? T.upDark : (draw ? T.ink : T.inkLo))),
              ),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 10),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  gradient: T.brandGradientShort,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('$hg : $ag',
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        fontFamily: T.fontMono)),
              ),
              Expanded(
                child: Text(localizedTeam(m.away, apiZh: m.awayZh),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: awayWon ? T.upDark : (draw ? T.ink : T.inkLo))),
              ),
              const SizedBox(width: 6),
              TeamCrest(name: m.away, id: m.awayId, leagueSlug: m.leagueSlug, size: 22),
            ],
          ),
        ],
      ),
    );
  }
}

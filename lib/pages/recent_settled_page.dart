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
import 'match_detail_page.dart';

/// 已结束比赛列表页 — 默认 7 天 / 50 条,可按联赛筛选。
/// 入口:首页"最近赛果"区块 SectionTitle 右侧"查看全部 ›"。
class RecentSettledPage extends StatefulWidget {
  const RecentSettledPage({super.key, required this.state});
  final AppState state;

  @override
  State<RecentSettledPage> createState() => _RecentSettledPageState();
}

class _RecentSettledPageState extends State<RecentSettledPage> {
  List<MatchInfo> _matches = const [];
  bool _loading = true;
  String? _error;
  String? _league; // null = 全部

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
      // 后端默认 days=3,这里给 7 天 + 大 limit 让用户能完整翻看一周
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
    final visible = _league == null
        ? _matches
        : _matches.where((m) => m.leagueSlug == _league).toList();

    final leagues = <String, String>{};
    for (final m in _matches) {
      if (m.leagueSlug.isNotEmpty) leagues[m.leagueSlug] = m.leagueName;
    }

    return Scaffold(
      backgroundColor: T.bgPage,
      body: Container(
        decoration: const BoxDecoration(gradient: T.pageGradient),
        child: SafeArea(
          child: RefreshIndicator(
            color: T.brandDeep,
            onRefresh: _load,
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _topBar(),
                if (leagues.isNotEmpty) _leagueChips(leagues),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 60),
                    child: Center(child: CircularProgressIndicator(color: T.brandDeep)),
                  )
                else if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 24),
                    child: Center(
                      child: Text(_error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: T.down, fontSize: 12)),
                    ),
                  )
                else if (visible.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 24),
                    child: Center(
                      child: Column(children: [
                        Icon(Icons.sports_soccer_outlined, size: 56, color: T.inkSubtle),
                        const SizedBox(height: 12),
                        Text(tr('settled.empty'),
                            style: const TextStyle(
                                fontSize: 13, color: T.inkLo, fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  )
                else
                  ...visible.map(_card),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 16, 6),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.chevron_left, color: T.ink),
          ),
          Text(tr('settled.title'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: T.ink)),
          const Spacer(),
          if (!_loading)
            Text('${_matches.length} ${tr('settled.matches_unit')}',
                style: const TextStyle(fontSize: 11, color: T.inkLo, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _leagueChips(Map<String, String> leagues) {
    final entries = [
      MapEntry<String?, String>(null, tr('matches.league_all')),
      ...leagues.entries.map((e) => MapEntry<String?, String>(e.key, e.value))
    ];
    return SizedBox(
      height: 44,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Row(
          children: [
            for (var i = 0; i < entries.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              _chip(entries[i]),
            ],
          ],
        ),
      ),
    );
  }

  Widget _chip(MapEntry<String?, String> e) {
    final on = _league == e.key;
    final label = e.key == null ? e.value : localizedLeague(e.value);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _league = e.key),
        borderRadius: BorderRadius.circular(999),
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            gradient: on
                ? const LinearGradient(
                    colors: [Color(0x2E2CD7FD), Color(0x0F2CD7FD)])
                : null,
            color: on ? null : Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: on ? T.brand : T.border),
          ),
          child: Center(
            widthFactor: 1.0,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 130),
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13,
                      color: on ? T.brandDeep : T.inkMd,
                      fontWeight: FontWeight.w700)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _card(MatchInfo m) {
    final fmt = DateFormat('MM-dd HH:mm');
    final sc = m.scores;
    final hg = sc?.home ?? 0;
    final ag = sc?.away ?? 0;
    final homeWon = hg > ag;
    final awayWon = ag > hg;
    final draw = hg == ag;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: LightCard(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        onTap: () => AntiSpam.guard('match_detail_${m.id}', () async {
          try {
            // 拿最新详情(可能是 DB fallback,确保有完整 metadata)
            final fresh = await widget.state.api.getMatch(m.id);
            if (!mounted) return;
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => MatchDetailPage(state: widget.state, match: fresh),
              ),
            );
          } catch (e) {
            if (mounted) Toast.error(context, '$e');
          }
        }),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 联赛 + 终场时间 + 已结束标
            Row(
              children: [
                LeagueFlag(slug: m.leagueSlug, height: 12, width: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(localizedLeague(m.leagueName),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11, color: T.inkLo, fontWeight: FontWeight.w700)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF2F7),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(tr('settled.ended_tag'),
                      style: const TextStyle(
                          color: T.inkLo, fontSize: 10, fontWeight: FontWeight.w800)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // 主队 — 比分 — 客队
            Row(
              children: [
                TeamCrest(name: m.home, leagueSlug: m.leagueSlug, size: 24),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(localizedTeam(m.home),
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: homeWon ? T.upDark : (draw ? T.ink : T.inkLo))),
                ),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    gradient: T.brandGradientShort,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('$hg : $ag',
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          fontFamily: T.fontMono)),
                ),
                Expanded(
                  child: Text(localizedTeam(m.away),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: awayWon ? T.upDark : (draw ? T.ink : T.inkLo))),
                ),
                const SizedBox(width: 6),
                TeamCrest(name: m.away, leagueSlug: m.leagueSlug, size: 24),
              ],
            ),
            const SizedBox(height: 8),
            // 终场时间
            Align(
              alignment: Alignment.centerRight,
              child: Text(fmt.format(m.date),
                  style: const TextStyle(fontSize: 10, color: T.inkLo)),
            ),
          ],
        ),
      ),
    );
  }
}

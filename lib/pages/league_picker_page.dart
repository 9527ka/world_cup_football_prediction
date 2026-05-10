import 'package:flutter/material.dart';

import '../models/match.dart';
import '../services/i18n.dart';
import '../theme/tokens.dart';
import '../utils/league_flags.dart';
import '../utils/team_names.dart';

/// 全联赛选择器 — 从 match list page 的"更多"chip 弹出。
///
/// 横向 chip 条只能放下少量联赛,后端开了 ~39 个不可能全显示。这里给一个
/// 可搜索的全列表,选中后 pop 返回 slug(`null` = 取消;`''` = 全部联赛)。
class LeaguePickerPage extends StatefulWidget {
  const LeaguePickerPage({
    super.key,
    required this.leagues,
    required this.selectedSlug,
  });

  final List<LeagueInfo> leagues;
  final String? selectedSlug;

  @override
  State<LeaguePickerPage> createState() => _LeaguePickerPageState();
}

class _LeaguePickerPageState extends State<LeaguePickerPage> {
  final _searchCtrl = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 过滤:输入可以匹配中文名 / 英文名 / slug,大小写不敏感。
    final q = _q.trim().toLowerCase();
    final all = widget.leagues;
    final filtered = q.isEmpty
        ? all
        : all.where((l) {
            final zh = localizedLeague(l.name);
            final hay = '${l.name} $zh ${l.slug}'.toLowerCase();
            return hay.contains(q);
          }).toList();

    return Scaffold(
      backgroundColor: T.bgPage,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        title: Text(tr('matches.league_pick_title'),
            style: const TextStyle(
                color: T.ink, fontSize: 16, fontWeight: FontWeight.w700)),
        iconTheme: const IconThemeData(color: T.ink),
      ),
      body: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _q = v),
              decoration: InputDecoration(
                hintText: tr('matches.league_pick_search_hint'),
                prefixIcon: const Icon(Icons.search, size: 20, color: T.inkSubtle),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                filled: true,
                fillColor: const Color(0xFFF5F5F5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 6),
              itemCount: filtered.length + 1,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, color: Color(0xFFF0F0F0), indent: 56),
              itemBuilder: (ctx, i) {
                if (i == 0) {
                  // "全部联赛" — 顶部置顶,选中时高亮。
                  final on = widget.selectedSlug == null;
                  return ListTile(
                    leading: const SizedBox(
                      width: 32, height: 22,
                      child: Icon(Icons.public, color: T.brandDeep, size: 22),
                    ),
                    title: Text(tr('matches.league_all'),
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: on ? T.brandDeep : T.ink)),
                    trailing: on
                        ? const Icon(Icons.check, color: T.brandDeep, size: 20)
                        : null,
                    onTap: () => Navigator.of(ctx).pop(''),
                  );
                }
                final l = filtered[i - 1];
                final on = widget.selectedSlug == l.slug;
                return ListTile(
                  leading: SizedBox(
                    width: 32, height: 22,
                    child: LeagueFlag(slug: l.slug, height: 18, width: 28),
                  ),
                  title: Text(localizedLeague(l.name),
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: on ? T.brandDeep : T.ink)),
                  subtitle: l.matchCount > 0
                      ? Text('${l.matchCount} ${tr('matches.league_pick_count_suffix')}',
                          style: const TextStyle(fontSize: 11, color: T.inkLo))
                      : null,
                  trailing: on
                      ? const Icon(Icons.check, color: T.brandDeep, size: 20)
                      : null,
                  onTap: () => Navigator.of(ctx).pop(l.slug),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

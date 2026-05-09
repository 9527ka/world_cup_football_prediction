import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/match.dart';
import '../services/app_state.dart';
import '../services/i18n.dart';
import '../theme/tokens.dart';
import '../widgets/light_card.dart';

/// 10 · 资金明细 — 月度统计 + 类型筛选 + 按天分组列表 + 分页加载。
class LedgerPage extends StatefulWidget {
  const LedgerPage({super.key, required this.state});
  final AppState state;

  @override
  State<LedgerPage> createState() => _LedgerPageState();
}

class _LedgerPageState extends State<LedgerPage> {
  static const _pageSize = 50;

  String _filter = 'all';
  List<LedgerEntry> _entries = [];
  String _nextCursor = '';
  UserStats? _stats;
  bool _initialLoading = true;
  bool _loadingMore = false;
  String? _error;

  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadInitial();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_loadingMore || _nextCursor.isEmpty) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _loadInitial() async {
    setState(() {
      _initialLoading = true;
      _error = null;
      _entries = [];
      _nextCursor = '';
    });
    try {
      final results = await Future.wait([
        widget.state.api.getLedger(type: _filter, limit: _pageSize),
        widget.state.api.getStats(),
      ]);
      final page = results[0] as LedgerResult;
      if (!mounted) return;
      setState(() {
        _entries = page.items;
        _nextCursor = page.nextCursor;
        _stats = results[1] as UserStats;
        _initialLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _initialLoading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _nextCursor.isEmpty) return;
    setState(() => _loadingMore = true);
    try {
      final page = await widget.state.api.getLedger(
        type: _filter,
        limit: _pageSize,
        before: _nextCursor,
      );
      if (!mounted) return;
      setState(() {
        _entries.addAll(page.items);
        _nextCursor = page.nextCursor;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  void _switch(String f) {
    _filter = f;
    _loadInitial();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: T.bgPage,
      body: Container(
        decoration: const BoxDecoration(gradient: T.pageGradient),
        child: SafeArea(
          child: _initialLoading
              ? const Center(child: CircularProgressIndicator(color: T.brandDeep))
              : _error != null
                  ? Center(
                      child: Text(tr('load_failed').replaceAll('{err}', _error!),
                          style: const TextStyle(color: T.down)))
                  : RefreshIndicator(
                      color: T.brandDeep,
                      onRefresh: () async => _loadInitial(),
                      child: ListView(
                        controller: _scroll,
                        padding: EdgeInsets.zero,
                        children: [
                          _topBar(),
                          if (_stats != null) _statRow(_stats!),
                          _filters(),
                          if (_entries.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 40),
                              child: Center(
                                  child: Text(tr('ledger.empty'),
                                      style: const TextStyle(
                                          color: T.inkLo, fontSize: 13))),
                            )
                          else
                            ..._buildGrouped(_entries),
                          if (_loadingMore)
                            const Padding(
                              padding: EdgeInsets.all(16),
                              child: Center(
                                  child: SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: T.brandDeep))),
                            ),
                          const SizedBox(height: 32),
                        ],
                      ),
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
          IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.chevron_left, color: T.ink)),
          Text(tr('ledger.title'),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: T.ink)),
        ],
      ),
    );
  }

  Widget _statRow(UserStats s) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          gradient: T.heroGradient,
          border: Border.all(color: const Color(0x382CD7FD)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            _cell(tr('ledger.month_in'),
                '+${NumberFormat('#,##0.00').format(s.monthIncome)}', T.upDark),
            _divider(),
            _cell(tr('ledger.month_out'),
                '-${NumberFormat('#,##0.00').format(s.monthExpense)}', T.down),
            _divider(),
            _cell(
                tr('ledger.month_net'),
                (s.monthProfit >= 0 ? '+' : '') +
                    NumberFormat('#,##0.00').format(s.monthProfit),
                s.monthProfit >= 0 ? T.ink : T.down,
                big: true),
          ],
        ),
      ),
    );
  }

  Widget _cell(String l, String v, Color c, {bool big = false}) => Expanded(
        child: Column(
          children: [
            Text(l,
                style: const TextStyle(
                    fontSize: 10, color: T.inkLo, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(v,
                style: TextStyle(
                    fontSize: big ? 16 : 14,
                    fontWeight: FontWeight.w800,
                    color: c,
                    fontFamily: T.fontMono)),
          ],
        ),
      );

  Widget _divider() => Container(
        width: 1,
        height: 28,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        color: const Color(0x190E2238),
      );

  Widget _filters() {
    final filters = [
      ['all', tr('ledger.f_all')],
      ['in', tr('ledger.f_in')],
      ['out', tr('ledger.f_out')],
      ['deposit', tr('ledger.f_deposit')],
      ['bet', tr('ledger.f_bet')],
    ];
    return SizedBox(
      height: 44,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final f = filters[i];
          final on = _filter == f[0];
          return InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: () => _switch(f[0]),
            child: Container(
              height: 30,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: on
                    ? const LinearGradient(
                        colors: [Color(0x2E2CD7FD), Color(0x0F2CD7FD)])
                    : null,
                color: on ? null : Colors.white,
                border: Border.all(color: on ? T.brand : T.border),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(f[1],
                  style: TextStyle(
                      fontSize: 12,
                      color: on ? T.brandDeep : T.inkMd,
                      fontWeight: FontWeight.w700)),
            ),
          );
        },
      ),
    );
  }

  List<Widget> _buildGrouped(List<LedgerEntry> items) {
    final dayFmt = DateFormat('MM-dd');
    final timeFmt = DateFormat('HH:mm');
    final groups = <String, List<LedgerEntry>>{};
    for (final e in items) {
      final key = dayFmt.format(e.when);
      groups.putIfAbsent(key, () => []).add(e);
    }
    final out = <Widget>[];
    groups.forEach((day, rows) {
      out.add(Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 16, 6),
        child: Text(day,
            style: const TextStyle(
                fontSize: 10,
                color: T.inkLo,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6)),
      ));
      out.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: LightCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++)
                _row(rows[i], divider: i > 0, timeFmt: timeFmt),
            ],
          ),
        ),
      ));
    });
    return out;
  }

  Widget _row(LedgerEntry e,
      {required bool divider, required DateFormat timeFmt}) {
    final cfg = _typeCfg(e.type);
    final positive = e.amount > 0;
    final negative = e.amount < 0;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: divider
          ? const BoxDecoration(border: Border(top: BorderSide(color: T.border)))
          : null,
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [cfg.c1, cfg.c2]),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(cfg.icon, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_titleFor(e),
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700, color: T.ink)),
                const SizedBox(height: 2),
                Text('${e.desc} · ${timeFmt.format(e.when)}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 10, color: T.inkLo, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                e.amount == 0
                    ? '0.00'
                    : '${positive ? '+' : ''}${e.amount.toStringAsFixed(2)}',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: positive ? T.upDark : negative ? T.down : T.inkLo,
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

String _titleFor(LedgerEntry e) {
  switch (e.type) {
    case 'deposit':
      return tr('ledger.t_deposit');
    case 'withdraw':
      return tr('ledger.t_withdraw');
    case 'bet':
      return tr('ledger.t_bet');
    case 'win':
      return tr('ledger.t_win');
    case 'loss':
      return tr('ledger.t_loss');
    default:
      return e.title;
  }
}

class _TypeCfg {
  final IconData icon;
  final Color c1;
  final Color c2;
  const _TypeCfg(this.icon, this.c1, this.c2);
}

_TypeCfg _typeCfg(String t) {
  switch (t) {
    case 'deposit':
      return const _TypeCfg(Icons.south, Color(0xFF5DD394), T.upDark);
    case 'withdraw':
      return const _TypeCfg(Icons.north, Color(0xFF9BA9BD), T.inkMd);
    case 'win':
      return const _TypeCfg(Icons.star_rounded, Color(0xFFFFE4A8), T.gold);
    case 'loss':
      return const _TypeCfg(Icons.close, Color(0xFFF0F4F9), T.inkSubtle);
    case 'rebate':
      return const _TypeCfg(Icons.percent, Color(0xFFC7B5F4), Color(0xFF8E7AD9));
    case 'bet':
    default:
      return const _TypeCfg(Icons.sports_soccer, Color(0xFF9BD9F4), T.brandDeep);
  }
}

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/match.dart';
import '../../utils/ny_time.dart';
import '../../services/app_state.dart';
import '../../services/i18n.dart';
import '../../theme/tokens.dart';

/// 桌面资金明细。复用 getLedger 分页 + getStats。
/// 月统计卡 + 类型筛选 + 宽表格(类型/描述/时间/金额)。无内置返回栏。
class LedgerDesktopPage extends StatefulWidget {
  const LedgerDesktopPage({super.key, required this.state});
  final AppState state;

  @override
  State<LedgerDesktopPage> createState() => _LedgerDesktopPageState();
}

class _LedgerDesktopPageState extends State<LedgerDesktopPage> {
  static const _pageSize = 30;
  static final _fmtBal = NumberFormat('#,##0.00');
  static final _fmtTime = DateFormat('MM-dd HH:mm');

  String _filter = 'all';
  List<LedgerEntry> _entries = [];
  String _nextCursor = '';
  UserStats? _stats;
  bool _initialLoading = true;
  bool _loadingMore = false;
  bool _switching = false; // 切换类型时的轻量加载态(不清空列表)
  String? _error;
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _reload(initial: true);
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

  // _reload — 统一加载入口。initial=true 首次进页(整屏 spinner);
  // initial=false 切换类型 —— 不清空旧列表、不整屏 spinner,数据回来原地替换,
  // 避免闪烁。target 锁定本次请求筛选,快速连切丢弃过期响应。
  Future<void> _reload({bool initial = false}) async {
    final target = _filter;
    if (initial) {
      setState(() {
        _initialLoading = true;
        _error = null;
      });
    }
    try {
      final results = await Future.wait([
        widget.state.api.getLedger(type: target, limit: _pageSize),
        widget.state.api.getStats(),
      ]);
      if (!mounted || _filter != target) return;
      final page = results[0] as LedgerResult;
      setState(() {
        _entries = page.items;
        _nextCursor = page.nextCursor;
        _stats = results[1] as UserStats;
        _initialLoading = false;
        _switching = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted || _filter != target) return;
      setState(() {
        _initialLoading = false;
        _switching = false;
        if (initial) _error = '$e';
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _nextCursor.isEmpty) return;
    setState(() => _loadingMore = true);
    try {
      final page = await widget.state.api
          .getLedger(type: _filter, limit: _pageSize, before: _nextCursor);
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
    if (_filter == f) return;
    setState(() {
      _filter = f;
      _switching = true; // 不清空 _entries → 旧列表保持可见,无闪烁
    });
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    if (_initialLoading) {
      return const Center(child: CircularProgressIndicator(color: T.brandDeep));
    }
    if (_error != null) {
      return Center(
          child: Text(tr('load_failed').replaceAll('{err}', _error!),
              style: const TextStyle(color: T.down)));
    }
    // 懒加载:CustomScrollView + SliverList.builder 只构建可见行,内存与翻页数无关
    // (原 ListView 一次性 build 全部行,翻页过多会 OOM)。DecoratedSliver 保留卡片外观。
    final showEmpty = _entries.isEmpty && !_switching;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: CustomScrollView(
            controller: _scroll,
            slivers: [
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 20),
                    if (_stats != null) _statRow(_stats!),
                    const SizedBox(height: 14),
                    _filters(),
                    // 固定 2px 占位:切换时显示进度条,高度恒定 → 无布局跳动。
                    SizedBox(
                      height: 2,
                      child: _switching
                          ? const LinearProgressIndicator(
                              minHeight: 2,
                              backgroundColor: Colors.transparent,
                              color: T.brand)
                          : null,
                    ),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
              if (showEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                        child: Text(tr('ledger.empty'),
                            style:
                                const TextStyle(color: T.inkLo, fontSize: 13))),
                  ),
                )
              else if (_entries.isNotEmpty)
                DecoratedSliver(
                  decoration: BoxDecoration(
                    color: T.surface,
                    borderRadius: BorderRadius.circular(T.rMd),
                    border: Border.all(color: T.border),
                    boxShadow: T.shadowSoft,
                  ),
                  sliver: SliverList.builder(
                    itemCount: _entries.length,
                    itemBuilder: (context, i) =>
                        _row(_entries[i], divider: i > 0),
                  ),
                ),
              SliverToBoxAdapter(
                child: Column(
                  children: [
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
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statRow(UserStats s) {
    Widget cell(String l, String v, Color c, {bool big = false}) => Expanded(
          child: Column(
            children: [
              Text(l,
                  style: const TextStyle(
                      fontSize: 11, color: T.inkLo, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(v,
                  style: TextStyle(
                      fontSize: big ? 20 : 16,
                      fontWeight: FontWeight.w800,
                      color: c,
                      fontFamily: T.fontMono)),
            ],
          ),
        );
    Widget div() => Container(width: 1, height: 32, color: const Color(0x190E2238));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        gradient: T.heroGradient,
        border: Border.all(color: const Color(0x382CD7FD)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          cell(tr('ledger.month_in'), '+${_fmtBal.format(s.monthIncome)}', T.upDark),
          div(),
          cell(tr('ledger.month_out'), '-${_fmtBal.format(s.monthExpense)}', T.down),
          div(),
          cell(
              tr('ledger.month_net'),
              (s.monthProfit >= 0 ? '+' : '') + _fmtBal.format(s.monthProfit),
              s.monthProfit >= 0 ? T.ink : T.down,
              big: true),
        ],
      ),
    );
  }

  Widget _filters() {
    final filters = [
      ['all', tr('ledger.f_all')],
      ['in', tr('ledger.f_in')],
      ['out', tr('ledger.f_out')],
      ['deposit', tr('ledger.f_deposit')],
      ['bet', tr('ledger.f_bet')],
    ];
    return Wrap(
      spacing: 8,
      children: filters.map((f) {
        final on = _filter == f[0];
        return InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () => _switch(f[0]),
          child: Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 16),
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
                    fontSize: 13,
                    color: on ? T.brandDeep : T.inkMd,
                    fontWeight: FontWeight.w700)),
          ),
        );
      }).toList(),
    );
  }

  Widget _row(LedgerEntry e, {required bool divider}) {
    final cfg = _typeCfg(e.type);
    final failed = e.status == 'rejected';
    final positive = e.amount > 0;
    final negative = e.amount < 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: divider
          ? const BoxDecoration(border: Border(top: BorderSide(color: T.border)))
          : null,
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [cfg.c1, cfg.c2]),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(cfg.icon, color: Colors.white, size: 19),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(_titleFor(e),
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700, color: T.ink)),
                    ),
                    if (e.status == 'pending' || e.status == 'rejected') ...[
                      const SizedBox(width: 6),
                      _statusChip(e.status),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(_descFor(e),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11, color: T.inkLo, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(_fmtTime.format(toNyWall(e.when)),
              style: const TextStyle(
                  fontSize: 11, color: T.inkLo, fontFamily: T.fontMono)),
          const SizedBox(width: 18),
          SizedBox(
            width: 120,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: e.type == 'deposit' && e.currency.isNotEmpty
                  ? [
                      Text(
                        '${positive ? '+' : ''}${e.amount.toStringAsFixed(e.currency == 'ETH' || e.currency == 'BTC' ? 4 : 2)}',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: failed ? T.inkLo : (positive ? T.upDark : T.inkLo),
                            fontFamily: T.fontMono),
                      ),
                      Text(e.currency,
                          style: const TextStyle(
                              fontSize: 9, color: T.inkLo, fontWeight: FontWeight.w600)),
                      if (e.amountUsdt > 0)
                        Text('≈ ${e.amountUsdt.toStringAsFixed(2)} USDT',
                            style: const TextStyle(
                                fontSize: 9, color: T.inkLo, fontWeight: FontWeight.w600)),
                    ]
                  : [
                      Text(
                        e.amount == 0
                            ? '0.00'
                            : '${positive ? '+' : ''}${e.amount.toStringAsFixed(2)}',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: failed
                                ? T.inkLo
                                : (positive
                                    ? T.upDark
                                    : negative
                                        ? T.down
                                        : T.inkLo),
                            fontFamily: T.fontMono),
                      ),
                      const Text('USDT',
                          style: TextStyle(
                              fontSize: 9, color: T.inkLo, fontWeight: FontWeight.w600)),
                    ],
            ),
          ),
        ],
      ),
    );
  }
}

Widget _statusChip(String status) {
  final rejected = status == 'rejected';
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(
      color: rejected ? const Color(0x1AE5484D) : const Color(0x1AE08A2B),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      tr(rejected ? 'ledger.st_rejected' : 'ledger.st_pending'),
      style: TextStyle(
        fontSize: 9,
        fontWeight: FontWeight.w700,
        color: rejected ? T.down : const Color(0xFFE08A2B),
      ),
    ),
  );
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
    case 'rebate':
      return tr('ledger.t_rebate');
    case 'convert':
      return e.currency.isEmpty
          ? e.title
          : tr('ledger.t_convert').replaceAll('{coin}', e.currency);
    default:
      return e.title;
  }
}

// 拼本地化明细文案;后端只回传语言中立数据(TxHash / 地址 / 拒绝原因)。
String _descFor(LedgerEntry e) {
  final rejected = e.status == 'rejected';
  switch (e.type) {
    case 'deposit':
      if (rejected) {
        return e.desc.isEmpty
            ? tr('ledger.deposit_failed')
            : '${tr('ledger.deposit_failed')} · ${e.desc}';
      }
      return e.desc;
    case 'withdraw':
      if (rejected) {
        final base = e.desc.isEmpty
            ? tr('ledger.withdraw_failed')
            : '${tr('ledger.withdraw_failed')} · ${e.desc}';
        return '$base (${tr('ledger.refunded')})';
      }
      return e.desc.isEmpty ? '' : '${tr('ledger.to_addr')} ${e.desc}';
    default:
      return e.desc;
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
    case 'adjust':
      return const _TypeCfg(Icons.tune, Color(0xFFFFD9A8), Color(0xFFE08A2B));
    case 'bet':
    default:
      return const _TypeCfg(Icons.sports_soccer, Color(0xFF9BD9F4), T.brandDeep);
  }
}

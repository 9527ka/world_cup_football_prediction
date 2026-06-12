import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/match.dart';
import '../utils/ny_time.dart';
import '../services/app_state.dart';
import '../services/i18n.dart';
import '../theme/tokens.dart';

/// 10 · 资金明细 — 月度统计 + 类型筛选 + 按天分组列表 + 分页加载。
class LedgerPage extends StatefulWidget {
  const LedgerPage({super.key, required this.state});
  final AppState state;

  @override
  State<LedgerPage> createState() => _LedgerPageState();
}

class _LedgerPageState extends State<LedgerPage> {
  static const _pageSize = 20;
  static final _fmtBal = NumberFormat('#,##0.00');
  static final _fmtDay = DateFormat('MM-dd');
  static final _fmtTime = DateFormat('HH:mm');

  String _filter = 'all';
  List<LedgerEntry> _entries = [];
  String _nextCursor = '';
  UserStats? _stats;
  bool _initialLoading = true;
  bool _loadingMore = false;
  bool _switching = false; // 切换类型时的轻量加载态(不清空列表、不整屏 spinner)
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

  // _reload — 统一加载入口。
  //   initial=true:首次进页(显示整屏 spinner)。
  //   initial=false:切换类型 / 下拉刷新 —— **不清空旧列表、不触发整屏 spinner**,
  //     数据回来再原地替换,避免闪烁与高度跳动。
  // 用 target 锁定本次请求对应的筛选,快速连切时丢弃过期响应(防错位)。
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
      if (!mounted || _filter != target) return; // 已被更晚的切换取代
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
        if (initial) _error = '$e'; // 切换/刷新失败保留旧列表,不整屏报错
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
    if (_filter == f) return;
    setState(() {
      _filter = f;
      _switching = true; // 仅标记,不清空 _entries → 旧列表保持可见,无闪烁
    });
    _reload();
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
                      onRefresh: () => _reload(),
                      child: _buildList(),
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
                '+${_fmtBal.format(s.monthIncome)}', T.upDark),
            _divider(),
            _cell(tr('ledger.month_out'),
                '-${_fmtBal.format(s.monthExpense)}', T.down),
            _divider(),
            _cell(
                tr('ledger.month_net'),
                (s.monthProfit >= 0 ? '+' : '') +
                    _fmtBal.format(s.monthProfit),
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

  // _buildList — 懒加载列表(ListView.builder),只构建可见项,内存与翻页数无关。
  // 结构:[0]=页头(标题/月统计/筛选/切换进度条) → 按天分组(每天一个 item) → 末尾(加载更多/底部留白)。
  // 之前用 ListView(children:[...全部条目]) 一次性 build,翻几十页后 widget 树膨胀 → 移动端 OOM 崩溃重载。
  Widget _buildList() {
    final flat = _flatItems(_entries);
    final showEmpty = flat.isEmpty && !_switching;
    final bodyCount = showEmpty ? 1 : flat.length;
    return ListView.builder(
      controller: _scroll,
      padding: EdgeInsets.zero,
      // 性能:逐行作为 item(最小渲染单元)+ 不保活离屏项(省内存)+ 适度预建范围。
      // 弱机/iOS WKWebView 下快速 fling 不卡顿、不被系统杀进程重载。
      addAutomaticKeepAlives: false,
      cacheExtent: 600,
      itemCount: 1 + bodyCount + 1, // 页头 + 主体 + 页尾
      itemBuilder: (context, i) {
        if (i == 0) return _headerBlock();
        if (i == 1 + bodyCount) return _footer();
        if (showEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Center(
                child: Text(tr('ledger.empty'),
                    style: const TextStyle(color: T.inkLo, fontSize: 13))),
          );
        }
        final it = flat[i - 1];
        return it.day != null
            ? _dayHeader(it.day!)
            : _rowCard(it.entry!, it.first, it.last);
      },
    );
  }

  Widget _headerBlock() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _topBar(),
        if (_stats != null) _statRow(_stats!),
        _filters(),
        // 固定 2px 高度占位:切换类型时显示进度条,不显示时留空白,高度恒定 → 切换不跳动。
        SizedBox(
          height: 2,
          child: _switching
              ? const LinearProgressIndicator(
                  minHeight: 2,
                  backgroundColor: Colors.transparent,
                  color: T.brand)
              : null,
        ),
      ],
    );
  }

  Widget _footer() {
    return Column(
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
        const SizedBox(height: 32),
      ],
    );
  }

  // _flatItems — 拍平成逐项列表:日期分隔头 + 单行(标记当天首/末行,用于扁平卡片圆角)。
  // 逐行作为 ListView item → 快速 fling 时一次只构建一行,最小渲染单元。
  List<_LItem> _flatItems(List<LedgerEntry> items) {
    final out = <_LItem>[];
    String? prevDay;
    for (var i = 0; i < items.length; i++) {
      final day = _fmtDay.format(toNyWall(items[i].when));
      final nextDay = i + 1 < items.length
          ? _fmtDay.format(toNyWall(items[i + 1].when))
          : null;
      final isFirst = day != prevDay;
      final isLast = day != nextDay;
      if (isFirst) out.add(_LItem.header(day));
      out.add(_LItem.row(items[i], isFirst, isLast));
      prevDay = day;
    }
    return out;
  }

  Widget _dayHeader(String day) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 16, 6),
        child: Text(day,
            style: const TextStyle(
                fontSize: 10,
                color: T.inkLo,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6)),
      );

  String _descTime(LedgerEntry e) {
    final d = _descFor(e);
    final t = _fmtTime.format(toNyWall(e.when));
    return d.isEmpty ? t : '$d · $t';
  }

  // _rowCard — 扁平卡片行(无阴影、无渐变):当天首行圆上角、末行圆下角,中间行用上边框分隔。
  // 阴影/渐变是 Flutter Web 上最贵的合成操作 → 一律去掉,改纯色 + 1px 边框,弱机滚动不卡。
  Widget _rowCard(LedgerEntry e, bool first, bool last) {
    final radius = BorderRadius.vertical(
      top: first ? const Radius.circular(14) : Radius.zero,
      bottom: last ? const Radius.circular(14) : Radius.zero,
    );
    final cfg = _typeCfg(e.type);
    final failed = e.status == 'rejected';
    final positive = e.amount > 0;
    final negative = e.amount < 0;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, last ? 6 : 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: T.surface,
          borderRadius: radius,
          border: Border(
            left: const BorderSide(color: T.border),
            right: const BorderSide(color: T.border),
            top: BorderSide(color: T.border, width: first ? 1 : 0.5),
            bottom: last ? const BorderSide(color: T.border) : BorderSide.none,
          ),
        ),
        child: Row(
          children: [
            // 纯色图标块(替代 LinearGradient,减少 web 合成开销)。
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: cfg.c2,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(cfg.icon, color: Colors.white, size: 18),
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
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: T.ink)),
                      ),
                      if (e.status == 'pending' || e.status == 'rejected') ...[
                        const SizedBox(width: 6),
                        _statusChip(e.status),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(_descTime(e),
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 10,
                          color: T.inkLo,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: e.type == 'deposit' && e.currency.isNotEmpty
                  ? [
                      Text(
                        '${positive ? '+' : ''}${e.amount.toStringAsFixed(e.currency == 'ETH' || e.currency == 'BTC' ? 4 : 2)}',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color:
                                failed ? T.inkLo : (positive ? T.upDark : T.inkLo),
                            fontFamily: T.fontMono),
                      ),
                      Text(e.currency,
                          style: const TextStyle(
                              fontSize: 9,
                              color: T.inkLo,
                              fontWeight: FontWeight.w600)),
                      if (e.amountUsdt > 0)
                        Text('≈ ${e.amountUsdt.toStringAsFixed(2)} USDT',
                            style: const TextStyle(
                                fontSize: 9,
                                color: T.inkLo,
                                fontWeight: FontWeight.w600)),
                    ]
                  : [
                      Text(
                        e.amount == 0
                            ? '0.00'
                            : '${positive ? '+' : ''}${e.amount.toStringAsFixed(2)}',
                        style: TextStyle(
                            fontSize: 14,
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
                              fontSize: 9,
                              color: T.inkLo,
                              fontWeight: FontWeight.w600)),
                    ],
            ),
          ],
        ),
      ),
    );
  }

}

// _LItem — 资金明细拍平后的列表项:日期分隔头(day 非空)或单行(entry + 当天首/末标记)。
class _LItem {
  final String? day;
  final LedgerEntry? entry;
  final bool first;
  final bool last;
  const _LItem.header(this.day)
      : entry = null,
        first = false,
        last = false;
  const _LItem.row(this.entry, this.first, this.last) : day = null;
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

// 拼本地化的明细文案。后端只回传语言中立数据(TxHash / 地址 / 拒绝原因),
// "充值失败 / 提现失败 / 到 / 已退回" 这些标签全部在前端按 type+status 本地化。
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

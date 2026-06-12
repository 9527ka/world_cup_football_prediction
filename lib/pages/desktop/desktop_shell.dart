import 'package:flutter/material.dart';

import '../../models/match.dart';
import '../../services/app_state.dart';
import '../../services/i18n.dart';
import '../../services/toast.dart';
import '../../theme/tokens.dart';
import '../../widgets/language_picker.dart';
import '../feature_pages.dart';
import '../match_detail_page.dart';
import 'deposit_desktop_page.dart';
import 'desktop_bet_slip_panel.dart';
import 'desktop_nav.dart';
import 'desktop_topnav.dart';
import 'home_desktop_page.dart';
import 'withdraw_desktop_page.dart';
import 'leaderboard_desktop_page.dart';
import 'ledger_desktop_page.dart';
import 'match_list_desktop_page.dart';
import 'predictions_desktop_page.dart';
import 'profile_desktop_page.dart';
import 'recent_settled_desktop_page.dart';

/// 桌面三栏外壳:左侧栏(220) | 主内容区(自适应) | 投注单右栏(340,有注单时)。
///
/// 仅在 `?a=test` 时由 [RootShell] 选用。手机版 [MainShell] 完全不受影响。
///
/// 导航:顶层 4 tab 用 [IndexedStack] 保活;桌面原生次级页(最近赛果等)压进
/// 主区内 [_stack] 切换(侧栏 + 投注单栏保持可见,顶栏提供返回)。
/// 尚未改造为桌面版的页(详情/充值/功能页)暂用现有移动页全屏打开。
class DesktopShell extends StatefulWidget {
  const DesktopShell({super.key, required this.state});
  final AppState state;

  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

class _MainRoute {
  _MainRoute(this.title, this.builder, {this.showBack = true});
  final String title;
  final WidgetBuilder builder;
  final bool showBack; // false → 顶栏不显示返回箭头(如充值,从 CTA 打开)
}

class _DesktopShellState extends State<DesktopShell> {
  int _tab = DesktopTab.home;
  final List<_MainRoute> _stack = [];
  // 懒加载:只构建访问过的 tab(首页默认),避免启动即 4 个 tab 同时发 API。
  // 访问过的保留在 _built,IndexedStack 保活其状态。
  final Set<int> _built = {DesktopTab.home};

  void _selectTab(int i) => setState(() {
        _tab = i;
        _built.add(i);
        _stack.clear();
      });

  /// 主区内打开桌面原生次级页(压栈,侧栏/投注单栏保持)。
  void _openDesktop(String title, WidgetBuilder builder, {bool showBack = true}) =>
      setState(() => _stack.add(_MainRoute(title, builder, showBack: showBack)));

  void _back() => setState(() {
        if (_stack.isNotEmpty) _stack.removeLast();
      });

  /// 无转场瞬间路由 —— 桌面不要手机端的左滑动画(对重页面做滑动动画会卡顿)。
  Route<void> _instantRoute(Widget page) => PageRouteBuilder<void>(
        pageBuilder: (_, __, ___) => page,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      );

  /// 全屏打开(比赛详情等已自适应桌面布局的页)。
  void _push(Widget page) => Navigator.of(context).push(_instantRoute(page));

  /// 居中限宽打开(功能页等整页 Scaffold,桌面下避免全宽拉伸)。
  void _pushCentered(Widget page) =>
      Navigator.of(context).push(_instantRoute(ColoredBox(
        color: T.bgPage,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: page,
          ),
        ),
      )));

  void _openMatch(MatchInfo m) => AntiSpam.guard(
        'match_detail_${m.id}',
        () => _push(MatchDetailPage(state: widget.state, match: m)),
      );

  /// 按 matchId 取最新 match 再打开详情(预测页"查看详情"用)。
  void _openMatchById(int id) => AntiSpam.guardAsync('match_detail_$id', () async {
        try {
          final m = await widget.state.api.getMatch(id);
          if (!mounted) return;
          _push(MatchDetailPage(state: widget.state, match: m));
        } catch (e) {
          if (mounted) Toast.error(context, '$e');
        }
      });

  void _openDeposit() => _openDesktop(
        tr('dep.title'),
        (_) => DepositDesktopPage(state: widget.state, onClose: _back),
        showBack: false, // 充值从顶部 CTA 打开,不显示返回箭头
      );
  void _openWithdraw() => _openDesktop(
        tr('wd.title'),
        (_) => WithdrawDesktopPage(state: widget.state, onClose: _back),
      );

  void _openLedger() => _openDesktop(
        tr('ledger.title'),
        (_) => LedgerDesktopPage(state: widget.state),
      );

  void _openPredictions() => _openDesktop(
        tr('pred.title'),
        (_) => PredictionsDesktopPage(
            state: widget.state, onOpenMatch: _openMatchById),
      );

  void _openSettled() => _openDesktop(
        tr('settled.title'),
        (_) => RecentSettledDesktopPage(
            state: widget.state, onOpenMatch: _openMatch),
      );

  void _openFeature(String key) {
    switch (key) {
      case 'home.language':
        showLanguagePicker(context);
      case 'home.share_earn':
        _pushCentered(ShareEarnPage(state: widget.state));
      case 'home.rebate':
        _pushCentered(RebatePage(state: widget.state));
      case 'home.vip':
        _pushCentered(VipPage(state: widget.state));
      case 'home.service':
        _pushCentered(CustomerServicePage(state: widget.state));
      case 'home.rules':
        _pushCentered(const RulesPage());
    }
  }

  @override
  Widget build(BuildContext context) {
    final tabs = <Widget>[
      HomeDesktopPage(
        state: widget.state,
        onOpenMatch: _openMatch,
        onOpenFeature: _openFeature,
        onGotoMatches: () => _selectTab(DesktopTab.matches),
        onViewAllSettled: _openSettled,
      ),
      MatchListDesktopPage(state: widget.state, onOpenMatch: _openMatch),
      LeaderboardDesktopPage(state: widget.state),
      ProfileDesktopPage(
        state: widget.state,
        onOpenDeposit: _openDeposit,
        onOpenWithdraw: _openWithdraw,
        onOpenLedger: _openLedger,
        onOpenPredictions: _openPredictions,
        onGotoLeaderboard: () => _selectTab(DesktopTab.leaderboard),
        onOpenFeature: _openFeature,
        onLanguage: () => showLanguagePicker(context),
      ),
    ];

    final inSub = _stack.isNotEmpty;
    final showBack = inSub && _stack.last.showBack;
    return Scaffold(
      backgroundColor: T.bgPage,
      body: Column(
        children: [
          DesktopTopNav(
            current: _tab,
            onSelect: _selectTab,
            onDeposit: _openDeposit,
            onLanguage: () => showLanguagePicker(context),
            subTitle: showBack ? _stack.last.title : null,
            onBack: showBack ? _back : null,
          ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Container(
                    decoration: const BoxDecoration(gradient: T.pageGradient),
                    child: inSub
                        ? _stack.last.builder(context)
                        : IndexedStack(
                            index: _tab,
                            children: [
                              for (var i = 0; i < tabs.length; i++)
                                _built.contains(i)
                                    ? tabs[i]
                                    : const SizedBox.shrink(),
                            ],
                          ),
                  ),
                ),
                AnimatedBuilder(
                  animation: widget.state.betSlip,
                  builder: (_, __) => widget.state.betSlip.isEmpty
                      ? const SizedBox.shrink()
                      : DesktopBetSlipPanel(state: widget.state),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../services/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/bet_slip_fab.dart';
import '../widgets/bottom_nav.dart';
import 'deposit_page.dart';
import 'home_page.dart';
import 'leaderboard_page.dart';
import 'match_list_page.dart';
import 'profile_page.dart';

/// Top-level scaffold: 5-tab IndexedStack with the brand center button
/// jumping to the deposit flow (matches the JSX `BottomNavLight`).
class MainShell extends StatefulWidget {
  const MainShell({super.key, required this.state});
  final AppState state;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      HomePage(state: widget.state, onJumpTab: _jump),
      MatchListPage(state: widget.state),
      // tab 2 is the center "+" — never selected as a page; we route to deposit.
      const SizedBox.shrink(),
      LeaderboardPage(state: widget.state),
      ProfilePage(state: widget.state),
    ];

    return Scaffold(
      backgroundColor: T.bgPage,
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(gradient: T.pageGradient),
            child: SafeArea(
              bottom: false,
              child: IndexedStack(index: _index, children: pages),
            ),
          ),
          // 全局 BetSlip 悬浮按钮 — 跨所有 tab 可见,有选项时才出现。
          Positioned(
            right: 16,
            bottom: 76, // 留出底部 nav 的空间
            child: BetSlipFab(state: widget.state),
          ),
        ],
      ),
      bottomNavigationBar: AppBottomNav(
        currentIndex: _index,
        onTap: _jump,
      ),
    );
  }

  void _jump(int i) {
    if (i == 2) {
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => DepositPage(state: widget.state)));
      return;
    }
    setState(() => _index = i);
  }
}

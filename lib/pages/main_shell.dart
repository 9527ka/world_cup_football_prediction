import 'dart:async';

import 'package:flutter/material.dart';

import '../services/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/bet_slip_fab.dart';
import '../widgets/bottom_nav.dart';
import 'home_page.dart';
import 'match_list_page.dart';
import 'deposit_page.dart' deferred as deposit;
import 'leaderboard_page.dart' deferred as leaderboard;
import 'profile_page.dart' deferred as profile;

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
  // Cache deferred futures so FutureBuilder keeps the same identity across
  // rebuilds — otherwise every tab switch recreates the child widget state.
  late final Future<void> _lbLib = leaderboard.loadLibrary();
  late final Future<void> _profileLib = profile.loadLibrary();

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      HomePage(state: widget.state, onJumpTab: _jump),
      MatchListPage(state: widget.state),
      const SizedBox.shrink(),
      _deferred(_lbLib, () => leaderboard.LeaderboardPage(state: widget.state)),
      _deferred(_profileLib, () => profile.ProfilePage(state: widget.state)),
    ];

    return Scaffold(
      backgroundColor: T.bgPage,
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(gradient: T.pageGradient),
            child: SafeArea(
              bottom: false,
              child: IndexedStack(
                index: _index,
                children: [
                  for (var i = 0; i < pages.length; i++)
                    TickerMode(
                      enabled: _index == i,
                      child: pages[i],
                    ),
                ],
              ),
            ),
          ),
          Positioned(
            right: 16,
            bottom: 76,
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

  Widget _deferred(Future<void> lib, Widget Function() builder) {
    return FutureBuilder(
      future: lib,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }
        return builder();
      },
    );
  }

  void _jump(int i) {
    if (i == 2) {
      deposit.loadLibrary().then((_) {
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => deposit.DepositPage(state: widget.state)));
      });
      return;
    }
    setState(() => _index = i);
  }
}

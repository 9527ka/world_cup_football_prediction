import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../models/match.dart';
import '../../services/api_client.dart';
import '../../services/app_state.dart';
import '../../services/auth_gate.dart';
import '../../services/i18n.dart';
import '../../services/toast.dart';
import '../../theme/tokens.dart';
import '../../widgets/light_card.dart';
import '../../widgets/login_wall.dart';

/// 桌面个人中心。复用 getStats / getVip / 用户信息 / logout / changePassword。
/// 布局:居中 1100,左列(头像卡 + 钱包黑卡 + 战绩)/ 右列(菜单网格 + 改密/登出)。
/// 次级页(充值/提现/明细/预测/功能)通过回调交给 [DesktopShell] 打开。
class ProfileDesktopPage extends StatefulWidget {
  const ProfileDesktopPage({
    super.key,
    required this.state,
    required this.onOpenDeposit,
    required this.onOpenWithdraw,
    required this.onOpenLedger,
    required this.onOpenPredictions,
    required this.onGotoLeaderboard,
    required this.onOpenFeature,
    required this.onLanguage,
  });

  final AppState state;
  final VoidCallback onOpenDeposit;
  final VoidCallback onOpenWithdraw;
  final VoidCallback onOpenLedger;
  final VoidCallback onOpenPredictions;
  final VoidCallback onGotoLeaderboard;
  final void Function(String key) onOpenFeature;
  final VoidCallback onLanguage;

  @override
  State<ProfileDesktopPage> createState() => _ProfileDesktopPageState();
}

class _Bundle {
  final UserStats stats;
  final VipStatus? vip;
  final Wallet? wallet;
  const _Bundle(this.stats, this.vip, [this.wallet]);
}

class _ProfileDesktopPageState extends State<ProfileDesktopPage> {
  static final _fmtBal = NumberFormat('#,##0.00');
  late Future<_Bundle> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_Bundle> _load() async {
    if (!widget.state.isAuthenticated) return _Bundle(UserStats.empty(), null);
    final stats = await widget.state.api.getStats();
    VipStatus? vip;
    try {
      vip = await widget.state.api.getVip();
    } catch (_) {}
    Wallet? wallet;
    try {
      wallet = await widget.state.api.getWallet();
    } catch (_) {}
    return _Bundle(stats, vip, wallet);
  }

  void _reload() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    final user = widget.state.user;
    if (!widget.state.isAuthenticated) {
      return ListView(
        padding: const EdgeInsets.symmetric(vertical: 24),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    _header(null, null),
                    const SizedBox(height: 12),
                    LoginRequiredCard(
                      state: widget.state,
                      label: tr('nav.profile'),
                      onLoggedIn: _reload,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    return FutureBuilder<_Bundle>(
      future: _future,
      builder: (_, snap) {
        final s = snap.data?.stats ?? UserStats.empty();
        final vip = snap.data?.vip;
        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 24),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 5,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _header(user, vip),
                              const SizedBox(height: 14),
                              _walletCard(s, snap.data?.wallet),
                              const SizedBox(height: 14),
                              _statsRow(s),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(flex: 6, child: _menu(s, vip, user)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _header(Map<String, dynamic>? user, VipStatus? vip) {
    final username = user == null
        ? tr('profile.guest')
        : (user['firstName'] as String?)?.isNotEmpty == true
            ? user['firstName'] as String
            : (user['username'] as String?)?.isNotEmpty == true
                ? '@${user['username']}'
                : 'User#${user['id']}';
    final initial = username.isEmpty ? '?' : username.characters.first.toUpperCase();
    final userCode = (user?['userCode'] as String?) ?? '';
    final photoUrl = (user?['photoUrl'] as String?) ?? '';

    final fallback = Container(
      decoration: const BoxDecoration(
          shape: BoxShape.circle, gradient: T.brandGradientShort),
      alignment: Alignment.center,
      child: Text(initial,
          style: const TextStyle(
              color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
    );

    return LightCard(
      padding: const EdgeInsets.all(16),
      radius: 16,
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Colors.white, Color(0xFFF4F8FC)],
      ),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: const [
                BoxShadow(
                    color: Color(0x4D11BAD9), blurRadius: 10, offset: Offset(0, 4))
              ],
            ),
            child: ClipOval(
              child: photoUrl.isEmpty
                  ? fallback
                  : Image.network(photoUrl,
                      fit: BoxFit.cover,
                      cacheWidth: 128,
                      cacheHeight: 128,
                      errorBuilder: (_, __, ___) => fallback),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(username,
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w800, color: T.ink)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text('${tr('profile.tg_id')}  ${userCode.isEmpty ? '-' : userCode}',
                        style: const TextStyle(
                            fontSize: 12,
                            color: T.inkLo,
                            fontWeight: FontWeight.w600,
                            fontFamily: T.fontMono)),
                    if (userCode.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      InkWell(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: userCode));
                          Toast.show(context, tr('common.copied'));
                        },
                        child: const Icon(Icons.copy_rounded, size: 14, color: T.inkLo),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0x1FD9AB7A),
                    border: Border.all(color: const Color(0x4DD9AB7A)),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    vip == null
                        ? tr('profile.vip_badge')
                        : '${tr(vip.currentTier.key)} · ${tr('profile.vip_rebate')} ${vip.currentTier.rate}',
                    style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFFA87644),
                        fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _walletCard(UserStats s, [Wallet? wallet]) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0E2238), Color(0xFF1B3358), Color(0xFF2A4870)],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(color: Color(0x330E2238), blurRadius: 24, offset: Offset(0, 8))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(tr('profile.balance'),
                  style: const TextStyle(
                      color: Color(0xFF9DE5F8),
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
              const Spacer(),
              Text(tr('profile.usdt_wallet'),
                  style: const TextStyle(
                      color: Color(0xFF9DE5F8),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(_fmtBal.format(s.balance),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 34,
                      fontWeight: FontWeight.w800,
                      fontFamily: T.fontMono)),
              const SizedBox(width: 6),
              const Text('USDT',
                  style: TextStyle(
                      color: T.brand, fontSize: 13, fontWeight: FontWeight.w700)),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                Text(tr('profile.today_pl'),
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
                Text(
                  (s.todayProfit >= 0 ? '+' : '') + _fmtBal.format(s.todayProfit),
                  style: TextStyle(
                      color: s.todayProfit >= 0
                          ? const Color(0xFF5DD394)
                          : T.down,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      fontFamily: T.fontMono),
                ),
              ],
            ),
          ),
          if (wallet != null) ...[
            _coinBalanceRow('ETH', wallet.balanceEth, wallet.rateEth),
            _coinBalanceRow('BTC', wallet.balanceBtc, wallet.rateBtc),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                  child: _walletAction(tr('profile.deposit'), Icons.add,
                      primary: true, onTap: widget.onOpenDeposit)),
              const SizedBox(width: 8),
              Expanded(
                  child: _walletAction(tr('profile.withdraw'), Icons.arrow_outward,
                      primary: false, onTap: widget.onOpenWithdraw)),
              const SizedBox(width: 8),
              Expanded(
                  child: _walletAction(tr('profile.ledger'), Icons.menu,
                      primary: false, onTap: widget.onOpenLedger)),
            ],
          ),
        ],
      ),
    );
  }

  static String _fmtCoinAmt(double v) {
    var s = v.toStringAsFixed(8);
    if (s.contains('.')) {
      s = s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
    }
    return s;
  }

  Widget _coinBalanceRow(String coin, double amount, double rate) {
    final approx = rate > 0 ? '≈ ${_fmtBal.format(amount * rate)} USDT' : '';
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(coin,
                style: const TextStyle(
                    color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_fmtCoinAmt(amount),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        fontFamily: T.fontMono)),
                if (approx.isNotEmpty)
                  Text(approx,
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.55),
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          OutlinedButton(
            onPressed: amount > 0 ? () => _showConvertDialog(coin, amount, rate) : null,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              disabledForegroundColor: Colors.white.withValues(alpha: 0.3),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.4)),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              minimumSize: const Size(0, 34),
            ),
            child: Text(tr('convert.action'),
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Future<void> _showConvertDialog(String coin, double maxAmount, double rate) async {
    final ctrl = TextEditingController(text: _fmtCoinAmt(maxAmount));
    String? err;
    bool busy = false;
    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setLocal) {
          final amt = double.tryParse(ctrl.text.trim()) ?? 0;
          final estUsdt = rate > 0 ? amt * rate : 0;
          return AlertDialog(
            title: Text('${tr('convert.title')} · $coin → USDT'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(rate > 0
                    ? '${tr('convert.rate')}: 1 $coin ≈ ${_fmtBal.format(rate)} USDT'
                    : tr('convert.rate_unavailable')),
                const SizedBox(height: 6),
                Text('${tr('convert.available')}: ${_fmtCoinAmt(maxAmount)} $coin',
                    style: const TextStyle(fontSize: 12, color: T.inkLo)),
                const SizedBox(height: 10),
                TextField(
                  controller: ctrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: '$coin ${tr('convert.amount')}',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixText: coin,
                  ),
                  onChanged: (_) => setLocal(() => err = null),
                ),
                const SizedBox(height: 8),
                Text('${tr('convert.you_get')}: ≈ ${_fmtBal.format(estUsdt)} USDT',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                if (err != null) ...[
                  const SizedBox(height: 8),
                  Text(err!, style: const TextStyle(color: T.down, fontSize: 12)),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: busy ? null : () => Navigator.pop(dialogCtx),
                child: Text(tr('common.cancel')),
              ),
              FilledButton(
                onPressed: busy || rate <= 0
                    ? null
                    : () async {
                        final a = double.tryParse(ctrl.text.trim()) ?? 0;
                        if (a <= 0 || a > maxAmount) {
                          setLocal(() => err = tr('convert.invalid_amount'));
                          return;
                        }
                        setLocal(() => busy = true);
                        try {
                          await widget.state.api.convertBalance(from: coin, amount: a);
                          if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                          _reload();
                        } catch (e) {
                          setLocal(() {
                            busy = false;
                            err = e.toString();
                          });
                        }
                      },
                child: Text(busy ? tr('convert.processing') : tr('common.confirm')),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _walletAction(String label, IconData icon,
      {required bool primary, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 42,
        decoration: BoxDecoration(
          gradient: primary ? T.brandGradientShort : null,
          color: primary ? null : const Color(0x1AFFFFFF),
          border: Border.all(
              color: primary ? Colors.transparent : const Color(0x29FFFFFF)),
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 15),
            const SizedBox(width: 6),
            Text(label,
                style: const TextStyle(
                    color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  Widget _statsRow(UserStats s) {
    Widget stat(String label, String value, Color color) => Expanded(
          child: Column(
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 10, color: T.inkLo, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(value,
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: color,
                      fontFamily: T.fontMono)),
            ],
          ),
        );
    Widget divider() => Container(
        width: 1, height: 28, color: const Color(0x140E2238));
    return LightCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Row(
        children: [
          stat(tr('profile.month_pl'),
              (s.monthProfit >= 0 ? '+' : '') + _fmtBal.format(s.monthProfit),
              s.monthProfit >= 0 ? T.upDark : T.down),
          divider(),
          stat(tr('profile.hit_rate'), '${(s.hitRate * 100).round()}%', T.ink),
          divider(),
          stat(tr('profile.won'), '${s.won}', T.gold),
        ],
      ),
    );
  }

  Widget _menu(UserStats s, VipStatus? vip, Map<String, dynamic>? user) {
    final vipLabel = vip != null
        ? '${tr(vip.currentTier.key)}${tr('profile.vip_member')}'
        : tr('profile.vip_badge_short');
    final hasEmail = (user?['email'] as String?)?.isNotEmpty ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LightCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              _row(tr('profile.my_bets'),
                  tr('profile.pending_count').replaceAll('{n}', '${s.pending}'),
                  Icons.bookmark_outline, T.brand, T.brandDeep,
                  widget.onOpenPredictions),
              _row(tr('profile.leaderboard'),
                  tr('profile.leaderboard_pl')
                      .replaceAll('{n}', _fmtBal.format(s.monthProfit)),
                  Icons.emoji_events_outlined,
                  const Color(0xFFFFD66E), T.gold, widget.onGotoLeaderboard),
              _row(tr('profile.rebate_center'), tr('profile.rebate_pending'),
                  Icons.percent, const Color(0xFFC7B5F4),
                  const Color(0xFF8E7AD9), () => widget.onOpenFeature('home.rebate')),
              _row(tr('profile.invite'), tr('profile.invite_sub'),
                  Icons.favorite_border, const Color(0xFFF4A8B8),
                  const Color(0xFFE07089), () => widget.onOpenFeature('home.share_earn')),
            ],
          ),
        ),
        const SizedBox(height: 14),
        LightCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              _setting(tr('profile.vip_level'), Icons.workspace_premium_outlined,
                  vipLabel, () => widget.onOpenFeature('home.vip')),
              _setting(tr('profile.rules'), Icons.help_outline, null,
                  () => widget.onOpenFeature('home.rules')),
              _setting(tr('profile.contact'), Icons.support_agent_outlined,
                  tr('profile.online'), () => widget.onOpenFeature('home.service')),
              _setting(tr('profile.language'), Icons.language, null, widget.onLanguage),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (hasEmail) ...[
          SizedBox(
            height: 44,
            child: OutlinedButton.icon(
              onPressed: _openChangePassword,
              style: OutlinedButton.styleFrom(
                foregroundColor: T.ink,
                side: const BorderSide(color: T.border),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.lock_outline_rounded, size: 18),
              label: Text(tr('profile.change_password'),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (!isInMiniApp())
          SizedBox(
            height: 44,
            child: OutlinedButton.icon(
              onPressed: _confirmLogout,
              style: OutlinedButton.styleFrom(
                foregroundColor: T.down,
                side: BorderSide(color: T.down.withValues(alpha: 0.45)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.logout_rounded, size: 18),
              label: Text(tr('profile.logout'),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            ),
          ),
      ],
    );
  }

  Widget _row(String label, String note, IconData icon, Color c1, Color c2,
      VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [c1, c2]),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, color: Colors.white, size: 17),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700, color: T.ink)),
            ),
            Text(note,
                style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700, color: T.inkLo)),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right, color: T.inkSubtle, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _setting(String label, IconData icon, String? note, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                  color: T.fill, borderRadius: BorderRadius.circular(9)),
              child: Icon(icon, color: T.inkMd, size: 17),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700, color: T.ink)),
            ),
            if (note != null)
              Text(note,
                  style: const TextStyle(fontSize: 11, color: T.inkLo)),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right, color: T.inkSubtle, size: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('profile.logout_confirm_title')),
        content: Text(tr('profile.logout_confirm_body')),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(tr('common.cancel'))),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: TextButton.styleFrom(foregroundColor: T.down),
              child: Text(tr('profile.logout'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await widget.state.api.logout();
    widget.state.stream.setToken(null);
    widget.state.notifyAuthChanged();
    if (!mounted) return;
    _reload();
    Toast.show(context, tr('profile.logout_done'));
  }

  Future<void> _openChangePassword() async {
    final oldCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    String? hint;
    bool busy = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        Future<void> submit() async {
          final oldP = oldCtrl.text;
          final newP = newCtrl.text;
          if (oldP.isEmpty) {
            setLocal(() => hint = tr('profile.cp.err_old_required'));
            return;
          }
          if (newP.length < 6 || newP.length > 72) {
            setLocal(() => hint = tr('profile.cp.err_new_length'));
            return;
          }
          if (newP != confirmCtrl.text) {
            setLocal(() => hint = tr('profile.cp.err_mismatch'));
            return;
          }
          setLocal(() {
            busy = true;
            hint = null;
          });
          try {
            await widget.state.api
                .changePassword(oldPassword: oldP, newPassword: newP);
            if (!ctx.mounted) return;
            Navigator.of(ctx).pop();
            if (mounted) Toast.show(context, tr('profile.cp.done'));
          } catch (e) {
            if (!ctx.mounted) return;
            String h = tr('profile.cp.err_unknown');
            if (e is ApiException) {
              switch (e.message) {
                case 'invalid_credentials':
                  h = tr('profile.cp.err_wrong_old');
                case 'no_password_set':
                  h = tr('profile.cp.err_no_password');
                case 'invalid_password':
                  h = tr('profile.cp.err_new_length');
              }
            }
            setLocal(() {
              busy = false;
              hint = h;
            });
          }
        }

        Widget input(TextEditingController c, String label) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TextField(
                controller: c,
                obscureText: true,
                autocorrect: false,
                decoration: InputDecoration(
                  hintText: label,
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
            );

        return AlertDialog(
          title: Text(tr('profile.change_password')),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                input(oldCtrl, tr('profile.cp.old_placeholder')),
                input(newCtrl, tr('profile.cp.new_placeholder')),
                input(confirmCtrl, tr('profile.cp.confirm_placeholder')),
                if (hint != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(hint!,
                        style: const TextStyle(fontSize: 12, color: T.down)),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: busy ? null : () => Navigator.of(ctx).pop(),
                child: Text(tr('common.cancel'))),
            TextButton(
                onPressed: busy ? null : submit,
                child: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(tr('profile.cp.submit'))),
          ],
        );
      }),
    );
    oldCtrl.dispose();
    newCtrl.dispose();
    confirmCtrl.dispose();
  }
}

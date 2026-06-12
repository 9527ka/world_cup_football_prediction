import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/match.dart';
import '../../services/app_state.dart';
import '../../services/i18n.dart';
import '../../theme/tokens.dart';
import '../../widgets/light_card.dart';
import '../../widgets/login_wall.dart';

/// 桌面提现。复用 getWallet / submitWithdrawal(提交逻辑零改动)。
/// 两栏:左(余额 + 网络 + 地址 + 金额)| 右(摘要 + 提交)。无内置返回栏;
/// 成功后通过 [onClose] 退回。
class WithdrawDesktopPage extends StatefulWidget {
  const WithdrawDesktopPage({
    super.key,
    required this.state,
    required this.onClose,
  });

  final AppState state;
  final VoidCallback onClose;

  @override
  State<WithdrawDesktopPage> createState() => _WithdrawDesktopPageState();
}

class _WithdrawDesktopPageState extends State<WithdrawDesktopPage> {
  static final _fmtBal = NumberFormat('#,##0.00');

  String _chain = 'trc20';
  String _currency = 'USDT';
  Wallet? _wallet;
  final _addressCtrl = TextEditingController();
  final _amountCtrl = TextEditingController(text: '500');
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadWallet();
  }

  @override
  void dispose() {
    _addressCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadWallet() async {
    if (!widget.state.isAuthenticated) {
      if (mounted) setState(() => _error = tr('wd.login_first'));
      return;
    }
    try {
      final w = await widget.state.api.getWallet();
      if (mounted) {
        setState(() {
          _wallet = w;
          if (_error != null && _error!.startsWith(tr('wd.wallet_error'))) {
            _error = null;
          }
          if (_addressCtrl.text.isEmpty && w.lastWithdrawAddress.isNotEmpty) {
            _addressCtrl.text = w.lastWithdrawAddress;
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '${tr('wd.wallet_error')}: $e');
    }
  }

  double get _fee {
    final w = _wallet;
    if (w == null) {
      return _chain == 'erc20' ? 12 : 1;
    }
    return _chain == 'erc20' ? w.withdrawFeeERC20 : w.withdrawFeeTRC20;
  }

  void _selectChain(String chain) {
    setState(() {
      _chain = chain;
      if (chain == 'trc20') _currency = 'USDT';
    });
  }

  Future<void> _submit() async {
    if (_wallet != null && _wallet!.hasPendingWithdrawal) {
      setState(() => _error = tr('err.pending_withdrawal'));
      return;
    }
    final amt = double.tryParse(_amountCtrl.text.trim()) ?? 0;
    final addr = _addressCtrl.text.trim();
    final balance = _wallet?.balance ?? 0;
    final minW = _wallet?.minWithdraw ?? 10;
    final maxW = _wallet?.maxWithdraw ?? 1000000;
    if (amt < minW) {
      setState(() => _error = '${tr('wd.amount_invalid')} (min ${minW.toStringAsFixed(0)})');
      return;
    }
    if (amt > maxW) {
      setState(() => _error = '${tr('wd.amount_invalid')} (max ${maxW.toStringAsFixed(0)})');
      return;
    }
    if (amt > balance) {
      setState(() => _error = tr('wd.insufficient'));
      return;
    }
    if (addr.length < 20) {
      setState(() => _error = tr('wd.addr_invalid'));
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.state.api.submitWithdrawal(amount: amt, address: addr, chain: _chain, currency: _currency);
      _addressCtrl.clear();
      _amountCtrl.text = '500';
      if (mounted) await _showSuccess(amt);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _showSuccess(double amount) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: T.upDark, size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Text(tr('wd.submitted'),
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
        content: Text('-${amount.toStringAsFixed(2)} USDT',
            style: const TextStyle(
                fontSize: 22, fontWeight: FontWeight.w800, color: T.down)),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              widget.onClose();
            },
            child: Text(tr('common.confirm')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.state.isAuthenticated) {
      return ListView(
        padding: const EdgeInsets.symmetric(vertical: 32),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: LoginRequiredCard(
                    state: widget.state,
                    label: tr('wd.title'),
                    onLoggedIn: _loadWallet),
              ),
            ),
          ),
        ],
      );
    }
    final hasPending = _wallet?.hasPendingWithdrawal ?? false;
    final amt = double.tryParse(_amountCtrl.text.trim()) ?? 0;
    final arrive = (amt - _fee).clamp(0, double.infinity).toDouble();
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 24),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (hasPending) _pendingBanner(),
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 6, child: _form(hasPending)),
                        const SizedBox(width: 16),
                        Expanded(flex: 5, child: _rightCol(amt, arrive, hasPending)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _pendingBanner() => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0x1AFF9800),
          border: Border.all(color: const Color(0x60FF9800)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            const Icon(Icons.hourglass_top, color: Color(0xFFE65100), size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(tr('err.pending_withdrawal'),
                  style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFFE65100),
                      fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );

  Widget _form(bool hasPending) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _balanceCard(),
        const SizedBox(height: 14),
        _label(tr('wd.network')),
        _chainTabs(),
        if (_chain == 'erc20') ...[
          const SizedBox(height: 10),
          _label(tr('wd.token')),
          _currencyTabs(),
        ],
        const SizedBox(height: 12),
        _label(tr('wd.address_label')),
        LightCard(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: TextField(
            controller: _addressCtrl,
            enabled: !hasPending,
            style: const TextStyle(
                color: T.ink, fontFamily: T.fontMono, fontSize: 12),
            decoration: InputDecoration(
              border: InputBorder.none,
              isDense: true,
              hintText: tr('wd.address_hint'),
              hintStyle: const TextStyle(color: T.inkLo, fontSize: 12),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _label(tr('wd.amount_label')),
        LightCard(
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _amountCtrl,
                      enabled: !hasPending,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      style: const TextStyle(
                          color: T.ink,
                          fontFamily: T.fontMono,
                          fontSize: 26,
                          fontWeight: FontWeight.w800),
                      decoration: const InputDecoration(
                          border: InputBorder.none, isDense: true),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const Text('USDT',
                      style: TextStyle(
                          color: T.brandDeep,
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: hasPending
                        ? null
                        : () {
                            _amountCtrl.text =
                                (_wallet?.balance ?? 0).toStringAsFixed(2);
                            setState(() {});
                          },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: T.brandDeep,
                      side: const BorderSide(color: T.border),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      minimumSize: const Size(0, 30),
                    ),
                    child: Text(tr('wd.all'),
                        style: const TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (final p in const [100, 500, 1000, 5000])
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: _preset(p),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _rightCol(double amt, double arrive, bool hasPending) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _summary(arrive),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(_error!, style: const TextStyle(color: T.down)),
          ),
        const SizedBox(height: 14),
        SizedBox(
          height: 48,
          child: ElevatedButton(
            onPressed: (_submitting || hasPending) ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: T.brand,
              foregroundColor: Colors.white,
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(_submitting ? tr('wd.submitting') : tr('wd.submit_btn'),
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          ),
        ),
      ],
    );
  }

  Widget _balanceCard() {
    final bal = _wallet?.balance ?? 0;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        gradient: T.heroGradient,
        border: Border.all(color: const Color(0x382CD7FD)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('wd.balance_label'),
              style: const TextStyle(
                  fontSize: 11, color: T.inkMd, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(_fmtBal.format(bal),
                  style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: T.ink,
                      fontFamily: T.fontMono)),
              const SizedBox(width: 6),
              const Text('USDT',
                  style: TextStyle(
                      fontSize: 11,
                      color: T.brandDeep,
                      fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
              '${tr('wd.min_amount')} ${(_wallet?.minWithdraw ?? 10).toStringAsFixed(0)} USDT',
              style: const TextStyle(
                  fontSize: 10, color: T.inkLo, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t,
            style: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: T.inkMd)),
      );

  Widget _chainTabs() {
    final w = _wallet;
    final tabs = [
      ['trc20', 'TRC20', '${(w?.withdrawFeeTRC20 ?? 1).toStringAsFixed(0)} USDT'],
      ['erc20', 'ERC20', '${(w?.withdrawFeeERC20 ?? 12).toStringAsFixed(0)} USDT'],
    ];
    return Row(
      children: tabs.map((c) {
        final on = _chain == c[0];
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => _selectChain(c[0]),
              child: Container(
                height: 46,
                decoration: BoxDecoration(
                  gradient: on
                      ? const LinearGradient(
                          colors: [Color(0x2E2CD7FD), Color(0x0F2CD7FD)])
                      : null,
                  color: on ? null : Colors.white,
                  border: Border.all(color: on ? T.brand : T.border),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(c[1],
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: on ? T.brandDeep : T.inkMd)),
                    Text(c[2],
                        style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: on ? T.brandDeep : T.inkLo)),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _currencyTabs() {
    return Row(
      children: ['USDT', 'USDC'].map((cur) {
        final on = _currency == cur;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => setState(() => _currency = cur),
              child: Container(
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: on
                      ? const LinearGradient(colors: [Color(0x2E2CD7FD), Color(0x0F2CD7FD)])
                      : null,
                  color: on ? null : Colors.white,
                  border: Border.all(color: on ? T.brand : T.border),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(cur,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: on ? T.brandDeep : T.inkMd)),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _preset(int v) {
    final cur = double.tryParse(_amountCtrl.text.trim()) ?? -1;
    final on = cur == v;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () {
        _amountCtrl.text = '$v';
        setState(() {});
      },
      child: Container(
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? const Color(0x242CD7FD) : T.fill,
          border: Border.all(color: on ? T.brand : T.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(v >= 1000 ? '${v ~/ 1000}K' : '$v',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: on ? T.brandDeep : T.inkMd)),
      ),
    );
  }

  Widget _summary(double arrive) {
    final rows = [
      [tr('wd.fee_label'), '${_fee.toStringAsFixed(2)} USDT', T.inkMd, false],
      [tr('wd.actual_label'), '${arrive.toStringAsFixed(2)} USDT', T.upDark, true],
      [tr('wd.eta_label'), tr('wd.eta_value'), T.inkMd, false],
    ];
    return LightCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: i == 0
                  ? null
                  : const BoxDecoration(
                      border: Border(top: BorderSide(color: T.border))),
              child: Row(
                children: [
                  Expanded(
                    child: Text(rows[i][0] as String,
                        style: const TextStyle(
                            fontSize: 12,
                            color: T.inkLo,
                            fontWeight: FontWeight.w600)),
                  ),
                  Text(rows[i][1] as String,
                      style: TextStyle(
                          fontSize: (rows[i][3] as bool) ? 15 : 13,
                          fontWeight: FontWeight.w800,
                          color: rows[i][2] as Color,
                          fontFamily: T.fontMono)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

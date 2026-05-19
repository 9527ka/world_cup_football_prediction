import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/match.dart';
import '../services/app_state.dart';
import '../services/i18n.dart';
import '../theme/tokens.dart';
import '../widgets/light_card.dart';
import '../widgets/login_wall.dart';

/// 09 · 提现 — 链选 + 地址 + 金额 + 摘要 + 提交。
class WithdrawPage extends StatefulWidget {
  const WithdrawPage({super.key, required this.state});
  final AppState state;

  @override
  State<WithdrawPage> createState() => _WithdrawPageState();
}

class _WithdrawPageState extends State<WithdrawPage> {
  String _chain = 'trc20';
  Wallet? _wallet;
  final _addressCtrl = TextEditingController();
  final _amountCtrl = TextEditingController(text: '500');
  bool _submitting = false;
  String? _error;
  String? _ok;

  @override
  void initState() {
    super.initState();
    _loadWallet();
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
          if (_error != null && _error!.startsWith(tr('wd.wallet_error'))) _error = null;
          // 预填上次的提现地址(用户没动过输入框时才填,避免覆盖正在输入的内容)。
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
    switch (_chain) {
      case 'erc20':
        return 12;
      case 'bep20':
        return 0.5;
      default:
        return 1;
    }
  }

  Future<void> _submit() async {
    final amt = double.tryParse(_amountCtrl.text.trim()) ?? 0;
    final addr = _addressCtrl.text.trim();
    final balance = _wallet?.balance ?? 0;
    if (amt <= 0) {
      setState(() => _error = tr('wd.amount_invalid'));
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
      _ok = null;
    });
    try {
      final w = await widget.state.api
          .submitWithdrawal(amount: amt, address: addr);
      _addressCtrl.clear();
      _amountCtrl.text = '500';
      if (mounted) setState(() => _ok = '${tr('wd.submitted')} (#${w.id})');
      await _loadWallet();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 浏览器未登录:用引导卡替代表单。Mini App 内已登录,不会进。
    if (!widget.state.isAuthenticated) {
      return Scaffold(
        backgroundColor: T.bgPage,
        body: Container(
          decoration: const BoxDecoration(gradient: T.pageGradient),
          child: SafeArea(
            child: Column(
              children: [
                _topBar(),
                Expanded(
                  child: LoginRequiredCard(
                    state: widget.state,
                    label: tr('wd.title'),
                    onLoggedIn: _loadWallet,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final amt = double.tryParse(_amountCtrl.text.trim()) ?? 0;
    final arrive = (amt - _fee).clamp(0, double.infinity);
    return Scaffold(
      backgroundColor: T.bgPage,
      body: Container(
        decoration: const BoxDecoration(gradient: T.pageGradient),
        child: SafeArea(
          child: Column(
            children: [
              _topBar(),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                  children: [
                    _balanceCard(),
                    const SizedBox(height: 14),
                    _label(tr('wd.network')),
                    _chainTabs(),
                    const SizedBox(height: 12),
                    _label(tr('wd.address_label')),
                    LightCard(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: TextField(
                        controller: _addressCtrl,
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
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
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
                                onPressed: () {
                                  _amountCtrl.text =
                                      (_wallet?.balance ?? 0).toStringAsFixed(2);
                                  setState(() {});
                                },
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: T.brandDeep,
                                  side: const BorderSide(color: T.border),
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                  minimumSize: const Size(0, 28),
                                ),
                                child: Text(tr('wd.all'),
                                    style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              for (final p in const [100, 500, 1000, 5000])
                                Expanded(
                                  child: Padding(
                                    padding:
                                        const EdgeInsets.symmetric(horizontal: 3),
                                    child: _preset(p),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _summary(amt, arrive.toDouble()),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(_error!, style: const TextStyle(color: T.down)),
                      ),
                    if (_ok != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(_ok!, style: const TextStyle(color: T.upDark)),
                      ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _submitting ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: T.brand,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text(_submitting ? tr('wd.submitting') : tr('wd.submit_btn'),
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w800)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topBar() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: Color(0xC7FFFFFF),
        border: Border(bottom: BorderSide(color: T.border)),
      ),
      child: Row(
        children: [
          IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.chevron_left, color: T.ink)),
          Text(tr('wd.title'),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: T.ink)),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _balanceCard() {
    final bal = _wallet?.balance ?? 0;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
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
              Text(NumberFormat('#,##0.00').format(bal),
                  style: const TextStyle(
                      fontSize: 24,
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
          Text(tr('wd.min_amount'),
              style: const TextStyle(fontSize: 10, color: T.inkLo, fontWeight: FontWeight.w600)),
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
    final tabs = const [
      ['trc20', 'TRC20', '1 USDT'],
      ['erc20', 'ERC20', '12 USDT'],
      ['bep20', 'BEP20', '0.5 USDT'],
    ];
    return Row(
      children: tabs.map((c) {
        final on = _chain == c[0];
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => setState(() => _chain = c[0]),
              child: Container(
                height: 42,
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
        height: 28,
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

  Widget _summary(double amt, double arrive) {
    final eta = _chain == 'erc20' ? tr('wd.eta_slow') : tr('wd.eta_fast');
    final rows = [
      [tr('wd.fee_label'), '${_fee.toStringAsFixed(2)} USDT', T.inkMd, false],
      [tr('wd.actual_label'), '${arrive.toStringAsFixed(2)} USDT', T.upDark, true],
      [tr('wd.eta_label'), eta, T.inkMd, false],
    ];
    return LightCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: i == 0
                  ? null
                  : const BoxDecoration(
                      border: Border(
                          top: BorderSide(color: T.border, style: BorderStyle.solid))),
              child: Row(
                children: [
                  Expanded(
                    child: Text(rows[i][0] as String,
                        style: const TextStyle(
                            fontSize: 11,
                            color: T.inkLo,
                            fontWeight: FontWeight.w600)),
                  ),
                  Text(rows[i][1] as String,
                      style: TextStyle(
                          fontSize: (rows[i][3] as bool) ? 14 : 12,
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

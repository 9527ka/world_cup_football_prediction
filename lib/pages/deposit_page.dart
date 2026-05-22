import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/match.dart';
import '../services/app_state.dart';
import '../services/file_picker_web.dart' as file_picker;
import '../services/i18n.dart';
import '../services/toast.dart';
import '../theme/tokens.dart';
import '../widgets/chain_icon.dart';
import '../widgets/light_card.dart';
import '../widgets/login_wall.dart';

/// 08 · 充值 — 链选 + 地址 + 凭证 + 金额 + 提交。
class DepositPage extends StatefulWidget {
  const DepositPage({super.key, required this.state});
  final AppState state;

  @override
  State<DepositPage> createState() => _DepositPageState();
}

class _DepositPageState extends State<DepositPage> {
  String _chain = 'trc20';
  Wallet? _wallet;
  final _amountCtrl = TextEditingController();
  final _hashCtrl = TextEditingController();
  String _proofUrl = '';
  bool _submitting = false;
  String? _error;
  String? _ok;
  bool _walletLoading = true;
  String? _walletError;

  @override
  void initState() {
    super.initState();
    _loadWallet();
  }

  Future<void> _loadWallet() async {
    if (!widget.state.isAuthenticated) {
      setState(() {
        _walletLoading = false;
        _walletError = tr('dep.login_first');
      });
      return;
    }
    setState(() {
      _walletLoading = true;
      _walletError = null;
    });
    try {
      final w = await widget.state.api.getWallet();
      if (mounted) setState(() { _wallet = w; _walletLoading = false; });
    } catch (e) {
      if (mounted) setState(() { _walletLoading = false; _walletError = '${tr('dep.wallet_error')}: $e'; });
    }
  }

  Future<void> _pickProof() async {
    final pf = await file_picker.pickImageFile();
    if (pf == null) return;
    setState(() => _submitting = true);
    try {
      final url =
          await widget.state.api.uploadProof(pf.bytes, filename: pf.name);
      if (mounted) setState(() => _proofUrl = url);
    } catch (e) {
      if (mounted) setState(() => _error = '${tr('dep.upload_fail')}: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _submit() async {
    final amt = double.tryParse(_amountCtrl.text.trim()) ?? 0;
    final hash = _hashCtrl.text.trim();
    final minD = _wallet?.minDeposit ?? 10;
    final maxD = _wallet?.maxDeposit ?? 1000000;
    if (amt < minD) {
      setState(() => _error = '${tr('dep.amount_invalid')} (min ${minD.toStringAsFixed(0)})');
      return;
    }
    if (amt > maxD) {
      setState(() => _error = '${tr('dep.amount_invalid')} (max ${maxD.toStringAsFixed(0)})');
      return;
    }
    if (hash.length < 10) {
      setState(() => _error = tr('dep.hash_required'));
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
      _ok = null;
    });
    try {
      await widget.state.api.submitDeposit(
        amount: amt,
        txHash: hash,
        proofUrl: _proofUrl,
        chain: _chain,
      );
      _amountCtrl.clear();
      _hashCtrl.clear();
      if (mounted) {
        setState(() {
          _proofUrl = '';
          _ok = null;
        });
        await _showDepositSuccessDialog(amt);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// Success popup — shown after a deposit POST returns 200. We deliberately
  /// don't auto-dismiss: the user should consciously close it so they remember
  /// the deposit is "submitted, awaiting admin review" (not "已到账").
  Future<void> _showDepositSuccessDialog(double amount) async {
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
              child: Text(tr('dep.submitted'),
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${amount.toStringAsFixed(_chain == 'trc20' ? 2 : 8)} ${_chain == 'eth' ? 'ETH' : _chain == 'btc' ? 'BTC' : 'USDT'}',
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w800, color: T.brandDeep)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pop(true);
            },
            child: Text(tr('common.confirm')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 浏览器未登录:用引导卡替代表单。Mini App 内 initialize() 已登录,不进这里。
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
                    label: tr('dep.title'),
                    onLoggedIn: _loadWallet,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
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
                    _label(tr('dep.step1')),
                    _chainPicker(),
                    const SizedBox(height: 14),
                    _addressCard(),
                    const SizedBox(height: 14),
                    _amountForm(),
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
                    _notes(),
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
          Text(tr('dep.title'),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: T.ink)),
          const Spacer(),
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

  Widget _chainPicker() {
    final chains = <_Chain>[
      _Chain('trc20', tr('dep.chain_trc20'), tr('dep.chain_trc20_note')),
      if (_wallet != null && _wallet!.ethDepositAddress.isNotEmpty)
        _Chain('eth', tr('dep.chain_eth'), tr('dep.chain_eth_note')),
      if (_wallet != null && _wallet!.btcDepositAddress.isNotEmpty)
        _Chain('btc', tr('dep.chain_btc'), tr('dep.chain_btc_note')),
    ];
    return Column(
      children: chains.map((c) {
        final on = _chain == c.id;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: InkWell(
            onTap: () => setState(() => _chain = c.id),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                gradient: on
                    ? const LinearGradient(
                        colors: [Color(0x1F2CD7FD), Color(0x0A2CD7FD)])
                    : null,
                color: on ? null : Colors.white,
                border: Border.all(color: on ? T.brand : T.border),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  ChainIcon(chain: c.id, size: 38),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.name,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w800, color: T.ink)),
                        const SizedBox(height: 2),
                        Text(c.note,
                            style: const TextStyle(
                                fontSize: 10, color: T.inkLo, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  Container(
                    width: 18, height: 18,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: on ? Colors.white : Colors.transparent,
                      border: Border.all(
                          color: on ? T.brand : T.inkSubtle,
                          width: on ? 5 : 1.5),
                      boxShadow: on
                          ? const [
                              BoxShadow(
                                  color: T.brand, blurRadius: 0, spreadRadius: 1)
                            ]
                          : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  String _currentAddress() {
    if (_wallet == null) return '';
    switch (_chain) {
      case 'eth': return _wallet!.ethDepositAddress;
      case 'btc': return _wallet!.btcDepositAddress;
      default: return _wallet!.depositAddress;
    }
  }

  Widget _addressCard() {
    final addr = _walletError != null
        ? _walletError!
        : _walletLoading
            ? tr('dep.wallet_loading')
            : (_currentAddress().isEmpty ? tr('dep.addr_not_set') : _currentAddress());
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.white, Color(0xFFF4F8FC)]),
        border: Border.all(color: T.border),
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
              color: Color(0x0F0E2238), blurRadius: 14, offset: Offset(0, 4))
        ],
      ),
      child: Column(
        children: [
          _label(tr('dep.step2')),
          // Mock QR placeholder — in production swap with `qr_flutter` package.
          Container(
            width: 160, height: 160,
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: T.border),
              borderRadius: BorderRadius.circular(14),
              boxShadow: const [
                BoxShadow(
                    color: Color(0x140E2238), blurRadius: 16, offset: Offset(0, 4))
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: GridView.count(
                    crossAxisCount: 21,
                    physics: const NeverScrollableScrollPhysics(),
                    children: List.generate(21 * 21, (i) {
                      final r = i ~/ 21, c = i % 21;
                      final v = ((r * 13 + c * 7) ^ (r * c)) % 5;
                      return Container(color: v < 2 ? T.ink : Colors.transparent);
                    }),
                  ),
                ),
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                  ),
                  alignment: Alignment.center,
                  child: ChainIcon(chain: _chain, size: 34),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: T.fill,
              border: Border.all(color: T.border),
              borderRadius: BorderRadius.circular(10),
            ),
            child: SelectableText(addr,
                style: const TextStyle(
                    fontSize: 12,
                    color: T.ink,
                    fontFamily: T.fontMono,
                    height: 1.5,
                    fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 10),
          if (_walletError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: ElevatedButton.icon(
                onPressed: _loadWallet,
                icon: const Icon(Icons.refresh, size: 14),
                label: Text(tr('dep.retry')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: T.brand,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 36),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _wallet != null && _currentAddress().isNotEmpty
                      ? () {
                          Clipboard.setData(
                              ClipboardData(text: _currentAddress()));
                          Toast.show(context, tr('dep.addr_copied'));
                        }
                      : null,
                  icon: const Icon(Icons.copy, size: 14),
                  label: Text(tr('dep.copy_addr')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: T.brand,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 38),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickProof,
                  icon: const Icon(Icons.image_outlined, size: 14),
                  label: Text(_proofUrl.isEmpty ? tr('dep.upload_proof') : tr('dep.uploaded')),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: T.brandDeep,
                    side: const BorderSide(color: T.brand),
                    minimumSize: const Size(0, 38),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _amountForm() {
    return LightCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(tr('dep.step3')),
          TextField(
            controller: _amountCtrl,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(color: T.ink, fontFamily: T.fontMono, fontSize: 16),
            decoration: _input(hint: '${tr('dep.amount_hint')} ${_chain == 'eth' ? 'ETH' : _chain == 'btc' ? 'BTC' : 'USDT'}'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _hashCtrl,
            style: const TextStyle(color: T.ink, fontFamily: T.fontMono, fontSize: 13),
            decoration: _input(hint: tr('dep.hash_hint')),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton(
              onPressed: _submitting ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: T.brand,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(_submitting ? tr('dep.submitting') : tr('dep.submit_btn'),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _notes() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0x14F5B544),
        border: Border.all(color: const Color(0x40F5B544)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('dep.note_title'),
              style: const TextStyle(
                  fontSize: 12, color: Color(0xFFC7861E), fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(tr('dep.note1'),
              style: const TextStyle(fontSize: 11, color: T.inkMd, height: 1.7)),
          Text(tr('dep.note2'),
              style: const TextStyle(fontSize: 11, color: T.inkMd, height: 1.7)),
          Text(tr('dep.note3'),
              style: const TextStyle(fontSize: 11, color: T.inkMd, height: 1.7)),
          Text(tr('dep.note4'),
              style: const TextStyle(fontSize: 11, color: T.inkMd, height: 1.7)),
          Text(tr('dep.note_eth_btc'),
              style: const TextStyle(fontSize: 11, color: T.inkMd, height: 1.7)),
        ],
      ),
    );
  }

  InputDecoration _input({String? hint}) => InputDecoration(
        filled: true,
        fillColor: T.fill,
        hintText: hint,
        hintStyle: const TextStyle(color: T.inkLo, fontSize: 13),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: T.border)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: T.border)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: T.brand, width: 1.5)),
      );
}

class _Chain {
  final String id;
  final String name;
  final String note;
  const _Chain(this.id, this.name, this.note);
}

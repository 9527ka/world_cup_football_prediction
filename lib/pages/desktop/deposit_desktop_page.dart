import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../models/match.dart';
import '../../services/app_state.dart';
import '../../services/file_picker_web.dart' as file_picker;
import '../../services/i18n.dart';
import '../../services/toast.dart';
import '../../theme/tokens.dart';
import '../../widgets/chain_icon.dart';
import '../../widgets/light_card.dart';
import '../../widgets/login_wall.dart';

/// 桌面充值。复用 getWallet / uploadProof / submitDeposit(提交逻辑零改动)。
/// 两栏:左(链选 + 地址/QR/复制/上传)| 右(金额/哈希表单 + 注意事项)。
/// 无内置返回栏;提交成功后通过 [onClose] 退回。
class DepositDesktopPage extends StatefulWidget {
  const DepositDesktopPage({
    super.key,
    required this.state,
    required this.onClose,
  });

  final AppState state;
  final VoidCallback onClose;

  @override
  State<DepositDesktopPage> createState() => _DepositDesktopPageState();
}

class _DepositDesktopPageState extends State<DepositDesktopPage> {
  String _chain = 'trc20';
  String _currency = 'USDT';
  Wallet? _wallet;
  final _amountCtrl = TextEditingController();
  final _hashCtrl = TextEditingController();
  String _proofUrl = '';
  bool _submitting = false;
  String? _error;
  bool _walletLoading = true;
  String? _walletError;

  @override
  void initState() {
    super.initState();
    _loadWallet();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _hashCtrl.dispose();
    super.dispose();
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
      if (mounted) setState(() {
        _wallet = w;
        _walletLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() {
        _walletLoading = false;
        _walletError = '${tr('dep.wallet_error')}: $e';
      });
    }
  }

  String _currentAddress() {
    if (_wallet == null) return '';
    switch (_chain) {
      case 'eth':
        return _wallet!.ethDepositAddress;
      case 'btc':
        return _wallet!.btcDepositAddress;
      default:
        return _wallet!.depositAddress;
    }
  }

  List<String> _currenciesForChain(String chain) {
    switch (chain) {
      case 'eth':
        return ['ETH', 'USDT', 'USDC'];
      case 'btc':
        return ['BTC'];
      default:
        return ['USDT'];
    }
  }

  void _onChainChanged(String chain) {
    setState(() {
      _chain = chain;
      _currency = _currenciesForChain(chain).first;
    });
  }

  DepositCurrencyCfg _curCfg() {
    final m = _wallet?.depositCurrencies ?? const {};
    return m[_currency] ??
        DepositCurrencyCfg(
            min: 0, max: double.infinity, decimals: _currency == 'ETH' || _currency == 'BTC' ? 4 : 2);
  }

  Future<void> _pickProof() async {
    final pf = await file_picker.pickImageFile();
    if (pf == null) return;
    setState(() => _submitting = true);
    try {
      final url = await widget.state.api.uploadProof(pf.bytes, filename: pf.name);
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
    final cfg = _curCfg();
    final dec = cfg.decimals;
    if (amt < cfg.min) {
      setState(() => _error = '${tr('dep.amount_invalid')} (min ${cfg.min.toStringAsFixed(dec)} $_currency)');
      return;
    }
    if (cfg.max > 0 && amt > cfg.max) {
      setState(() => _error = '${tr('dep.amount_invalid')} (max ${cfg.max.toStringAsFixed(dec)} $_currency)');
      return;
    }
    if (hash.length < 10) {
      setState(() => _error = tr('dep.hash_required'));
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.state.api.submitDeposit(
        amount: amt,
        txHash: hash,
        proofUrl: _proofUrl,
        chain: _chain,
        currency: _currency,
      );
      _amountCtrl.clear();
      _hashCtrl.clear();
      if (mounted) {
        setState(() => _proofUrl = '');
        await _showSuccess(amt);
      }
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
              child: Text(tr('dep.submitted'),
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
        content: Text(
            '${amount.toStringAsFixed(_curCfg().decimals)} $_currency',
            style: const TextStyle(
                fontSize: 22, fontWeight: FontWeight.w800, color: T.brandDeep)),
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
                    label: tr('dep.title'),
                    onLoggedIn: _loadWallet),
              ),
            ),
          ),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 24),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 880),
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
                          _label(tr('dep.step1')),
                          _chainPicker(),
                          _currencyPicker(),
                          const SizedBox(height: 12),
                          _addressCard(),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 5,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _amountForm(),
                          if (_error != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: Text(_error!,
                                  style: const TextStyle(color: T.down)),
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
          ),
        ),
      ],
    );
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t,
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: T.inkMd)),
      );

  Widget _currencyPicker() {
    final curs = _currenciesForChain(_chain);
    if (curs.length <= 1) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Wrap(
        spacing: 8,
        children: curs.map((cur) {
          final on = _currency == cur;
          return ChoiceChip(
            label: Text(cur,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: on ? FontWeight.w800 : FontWeight.w600,
                    color: on ? Colors.white : T.ink)),
            selected: on,
            selectedColor: T.brand,
            backgroundColor: const Color(0xFFEAF1F8),
            visualDensity: VisualDensity.compact,
            onSelected: (_) => setState(() => _currency = cur),
          );
        }).toList(),
      ),
    );
  }

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
            onTap: () => _onChainChanged(c.id),
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
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: T.ink)),
                        const SizedBox(height: 2),
                        Text(c.note,
                            style: const TextStyle(
                                fontSize: 10,
                                color: T.inkLo,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  Icon(on ? Icons.radio_button_checked : Icons.radio_button_off,
                      color: on ? T.brand : T.inkSubtle, size: 20),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _addressCard() {
    final addr = _walletError != null
        ? _walletError!
        : _walletLoading
            ? tr('dep.wallet_loading')
            : (_currentAddress().isEmpty
                ? tr('dep.addr_not_set')
                : _currentAddress());
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.white, Color(0xFFF4F8FC)]),
        border: Border.all(color: T.border),
        borderRadius: BorderRadius.circular(18),
        boxShadow: T.shadowCard,
      ),
      child: Column(
        children: [
          _label(tr('dep.step2')),
          // 真实二维码:内容 = 当前充值地址,随链/币种切换自动重建;高容错(H)
          // 以便中心叠加链图标后钱包仍可扫描识别。地址为空时显示占位图标。
          Container(
            width: 150,
            height: 150,
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: T.border),
              borderRadius: BorderRadius.circular(14),
            ),
            child: _currentAddress().isEmpty
                ? Center(
                    child: Icon(Icons.qr_code_2, size: 68, color: T.border))
                : Stack(
                    alignment: Alignment.center,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(10),
                        child: QrImageView(
                          data: _currentAddress(),
                          version: QrVersions.auto,
                          size: 130,
                          backgroundColor: Colors.white,
                          errorCorrectionLevel: QrErrorCorrectLevel.H,
                        ),
                      ),
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                        ),
                        alignment: Alignment.center,
                        child: ChainIcon(chain: _chain, size: 32),
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
                    minimumSize: const Size(0, 40),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickProof,
                  icon: const Icon(Icons.image_outlined, size: 14),
                  label: Text(_proofUrl.isEmpty
                      ? tr('dep.upload_proof')
                      : tr('dep.uploaded')),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: T.brandDeep,
                    side: const BorderSide(color: T.brand),
                    minimumSize: const Size(0, 40),
                  ),
                ),
              ),
            ],
          ),
          // 已上传凭证 → 居中缩略图,点击全屏放大核对
          if (_proofUrl.isNotEmpty) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.center,
              child: GestureDetector(
                onTap: _viewProof,
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        widget.state.api.mediaUrl(_proofUrl),
                        width: 72,
                        height: 72,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 72,
                          height: 72,
                          color: Colors.black12,
                          child: const Icon(Icons.broken_image,
                              size: 20, color: Colors.black38),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 2,
                      bottom: 2,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Icon(Icons.zoom_in,
                            size: 13, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 全屏查看凭证(可双指/滚轮缩放),点背景关闭。
  void _viewProof() {
    if (_proofUrl.isEmpty) return;
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => GestureDetector(
        onTap: () => Navigator.of(ctx).pop(),
        child: Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          insetPadding: const EdgeInsets.all(12),
          child: InteractiveViewer(
            maxScale: 5,
            child: Image.network(
              widget.state.api.mediaUrl(_proofUrl),
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) =>
                  const Icon(Icons.broken_image, size: 48, color: Colors.white54),
            ),
          ),
        ),
      ),
    );
  }

  Widget _amountForm() {
    return LightCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(tr('dep.step3')),
          TextField(
            controller: _amountCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(
                color: T.ink, fontFamily: T.fontMono, fontSize: 16),
            decoration: _input(
                hint:
                    '${tr('dep.amount_hint')} $_currency'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _hashCtrl,
            style: const TextStyle(
                color: T.ink, fontFamily: T.fontMono, fontSize: 13),
            decoration: _input(hint: tr('dep.hash_hint')),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton(
              onPressed: _submitting ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: T.brand,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(
                  _submitting ? tr('dep.submitting') : tr('dep.submit_btn'),
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w800)),
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
                  fontSize: 12,
                  color: Color(0xFFC7861E),
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          for (final k in const [
            'dep.note1',
            'dep.note2',
            'dep.note3',
            'dep.note4',
            'dep.note_eth_btc'
          ])
            Text(tr(k),
                style: const TextStyle(
                    fontSize: 11, color: T.inkMd, height: 1.7)),
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

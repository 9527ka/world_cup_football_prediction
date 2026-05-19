// LoginWall — 浏览器环境(非 Telegram Mini App)未登录拦截层。
//
// 用法:在需要登录的操作前调用 `requireLogin(ctx, state)`(在 services/auth_gate.dart)。
// 它会自动弹这个 sheet。LoginWall.installOnce() 必须在 app 启动时调一次,把
// modal 打开器注入到 auth_gate(避免 services 反向依赖 widgets)。
import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/app_state.dart';
import '../services/auth_gate.dart';
import '../services/i18n.dart';
import '../theme/tokens.dart';

class LoginWall {
  /// 在 main() 里调一次,把 sheet 打开器注入到 auth_gate。
  static void installOnce() {
    registerLoginWallShower((ctx, state) => _show(ctx, state));
  }

  static Future<bool> _show(BuildContext ctx, AppState state) async {
    final ok = await showModalBottomSheet<bool>(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => _LoginWallSheet(state: state),
    );
    return ok ?? false;
  }
}

/// `LoginRequiredCard` —— 页面级 inline 提示,替代受保护内容(钱包卡、充值表
/// 单等)显示。点击 CTA 触发 LoginWall 弹层,成功后调用 [onLoggedIn] 让上层
/// 刷新数据。`label` 形如 "充值" / "提现",用于个性化提示。
class LoginRequiredCard extends StatelessWidget {
  const LoginRequiredCard({
    super.key,
    required this.state,
    required this.label,
    this.onLoggedIn,
  });
  final AppState state;
  final String label;
  final VoidCallback? onLoggedIn;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 32, 16, 24),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: T.border),
        ),
        child: Column(
          children: [
            Container(
              width: 56, height: 56, alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF229ED9), Color(0xFF2AABEE)]),
                borderRadius: BorderRadius.circular(28),
              ),
              child: const Icon(Icons.lock_outline_rounded, color: Colors.white, size: 26),
            ),
            const SizedBox(height: 14),
            Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: T.ink)),
            const SizedBox(height: 6),
            Text(tr('login.subtitle'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: T.inkMd, height: 1.5)),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 42,
              child: ElevatedButton(
                onPressed: () async {
                  final ok = await requireLogin(context, state);
                  if (ok && onLoggedIn != null) onLoggedIn!();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF229ED9),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
                // 不放 TG 图标:LoginRequiredCard 进入的是混合登录弹层(邮箱 + TG),
                // 不应暗示只有 TG。文案"登录/注册"通用,跟 LoginWall 内的 Telegram-only
                // 按钮(`login.cta` = "使用 Telegram 授权登录")分开。
                child: Text(tr('login.cta_signup'),
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoginWallSheet extends StatefulWidget {
  const _LoginWallSheet({required this.state});
  final AppState state;

  @override
  State<_LoginWallSheet> createState() => _LoginWallSheetState();
}

class _LoginWallSheetState extends State<_LoginWallSheet> {
  // 0 = 邮箱表单(网页默认),1 = Telegram。Mini App 不显示 0 这个选项。
  int _mode = 0;
  // 邮箱面板内部:false = 登录,true = 注册。
  bool _isRegister = false;
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _displayNameCtrl = TextEditingController();

  bool _busy = false;
  String? _hint;

  @override
  void initState() {
    super.initState();
    // Mini App 永远 mode=1 (邮箱表单不展示);浏览器进来默认显示邮箱。
    _mode = isInMiniApp() ? 1 : 0;
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _displayNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _onTelegramTap() async {
    setState(() {
      _busy = true;
      _hint = null;
    });
    // startBrowserTelegramLogin 走整页跳转,fire-and-forget;失败回退在 .then。
    startBrowserTelegramLogin(widget.state).then((ok) {
      if (!mounted) return;
      if (!ok) {
        setState(() {
          _busy = false;
          _hint = tr('login.failed_hint');
        });
      }
    });
  }

  Future<void> _onEmailSubmit() async {
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    final displayName = _displayNameCtrl.text.trim();

    // 表单本地基本校验 — 跟后端约束保持一致以提示更友好。
    if (email.isEmpty || !email.contains('@') || !email.contains('.')) {
      setState(() => _hint = tr('login.email.err_email'));
      return;
    }
    if (password.length < 6 || password.length > 72) {
      setState(() => _hint = tr('login.email.err_password'));
      return;
    }
    if (_isRegister && (displayName.isEmpty || displayName.length > 30)) {
      setState(() => _hint = tr('login.email.err_display_name'));
      return;
    }

    setState(() {
      _busy = true;
      _hint = null;
    });
    try {
      if (_isRegister) {
        await widget.state.api.registerEmail(
          email: email,
          password: password,
          displayName: displayName,
        );
      } else {
        await widget.state.api.loginEmail(email: email, password: password);
      }
      // register/login 内部已 _token + _user + _persist,直接通知 listener 重建。
      widget.state.notifyAuthChanged();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      // ApiException.message = 后端 raw 错码;toString() 已被 _zhError 翻译,不能精确匹配。
      String hint = tr('login.email.err_unknown');
      if (e is ApiException) {
        switch (e.message) {
          case 'email_taken':
            hint = tr('login.email.err_taken');
          case 'invalid_credentials':
            hint = tr('login.email.err_credentials');
          case 'invalid_email':
            hint = tr('login.email.err_email');
          case 'invalid_password':
            hint = tr('login.email.err_password');
          case 'invalid_display_name':
            hint = tr('login.email.err_display_name');
        }
      }
      setState(() {
        _busy = false;
        _hint = hint;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final showEmail = !isInMiniApp();
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [
            BoxShadow(color: Color(0x33000000), blurRadius: 20, offset: Offset(0, 6)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // logo
            Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF229ED9), Color(0xFF2AABEE)],
                ),
                borderRadius: BorderRadius.circular(32),
              ),
              child: const Icon(Icons.send_rounded, color: Colors.white, size: 32),
            ),
            const SizedBox(height: 14),
            Text(tr('login.title'),
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: T.ink)),
            const SizedBox(height: 6),
            Text(
              tr('login.subtitle'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: T.inkMd, height: 1.5),
            ),
            const SizedBox(height: 16),
            if (showEmail) ...[
              _tabBar(),
              const SizedBox(height: 14),
            ],
            if (_mode == 0 && showEmail) _emailPanel() else _telegramPanel(),
            if (_hint != null) ...[
              const SizedBox(height: 10),
              Text(_hint!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: T.down)),
            ],
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy ? null : () => Navigator.of(context).pop(false),
              child: Text(tr('login.later'),
                  style: const TextStyle(fontSize: 12, color: T.inkMd)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabBar() {
    Widget btn(int idx, String label) {
      final on = _mode == idx;
      return Expanded(
        child: GestureDetector(
          onTap: _busy
              ? null
              : () => setState(() {
                    _mode = idx;
                    _hint = null;
                  }),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: on ? const Color(0xFF229ED9) : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: on ? Colors.white : T.inkMd,
                )),
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: T.bgPage,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(children: [
        btn(0, tr('login.tab.email')),
        btn(1, tr('login.tab.telegram')),
      ]),
    );
  }

  Widget _emailPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_isRegister) ...[
          _input(_displayNameCtrl, tr('login.email.display_name_placeholder')),
          const SizedBox(height: 10),
        ],
        _input(_emailCtrl, tr('login.email.email_placeholder'),
            keyboard: TextInputType.emailAddress),
        const SizedBox(height: 10),
        _input(_passwordCtrl, tr('login.email.password_placeholder'), obscure: true),
        const SizedBox(height: 14),
        SizedBox(
          height: 44,
          child: ElevatedButton(
            onPressed: _busy ? null : _onEmailSubmit,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF229ED9),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            child: _busy
                ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : Text(_isRegister ? tr('login.email.register_cta') : tr('login.email.login_cta'),
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          ),
        ),
        const SizedBox(height: 6),
        TextButton(
          onPressed: _busy
              ? null
              : () => setState(() {
                    _isRegister = !_isRegister;
                    _hint = null;
                  }),
          child: Text(
            _isRegister ? tr('login.email.switch_to_login') : tr('login.email.switch_to_register'),
            style: const TextStyle(fontSize: 12, color: T.inkMd),
          ),
        ),
      ],
    );
  }

  Widget _input(TextEditingController c, String hint,
      {bool obscure = false, TextInputType? keyboard}) {
    return TextField(
      controller: c,
      obscureText: obscure,
      keyboardType: keyboard,
      autocorrect: false,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 13, color: T.inkLo),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: T.border)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: T.border)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFF229ED9), width: 1.4)),
      ),
    );
  }

  Widget _telegramPanel() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 46,
          child: ElevatedButton(
            onPressed: _busy ? null : _onTelegramTap,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF229ED9),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: _busy
                ? const SizedBox(
                    width: 22, height: 22,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.send_rounded, size: 18),
                      const SizedBox(width: 8),
                      Text(tr('login.cta'),
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          tr('login.popup_note'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 11, color: T.inkLo, height: 1.5),
        ),
      ],
    );
  }
}

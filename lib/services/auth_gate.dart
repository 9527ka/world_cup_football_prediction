// 网页版登录拦截 + Telegram OAuth 整页跳转流程(2026-05-18b 重写)。
//
// 两种登录入口:
//  1. Mini App(Telegram WebApp 注入 initData):initialize() 自动登录,无需用户操作
//  2. 普通浏览器:用户访问需要鉴权的功能时 LoginWall 弹层 → 点击「Telegram 登录」
//     → **整页跳转**到 https://oauth.telegram.org/auth?... → 用户授权 → Telegram
//     redirect 回 https://cup.douwen.me/tg_auth_done.html#tgAuthResult=...
//     → 中转页 JS 自己 POST /api/auth/telegram-web 拿 token → location.replace
//     到主页 `?tg_token=...` → Flutter main() 检测 URL → 写 token + 清 URL。
//
// 不用 popup:Chrome 已默认拦第三方 cookie,popup 内 oauth.telegram.org 无法
// 维持会话;再加 popup blocker 风险。整页跳转 = 没第三方 cookie / 没 opener /
// 没 postMessage origin 问题,稳定。
//
// 重要:bot 必须在 BotFather 用 `/setdomain cup.douwen.me` 配置好,否则
// Telegram OAuth 会拒绝(报 "Bot domain invalid")。
import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/widgets.dart';

import 'app_state.dart';
import 'telegram.dart';

/// Mini App vs 浏览器环境判定。
/// `Telegram.initData()` 非空 = Mini App(Telegram WebView 注入了 user payload)。
bool isInMiniApp() => Telegram.initData().isNotEmpty;

/// 浏览器登录:整页跳转到 Telegram OAuth,授权回来后由 tg_auth_done.html 接管。
///
/// **不会 return**(浏览器已 navigate 走)。返回 false 表示前置检查就失败了
/// (bot 配置缺失 / 无法读 location.origin),调用方应当 toast 提示。
Future<bool> startBrowserTelegramLogin(AppState state) async {
  AuthCheck:
  {
    final cfg = await () async {
      try {
        return await state.api.authConfig();
      } catch (_) {
        return null;
      }
    }();
    if (cfg == null || !cfg.isConfigured) return false;

    final origin = _windowOrigin();
    if (origin.isEmpty) return false;

    // 保存当前 URL,登录回来后 tg_auth_done.html 跳回这里。
    _saveReturnUrl();

    final returnTo = '$origin/tg_auth_done.html';
    final oauthUrl = 'https://oauth.telegram.org/auth'
        '?bot_id=${cfg.botId}'
        '&origin=${Uri.encodeQueryComponent(origin)}'
        '&return_to=${Uri.encodeQueryComponent(returnTo)}'
        '&request_access=write';

    // 整页跳转。assign() 保留浏览器历史(用户可以 Back 回原页);replace() 不保留。
    // 用 assign,Back 回来时 LoginWall 还在,UX 友好。
    try {
      final loc = globalContext.getProperty('location'.toJS) as JSObject?;
      loc?.callMethod('assign'.toJS, oauthUrl.toJS);
    } catch (_) {
      return false;
    }
    // 浏览器已经跳走,后面代码理论上不会跑;Future 保留 90s 心态防 await 立刻返回。
    await Future.delayed(const Duration(seconds: 90));
    break AuthCheck;
  }
  return false;
}

/// 在主流程里包一层「需要登录」拦截。已登录直接 true;未登录:
///  - Mini App:报错(不正常情况;初始化已经尝试过自动登录),返回 false
///  - 浏览器:弹 LoginWall(UI 在 widgets/login_wall.dart)
///
/// 浏览器路径下 LoginWall 内点击「Telegram 登录」会整页跳走;此 Future 实际
/// **不会**自己 complete,因为浏览器已 navigate。Future 只在用户取消(关 sheet)
/// 时 complete(false)。
typedef LoginWallShower = Future<bool> Function(BuildContext ctx, AppState state);

LoginWallShower? _shower;

/// LoginWall widget 启动时调一次,把 modal 打开器注入。避免 services 包反向
/// 依赖 widgets 包。
void registerLoginWallShower(LoginWallShower fn) {
  _shower = fn;
}

Future<bool> requireLogin(BuildContext ctx, AppState state) async {
  if (state.isAuthenticated) return true;
  if (!isInMiniApp() && _shower != null) {
    return _shower!(ctx, state);
  }
  return false;
}

/// 浏览器主入口启动时调一次:检查 URL 是否带 `?tg_token=...`(从
/// tg_auth_done.html 跳回的),有就取 token 写入 ApiClient,然后清 URL。
///
/// 返回 token(若有),由 main.dart 决定是否要立刻持久化 / 发请求验证用户信息。
Future<String?> consumeIncomingToken(AppState state) async {
  String? tok;
  try {
    final loc = globalContext.getProperty('location'.toJS) as JSObject?;
    final search = (loc?.getProperty('search'.toJS))?.toString() ?? '';
    if (search.isEmpty || !search.contains('tg_token=')) return null;
    final params = Uri.splitQueryString(search.startsWith('?') ? search.substring(1) : search);
    tok = params['tg_token'];
    if (tok == null || tok.isEmpty) return null;
    // 把 token 写入 api(并持久化 SharedPreferences)+ 拉一次 user 信息。
    // await:防止后续 loadFromStorage 用旧值覆盖 in-memory token。
    await state.api.setTokenFromExternal(tok);
    try {
      final u = await state.api.getMe();
      await state.api.setUserFromExternal(u);
    } catch (_) {/* 拉不到 me 时 token 也能用,留给后续请求验证 */}
    state.stream.setToken(state.api.token);
    // 清掉 URL 上的 token 防止用户分享 URL 泄露:用 history.replaceState 改 URL,
    // 不刷新页面。保留其它 query 参数。
    _clearTokenFromUrl();
    state.notifyAuthChanged();
  } catch (_) {/* 静默失败,用户会看到未登录态,可以重来 */}
  return tok;
}

// ── helpers ────────────────────────────────────────────────────────

String _windowOrigin() {
  try {
    final loc = globalContext.getProperty('location'.toJS) as JSObject?;
    final o = loc?.getProperty('origin'.toJS);
    if (o == null) return '';
    return o.toString();
  } catch (_) {
    return '';
  }
}

void _saveReturnUrl() {
  try {
    final loc = globalContext.getProperty('location'.toJS) as JSObject?;
    final href = (loc?.getProperty('href'.toJS))?.toString() ?? '';
    if (href.isEmpty) return;
    final win = globalContext.getProperty('window'.toJS) as JSObject?;
    final ss = win?.getProperty('sessionStorage'.toJS) as JSObject?;
    ss?.callMethod('setItem'.toJS, 'tg.return_url'.toJS, href.toJS);
  } catch (_) {}
}

void _clearTokenFromUrl() {
  try {
    final win = globalContext.getProperty('window'.toJS) as JSObject?;
    final loc = win?.getProperty('location'.toJS) as JSObject?;
    final pathname = (loc?.getProperty('pathname'.toJS))?.toString() ?? '/';
    final search = (loc?.getProperty('search'.toJS))?.toString() ?? '';
    final hash = (loc?.getProperty('hash'.toJS))?.toString() ?? '';
    // 去掉 tg_token 这一个参数,保留其它
    var qs = search.startsWith('?') ? search.substring(1) : search;
    final params = qs.isEmpty ? <String, String>{} : Uri.splitQueryString(qs);
    params.remove('tg_token');
    final rebuilt = params.entries
        .map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    final newUrl = pathname + (rebuilt.isEmpty ? '' : '?$rebuilt') + hash;
    final hist = win?.getProperty('history'.toJS) as JSObject?;
    hist?.callMethod('replaceState'.toJS, null, ''.toJS, newUrl.toJS);
  } catch (_) {}
}

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

class Telegram {
  static String initData() {
    return _readString('__TG_INIT_DATA');
  }

  static String theme() {
    final v = _readString('__TG_THEME');
    return v.isEmpty ? 'dark' : v;
  }

  /// IETF language tag injected by index.html from
  /// `Telegram.WebApp.initDataUnsafe.user.language_code` ("zh", "en", "ru", ...).
  /// Empty when running outside Telegram.
  static String languageCode() => _readString('__TG_LANG');

  /// Deep-link start parameter from `t.me/<bot>?start=<code>`.
  /// Forwarded to /api/auth/telegram so the backend can bind the inviter
  /// on first login. Empty when not invited via link.
  static String startParam() => _readString('__TG_START_PARAM');

  /// Open a t.me link via Telegram WebApp's openTelegramLink (stays inside
  /// Telegram, no browser hop). Falls back to window.open for the dev/web
  /// case where Telegram WebApp isn't injected.
  static void openTelegramLink(String url) {
    try {
      final tg = globalContext.getProperty('Telegram'.toJS);
      if (tg != null) {
        final webApp = (tg as JSObject).getProperty('WebApp'.toJS);
        if (webApp != null) {
          (webApp as JSObject).callMethod('openTelegramLink'.toJS, url.toJS);
          return;
        }
      }
    } catch (_) {}
    try {
      final win = globalContext.getProperty('window'.toJS) as JSObject?;
      win?.callMethod('open'.toJS, url.toJS, '_blank'.toJS);
    } catch (_) {}
  }

  /// 重载整个 WebApp。Telegram 会在页面重新加载时重新注入**新的 initData**
  /// (新的 auth_date / hash)。当旧 initData 失效("登录失效")时,重发同一份
  /// 永远会被后端拒 —— 必须 reload 才能拿到新签名。供"重试"按钮使用。
  static void reloadApp() {
    try {
      final win = globalContext.getProperty('window'.toJS) as JSObject?;
      final loc = win?.getProperty('location'.toJS) as JSObject?;
      loc?.callMethod('reload'.toJS);
    } catch (_) {}
  }

  /// 是否运行在真正的 Telegram Mini App 容器里(与 initData 是否为空无关)。
  /// 判据:`window.Telegram.WebApp.platform` 存在且不是 "unknown"。
  /// 用于区分「Mini App 但 initData 暂缺/失效」(应 reload 自愈)与「普通浏览器」
  /// (应走网页登录)。initData 为空时不能再用它来判断是不是 Mini App。
  static bool inTelegramWebApp() {
    try {
      final tg = globalContext.getProperty('Telegram'.toJS) as JSObject?;
      final webApp = tg?.getProperty('WebApp'.toJS) as JSObject?;
      if (webApp == null) return false;
      final p = webApp.getProperty('platform'.toJS);
      final s = (p is JSString) ? p.toDart : (p?.toString() ?? '');
      return s.isNotEmpty && s != 'unknown';
    } catch (_) {
      return false;
    }
  }

  /// 实时读取 `window.Telegram.WebApp.initData`(权威当前值);为空则回退到
  /// index.html 在页面加载时抓的快照 `__TG_INIT_DATA`。某些客户端 initData 会在
  /// ready() 之后才填充,直接读 WebApp 比读快照更稳。
  static String liveInitData() {
    try {
      final tg = globalContext.getProperty('Telegram'.toJS) as JSObject?;
      final webApp = tg?.getProperty('WebApp'.toJS) as JSObject?;
      final v = webApp?.getProperty('initData'.toJS);
      final s = (v is JSString) ? v.toDart : (v?.toString() ?? '');
      if (s.isNotEmpty) return s;
    } catch (_) {}
    return initData();
  }

  // ── 自动 reload 自愈计数(sessionStorage,按 WebView 会话隔离)──────────
  // 每次新开 Mini App = 新 WebView = sessionStorage 清空 → 允许重试一次。
  // reload 后同一会话内计数保留 → 避免「拿不到 initData 就无限刷新」。
  static const _reloadKey = 'tg.auth_reload';

  static int authReloadAttempts() {
    try {
      final ss = _sessionStorage();
      final v = ss?.callMethod('getItem'.toJS, _reloadKey.toJS);
      final s = (v is JSString) ? v.toDart : (v?.toString() ?? '');
      return int.tryParse(s) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// 记录一次自愈 reload 尝试。**返回是否真的持久化成功** —— 只有成功记下计数
  /// 才允许调用方 reload,否则(如 sessionStorage 不可用)计数永远是 0 会导致
  /// 无限刷新。调用方务必:`if (attempts < 1 && markAuthReload()) reloadApp();`
  static bool markAuthReload() {
    try {
      final before = authReloadAttempts();
      _sessionStorage()?.callMethod('setItem'.toJS, _reloadKey.toJS, '${before + 1}'.toJS);
      return authReloadAttempts() > before; // 读回校验:确实写进去了才返回 true
    } catch (_) {
      return false;
    }
  }

  static void clearAuthReload() {
    try {
      _sessionStorage()?.callMethod('removeItem'.toJS, _reloadKey.toJS);
    } catch (_) {}
  }

  static JSObject? _sessionStorage() {
    final win = globalContext.getProperty('window'.toJS) as JSObject?;
    return win?.getProperty('sessionStorage'.toJS) as JSObject?;
  }

  static String _readString(String name) {
    try {
      final js = globalContext.getProperty(name.toJS);
      if (js == null) return '';
      if (js is JSString) return js.toDart;
      return js.toString();
    } catch (_) {
      return '';
    }
  }
}

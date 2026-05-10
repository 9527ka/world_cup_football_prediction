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

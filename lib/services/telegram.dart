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

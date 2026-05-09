import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'pages/main_shell.dart';
import 'services/api_client.dart';
import 'services/app_state.dart';
import 'services/i18n.dart';
import 'services/odds_stream.dart';
import 'services/team_overrides.dart';
import 'theme/tokens.dart';

/// 全局 ScrollBehavior — 让 ScrollView 在 Web / WebApp 内也接受鼠标拖动 + 触控板,
/// 否则水平 ScrollView(如 chip 行)在桌面浏览器和 Telegram Mini App 内只能用
/// 滚轮,无法用鼠标 / 手指拖动 → 用户体验为"滚不动"。
class _AppScrollBehavior extends MaterialScrollBehavior {
  const _AppScrollBehavior();
  @override
  Set<PointerDeviceKind> get dragDevices => const {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };
}

const String _envApiBase = String.fromEnvironment('API_BASE');
const String _envWsBase = String.fromEnvironment('WS_BASE');

String _resolveApiBase() {
  if (_envApiBase.isNotEmpty) return _envApiBase;
  if (kIsWeb) return Uri.base.origin;
  return 'http://localhost:8080';
}

String _resolveWsBase() {
  if (_envWsBase.isNotEmpty) return _envWsBase;
  if (kIsWeb) {
    final scheme = Uri.base.isScheme('HTTPS') ? 'wss' : 'ws';
    final host = Uri.base.host;
    final port = Uri.base.hasPort ? ':${Uri.base.port}' : '';
    return '$scheme://$host$port/ws';
  }
  return 'ws://localhost:8080/ws';
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await I18n.instance.initialize();
  final api = ApiClient(_resolveApiBase());
  final stream = OddsStream(_resolveWsBase());
  final state = AppState(api: api, stream: stream);
  await state.initialize();
  // Best-effort: load admin-edited team overrides before first paint so
  // the very first match list renders the correct names/logos.
  await TeamOverrides.instance.load(api);
  runApp(CupApp(state: state));
}

class CupApp extends StatelessWidget {
  const CupApp({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    // Rebuild whole tree when locale changes so every tr() call refreshes.
    return AnimatedBuilder(
      animation: I18n.instance,
      builder: (context, _) => MaterialApp(
        title: tr('home.title_a') + tr('home.title_b'),
        debugShowCheckedModeBanner: false,
        theme: T.lightTheme(),
        scrollBehavior: const _AppScrollBehavior(),
        home: MainShell(state: state),
      ),
    );
  }
}

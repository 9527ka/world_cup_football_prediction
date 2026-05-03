import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'pages/main_shell.dart';
import 'services/api_client.dart';
import 'services/app_state.dart';
import 'services/i18n.dart';
import 'services/odds_stream.dart';
import 'theme/tokens.dart';

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
        home: MainShell(state: state),
      ),
    );
  }
}

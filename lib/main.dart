import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'pages/desktop/desktop_shell.dart';
import 'pages/main_shell.dart';
import 'services/api_client.dart';
import 'services/app_state.dart';
import 'services/auth_gate.dart';
import 'services/desktop_mode.dart';
import 'services/i18n.dart';
import 'services/odds_stream.dart';
import 'services/team_overrides.dart';
import 'theme/tokens.dart';
import 'widgets/login_wall.dart';

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
  // 只 await 真正本地、毫秒级的初始化(SharedPreferences 读 locale)。
  // 其余 API 往返(登录 / matches / team overrides)放到 runApp 之后异步跑,
  // 否则 Telegram WebView 冷启动会在 splash 阶段堵 1-3 个 RTT,首页文字迟迟不显示。
  // AppState / TeamOverrides 都是 ChangeNotifier,数据回来会自动触发 listener 刷 UI。
  I18n.instance.initialize();
  final api = ApiClient(_resolveApiBase());
  final stream = OddsStream(_resolveWsBase());
  final state = AppState(api: api, stream: stream);
  // 注册浏览器登录拦截弹层(auth_gate.requireLogin 调它)。Mini App 内不会触发,
  // 因为 initData 流程在 initialize() 直接登录成功。
  LoginWall.installOnce();
  // 浏览器 OAuth 回跳:URL 上带 ?tg_token=... 时把 token 写入 ApiClient + 清 URL。
  // 必须**在** state.initialize() 之前完成,否则 initialize 会因为 token 已存在
  // 跳过浏览器登录路径,但又因为 api.token 还没设而当未登录。
  unawaited(consumeIncomingToken(state).catchError((_) => null).then((_) => state.initialize()));
  // 按访客 IP 国家自动定界面语言(后端 CF-IPCountry → geoLang)。异步不堵 splash:
  // 首帧先用设备/TG 语言,geoLang 回来后若用户未手动选过则切换并重绘。
  unawaited(api.authConfig().then((cfg) => I18n.instance.applyGeoLocale(cfg.geoLang)).catchError((_) {}));
  runApp(CupApp(state: state));
  unawaited(TeamOverrides.instance.load(api));
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
        // 手机版:黑底 + 居中 460px 窄栏(含所有 pushed 路由)。
        // 桌面版(?a=test 且宽屏):放开宽度,由 DesktopShell 自行排版。
        builder: (context, child) {
          final desktop = isDesktopLayout(MediaQuery.of(context).size.width);
          if (desktop) {
            return Container(color: T.bgPage, child: child);
          }
          return Container(
            color: const Color(0xFF0A0E1A),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: child,
              ),
            ),
          );
        },
        home: RootShell(state: state),
      ),
    );
  }
}

/// 根据网关 + 当前宽度选择手机壳或桌面壳。随窗口缩放自动切换,
/// 与 [MaterialApp.builder] 里的 clamp 判断用同一 [isDesktopLayout]。
class RootShell extends StatelessWidget {
  const RootShell({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final desktop = isDesktopLayout(MediaQuery.of(context).size.width);
    if (desktop) return DesktopShell(state: state);
    return MainShell(state: state);
  }
}

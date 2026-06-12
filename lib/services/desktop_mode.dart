import 'package:flutter/foundation.dart' show kIsWeb;

/// 进入桌面布局的最小逻辑宽度。窄于此(手机 / Telegram Mini App / 窄窗)→ 手机版。
const double kDesktopMinWidth = 1024;

/// 当前是否渲染桌面布局。
///
/// 按宽度自动响应,面向所有用户:仅 Web 且可用宽度 ≥ [kDesktopMinWidth] 时
/// 走桌面三栏布局,否则走手机版。
/// (已去掉早期的 `?a=test` 测试网关 —— PC 版正式对所有桌面访客开放。)
bool isDesktopLayout(double width) => kIsWeb && width >= kDesktopMinWidth;

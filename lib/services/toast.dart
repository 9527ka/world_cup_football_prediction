import 'package:flutter/material.dart';

/// 全局 Toast 提示。
///
/// 解决两个问题:
/// 1. 默认 `showSnackBar` 队列累加,频繁点击会一条一条排队弹完。
///    我们改为「先 `hideCurrentSnackBar` 再 show」,只显示最后一次。
/// 2. 同样的内容 N 毫秒内重复触发只显示一次,防快速点击导致 toast 重复。
class Toast {
  Toast._();

  static String? _lastMessage;
  static DateTime _lastShownAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const _dedupeWindow = Duration(milliseconds: 800);

  /// 显示一条覆盖式 Toast。
  /// `kind`: success / error / info — 决定颜色。
  static void show(BuildContext context, String message, {String kind = 'info'}) {
    if (!context.mounted) return;
    final now = DateTime.now();
    if (message == _lastMessage &&
        now.difference(_lastShownAt) < _dedupeWindow) {
      // 800ms 内重复内容直接吞掉
      return;
    }
    _lastMessage = message;
    _lastShownAt = now;

    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.hideCurrentSnackBar();
    final color = switch (kind) {
      'success' => const Color(0xFF2E7D32),
      'error' => const Color(0xFFC62828),
      _ => const Color(0xFF263238),
    };
    messenger.showSnackBar(
      SnackBar(
        content: Text(message,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  static void error(BuildContext context, String message) =>
      show(context, message, kind: 'error');
  static void success(BuildContext context, String message) =>
      show(context, message, kind: 'success');
}

/// 按钮防抖工具。在 N 毫秒内重复触发同一个 [tag] 的动作 → 直接吞掉,
/// 防多次点击重复跳转 / 重复提交。
///
/// 用法:
/// ```dart
/// AntiSpam.guard('match_detail_${b.id}', () => _goMatchDetail(b));
/// ```
class AntiSpam {
  AntiSpam._();

  static final Map<String, DateTime> _lastFired = {};
  static const _defaultGap = Duration(milliseconds: 600);

  /// 返回 true 表示动作已执行(允许执行)。
  /// 返回 false 表示在防抖窗口内,被吞掉。
  static bool guard(String tag, VoidCallback action,
      {Duration gap = _defaultGap}) {
    final now = DateTime.now();
    final last = _lastFired[tag];
    if (last != null && now.difference(last) < gap) {
      return false;
    }
    _lastFired[tag] = now;
    action();
    return true;
  }

  /// async 版本 — 同样的去重逻辑。
  static Future<bool> guardAsync(String tag, Future<void> Function() action,
      {Duration gap = _defaultGap}) async {
    final now = DateTime.now();
    final last = _lastFired[tag];
    if (last != null && now.difference(last) < gap) {
      return false;
    }
    _lastFired[tag] = now;
    await action();
    return true;
  }
}

import 'package:flutter/material.dart';

import '../services/i18n.dart';
import '../theme/tokens.dart';

/// Native language names — shared by all language pickers.
const nativeLanguageNames = {
  'zh': '简体中文',
  'en': 'English',
  'ru': 'Русский',
  'es': 'Español',
  'ar': 'العربية',
  'fa': 'فارسی',
  'hi': 'हिन्दी',
  'id': 'Bahasa Indonesia',
  'ja': '日本語',
  'ko': '한국어',
  'pt': 'Português',
  'tr': 'Türkçe',
  'vi': 'Tiếng Việt',
  'fr': 'Français',
  'de': 'Deutsch',
  'it': 'Italiano',
};

/// Reusable bottom-sheet language picker.
///
/// Mutates [I18n.instance] and closes itself. Anyone listening to I18n's
/// [ChangeNotifier] will rebuild automatically — no callback wiring needed.
Future<void> showLanguagePicker(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: T.inkSubtle,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(tr('profile.language_picker_title'),
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800, color: T.ink)),
              const SizedBox(height: 6),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _langTile(
                        ctx,
                        label:
                            'Auto · ${nativeLanguageNames[I18n.instance.detectedLocale] ?? I18n.instance.detectedLocale}',
                        code: null,
                      ),
                      const Divider(height: 1, color: T.border),
                      for (final code in I18n.supported)
                        _langTile(ctx,
                            label: nativeLanguageNames[code] ?? code, code: code),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

Widget _langTile(BuildContext ctx,
    {required String label, required String? code}) {
  final i18n = I18n.instance;
  final selected = code == null
      ? !i18n.userOverride
      : (i18n.userOverride && i18n.locale == code);
  return InkWell(
    onTap: () async {
      if (code == null) {
        I18n.instance.resetToAuto();
      } else {
        I18n.instance.setLocale(code);
      }
      if (ctx.mounted) Navigator.pop(ctx);
    },
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: const TextStyle(
                    fontSize: 14, color: T.ink, fontWeight: FontWeight.w600)),
          ),
          if (selected)
            const Icon(Icons.check_circle, color: T.brandDeep, size: 20),
        ],
      ),
    ),
  );
}

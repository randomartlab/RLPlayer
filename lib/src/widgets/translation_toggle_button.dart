import 'package:flutter/material.dart';

import '../utils/ui_tokens.dart';

/// 文件树翻译切换按钮（照抄 kikoflu 交互：原文 ⇄ 译文切换 + 批量翻译进度）。
class TranslationToggleButton extends StatelessWidget {
  const TranslationToggleButton({
    super.key,
    required this.isTranslated,
    required this.onPressed,
    this.isLoading = false,
    this.progress,
  });

  final bool isTranslated;
  final bool isLoading;
  final String? progress;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foregroundColor = isTranslated
        ? scheme.primary
        : scheme.onSurface.withValues(alpha: 0.7);
    final borderColor = isTranslated
        ? scheme.primary.withValues(alpha: 0.3)
        : scheme.onSurface.withValues(alpha: 0.2);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isLoading ? null : onPressed,
        borderRadius: BorderRadius.circular(UiRadii.control),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(UiRadii.control),
            border: Border.all(color: borderColor, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isLoading) ...[
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: scheme.primary,
                  ),
                ),
                if (progress != null) ...[
                  const SizedBox(width: UiSpacing.xSmall),
                  Text(progress!,
                      style: TextStyle(fontSize: 12, color: foregroundColor)),
                ],
              ] else ...[
                Icon(Icons.g_translate, size: 16, color: foregroundColor),
                const SizedBox(width: 4),
                Text(
                  isTranslated ? '原文' : '译文',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: foregroundColor,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 紧凑标签行组件，用于展示可折叠 token 列表。
library;

import 'package:flutter/material.dart';

/// 单行紧凑标签行：每个 token 使用独立圆角矩形包裹。
class CompactTokenRow extends StatelessWidget {
  final List<String> tokens;

  const CompactTokenRow({
    super.key,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final candidates = tokens.where((t) => t.trim().isNotEmpty).toList();
    if (candidates.isEmpty) return const SizedBox.shrink();

    const chipPadding = 16.0; // 左右 padding 合计
    const chipBorder = 2.0; // 边框总宽度
    const chipSpacing = 6.0;
    final chipTextStyle = TextStyle(color: cs.onSurfaceVariant, fontSize: 12);

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final visible = <String>[];
        var used = 0.0;

        for (final text in candidates) {
          final painter = TextPainter(
            text: TextSpan(text: text, style: chipTextStyle),
            maxLines: 1,
            textDirection: Directionality.of(context),
          )..layout(maxWidth: maxWidth.isFinite ? maxWidth : double.infinity);
          final tokenWidth = painter.width + chipPadding + chipBorder;
          final required = visible.isEmpty ? tokenWidth : tokenWidth + chipSpacing;
          if (maxWidth.isFinite && used + required > maxWidth) break;
          used += required;
          visible.add(text);
        }

        if (visible.isEmpty) {
          visible.add(candidates.first);
        }

        return SizedBox(
          height: 22,
          child: Row(
            children: [
              for (int index = 0; index < visible.length; index++) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _chipBackgroundColor(cs, visible[index]),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: _chipBorderColor(cs, visible[index])),
                  ),
                  child: Text(
                    visible[index],
                    maxLines: 1,
                    softWrap: false,
                    style: chipTextStyle.copyWith(
                      color: _chipTextColor(cs, visible[index]),
                    ),
                  ),
                ),
                if (index < visible.length - 1) const SizedBox(width: 6),
              ],
            ],
          ),
        );
      },
    );
  }

  Color _chipBackgroundColor(ColorScheme cs, String token) {
    final accent = _tokenAccentColor(token);
    if (accent == null) return cs.surfaceContainerHighest;
    final isDark = cs.brightness == Brightness.dark;
    if (isDark) {
      return Color.alphaBlend(accent.withValues(alpha: 0.26), cs.surfaceContainerHighest);
    }
    return Color.alphaBlend(accent.withValues(alpha: 0.14), cs.surface);
  }

  Color _chipBorderColor(ColorScheme cs, String token) {
    final accent = _tokenAccentColor(token);
    if (accent == null) return cs.outlineVariant;
    final isDark = cs.brightness == Brightness.dark;
    return isDark
        ? Color.alphaBlend(accent.withValues(alpha: 0.72), cs.outlineVariant)
        : Color.alphaBlend(accent.withValues(alpha: 0.54), cs.outlineVariant);
  }

  Color _chipTextColor(ColorScheme cs, String token) {
    final accent = _tokenAccentColor(token);
    if (accent == null) return cs.onSurfaceVariant;
    final isDark = cs.brightness == Brightness.dark;
    return isDark
        ? Color.alphaBlend(accent.withValues(alpha: 0.92), cs.onSurface)
        : Color.alphaBlend(accent.withValues(alpha: 0.72), cs.onSurface);
  }

  Color? _tokenAccentColor(String token) {
    final normalized = token.trim().toLowerCase();
    if (normalized == '水性') return const Color(0xFF4FC3F7);
    if (normalized == '油性') return const Color(0xFFFFB74D);
    if (normalized == 'pu') return const Color(0xFFBA68C8);
    if (normalized == 'pud') return const Color(0xFF66BB6A);
    if (normalized == 'uv') return const Color(0xFF7986CB);
    if (normalized == '双固化') return const Color(0xFFEF5350);
    if (normalized == '聚烯烃') return const Color(0xFF4DB6AC);
    return null;
  }
}

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
    final chipTextStyle = TextStyle(
      color: cs.onSurfaceVariant,
      fontSize: 12,
    );

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
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: cs.outlineVariant),
                  ),
                  child: Text(
                    visible[index],
                    maxLines: 1,
                    softWrap: false,
                    style: chipTextStyle,
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
}

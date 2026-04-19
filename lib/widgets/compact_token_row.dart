import 'package:flutter/material.dart';

/// 单行紧凑标签行：每个 token 使用独立圆角矩形包裹。
class CompactTokenRow extends StatelessWidget {
  final List<String> tokens;
  final int maxTokens;

  const CompactTokenRow({
    super.key,
    required this.tokens,
    this.maxTokens = 3,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final visible = tokens.where((t) => t.trim().isNotEmpty).take(maxTokens).toList();
    if (visible.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 22,
      child: Row(
        children: [
          for (int index = 0; index < visible.length; index++) ...[
            Flexible(
              fit: FlexFit.loose,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: cs.outlineVariant),
                ),
                child: Text(
                  visible[index],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
            if (index < visible.length - 1) const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }
}

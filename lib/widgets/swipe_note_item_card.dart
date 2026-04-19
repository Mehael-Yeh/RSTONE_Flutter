import 'package:flutter/material.dart';

import 'compact_token_row.dart';
import 'note_swipe_tile.dart';

/// 带“右滑露出笔记按钮”的统一项目卡片。
class SwipeNoteItemCard extends StatelessWidget {
  final String title;
  final List<String> subtitleTokens;
  final Color indicatorColor;
  final VoidCallback onTap;
  final NoteTapCallback onNoteTap;
  final int noteResetSignal;
  final TextStyle? titleStyle;

  const SwipeNoteItemCard({
    super.key,
    required this.title,
    required this.subtitleTokens,
    required this.indicatorColor,
    required this.onTap,
    required this.onNoteTap,
    required this.noteResetSignal,
    this.titleStyle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: NoteSwipeTile(
        onNoteTap: onNoteTap,
        resetSignal: noteResetSignal,
        noteButtonInsets: const EdgeInsets.symmetric(vertical: 1),
        noteButtonBorderRadius: const BorderRadius.horizontal(
          left: Radius.circular(12),
        ),
        child: Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: EdgeInsets.zero,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Center(
                    child: Container(
                      width: 4,
                      height: 40,
                      decoration: BoxDecoration(
                        color: indicatorColor,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Text(
                                title,
                                style: titleStyle ??
                                    Theme.of(context).textTheme.titleMedium?.copyWith(
                                          color: cs.onSurface,
                                          fontWeight: FontWeight.w700,
                                        ),
                              ),
                            ),
                          ],
                        ),
                        if (subtitleTokens.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          CompactTokenRow(tokens: subtitleTokens),
                        ],
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

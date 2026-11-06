/// 笔记卡片组件，封装滑动操作与笔记摘要展示。
library;

import 'package:flutter/material.dart';
import '../utils/app_shapes.dart';

import 'compact_token_row.dart';
import 'note_swipe_tile.dart';

/// 带“右滑露出笔记按钮”的统一项目卡片。
class SwipeNoteItemCard extends StatelessWidget {
  final String title;
  final List<String> subtitleTokens;
  final Color indicatorColor;
  final VoidCallback onTap;
  final NoteTapCallback onNoteTap;
  final DeleteTapCallback? onDeleteTap;
  final int noteResetSignal;
  final TextStyle? titleStyle;
  final bool showUserAddedDot;
  final TextDecoration? titleDecoration;
  final String? statusLabel;
  final Widget? titleBadge;

  /// Inline accessory directly after the title, not at the trailing edge.
  final Widget? titleSuffix;

  const SwipeNoteItemCard({
    super.key,
    required this.title,
    required this.subtitleTokens,
    required this.indicatorColor,
    required this.onTap,
    required this.onNoteTap,
    this.onDeleteTap,
    required this.noteResetSignal,
    this.titleStyle,
    this.showUserAddedDot = false,
    this.titleDecoration,
    this.statusLabel,
    this.titleBadge,
    this.titleSuffix,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: NoteSwipeTile(
        onNoteTap: onNoteTap,
        onDeleteTap: onDeleteTap,
        resetSignal: noteResetSignal,
        noteButtonInsets: const EdgeInsets.symmetric(vertical: 1),
        noteButtonBorderRadius: AppShapes.left,
        deleteButtonBorderRadius: AppShapes.right,
        child: Card(
          shape:
              AppShapes.rounded,
          margin: EdgeInsets.zero,
          child: InkWell(
            onTap: onTap,
            borderRadius: AppShapes.borderRadius,
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
                        borderRadius: AppShapes.borderRadius,
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
                              child: titleSuffix == null
                                  ? Text(
                                      title,
                                      style: (titleStyle ??
                                              Theme.of(context)
                                                  .textTheme
                                                  .titleMedium
                                                  ?.copyWith(
                                                    color: cs.onSurface,
                                                    fontWeight: FontWeight.w700,
                                                  ))
                                          ?.copyWith(
                                              decoration: titleDecoration),
                                    )
                                  : Row(children: [
                                      Flexible(
                                          child: Text(title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: (titleStyle ??
                                                      Theme.of(context)
                                                          .textTheme
                                                          .titleMedium
                                                          ?.copyWith(
                                                              color:
                                                                  cs.onSurface,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w700))
                                                  ?.copyWith(
                                                      decoration:
                                                          titleDecoration))),
                                      Flexible(child: titleSuffix!),
                                    ]),
                            ),
                            if (titleBadge != null) titleBadge!,
                            if (statusLabel != null)
                              Container(
                                margin: const EdgeInsets.only(left: 6),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: cs.secondaryContainer,
                                  borderRadius: AppShapes.borderRadius,
                                ),
                                child: Text(
                                  statusLabel!,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: cs.onSecondaryContainer,
                                  ),
                                ),
                              ),
                            if (showUserAddedDot)
                              Container(
                                width: 8,
                                height: 8,
                                margin: const EdgeInsets.only(left: 8),
                                decoration: const BoxDecoration(
                                  color: Colors.redAccent,
                                  shape: BoxShape.circle,
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
                    child:
                        Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
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

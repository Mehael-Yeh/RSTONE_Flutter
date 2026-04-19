/// 可侧滑的笔记条目组件，支持编辑与删除动作。

import 'package:flutter/material.dart';

typedef NoteTapCallback = Future<void> Function();

/// 可右滑露出“笔记”按钮的容器。
class NoteSwipeTile extends StatefulWidget {
  final Widget child;
  final NoteTapCallback onNoteTap;
  final int resetSignal;
  final EdgeInsets noteButtonInsets;
  final BorderRadius noteButtonBorderRadius;
  final double noteButtonWidthFactor;
  final double noteButtonRightOverlap;

  const NoteSwipeTile({
    super.key,
    required this.child,
    required this.onNoteTap,
    this.resetSignal = 0,
    this.noteButtonInsets = EdgeInsets.zero,
    this.noteButtonBorderRadius = BorderRadius.zero,
    this.noteButtonWidthFactor = 0.17,
    this.noteButtonRightOverlap = 10,
  });

  @override
  State<NoteSwipeTile> createState() => _NoteSwipeTileState();
}

class _NoteSwipeTileState extends State<NoteSwipeTile> {
  static _NoteSwipeTileState? _activeTile;
  double _offsetX = 0;

  bool get _isRevealed => _offsetX > 0;

  void _collapse() {
    if (!mounted || _offsetX == 0) return;
    setState(() => _offsetX = 0);
  }

  void _markAsActiveIfNeeded() {
    if (!_isRevealed) return;
    if (!identical(_activeTile, this)) {
      _activeTile?._collapse();
      _activeTile = this;
    }
  }

  Future<void> _handleNoteTap() async {
    await widget.onNoteTap();
    if (!mounted) return;
    _collapse();
    if (identical(_activeTile, this)) {
      _activeTile = null;
    }
  }

  @override
  void didUpdateWidget(covariant NoteSwipeTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resetSignal != widget.resetSignal) {
      _collapse();
      if (identical(_activeTile, this)) {
        _activeTile = null;
      }
    }
  }

  @override
  void dispose() {
    if (identical(_activeTile, this)) {
      _activeTile = null;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = (constraints.maxWidth - widget.noteButtonInsets.horizontal)
            .clamp(0.0, double.infinity)
            .toDouble();
        final revealWidth = (availableWidth * widget.noteButtonWidthFactor).clamp(52.0, 108.0).toDouble();
        final buttonWidth = (revealWidth + widget.noteButtonRightOverlap).clamp(revealWidth, 132.0).toDouble();

        return Stack(
          children: [
            Positioned.fill(
              child: Padding(
                padding: widget.noteButtonInsets,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: buttonWidth,
                    height: double.infinity,
                    child: FilledButton(
                      onPressed: _handleNoteTap,
                      child: Transform.translate(
                        offset: Offset(-2, 0),
                        child: Icon(Icons.note_alt_outlined, size: 24),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: cs.primaryContainer,
                        foregroundColor: cs.onPrimaryContainer,
                        elevation: 0,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: widget.noteButtonBorderRadius,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            GestureDetector(
              onHorizontalDragUpdate: (details) {
                setState(() {
                  _offsetX = (_offsetX + details.delta.dx).clamp(0, revealWidth);
                });
                _markAsActiveIfNeeded();
              },
              onHorizontalDragEnd: (_) {
                setState(() {
                  _offsetX = _offsetX >= revealWidth * 0.5 ? revealWidth : 0;
                });
                if (_isRevealed) {
                  _markAsActiveIfNeeded();
                } else if (identical(_activeTile, this)) {
                  _activeTile = null;
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                transform: Matrix4.translationValues(_offsetX, 0, 0),
                child: widget.child,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 简易笔记编辑弹窗。
class NoteEditorDialog extends StatefulWidget {
  final String title;
  final String initialValue;

  const NoteEditorDialog({
    super.key,
    required this.title,
    required this.initialValue,
  });

  @override
  State<NoteEditorDialog> createState() => _NoteEditorDialogState();
}

class _NoteEditorDialogState extends State<NoteEditorDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _closeAndSave() {
    Navigator.of(context).pop(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        '笔记 - ${widget.title}',
        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 16),
      ),
      titlePadding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      actionsPadding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      content: SizedBox(
        width: 460,
        height: 320,
        child: TextField(
          controller: _controller,
          expands: true,
          maxLines: null,
          minLines: null,
          textAlignVertical: TextAlignVertical.top,
          decoration: const InputDecoration(
            hintText: '请输入记录内容',
            border: OutlineInputBorder(),
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: _closeAndSave,
          child: const Text('确认'),
        ),
      ],
    );
  }
}

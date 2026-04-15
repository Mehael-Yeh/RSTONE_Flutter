import 'package:flutter/material.dart';

/// 可右滑露出“笔记”按钮的容器。
class NoteSwipeTile extends StatefulWidget {
  final Widget child;
  final VoidCallback onNoteTap;

  const NoteSwipeTile({
    super.key,
    required this.child,
    required this.onNoteTap,
  });

  @override
  State<NoteSwipeTile> createState() => _NoteSwipeTileState();
}

class _NoteSwipeTileState extends State<NoteSwipeTile> {
  double _offsetX = 0;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final revealWidth = constraints.maxWidth * 0.25;

        return Stack(
          children: [
            Positioned.fill(
              child: Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: revealWidth,
                  height: double.infinity,
                  child: FilledButton.icon(
                    onPressed: widget.onNoteTap,
                    icon: const Icon(Icons.note_alt_outlined),
                    label: const Text('笔记'),
                    style: FilledButton.styleFrom(
                      backgroundColor: cs.primaryContainer,
                      foregroundColor: cs.onPrimaryContainer,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(0),
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
              },
              onHorizontalDragEnd: (_) {
                setState(() {
                  _offsetX = _offsetX >= revealWidth * 0.5 ? revealWidth : 0;
                });
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
      title: Text('笔记 - ${widget.title}'),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
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
